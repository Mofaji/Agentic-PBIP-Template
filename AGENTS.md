# AGENTS.md

Universal entry point for any coding agent working in this repository. Keep it short — the full rulebook is `copilot-instructions.md`.

## What this repo is

A Power BI PBIP starter template for agentic dashboard development. Reports and semantic models are source-controlled as plain files (`Template.Report/` PBIR JSON, `Template.SemanticModel/` TMDL), built by agents, and verified against what Power BI Desktop actually rendered — not against JSON validity.

## Rule precedence

`copilot-instructions.md` is the final authority for PBIP authoring. Where it conflicts with anything in `.claude/skills/`, `.github/agents/`, `.github/instructions/`, or this file, **it wins**. Read it before touching `Template.Report/` or `Template.SemanticModel/`.

## Non-negotiable guardrails

1. Business measures go in `_Measures` only.
2. SVG KPI measures go in `_SVG_Measures` only, named by page (`P1_...`, `P2_...`).
3. SVG backgrounds and custom themes live in `Template.Report/StaticResources/RegisteredResources/` and must be registered in `report.json`.
4. Follow the PBIP schema and property constraints in `copilot-instructions.md` exactly — including the forbidden properties.
5. Write `.tmdl` as UTF-8 **without BOM**, and never use inline `//` comments in TMDL.
6. Follow the formatting conventions: whole numbers, thousand separators, data labels on, descending sort except time series, Jan→Dec month order.
7. SVG KPI cards use the image visual pattern (`sourceType='imageData'`, measure in `sourceField`).
8. Generate fake CSV data with Python (numpy + pandas), no venv.
9. Never call a page done on JSON validity alone — verify the rendered screenshot against `.claude/skills/powerbi-visual-verify/SKILL.md`.
10. Give every measure a `description`. The model is context for the next agent and for Copilot/data agents; an undocumented measure is a measure someone will duplicate.

## How work is organised

Three layers, deliberately separate. `docs/AI-CONTEXT.md` explains why.

| Layer | Answers | Where |
| --- | --- | --- |
| **Steering** | How we always build | `copilot-instructions.md` (rulebook), this file, `CLAUDE.md`, `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md` |
| **Specs** | What we are building, this once | `specs/` — one file per dashboard or page |
| **Hooks** | What runs automatically, and when | `.claude/settings.json` → `scripts/hooks/` |

**Write a spec before building a new dashboard or page.** Copy `specs/TEMPLATE.md`, fill it in, build against it. When the page renders clean, fold any rule that will apply to the *next* dashboard back into `copilot-instructions.md` and let the spec go stale — specs are disposable, steering is not.

## Verification is part of building

Every report or model edit ends in the Desktop Bridge loop:

```
edit PBIR/TMDL → validate → reload Desktop → screenshot every page → review PNGs → fix
```

A `Stop` hook runs it automatically and blocks the turn until the screenshots have been reviewed. Preflight with `powershell -NoProfile -File scripts\Test-PbipBridge.ps1`. If the bridge is unavailable the loop fails open — say the report was not visually verified rather than claiming it renders correctly.

On a **first build**, Power BI Desktop often refuses to load the PBIP at all and leaves the window on *Untitled*. That is a load error, not a broken bridge, and *continue with errors* is not a fix. The bridge cannot read that dialog — run `scripts\Test-PbipSemantics.ps1` to find the cause in the source. See *Known caveats* in `.claude/skills/powerbi-visual-verify/SKILL.md`.

## Before you finish

- `powershell -NoProfile -File scripts\validate-json.ps1`
- `powershell -NoProfile -File scripts\validate-pbip.ps1`
- `powershell -NoProfile -File scripts\Test-PbipSemantics.ps1` — the load-time errors Desktop reports as a dialog, found in source
- Screenshots reviewed, findings reported by page **display name** (not page id).
