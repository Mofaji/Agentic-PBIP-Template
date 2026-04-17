# CI/CD Setup for Dev -> Test -> Prod

This repository includes template-safe CI/CD for Power BI PBIP projects:
- CI validates pull requests.
- CD deployments are manual to avoid automatic deploy failures in newly cloned template repos.

## Deployment Model

- Pull requests into `dev`, `test`, and `main` run CI validation.
- Deployments to `dev`, `test`, and `prod` are triggered manually using `workflow_dispatch` in `.github/workflows/cd.yml`.
- Use `target_environment` and `git_ref` inputs when running CD.

## 1. Create Branches

Create and protect these long-lived branches:
- `dev`
- `test`
- `main`

Recommended pull-request path:
- Feature work -> `dev`
- Release candidate -> `test`
- Production release -> `main`

## 2. Configure GitHub Environments

Create GitHub environments with these names:
- `dev`
- `test`
- `prod`

Recommended protections:
- Required reviewers for `test` and `prod`
- Prevent self-approval for production
- Optional wait timer for production

## 3. Add Secrets

Repository or environment secrets:
- `FABRIC_TENANT_ID`
- `FABRIC_CLIENT_ID`
- `FABRIC_CLIENT_SECRET`

The service principal should have access to the corresponding Power BI workspaces.

## 4. Add Variables

Repository or environment variables:
- `PBI_WORKSPACE_ID_DEV`
- `PBI_WORKSPACE_ID_TEST`
- `PBI_WORKSPACE_ID_PROD`
- `PBI_DEPLOYMENT_PIPELINE_ID` (optional)

## 5. Configure Branch Protection Rules

For `dev`, `test`, and `main`:
- Require pull request before merge
- Require status checks from CI
- Require at least one reviewer (`test` and `main` should be stricter)
- Dismiss stale reviews when new commits are pushed

## 6. Validate the End-to-End Flow

1. Create a feature branch and open PR to `dev`.
2. Confirm CI passes.
3. Merge PR, then run CD manually for `dev` (select `git_ref=dev` or commit SHA).
4. Open PR from `dev` to `test`, confirm CI passes, then run CD manually for `test`.
5. Open PR from `test` to `main`, confirm CI passes, then run CD manually for `prod`.

## 7. Optional Hardening

- Add secret scanning (Gitleaks or GitHub Advanced Security)
- Add semantic model linting scripts
- Add report regression screenshots as build artifacts
- Add release notes automation for dashboard changes

## 8. AI Markdown Testing in Test Stage

This starter pack includes prompt-based AI testing from:
- `tests/prompts/PowerBI_Test.md`

Workflow:
- `.github/workflows/ai-testing.yml`

Default behavior:
- Runs on push to `test`
- Executes `scripts/run-ai-md-test.ps1`
- Stores outputs in `tests/results/`
- Uploads `tests/results/**` as artifacts

Required secret (at least one):
- `GITHUB_MODELS_API_KEY`
- `AZURE_OPENAI_API_KEY`

Optional variable:
- `AI_TEST_COMMIT_RESULTS=true` to auto-commit generated results back to `test`

Manual run support:
- Use `workflow_dispatch` to pick a model and BPA inclusion mode.

## 9. Python Data-Value Validation in Test Stage

For SQL-backed metric verification, use:
- Prompt: `tests/prompts/Python_Data_Value_Test.md`
- Guidance: `tests/python/README.md`

This starter pack intentionally does not ship one fixed validator script. Each team should implement its preferred Python validator in `tests/python/`.

Typical command:

```powershell
python tests/python/<your_script_name>.py --branch ABV --month March --year 2026
```

If credentials are unavailable:

```powershell
python tests/python/<your_script_name>.py --branch ABV --month March --year 2026 --dry-run
```

Required SQL environment variables (local `.env` or pipeline secrets):
- `SERVER`
- `DATABASE`
- `USERNAME`
- `PASSWORD`
- `DRIVER`

Output artifacts are written to `tests/results/`.
