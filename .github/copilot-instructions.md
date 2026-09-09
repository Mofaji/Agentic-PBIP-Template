# Copilot instructions — PBIP Agentic BI Starter Pack

GitHub Copilot loads this file automatically. It is a digest. **The full rulebook is `copilot-instructions.md` in the repository root — open it before making any change to `Template.Report/` or `Template.SemanticModel/`.**

That file is the final authority. Where it conflicts with this digest, the agent modes in `.github/agents/`, the scoped instructions in `.github/instructions/`, or the skills in `.claude/skills/`, the root rulebook wins.

## Before generating dashboard pages on an initial prompt

Ask the user: `Do you want a Documentation page also?` — then follow the *Mandatory Clarification Question* section of the root rulebook.

## Non-negotiable guardrails

1. Business measures go in `_Measures` only.
2. SVG KPI measures go in `_SVG_Measures` only, named by page (`P1_...`, `P2_...`).
3. SVG backgrounds and custom themes live in `Template.Report/StaticResources/RegisteredResources/` and must be registered in `report.json`.
4. Follow the PBIP schema and property constraints in the root rulebook exactly — including the forbidden properties.
5. Write `.tmdl` as UTF-8 **without BOM**, and never use inline `//` comments in TMDL.
6. Follow the formatting conventions: whole numbers, thousand separators, data labels on, descending sort except time series, Jan→Dec month order.
7. SVG KPI cards use the image visual pattern (`sourceType='imageData'`, measure in `sourceField`).
8. Generate fake CSV data with Python (numpy + pandas), no venv.
9. Never call a page done on JSON validity alone — verify what Power BI actually rendered.
10. Give every measure a `description`.

## Where things live

| | |
| --- | --- |
| Full PBIP rulebook | `copilot-instructions.md` (root) |
| Scoped instructions (`applyTo` globs) | `.github/instructions/*.instructions.md` |
| Agent modes | `.github/agents/*.agent.md` |
| Skills (plain markdown, readable by any agent) | `.claude/skills/*/SKILL.md` |
| Per-dashboard specs | `specs/` — write one before building a new page |
| How the context layers fit together | `docs/AI-CONTEXT.md` |

## Validation

```powershell
powershell -NoProfile -File scripts\validate-json.ps1
powershell -NoProfile -File scripts\validate-pbip.ps1
```

Rendered-output verification runs through the Power BI Desktop Bridge (`scripts\Test-PbipBridge.ps1`, `scripts\Invoke-PbipVerify.ps1`). It is automated for Claude Code via a `Stop` hook; in Copilot, run it yourself and review the PNGs in `tests/screenshots/` against `.claude/skills/powerbi-visual-verify/SKILL.md` before calling a page done.
