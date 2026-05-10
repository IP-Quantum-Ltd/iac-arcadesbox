# Terraform CI/CD Bootstrap

One-time setup to enable the GitHub Actions workflow at `.github/workflows/terraform.yml`. After this is done, all Terraform changes flow through PR → plan-on-PR → merge → apply.

## Status of automated setup

The following has already been provisioned (by `gh` CLI) and you can verify with `gh secret list --env <env>` or in the GitHub UI under Settings → Environments:

- Three GitHub Environments: `development`, `staging`, `production`
- `production` Environment is restricted to the `main` branch (deployment-branch policy)
- Per-Environment secrets set:

| Secret                          | development | staging | production |
|---------------------------------|:-----------:|:-------:|:----------:|
| `AWS_REGION`                    | ✓           | ✓       | ✓          |
| `AWS_TERRAFORM_ROLE_ARN`        | —           | ✓       | ✓          |
| `TF_VAR_R2_SECRET_ACCESS_KEY`   | ✓           | ✓       | ✓          |
| `TF_VAR_R2_ACCESS_KEY_ID`       | ✓           | ✓       | ✓          |
| `TF_VAR_WORKER_JWT_SECRET`      | ✓           | ✓       | ✓          |
| `TF_VAR_CLOUDFLARE_ZONE_ID`     | ✓           | ✓       | ✓          |
| `TF_VAR_CLOUDFLARE_API_TOKEN`   | ✓           | ✓       | ✓          |

`staging` and `production` are fully wired — pushes / merges to those branches will execute the workflow. `development` is intentionally parked: no AWS role has been bootstrapped for it (no dev environment exists yet). When a dev environment is needed, follow the runbook in §1 below.

## When you spin up a dev environment in future

### 1. Bootstrap the dev IAM role

```bash
cd ~/arcadesbox/iac-arcadesbox
aws sso login   # or however you authenticate locally

terraform init
terraform workspace select development || terraform workspace new development

terraform apply -var-file=envs/dev.tfvars \
                -target=aws_iam_role.github_terraform_ci_role \
                -target=aws_iam_role_policy_attachment.github_terraform_ci_admin
```

### 2. Set the resulting ARN as a Secret

```bash
arn=$(terraform output -raw github_terraform_ci_role_arn)
gh secret set AWS_TERRAFORM_ROLE_ARN \
  --env development \
  --repo IP-Quantum-Ltd/iac-arcadesbox \
  --body "$arn"
```

After that, pushes / merges to `dev` will run the workflow against the development workspace.

### Production approval gate (limitation)

GitHub's **Required Reviewers** protection is a paid feature on private repos. The `gh` setup attempted it and was rejected with HTTP 422: "Please ensure the billing plan supports the required reviewers protection rule."

What we have instead:
- `production` Environment is restricted to the `main` branch only (deployment-branch policy, free).
- Branch protection on `main` (you'll set this in repo Settings → Branches) means changes only land on `main` via reviewed PRs.

Practical effect: prod applies will run automatically after merge to `main`. The PR review IS the approval gate. If that's insufficient, options are:

1. Upgrade the org to a plan that includes Environments protection rules on private repos.
2. Add a `workflow_dispatch`-only trigger for prod (replacing the push-to-main trigger), so prod applies require manually clicking "Run workflow."
3. Make the repo public (Required Reviewers is free for public repos).

## Branch protection (recommended)

In repo Settings → Branches, add rules for `dev`, `staging`, and `main`:

- Require pull request before merging
- Require status checks: `terraform fmt`, `Plan (development|staging|production)`
- Require linear history (optional)
- Restrict who can push directly: nobody (force PR flow)

## First end-to-end test

1. Create a feature branch from `dev`, change a comment in any `.tf` file.
2. Open PR targeting `dev`.
3. Confirm `fmt` and `Plan (development)` jobs run, and the plan posts as a sticky comment on the PR.
4. Merge the PR.
5. Confirm `Apply (development)` runs and succeeds.

If that works, repeat the cycle targeting `staging`, then `main` for production.

## Workflow architecture summary

| Branch     | Workspace    | Environment    | Tfvars                  |
|------------|--------------|----------------|-------------------------|
| `dev`      | development  | development    | `envs/dev.tfvars`       |
| `staging`  | staging      | staging        | `envs/staging.tfvars`   |
| `main`     | production   | production     | `envs/prod.tfvars`      |

PRs trigger `plan` only. Pushes (post-merge) trigger `plan` then `apply`. Apply jobs run sequentially per workspace via `concurrency: tf-<workspace>`.
