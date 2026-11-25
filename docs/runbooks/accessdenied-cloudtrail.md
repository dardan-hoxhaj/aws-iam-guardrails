# Runbook: trace an AccessDenied with CloudTrail

**Use when:** someone (a person, a pipeline, an app) reports *AccessDenied*,
*AccessDeniedException*, *UnauthorizedOperation* or *not authorized to perform*.

**Goal:** in under 15 minutes, answer three questions:
1. **Who** made the call? (which identity, which account)
2. **What** was denied? (action, resource, region)
3. **Which policy** denied it, and is that intended?

---

## 1. Read the error message first

Modern AWS error messages usually say which kind of policy denied the call. This is the
fastest clue, so copy the full message before doing anything else.

| Message ends with… | Meaning | Usual fix |
|---|---|---|
| `…with an explicit deny in a service control policy` | An SCP blocks it for the whole account/OU. | Often **working as intended**. If not, change the SCP or move the account to another OU (needs review). |
| `…because no identity-based policy allows the <action> action` | **Implicit deny**: nothing grants it. | Add the specific action to the role / permission set. Smallest change only. |
| `…with an explicit deny in an identity-based policy` | A `Deny` statement on the caller's role/user. | Find and review the deny statement. |
| `…with an explicit deny in a permissions boundary` | A permissions boundary caps the role. | Change the boundary, not the role policy. |
| `…because no resource-based policy allows…` / `…in a resource-based policy` | The bucket/key/queue policy is the blocker. | Fix the resource policy. |
| `…with an explicit deny in a session policy` | The credentials were requested with a narrower session policy. | Check how the session was created. |

> Remember the evaluation rule: **an explicit Deny anywhere always wins**. Otherwise, a call
> needs an Allow from the identity policy (and the resource policy where relevant), and it
> must not be blocked by an SCP, permissions boundary or session policy.

## 2. Find the event in CloudTrail

The error code differs by service: `AccessDenied` (S3, IAM), `AccessDeniedException`
(DynamoDB, KMS, most newer services), `Client.UnauthorizedOperation` (EC2).

**Where to look:**
- **Event history** (console or `lookup-events`): last 90 days, **per account and per region**.
  Look in the account and region where the call was made, not only the management account.
- **Organization trail S3 bucket**: all accounts, all regions, delivered within about 15 minutes.
  Path: `AWSLogs/<org-id>/<account-id>/CloudTrail/<region>/YYYY/MM/DD/`.

**Console:** CloudTrail → Event history → filter *Event name* = the action from the error
→ open the event → read `errorCode`, `errorMessage`, `userIdentity.arn`, `awsRegion`, `sourceIPAddress`.

**CLI** (event history cannot filter on errorCode, so filter with `jq`):

```bash
aws cloudtrail lookup-events \
  --region <region-where-the-call-was-made> \
  --lookup-attributes AttributeKey=EventName,AttributeValue=<EventName> \
  --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)" \
  --max-results 50 --output json \
| jq -r '.Events[].CloudTrailEvent | fromjson
         | select(.errorCode != null)
         | [.eventTime, .userIdentity.arn, .eventName, .awsRegion, .errorCode, .errorMessage] | @tsv'
```

(`date -v-1H` is macOS. On Linux use `date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ`.)

**Read the event:**

| Field | Tells you |
|---|---|
| `userIdentity.arn` | Who. `assumed-role/AWSReservedSSO_<PermissionSet>_…/<user>` is a person via Identity Center; `assumed-role/iam-guardrails-gha-plan/…` is the CI plan role. |
| `userIdentity.accountId` / `recipientAccountId` | Which account. |
| `eventSource` + `eventName` | The exact action, e.g. `dynamodb.amazonaws.com` + `ListTables` → `dynamodb:ListTables`. |
| `awsRegion` | Where. Important for the region SCP. |
| `errorCode` / `errorMessage` | The denial and, usually, the policy type. |

## 3. Decide and act

```
explicit deny in an SCP?
 ├─ yes → is the guardrail doing its job? (wrong region, root user, stopping the trail…)
 │         ├─ yes → reply with the reason, close. No change.
 │         └─ no  → PR to modules/scps with the reason. Never detach SCPs by hand.
 └─ no  → implicit deny?
           ├─ person  → right permission set? If yes, PR adding the one action.
           └─ CI role → PR adding the one action to bootstrap/github_oidc.tf,
                        then re-run the bootstrap apply locally.
```

After the fix, repeat the original call and confirm it succeeds (or, for an intended
SCP deny, that it still fails with the same message).

---

## Drill A: SCP explicit deny (needs the sandbox account)

**Setup:** `create_sandbox_account = true` applied, you are in the `platform-admins` group.

1. Add a CLI profile for the sandbox account with the `PlatformAdmin` permission set:
   ```bash
   aws configure sso --profile sandbox-admin    # pick the sandbox account + PlatformAdmin
   aws sts get-caller-identity --profile sandbox-admin
   ```
2. Make a call in a region that is **not** in `allowed_regions` (default allows
   `us-east-1`, `us-west-2`):
   ```bash
   aws dynamodb list-tables --region eu-west-1 --profile sandbox-admin
   ```
   **Expected:** an `AccessDeniedException` that says *explicit deny in a service control policy*,
   even though `PlatformAdmin` is AdministratorAccess. That is the point of an SCP.
3. Same call in an allowed region should work:
   ```bash
   aws dynamodb list-tables --region us-east-1 --profile sandbox-admin
   ```
4. Find the denied event (Step 2 above) with `--region eu-west-1 --profile sandbox-admin`
   and `EventName=ListTables`.

<!-- TODO(apply): paste the real error message (account ID replaced with <account-id>). -->
<!-- TODO(apply): paste the real CloudTrail fields: eventTime, userIdentity.arn (redacted), eventName, awsRegion, errorCode, errorMessage. -->
<!-- TODO(apply): screenshot of the event in CloudTrail Event history. -->

## Drill B: implicit deny (no sandbox account needed)

1. Assign yourself the `ReadOnly` permission set on the management account (add yourself
   to the `readonly` group), and create a profile for it:
   ```bash
   aws configure sso --profile mgmt-readonly
   ```
2. Try to create something:
   ```bash
   aws s3api create-bucket --bucket iam-guardrails-drill-$RANDOM --profile mgmt-readonly
   ```
   **Expected:** `AccessDenied` saying *no identity-based policy allows the s3:CreateBucket action*.
   The SCPs are not involved here (management account); `ViewOnlyAccess` simply has no Allow.
3. Find it: `--region us-east-1`, `EventName=CreateBucket`.

<!-- TODO(apply): paste the real error and CloudTrail fields, redacted. -->

## Drill C (real life): the CI plan fails with AccessDenied

If the `plan` job fails with *not authorized to perform: X*, the role is missing action `X`.
Confirm it in CloudTrail (`userIdentity.arn` contains `iam-guardrails-gha-plan`), add exactly
that action to the plan statement in `bootstrap/github_oidc.tf`, open a PR, then run
`terraform apply` in `bootstrap/` from your laptop. Write down the action and the error here.

<!-- TODO(apply): record any real occurrence. -->

## Interview talking points

- Explicit deny vs. implicit deny, and why an SCP denies even an administrator.
- SCPs do not apply to the management account, so nobody runs workloads there.
- Event history is per account and per region; the org trail is the single place for everything.
- The fix is the smallest change, made through a pull request, so it is reviewed and logged.
