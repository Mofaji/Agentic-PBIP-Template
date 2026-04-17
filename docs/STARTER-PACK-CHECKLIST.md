# PBIP Starter Pack Checklist

Use this checklist to evolve this template into a complete agentic BI delivery platform.

## Repository and Governance

- [ ] Branch strategy in place: `feature/*` -> `dev` -> `test` -> `main`
- [ ] Branch protections configured for all long-lived branches
- [ ] CODEOWNERS file added for BI model/report review ownership
- [ ] PR template includes testing and deployment impact checks
- [ ] Issue templates cover bug, feature, and data-quality defects

## Security and Secrets

- [ ] `.env` remains local-only and never committed
- [ ] `.env.example` keeps placeholder values only
- [ ] Fabric credentials stored in GitHub secrets only
- [ ] Workspace and pipeline IDs stored in GitHub variables
- [ ] Production environment has required reviewers and approval gates

## Semantic Model Standards

- [ ] Star schema implemented (clear dimensions and facts)
- [ ] Date table marked and used for time intelligence
- [ ] `_Measures` table added and used for all business measures
- [ ] Key measures have descriptions and format strings
- [ ] RLS roles defined and tested by persona

## Report Standards

- [ ] Theme versioned in source control
- [ ] Page-level layout conventions documented
- [ ] Naming standards for pages and visuals adopted
- [ ] Visual interactions reviewed for performance
- [ ] Accessibility checks completed (contrast, labels, tab order)

## Testing and Quality Gates

- [ ] JSON/PBIP validation in CI
- [ ] PBIP structure validation in CI
- [ ] Placeholder/env template validation in CI
- [ ] Data-quality checks added for critical source metrics
- [ ] Smoke test checklist for each environment

## Deployment and Operations

- [ ] Dev/Test/Prod workspaces mapped in CD variables
- [ ] Deployment scripts updated with tenant-specific API calls
- [ ] Rollback path documented
- [ ] Monitoring dashboard for refresh and query failures configured
- [ ] Incident response checklist available for BI outages

## Agentic BI Enablement

- [ ] Modeling skill prompts aligned to team standards
- [ ] Measure naming and formatting guardrails enforced
- [ ] Prompt templates for common dashboard patterns created
- [ ] PR review guidance includes AI-generated artifact verification
- [ ] Human sign-off required for production semantic model changes
