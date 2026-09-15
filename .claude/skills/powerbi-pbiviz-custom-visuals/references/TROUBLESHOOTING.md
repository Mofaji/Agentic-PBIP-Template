# Troubleshooting

Every entry here cost a debugging round on a real build. Symptom first.

---

## Build (`pbiviz package`)

| Symptom | Cause | Fix |
| --- | --- | --- |
| `error Create certificate error: 'pwsh' is not recognized` | Dev-server certificate generation needs PowerShell 7 | **Ignore.** It only affects `pbiviz start`; packaging still completes ("Build completed successfully"). |
| `TS2307 Cannot find module 'powerbi-visuals-api'` in shared code | Shared TS imported across projects | Import from `./shared/...`; let `sync-visuals.mjs` copy `visuals/shared` into `src/shared` |
| `TS2307` or empty `powerbi-visuals-api` typings after copying `node_modules` | The copy filtered out `src/` directories (the API package keeps its typings in `node_modules/powerbi-visuals-api/src/`) | Copy `node_modules` with no ignore patterns (`new_visual.py --node-modules-from` does this) |
| Lint fails on `innerHTML` / `outerHTML` / `eval` | `eslint-plugin-powerbi-visuals` forbids them | Build DOM with `shared/dom.ts` (`el`, `svg`, `svgText`, `textContent`) |
| Packaging refuses: author / supportUrl missing | `pbiviz.json` placeholders not filled | Ask the user for author name + email; `new_visual.py` requires them |
| "Visual doesn't support some features recommended…" | Informational list (keyboard, high contrast, landing page…) | Not a failure. Address only if the client needs certification. |
| `cannot remove … node_modules: Device or resource busy` | A shell's working directory is inside that folder | `cd` out and retry |

## Embedding

| Symptom | Cause | Fix |
| --- | --- | --- |
| Visual is an empty box, no error | `visualType` GUID not registered in `report.json` | `node tools/sync-visuals.mjs --check`; `scripts/validate-pbip.ps1` |
| Code change has no effect in Desktop | Bundle cached by guid+version | Sync bumps the version; then **close and reopen** Desktop (reload is not enough) |
| `guid drift` from sync | `pbiviz.json` GUID edited, or two projects share a name | Restore the GUID from `tools/visuals.json`. Never regenerate it. |
| `validate-pbip.ps1`: "Missing CustomVisual resource package item" under `StaticResources` | Old validator | This template's validator resolves `CustomVisuals/<guid>/resources/` |
| `validate-json.ps1` fails on `globals.json`, `package-lock.json`, `tsconfig.json` | Old validator scanning `node_modules` / JSONC | This template's validator excludes them |
| Edits vanish after running sync | Desktop was open and saved over the files | Close Desktop before syncing |

## Binding (`visual.json`)

| Symptom | Cause | Fix |
| --- | --- | --- |
| Visual shows "Add a category…" although fields are bound | `queryState` key is a display name or old role (`Values`, `Category`) instead of `dataRoles[].name` | `check_against_capabilities()` |
| Format setting ignored | Property not in `capabilities.json > objects`, or wrong literal suffix (`11` instead of `11D`) | Declare it; see literal encoding table |
| Hierarchy levels reversed | Projection order in the role | Order projections outer → inner |
| Rows alphabetical instead of statement order | No `rowOrder` indices bound | Bind index columns per level |
| Subtotals wrong for % or average measures | `table` mapping sums in the visual | Bind additive measures only; compute ratios from components, or use a `matrix` mapping |
| Numbers differ from the old visual | Page-level filters dropped, or visual-level filters not carried over | Keep page filters; copy non-date visual filters |

## Rendering and data

| Symptom | Cause | Fix |
| --- | --- | --- |
| Blank page in a screenshot, other pages fine | Captured during recalculation or first render | Wait, capture again; do not "fix" a timing artefact |
| Month/year label one year off, or KPI shows "–" on a YTD page | A month-number slicer spans every year in the date table, so `MAX(Date)` lands in a year with no data | Bound dates by months with data: `MAXX(FILTER(VALUES(Dates[Date]), NOT ISBLANK([Measure])), Dates[Date])` |
| Percent labels clipped at column edge | Label room too small for `+171.1%` | Reserve ≥ 60 px beyond the axis in pin columns |
| Long labels truncated with `…` | Label column too narrow | Widen (≥ 210 px for cash-flow line names) or accept truncation with a tooltip |
| Tooltip or selection selects too little | Selection IDs built from one row of an aggregated mark | Build IDs for every underlying row |

## Model-side changes around custom visuals

| Symptom | Cause | Fix |
| --- | --- | --- |
| New calculated **table** stays empty after open | Desktop does not process a new or changed calculated partition from TMDL; external TMSL `refresh` against the Desktop engine returns success but does nothing | Avoid new calculated tables where possible (a calculated **column** on an existing table is computed on open), or have the user refresh/save once in Desktop |
| Changed measure expression not picked up | `file.reload` does not reliably re-apply TMDL | Close and reopen Desktop |
| Refresh impossible | Source files or cloud sources unreachable from this machine | Keep every change calculated; never convert an import table to depend on a refresh |
