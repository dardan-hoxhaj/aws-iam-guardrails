# Deploy guide

From an empty AWS account to guardrails applied by CI, then teardown. Each step says
**why** before **how**. Commands are for macOS with zsh; they work the same on Linux.

> Use a personal sandbox or free-tier account, never a work account. Never paste access
> keys, passwords or tokens into chat, issues, or commits.

Placeholders you replace with your own values: `<account-id>`, `<org-id>`, `<your-github-user>`.

---

## Step 0: Budget alert (before anything else)

**Why:** if something is left running by mistake, you get an email instead of a surprise bill.

1. Sign in to the AWS console as the root user (with MFA turned on).
2. Go to **Billing and Cost Management → Budgets → Create budget**.
3. Choose **Use a template → Zero spend budget**. It emails you as soon as spend goes over $0.01.
4. Optionally add a second **Monthly cost budget** of $5.
5. Enter the email you want alerts sent to and create it.

*Done when:* Budgets lists your budget(s).

## Step 1: Turn on IAM Identity Center and give yourself a sign-in

**Why:** you need admin credentials on your laptop to run the bootstrap once, and they
should be short-lived Identity Center credentials, not root and not IAM user keys.

1. Pick your home region in the console's top-right (this guide uses `us-east-1`). Identity
   Center lives in exactly one region, and the Terraform must use the same one.
2. Open **IAM Identity Center → Enable**. Choose the organization instance. This also creates
   an **AWS Organization** with your account as the management account.
3. **Users → Add user**: create a user for yourself and finish the email invitation.
4. **Permission sets → Create permission set → Predefined → AdministratorAccess**.
   Name it `BootstrapAdmin`, session duration 1 hour.
   This one is created by hand on purpose: Terraform cannot create the credentials it needs
   to run for the very first time.
5. **AWS accounts →** select your management account **→ Assign users or groups →** your
   user **→** `BootstrapAdmin`.
6. Copy the **AWS access portal URL** from the Identity Center dashboard (Settings → Identity source).

*Done when:* you can open the access portal URL, sign in, and see your account with `BootstrapAdmin`.

## Step 2: Install the AWS CLI and sign in

**Why:** Terraform on your laptop uses the AWS CLI's login.

```bash
brew install awscli
aws --version

aws configure sso
# SSO session name:    guardrails
# SSO start URL:       <your access portal URL>
# SSO region:          us-east-1
# Registration scopes: (press Enter for the default)
# Pick your account and the BootstrapAdmin role when asked.
# CLI default region:  us-east-1
# CLI output format:   json
# Profile name:        guardrails-admin

export AWS_PROFILE=guardrails-admin
aws sts get-caller-identity
```

*Done when:* `get-caller-identity` prints an `Arn` containing `AWSReservedSSO_BootstrapAdmin`.
Sessions expire; run `aws sso login` again when commands start failing with an expired token.

## Step 3: Bootstrap (state bucket + GitHub OIDC roles)

**Why:** this creates the S3 bucket that holds Terraform state and the two roles GitHub
Actions will assume. After this, CI never needs stored AWS keys.

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set github_owner to your GitHub username

terraform init
terraform plan        # read it: 1 bucket (+ settings), 1 OIDC provider, 2 roles, 2 policies
terraform apply
terraform output
```

If `apply` fails with *EntityAlreadyExists* on the OIDC provider, your account already has
one: set `create_github_oidc_provider = false` in `terraform.tfvars` and apply again.

The bootstrap state stays on your laptop in `bootstrap/terraform.tfstate` (git-ignored).
Don't delete it; you need it for teardown.

*Done when:* `terraform output` shows `state_bucket_name`, `plan_role_arn`, `apply_role_arn`.

<!-- TODO(apply): note anything that failed here and how you fixed it. -->

## Step 4: First apply of the guardrails, from your laptop

**Why:** the first run imports the organization that Identity Center created in Step 1,
so Terraform manages it instead of trying to create a second one.

```bash
cd ../live
cp terraform.tfvars.example terraform.tfvars        # edit if you want other regions
cp backend.hcl.example backend.hcl                   # put in your state bucket name

terraform init -backend-config=backend.hcl

# Bring the existing organization under Terraform
aws organizations describe-organization --query Organization.Id --output text   # prints o-xxxxxxxxxx
terraform import module.organization.aws_organizations_organization.this <org-id>

terraform plan
terraform apply
```

Want to run the SCP drill? SCPs never affect the management account, so you need one
member account. In `terraform.tfvars` set `create_sandbox_account = true` and
`sandbox_account_email` to an address you control that has never been used for an AWS
account (Gmail-style `you+aws-sandbox@…` works). Then `terraform apply` again.

Finally add yourself to the Terraform-managed `platform-admins` group in Identity Center
(**Groups → platform-admins → Add users**).

*Done when:* the Organizations console shows the `Security`, `Workloads` and `Sandbox` OUs,
with both SCPs attached to `Workloads` and `Sandbox`.

## Step 5: Commit the provider lock files

**Why:** the lock file pins the exact AWS provider build so CI and your Mac use the same one.

```bash
cd ..
for d in bootstrap live; do
  terraform -chdir=$d providers lock -platform=darwin_arm64 -platform=linux_amd64
done
git add bootstrap/.terraform.lock.hcl live/.terraform.lock.hcl
git commit -m "Pin AWS provider with lock files"
```

## Step 6: Connect GitHub Actions

In the repo on GitHub, **Settings → Secrets and variables → Actions**:

| Kind | Name | Value |
|---|---|---|
| Variable | `AWS_DEPLOY_ENABLED` | `true` |
| Variable | `AWS_REGION` | `us-east-1` |
| Variable | `TF_STATE_BUCKET` | `state_bucket_name` output |
| Secret | `AWS_PLAN_ROLE_ARN` | `plan_role_arn` output |
| Secret | `AWS_APPLY_ROLE_ARN` | `apply_role_arn` output |
| Variable (only with sandbox) | `CREATE_SANDBOX_ACCOUNT` | `true` |
| Secret (only with sandbox) | `SANDBOX_ACCOUNT_EMAIL` | the sandbox email |

Role ARNs are not passwords, but they contain your account ID, and secrets are masked in
logs. Logs of a public repo are public.

**Settings → Environments → New environment** named `production`:
add yourself under **Required reviewers**, and under **Deployment branches** allow only `main`.

**Settings → Rules → Rulesets → New branch ruleset** for `main`: require a pull request and
require these status checks: `fmt, validate, test`, `tflint`, `checkov security gate`,
`gitleaks secret scan`.

*Done when:* a pull request that touches `live/` shows a green `plan` job.

## Step 7: Prove the gate blocks a risky change

On a branch, add `"iam:*"` with `resources = ["*"]` to a statement in
`bootstrap/github_oidc.tf`, open a pull request, and watch `checkov security gate` fail.
Screenshot it, then close the PR without merging.

## Step 8: AccessDenied drill

Follow [runbooks/accessdenied-cloudtrail.md](runbooks/accessdenied-cloudtrail.md).

---

## Teardown

Order matters: guardrails first, bootstrap last (the live stack's state lives in the
bootstrap bucket). Sign in first: `export AWS_PROFILE=guardrails-admin && aws sso login`.

```bash
# 0. Stop CI from re-applying: set the GitHub variable AWS_DEPLOY_ENABLED to false.

# 1. Guardrails
cd live
terraform apply -var force_destroy_trail_bucket=true    # lets destroy empty the log bucket
# Keep the organization itself: it is free, and deleting it would require turning off
# Identity Center and removing every member account first.
terraform state rm module.organization.aws_organizations_organization.this
terraform destroy

# 2. Bootstrap
cd ../bootstrap
terraform apply -var force_destroy_state_bucket=true
terraform destroy
```

If you created the sandbox account, `destroy` closes it. AWS keeps a closed account in a
suspended state for up to 90 days (free). If `destroy` stops on the `Sandbox` OU because the
closed account is still inside it, run
`terraform state rm 'module.organization.aws_organizations_organizational_unit.this["Sandbox"]'`,
re-run `terraform destroy`, and delete the OU in the console after AWS removes the account.

### Verify nothing is left

Each command should print nothing (or `[]`):

```bash
aws cloudtrail describe-trails --query "trailList[?starts_with(Name,'iam-guardrails')].Name" --output text
aws s3api list-buckets --query "Buckets[?starts_with(Name,'iam-guardrails')].Name" --output text
aws accessanalyzer list-analyzers --query "analyzers[?starts_with(name,'iam-guardrails')].name" --output text
aws iam list-roles --query "Roles[?starts_with(RoleName,'iam-guardrails')].RoleName" --output text
aws organizations list-policies --filter SERVICE_CONTROL_POLICY --query "Policies[?starts_with(Name,'iam-guardrails')].Name" --output text
```

Left on purpose (all free): the organization, IAM Identity Center, your user, and the
hand-made `BootstrapAdmin` permission set. Check Cost Explorer after a few days to confirm $0.
