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
- skill files in `.claude/skills/`
- agent modes in `.github/agents/`
- additional instruction files in `.github/instructions/`
- the steering digests (`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`)

follow `copilot-instructions.md`.

The three digests exist because no harness auto-loads a file called `copilot-instructions.md` from the repository root: Claude Code reads `CLAUDE.md`, GitHub Copilot reads `.github/copilot-instructions.md`, and `AGENTS.md` is the cross-vendor convention. Each carries the guardrails and points here for the detail. How the whole context system fits together is in [`docs/AI-CONTEXT.md`](docs/AI-CONTEXT.md).

## Repository Structure

- `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`: steering digests that auto-load per harness
- `specs/`: one spec per dashboard or page, written before the build ([`specs/README.md`](specs/README.md))
- `.github/`: issue/PR templates, AI workflow, ownership
- `.claude/`: Claude Code settings, including the visual verification `Stop` hook
- `.claude/skills/`: reusable Power BI skills, auto-discovered by Claude Code
  - `powerbi-modeling/`, `power-bi-model-design-review/`, `power-bi-performance-troubleshooting/`
  - `powerbi-fieldparameter/`: field-parameter page builder (table + bar chart, bookmarks, toggles)
  - `powerbi-dashboard-header/`: standard header band and page chrome
  - `powerbi-visual-verify/`: rendered-screenshot review checklist
- `Template.pbip`: PBIP entry point
- `Template.Report/`: report pages, visuals, theme references
- `Template.SemanticModel/`: TMDL-based semantic model files
- `scripts/`: PBIP validation, AI test runner, Desktop Bridge verification, and hook implementations
- `docs/`: operational guidance, rollout checklist, and [`AI-CONTEXT.md`](docs/AI-CONTEXT.md) (how steering, specs, and hooks fit together)
- `tests/`: testing conventions and placeholders (`tests/screenshots/` is generated and gitignored)
- `python/`: standalone Python utilities for data validation, automated email reporting, and DB alert notifications
  - `python/db_alerts/`: DB-triggered alert email builder (Outlook-safe HTML, `.env` credentials pattern)
  - `python/email_reporting/`: Power BI page replication email reports with DAX-to-Python validation protocol

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
9. Never call a page done on JSON validity alone — verify the rendered screenshot against `.claude/skills/powerbi-visual-verify/SKILL.md`.
10. Give every measure a `///` description in TMDL. The model is context for the next agent and for Copilot; an undocumented measure is one someone will duplicate.

## Quick Start

1. Copy `.env.example` to `.env` if you want local environment placeholders.
2. Read `copilot-instructions.md` before making model/report changes.
3. Open `Template.pbip` in Power BI Desktop.
4. Write a spec for what you are about to build — copy [`specs/TEMPLATE.md`](specs/TEMPLATE.md). Required for a new dashboard, page, or fact table.
5. Build model objects in `Template.SemanticModel/definition/`.
6. Build visuals/pages in `Template.Report/definition/`.
7. Verify what actually rendered — see [Visual Verification](#visual-verification-power-bi-desktop-bridge). Confirm your setup once with `powershell -NoProfile -File scripts\Test-PbipBridge.ps1`.
8. Push to `test` branch (or run workflow manually) to execute AI markdown testing.

## Agent Context Layers

Three layers, deliberately separate. Full rationale in [`docs/AI-CONTEXT.md`](docs/AI-CONTEXT.md).

| Layer | Answers | Lives in | Loads |
| --- | --- | --- | --- |
| **Steering** | How we always build | `copilot-instructions.md` (rulebook) + `AGENTS.md` / `CLAUDE.md` / `.github/copilot-instructions.md` digests + `.claude/skills/` | Automatically, every session |
| **Specs** | What we build this once | `specs/` — one file per dashboard or page | On demand, for one task |
| **Hooks** | What runs regardless | `.claude/settings.json` → `scripts/hooks/` | On harness events |

Hooks in this template (Claude Code; all fail open by design):

| Event | Script | Enforces |
| --- | --- | --- |
| `SessionStart` | `pbip-session-brief.ps1` | Guardrails and live bridge status are in context before the first prompt |
| `PreToolUse` | `pbip-write-guard.ps1` | No writes to `Proposals/`, `**/.pbi/`, `tests/screenshots/`, `.claude/.pbip-state/` |
| `PostToolUse` | `pbip-validate-hook.ps1` | Every PBIP JSON written parses; TMDL carries no BOM, no `//` comments, and no measure/column name collision |
| `Stop` | `pbip-stop-hook.ps1` | The turn cannot end until rendered screenshots have been reviewed |

The `PostToolUse` validator matters most on a first build: malformed JSON or a BOM'd TMDL is exactly what makes Power BI Desktop refuse to open the PBIP, and it catches that at the moment of writing rather than at the error dialog.

## Visual Verification (Power BI Desktop Bridge)

Valid PBIR still renders wrong — a chart overlapping its SVG card title, truncated labels, a blank visual, stale theme colors. None of that is visible to JSON validation. This template closes the loop by driving a running Power BI Desktop and reviewing what it actually drew:

```
edit PBIR/TMDL → validate → reload → screenshot every page → review → fix → repeat
```

A `Stop` hook runs this automatically when the agent tries to end its turn, and blocks until the rendered pages have been reviewed against `.claude/skills/powerbi-visual-verify/SKILL.md`. Screenshots go to `tests/screenshots/` (gitignored).

**Requires Power BI Desktop 2.155.756.0 (June 2026) or later** — below that build the Desktop Bridge does not exist. Enable *File > Options and settings > Options > Preview features > Enable external tool access to Power BI Desktop through secure local APIs*, then:

```bash
npm install -g @microsoft/powerbi-desktop-bridge-cli@latest      # powerbi-desktop
npm install -g @microsoft/powerbi-report-authoring-cli@latest    # powerbi-report-author
```

| Script | Purpose |
| --- | --- |
| `scripts/Test-PbipBridge.ps1` | Preflight: version, bridge pipe, CLIs, matching instance, semantic + PBIR validity |
| `scripts/Test-PbipSemantics.ps1` | The load-time errors Desktop reports as a dialog, found in source |
| `scripts/Get-PbipLoadError.ps1` | Reads Desktop's load-error dialog when one appears — its text, its "Copy details to clipboard" content, and a cropped PNG |
| `scripts/Invoke-PbipVerify.ps1` | The loop: validate → semantics → wait for load (30s) → reload → screenshot-all → page manifest |
| `scripts/Invoke-PbipRefresh.ps1` | Triggers a data refresh via UI automation — the bridge has no refresh method, and a freshly generated PBIP renders empty until refreshed once |
| `scripts/hooks/pbip-stop-hook.ps1` | `Stop` hook wrapper with change detection and fix budget |
| `scripts/PbipBridge.Common.ps1` | Shared helpers |

Design notes worth knowing before you rely on it:

- **Fix budget is one round** — at most two blocks per turn (review + fix, then confirm + report).
- **Change detection is by content hash**, not by tool call, so edits written by Python build scripts are caught too. Nothing changed means Power BI is never touched.
- **The loop fails open.** No Desktop, no bridge, no CLI — the turn ends with a skip notice rather than trapping the session.
- **Load errors are caught in source, not scraped off the screen.** The bridge cannot read Desktop's "Issues were found" dialog — during a failed load there is no report to serve the API. `scripts/Test-PbipSemantics.ps1` finds that class of error before Desktop ever sees the file: measure/column name collisions, duplicate measure names, relationship endpoints that do not exist, unresolved `'Table'[Column]` references, resource items referenced but never registered, duplicate page ids. It runs in the verify loop before Desktop is touched, and file-local checks run on every edit via the `PostToolUse` hook.
- **The loop waits 30 seconds for a load, then says which failure it was** — `not_running`, `no_bridge`, `other_project` (it names what *is* open), or `load_failed`. Only the last blocks the turn: a rejected definition is a defect, not an outage.
- **On `load_failed` it reads Desktop's error dialog** — text, the "Copy details to clipboard" diagnostic (which carries the offending file and line), and a cropped PNG. That is usually enough to fix the source directly.
- **It recovers from a load failure on its own** — capture the dialog, dismiss it, close the spent instance, reopen, retry. The order is deliberate: `powerbi-desktop open` starts a *new* instance rather than reusing the running one, so the failed window has to be gone before the reopen. Two guarantees keep that safe — the reopen is **net-zero on failure** (the running-instance count returns to what it was, and anything it starts it also closes), and it only ever closes an instance it started itself or one that was showing a load-error dialog, never an arbitrary *Untitled* window that might hold unsaved work. `-NoReopen` turns the recovery off.
- **A first-run report may not open at all.** Power BI Desktop can reject a freshly generated PBIP with an error dialog and leave the window on *Untitled* — the modal blocks the bridge, and *continue with errors* opens the report with the failing parts dropped, so the screenshots lie. Dismiss it, fix the reported PBIR/TMDL error, reopen, and confirm `powerbi-desktop status` shows the project path. Details in `.claude/skills/powerbi-visual-verify/SKILL.md`.
- **Theme JSON is cached by Desktop.** After editing a theme, rename it with a new suffix and update its `report.json` registration, or reopen Desktop; a plain reload shows stale colors.

Run it manually with `powershell -NoProfile -File scripts\Invoke-PbipVerify.ps1 -Mode Review`. Full detail is in `copilot-instructions.md`.

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
- Guidance: `python/README.md`
- Outputs (recommended): `tests/results/python_value_validation.md`, `tests/results/python_value_validation.json`, and history snapshots

Teams create their own preferred Python validator implementation and align it to their SQL platform, coding standards, and governance requirements.

## Python Email Reporting & Alerts

The `python/` folder contains standalone utilities for automated reporting and alerting outside of the PBIP test pipeline:

### Email Reporting
- Folder: `python/email_reporting/`
- Style & DAX-to-Python validation guide: `python/email_reporting/emal_style_instructions.md`
- Replicates Power BI report pages as Outlook-safe HTML emails using Python + pandas
- Follow the mandatory DAX-to-Python validation protocol in the style guide before implementing any metric

### DB Alert Emails
- Folder: `python/db_alerts/`
- Build instructions: `python/db_alerts/ALERT_EMAIL_INSTRUCTIONS.md`
- General-purpose DB-triggered alert email builder (pyodbc, Outlook-safe HTML, `.env` credentials)
- Never hardcode credentials — use `.env` with `python-dotenv`

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
 
