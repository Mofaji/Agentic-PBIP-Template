---
name: powerbi-pbiviz-custom-visuals
description: 'Builds Power BI custom visuals as .pbiviz projects the team owns and embeds them into a PBIP report so it opens complete with no import and no licence - scaffold from starter templates (IBCS variance/statement table, variance period chart, blank skeleton), shared TypeScript library, build/embed/register pipeline, visual.json bindings, validation and Desktop Bridge verification. Use when a native visual cannot do the job, when replacing expired or unlicensed third-party marketplace visuals, when replicating a visual from a screenshot, or when the user mentions pbiviz, custom visual, CustomVisuals folder, capabilities.json or an IBCS table/chart.'
---

# Power BI custom visuals (`.pbiviz`) for PBIP

Builds custom visuals as source-controlled `pbiviz` projects inside the dashboard repo, embeds their bundles into `<Project>.Report/CustomVisuals/`, and binds them from `visual.json`. The report then renders on any machine with nothing to install and no third-party licence.

The starter kit is working code from real dashboard builds, generalised and stripped of client specifics.

## Precedence

`copilot-instructions.md` stays the final authority for everything in `*.Report/` and `*.SemanticModel/`: schemas, forbidden properties, TMDL rules, the SVG canvas pattern. This skill adds the custom-visual layer on top. Where it deliberately deviates, it says so and the deviation goes into the spec (*Exceptions requested*).

`.github/instructions/power-bi-custom-visuals-development.instructions.md` is the generic React/D3 reference. Use it for visual-internal techniques. Use **this skill** for anything touching PBIP: scaffolding, embedding, binding, verification.

## When to use / when not

Use it when:

- a native visual cannot express the design (IBCS variance tables, running P&L results, variance strips, custom statement layouts)
- a report depends on a third-party marketplace visual that is expired, unlicensed or not approved. Follow [references/REPLACING-LICENSED-VISUALS.md](references/REPLACING-LICENSED-VISUALS.md).
- the user asks for a pbiviz or custom visual, or to replicate a visual from a screenshot

Do **not** use it when a native visual with formatting, or an SVG measure in an image visual (rulebook pattern), gets there. A custom visual is code to maintain. Say so if the request does not need one.

---

## Mandatory questions: ask before building

Ask in one round and wait for the answers. Do not scaffold on assumptions.

1. **Purpose and reference.** What should the visual show and what decision does it support? Is there a reference screenshot, an existing licensed visual to replace, or a mockup? If it is a replacement, which pages and visuals?
2. **Interactivity level.** Default is **interactive**: tooltips, click cross-filter, Ctrl multi-select, highlight, expand/collapse where relevant. Confirm, or accept "static replica".
3. **Author for `pbiviz.json`.** Name and email. Packaging refuses without them, and there is no default.

Ask as well when the answer is not already in the spec or the conversation:

4. The fields and measures for each data role, plus the reconciliation numbers (e.g. "full-year revenue total").
5. Number format and units (EUR K? 1-dp percent?). This is an exception to the house rules and must be recorded.
6. Brand accent colour (or permission to sample it from the logo).
7. The desired visual name (camelCase, becomes the GUID prefix and can never change).

---

## Workflow

```
0 spec → 1 preflight → 2 scaffold → 3 capabilities → 4 implement → 5 build + embed
      → 6 bind visual.json → 7 validate → 8 open in Desktop + screenshot → 9 fold back
```

### 0. Spec

Copy `specs/TEMPLATE.md`. For each custom visual record: roles → fields, objects you will set, computed logic (running totals, ratio rows…), interactivity, sizing, exceptions. For a replacement, add the old-to-new mapping table (see the playbook).

### 1. Preflight

```powershell
node --version                          # >= 18
pbiviz --version                        # powerbi-visuals-tools; install: npm i -g powerbi-visuals-tools
powershell -NoProfile -File scripts\Test-PbipBridge.ps1
powerbi-desktop status                  # Desktop must NOT have the project open while syncing
```

The report must be **PBIR** (`<Project>.Report/definition/pages/...`). A `.pbix` or legacy report has to be saved as PBIP by the user first (playbook, step 0).

### 2. Scaffold

```powershell
python .claude\skills\powerbi-pbiviz-custom-visuals\assets\tools\new_visual.py `
  --name finVarianceTable --template varianceTable `
  --display "Variance Table" --description "IBCS statement table" `
  --author-name "<from question 3>" --author-email "<from question 3>"
```

- Templates: `varianceTable`, `varianceChart`, `blank`. See [references/TEMPLATES.md](references/TEMPLATES.md).
- First run in a repo also installs `visuals/shared/`, `tools/sync-visuals.mjs` and `tools/pbir_helpers.py`. It creates `tools/visuals.json` too.
- Runs `npm install`. **Offline:** add `--node-modules-from <path to an existing visual project>`. The copy must not filter `src/` folders.
- Add to the **dashboard repo's** `.gitignore`: `visuals/*/node_modules/`, `visuals/*/dist/`, `visuals/*/.tmp/`, `visuals/*/src/shared/`.
- Set the client accent in `visuals/shared/tokens.ts` and `visuals/shared/base.less`.

### 3. Capabilities

Edit `visuals/<name>/capabilities.json`: roles, mapping, conditions with `max`, objects. See [references/CAPABILITIES-AND-DATAVIEW.md](references/CAPABILITIES-AND-DATAVIEW.md).

Role names are permanent once a report binds them.

### 4. Implement

Edit `visuals/<name>/src/visual.ts` and `style/visual.less`.

- Parse by role, never by column position.
- Keep a `PropSpec` per Format pane card in step with capabilities: [references/FORMATTING-PANE.md](references/FORMATTING-PANE.md).
- Wire the interactions: [references/INTERACTIVITY.md](references/INTERACTIVITY.md).
- Follow the design conventions (chrome, IBCS, numbers, empty states): [references/DESIGN-IBCS.md](references/DESIGN-IBCS.md).
- Edit shared code only in `visuals/shared/`. `src/shared/` is overwritten on every build.

### 5. Build and embed

```powershell
node tools\sync-visuals.mjs                    # all visuals
node tools\sync-visuals.mjs --only finVarianceTable
```

Per visual this copies the shared code, bumps the build number, runs `pbiviz package --resources`, byte-copies the payload into `CustomVisuals/<guid>/`, registers the GUID in `report.json`, and verifies every guid-shaped `visualType` is registered.

A TypeScript or lint error stops the build here. The `pwsh` certificate error is harmless. Details: [references/PBIP-EMBEDDING.md](references/PBIP-EMBEDDING.md).

### 6. Bind in `visual.json`

Prefer the page's Python build script. Use `tools/pbir_helpers.py`:

```python
from pbir_helpers import *
G = load_guids()                          # tools/visuals.json, keyed by --name
v = custom_visual(name, G["finVarianceTable"], x, y, w, h, z,
                  roles={"rows": [col(...), col(...)], "ac": [meas(..., display="AC")]},
                  objects={"display": props(unit=s("K"))},
                  filters=[categorical_filter("fYear", "Dates", "Year", [2025])])
check_against_capabilities(v, "visuals/finVarianceTable/capabilities.json")
write_json(path, v)
```

- Position the visual inside its canvas card at `card_y + 30` or lower.
- Set `page.json > visualInteractions` where a slicer must **not** filter a trend chart.
- Remove replaced GUIDs from `publicCustomVisuals`.
- If the script owns whole pages, it must be **idempotent** and must **preserve visuals it does not own**. Users add branding in Desktop between runs.

### 7. Validate

```powershell
powershell -NoProfile -File scripts\validate-json.ps1
powershell -NoProfile -File scripts\validate-pbip.ps1
powershell -NoProfile -File scripts\Test-PbipSemantics.ps1
node tools\sync-visuals.mjs --check
powerbi-report-author validate "<Project>.pbip"      # 'PBIR_VISUAL_TYPE_UNKNOWN' warnings for your GUIDs are expected
```

### 8. Open in Desktop and verify

```powershell
powerbi-desktop open "<Project>.pbip"     # close any running instance of the project first
powerbi-desktop status                    # currentFilePath = the project
```

Screenshot every page and review with the `powerbi-visual-verify` skill (the Stop hook runs the loop).

Checks specific to custom visuals:

- no empty boxes
- no licence or vendor overlays
- labels not clipped at column edges
- the reconciliation numbers match
- interactions behave: expand, cross-filter, clear

After a bundle change, **reopen** Desktop; reload serves the cached bundle. A page that comes back blank while others render is usually a capture during recalculation. Capture it again before changing code. More in [references/TROUBLESHOOTING.md](references/TROUBLESHOOTING.md).

### 9. Fold back

Move any rule that will matter for the next report into `copilot-instructions.md` or this skill, as the spec's *Fold-back* section asks.

---

## Hard rules

1. **A GUID never changes** once bound. Rename with `displayName` only.
2. `queryState` keys = `dataRoles[].name`; `objects` = declared capabilities objects. Check with `check_against_capabilities`.
3. **Desktop closed** while running `sync-visuals.mjs`; **reopen** Desktop after syncing.
4. Byte-copy `.pbiviz.json` payloads; never re-serialise them.
5. No `innerHTML`, no external network (`privileges: []`), no vendor branding or licence imagery.
6. Visual containers suppress PBI chrome; the canvas draws cards and titles.
7. Additive measures only in `table`-mapped visuals that aggregate in code; ratios are computed from components.
8. Never replicate a licensed visual's popup, logo or patent strip. Drop hardcoded date filters; keep non-date visual filters and all page filters.
9. Interactive by default; call `renderingStarted/Finished/Failed` in every `update`.
10. Never call a visual done on a successful build. Only the reviewed Desktop screenshot counts.

## Starter kit

| Path (under `assets/`) | What it is |
| --- | --- |
| `tools/new_visual.py` | Scaffold a visual: template copy, GUID, `visuals.json`, shared lib, deps |
| `tools/sync-visuals.mjs` | Build → embed → register → verify (auto-detects the `.pbip`) |
| `tools/pbir_helpers.py` | `visual.json` builders, literal encoders, filters, capabilities check |
| `shared/` | `tokens.ts` (neutral + IBCS), `dom.ts`, `format.ts`, `props.ts`, `interaction.ts`, `scale.ts`, `text.ts`, `paths.ts`, `base.less` |
| `project/` | `pbiviz.json` (placeholders), `package.json`, `tsconfig.json`, `eslint.config.mjs`, `assets/icon.png` |
| `templates/varianceTable/` | IBCS statement table: variance and cross-tab layouts, running results, ratio rows |
| `templates/varianceChart/` | IBCS period chart: columns/line/area, variance strip |
| `templates/blank/` | Minimal skeleton showing every required pattern |

Pinned versions: `powerbi-visuals-tools` 7.x, `powerbi-visuals-api` 5.11.1, `powerbi-visuals-utils-formattingmodel` 6.0.4, TypeScript 5.5.4. Verified with Power BI Desktop 2.157.879.0 (`visualContainer` schema 2.12.0).

## References

| File | Read when |
| --- | --- |
| [references/PBIP-EMBEDDING.md](references/PBIP-EMBEDDING.md) | Payload, registration, `visual.json`, version cache, repo layout |
| [references/CAPABILITIES-AND-DATAVIEW.md](references/CAPABILITIES-AND-DATAVIEW.md) | Designing roles and mappings, reading the dataView, highlights |
| [references/FORMATTING-PANE.md](references/FORMATTING-PANE.md) | Adding Format pane properties and setting them from build scripts |
| [references/INTERACTIVITY.md](references/INTERACTIVITY.md) | Selection IDs, tooltips, expand/collapse state, page interactions |
| [references/DESIGN-IBCS.md](references/DESIGN-IBCS.md) | Tokens, IBCS conventions, number formats, empty states |
| [references/TEMPLATES.md](references/TEMPLATES.md) | Template roles/objects, behaviour, sizing, example bindings |
| [references/REPLACING-LICENSED-VISUALS.md](references/REPLACING-LICENSED-VISUALS.md) | Replacing third-party marketplace visuals end to end |
| [references/TROUBLESHOOTING.md](references/TROUBLESHOOTING.md) | Any build, embed, binding or rendering failure |

## Definition of done

- [ ] Mandatory questions answered; spec written with role mapping and exceptions
- [ ] `sync-visuals.mjs` builds every visual; `--check` passes
- [ ] `validate-json`, `validate-pbip`, `Test-PbipSemantics`, `powerbi-report-author validate` show no errors
- [ ] Desktop opens the project with no dialog; every page screenshot reviewed by **display name**
- [ ] Reconciliation numbers match; no empty boxes, overlays, clipped labels
- [ ] Replaced third-party GUIDs gone from `publicCustomVisuals` and all `visual.json`
- [ ] Dashboard repo `.gitignore` excludes `node_modules`, `dist`, `.tmp`, `src/shared`
