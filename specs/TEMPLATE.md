# Spec: <dashboard or page name>

> Copy this file to `specs/<name>.md` and fill it in before building. Delete the quoted guidance lines as you go.
> Status: `draft` | `building` | `built` · Date: `YYYY-MM-DD` · Author:

## 1. Goal

> Two or three sentences. Who looks at this, what decision it supports, and what "good" looks like. If you cannot say what decision the page supports, the page is a chart collection, not a dashboard.

## 2. Data required

**Source tables**

| Table | Role | Grain | Notes |
| --- | --- | --- | --- |
| | fact / dimension | | |

**Measures**

> Home table is a rule, not a preference: business measures in `_Measures`, SVG KPI measures in `_SVG_Measures` with page-prefixed names.

| Measure | Home table | Definition (plain English) | Format |
| --- | --- | --- | --- |
| | `_Measures` | | whole number, thousand separators |
| `P1_..._SVG` | `_SVG_Measures` | | |

**Relationships needed that do not exist yet**

| From | To | Cardinality | Cross-filter |
| --- | --- | --- | --- |

## 3. Pages

> One block per page. The SVG background defines the card grid; visuals sit on top of it. Card titles are drawn in the SVG, so visuals must not carry their own titles.

### Page: <display name>

- **Page id / folder:**
- **SVG background:** `<name>.svg` in `RegisteredResources/`, registered in `report.json`
- **Card grid:** > sketch it — e.g. "4 KPI cards across the top at y=90, two charts at y=260, table full width at y=560"

| Card / region | Visual type | Fields | Sort | Notes |
| --- | --- | --- | --- | --- |
| | | | | |

> Geometry reminder: `card_with_title()` draws its label at `card_y + 24`, so a visual's `y` must be at least `card_y + 30` or the chart lands on top of its own title. This is the single most common rendering defect in this template and JSON validation cannot see it.

## 4. Rules that apply

> Default is: everything in `copilot-instructions.md`. Use this section only for the decisions this page makes *within* the rules, and for anything that needs an explicit exception.

- Formatting: whole numbers, thousand separators, data labels on, no axis titles, value axis hidden, category axis visible
- Sort: descending by value, except time series (Jan→Dec by month number, displayed MMM)
- Chrome: no visual title, no background, no border, no shadow — titles come from the SVG
- Theme: `<theme name>.json`
- **Exceptions requested:** > none, or name the rule and justify it. An exception recorded here is a decision; an exception discovered in a screenshot is a defect.

## 5. Build tasks

- [ ] Measures added to `_Measures` with descriptions
- [ ] SVG KPI measures added to `_SVG_Measures` (`P<n>_` prefix)
- [ ] Theme saved to `RegisteredResources/` and registered in `report.json`
- [ ] SVG canvas background generated and registered
- [ ] Page created with background wired up
- [ ] Visuals built and bound to fields
- [ ] Build script updated (if a script owns these files)
- [ ] `validate-json.ps1` + `validate-pbip.ps1` + `Test-PbipSemantics.ps1` pass

## 6. Definition of done

- [ ] All three validation scripts pass (JSON, PBIP structure, semantics)
- [ ] PBIP **opens in Desktop with no error dialog** — window title shows the project, not *Untitled*
- [ ] `powerbi-desktop status` reports the project path
- [ ] Verification loop run; every page screenshot reviewed against `.claude/skills/powerbi-visual-verify/SKILL.md`
- [ ] No visual overlaps its SVG card title; no truncated labels; no blank charts
- [ ] Findings reported by page display name

## 7. Open questions

> Anything that would change the build if answered differently. Ask before building, not after.

- [ ]

## 8. Fold-back

> After the page renders clean: which rules here were not one-offs? Move them into `copilot-instructions.md` and note what moved.

-
