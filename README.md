# PBIP Agentic BI Starter Pack

[![Visitors](https://visitor-badge.laobi.icu/badge?page_id=Mofaji.Agentic-PBIP-Template&left_color=green&right_color=blue)](https://github.com/Mofaji/Agentic-PBIP-Template)

This repository is a starter template for agentic BI dashboard development with Power BI PBIP and AI-driven markdown testing.

It combines:
- PBIP report and semantic model scaffolding
- Modeling and performance skill references
- GitHub Actions AI testing on PBIP artifacts
- Contributor and governance templates

## Goals

- Standardize how dashboards are built, reviewed, and tested
- Keep report/model artifacts source-controlled and auditable
- Support AI-assisted dashboard development with clear guardrails
- Provide repeatable test evidence from prompt-based PBIP checks

## Rule Precedence (Final Boss)

For this repository, `copilot-instructions.md` is the final authority for PBIP authoring.

If there is any conflict between:
- skill files in `skills/`
- agent modes in `.github/agents/`
- additional instruction files in `.github/instructions/`

follow `copilot-instructions.md`.

## Repository Structure

- `.github/`: issue/PR templates, AI workflow, ownership
- `skills/`: reusable Power BI modeling and review skills
- `Template.pbip`: PBIP entry point
- `Template.Report/`: report pages, visuals, theme references
- `Template.SemanticModel/`: TMDL-based semantic model files
- `scripts/`: PBIP validation and AI test runner scripts
- `docs/`: operational guidance and rollout checklist
- `tests/`: testing conventions and placeholders

## Non-Negotiable PBIP Guardrails

These are the minimum rules every contributor must follow (full detail is in `copilot-instructions.md`):

1. Create all business measures in `_Measures` only.
2. Create SVG KPI measures in `_SVG_Measures` only, with page-based naming (`P1_...`, `P2_...`).
3. Store SVG backgrounds and custom themes in `Template.Report/StaticResources/RegisteredResources/` and reference them correctly in report metadata.
4. Follow approved PBIP schema/property constraints exactly (visual/page/report JSON shape and forbidden properties).
5. Save all `.tmdl` files as UTF-8 without BOM and avoid inline `//` comments in TMDL.
6. Follow repository formatting conventions for visuals (labels, axis behavior, sorting, month ordering, whole-number defaults).
7. Use image visual pattern for SVG KPI cards (`sourceType='imageData'` with direct measure reference in `sourceField`).
8. If generating fake CSV data, use Python with NumPy and pandas (no venv required).

## Quick Start

1. Copy `.env.example` to `.env` if you want local environment placeholders.
2. Read `copilot-instructions.md` before making model/report changes.
3. Open `Template.pbip` in Power BI Desktop.
4. Build model objects in `Template.SemanticModel/definition/`.
5. Build visuals/pages in `Template.Report/definition/`.
6. Push to `test` branch (or run workflow manually) to execute AI markdown testing.

## Automation Overview

The active automation in this template is AI markdown PBIP testing:
- Workflow: `.github/workflows/ai-testing.yml`
- Trigger: push to `test` branch
- Optional trigger: manual `workflow_dispatch`
- Validation steps before AI execution:
	- `scripts/validate-json.ps1`
	- `scripts/validate-pbip.ps1`
- Runner:
	- `scripts/run-ai-md-test.ps1`

## AI-Based Test Execution

This starter pack includes a markdown-driven AI test prompt and result storage pipeline:

- Prompt: `tests/prompts/PowerBI_Test.md`
- Runner: `scripts/run-ai-md-test.ps1`
- Results: `tests/results/test_results.md` and `tests/results/history/`
- Workflow: `.github/workflows/ai-testing.yml` (runs on `test` branch by default)

To run manually from GitHub Actions, use workflow dispatch and optionally override:
- model
- include_bpa_rules

## Python Data Value Validation

For source-level numeric verification, this starter pack includes an instruction-driven Python validation pattern:

- Prompt: `tests/prompts/Python_Data_Value_Test.md`
- Guidance: `tests/python/README.md`
- Outputs (recommended): `tests/results/python_value_validation.md`, `tests/results/python_value_validation.json`, and history snapshots

Teams create their own preferred Python validator implementation and align it to their SQL platform, coding standards, and governance requirements.

## Required GitHub Configuration

Set these once in repository settings.

### AI Secrets

At least one of these is required for AI execution:
- `GITHUB_MODELS_API_KEY`
- `AZURE_OPENAI_API_KEY`

### Optional Variable

- `AI_TEST_COMMIT_RESULTS=true` to auto-commit generated results on `test`

## What To Add Next

- Real semantic model tables, relationships, and measures
- RLS roles and test personas
- Visual regression checks for critical pages
- Data quality checks against source systems
- Release notes automation for BI changes

Detailed checklist: `docs/STARTER-PACK-CHECKLIST.md` .
 
