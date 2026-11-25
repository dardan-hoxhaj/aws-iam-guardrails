# Design decisions

Why the project is built the way it is. Each answer is short enough to say out loud in an interview.

**Why SCPs on OUs instead of the organization root?**
Blast radius. A bad SCP on the root can lock every member account out at once. On OUs,
it only hits accounts you deliberately moved there, so you can test on `Sandbox` first.

**Why deny-list SCPs, not allow-lists?**
AWS attaches a default `FullAWSAccess` SCP. Adding targeted `Deny` statements is easier to
reason about and review than replacing it with an allow-list, which can silently block new services.

**Why exempt global services from the region SCP?**
IAM, STS, Organizations, billing and support are global or live only in `us-east-1`.
Denying them by region breaks sign-in and billing. `NotAction` lists them.

**Why is the region SCP's `NotAction` list checked against the 5,120-character limit in tests?**
SCPs have a hard size limit. Exceeding it fails only at apply time; the unit test catches it in CI.

**Why GitHub OIDC instead of access keys in GitHub secrets?**
Keys stored in GitHub never expire unless someone rotates them, and they leak through logs,
forks, or compromised actions. OIDC credentials last one hour and only exist during the job.

**Why two CI roles?**
A pull request can come from anyone with write access and runs code from a branch. It only
gets a read-only role. Writing to AWS needs a merge to `main` *and* a human approving the
`production` environment, and only that environment's token can assume the apply role.

**Why match `sub` exactly instead of `repo:owner/*`?**
A wildcard lets any repo, branch, or environment that matches assume the role. Checkov's
`CKV_AWS_393` flags this, and the gate self-test proves it does.

**Why can the plan role write `*.tflock` objects?**
`terraform plan` takes the state lock. Without write access to the lock file it fails, but
it does not need to write the state file itself, so only the lock path is allowed.

**Why S3 native locking instead of DynamoDB?**
Terraform 1.10+ can lock with a lock file in the same bucket (`use_lockfile = true`).
One less resource to create, secure and pay for.

**Why is bootstrap state local?**
The bootstrap creates the remote-state bucket, so it can't store its state there before the
bucket exists. It is tiny, changes rarely, and is git-ignored.

**Why Identity Center instead of IAM users?**
People get short sessions (1 hour for admin), access is granted through groups, and leaving
the company means removing one user in one place. The SCP blocks creating IAM users and keys
in member accounts to keep it that way.

**Why `ViewOnlyAccess` for ReadOnly instead of `ReadOnlyAccess`?**
`ReadOnlyAccess` can read data, such as S3 objects and DynamoDB items. `ViewOnlyAccess` shows
resources and configuration without the data in them.

**Why AdministratorAccess at all (`PlatformAdmin`)?**
Someone has to be able to fix things. It is group-assigned, limited to one-hour sessions,
and every call is in the org trail. The Checkov finding is skipped with that reason in code.

**Why an organization trail?**
One trail in the management account logs every account and region, and member accounts
cannot turn it off. The `ProtectAuditTrail` SCP is defense in depth.

**Why SSE-S3 rather than KMS for the buckets?**
Cost and simplicity for a demo: a customer-managed key is about $1 a month plus requests.
It is listed in "What's next", and the Checkov skips say so.

**Why `for_each` keys use account labels, not account IDs?**
`for_each` keys must be known at plan time. A new account's ID only exists after apply,
so keying by ID fails on the first run. The `live` test caught this during the build.

**Why are Checkov skips inline and not in a global config?**
Each exception sits next to the resource with its reason, so a reviewer sees it in the same
diff. A global skip list hides exceptions and applies them everywhere.
