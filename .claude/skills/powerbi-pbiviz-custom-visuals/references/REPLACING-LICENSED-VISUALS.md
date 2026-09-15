# Playbook: replacing licensed third-party visuals

For reports built on third-party marketplace visuals whose licence expired or cannot be bought. The goal is a report that renders everything with **visuals your team owns**, keeps the author's field bindings and filters, and needs no licence.

Proven on real dashboards: drill-down charts and IBCS-style variance tables/charts replaced with owned visuals.

---

## 0. Get the report into PBIR

Licensed-visual reports usually arrive as `.pbix`. An agent cannot drive *Save As*, so ask the user to:

1. Enable *Options → Preview features → Store reports using enhanced metadata format (PBIR)*
2. *File → Save As → Power BI Project (.pbip)* into the repo
3. Confirm with `powerbi-desktop status` (the `reportDir` must be set)

Before that, screenshot the PBIX (`powerbi-desktop open "<file>.pbix"`, then `powerbi-desktop screenshot <pageId>`). Page IDs for a legacy `.pbix` come from `Report/Layout` inside the zip (UTF-16 JSON, `sections[].name`). Those screenshots are the "before" record, licence popups included.

## 1. Inventory

List every visual whose `visualType` is not built in, with its page, position, bindings and filters:

```python
for vj in glob("<Project>.Report/definition/pages/*/visuals/*/visual.json"):
    v = json.load(open(vj, encoding="utf-8")); vis = v["visual"]
    print(page_display_name, v["name"], vis["visualType"], v["position"],
          {role: [p["queryRef"] for p in st["projections"]] for role, st in vis.get("query", {}).get("queryState", {}).items()},
          [f["field"] for f in v.get("filterConfig", {}).get("filters", [])])
```

Also record `report.json > publicCustomVisuals` (the third-party GUIDs) and the page-level filters. Those shape the numbers and must survive untouched.

Identify each third-party visual from its GUID in `publicCustomVisuals` and its data roles; do not rely on the GUID prefix alone.

## 2. Map roles, don't re-model

For each licensed visual, write a row in the spec:

| Page | Old visual (type) | Old roles → fields | New visual | New roles |
| --- | --- | --- | --- | --- |
| Monthly P&L | third-party table | `Category`: Level 1, Level 2 · `Values`: Actual · `PreviousYear`: Actual PM · `Group`: Date | varianceTable | `rows`: Level 1, Level 2 · `rowOrder`: Level 1 idx, Level 2 idx · `ac` · `pm` |

- **Reuse the existing measures and columns.** The replacement is frontend work. New display-only measures go in `_SVG_Measures` / `_Measures` per the rulebook, never into the source tables.
- Note what the licensed visual computed **itself**, because the data will not contain it: running P&L results, calculated "%" rows, invert-for-costs colouring, drill levels. The replacement must reimplement these (the variance table's `groupTotal: running` + `showRatios`).
- A queryRef naming a table that no longer exists (`Old Table.Level 1` while the field points at `Account Hierarchy`) is harmless. The `field` expression is authoritative.

## 3. Profile the data before designing

Query the local model (port from `%LOCALAPPDATA%\Microsoft\Power BI Desktop\AnalysisServicesWorkspaces\*\Data\msmdsrv.port.txt`, `Provider=MSOLAP;Data Source=localhost:<port>`). Check:

- the date range that actually has data. It is often narrower than the date table, which then produces empty months or years.
- the statement structure tables (levels, index columns, sign conventions: revenue positive, costs negative?)
- one reconciliation number per visual (e.g. the year's Net Revenue), to verify the replacement against

## 4. Decide what not to replicate

- Licence overlays, vendor logos, "powered by" strips: **never**.
- Decorative controls that would do nothing (a Back/Zoom-out bar on a non-drilling visual): omit, or add a format toggle defaulting to off.
- Hardcoded period filters on the licensed visual (`Date = <one fixed month>`) are usually a workaround for a missing slicer. Drop them and give the page a real period control. **Keep** the non-date visual filters (e.g. `Account Level 1 ≠ Total Change in Cash`, `Account Level 3 = Bank`).

## 5. Build

1. `new_visual.py` per needed visual type (usually 2–4 visuals cover a whole report).
2. Implement the roles and computed logic from step 2.
3. `node tools/sync-visuals.mjs`.
4. Rewrite each licensed `visual.json` **in place** (same folder and `name`, so page `visualInteractions` and bookmarks still match): new `visualType`, roles renamed per the mapping, filters carried over minus hardcoded dates, chrome suppressed.
5. Remove the replaced GUIDs from `report.json > publicCustomVisuals` (delete the key if it becomes empty).
6. If a build script owns the pages, make it **idempotent**: it must recognise its own output on a second run and **preserve visuals it does not own**. Users will add branding in Desktop between runs.

## 6. Verify

- `scripts/validate-json.ps1`, `scripts/validate-pbip.ps1`, `scripts/Test-PbipSemantics.ps1`, `powerbi-report-author validate "<Project>.pbip"`
- Close Desktop → `powerbi-desktop open` → screenshot every page → review against `powerbi-visual-verify`
- No licence popups anywhere; every reconciliation number from step 3 matches
- `grep` the report for the old GUIDs: zero hits

## 7. Report back

Tell the user, by page display name: what was replaced, which numbers reconcile, and which data oddities surfaced now that the visuals render. Licensed visuals often hid those behind the popup (margin above 100%, two series that are identical because a flow is empty).
