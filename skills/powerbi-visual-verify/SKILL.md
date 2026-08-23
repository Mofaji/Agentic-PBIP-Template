---
name: powerbi-visual-verify
description: 'Reviews rendered Power BI page screenshots captured through the Desktop Bridge and decides what to fix in the PBIR/TMDL source. Use when verifying that a report actually renders correctly after edits, when screenshots have been captured to tests/screenshots/, or when the Stop hook blocks a turn with a visual verification report. Triggers on queries about visual verification, screenshot review, "does the report render correctly", overlapping visuals, truncated labels, blank visuals, stale theme colors, and the edit-validate-reload-screenshot loop.'
---

# Power BI Visual Verification

Reviews what Power BI Desktop **actually rendered**, not what the JSON claims. Valid PBIR routinely renders wrong: a chart sits on top of its SVG card title, labels truncate, a visual comes back blank, theme colors are stale.

## Repository Final Boss Alignment

For this repository, `copilot-instructions.md` is the final authority. Every check below traces back to a numbered rule in its **General Dashboard Formatting Rules** section; where this file and `copilot-instructions.md` disagree, `copilot-instructions.md` wins.

---

## The loop

```
edit PBIR/TMDL -> validate -> reload -> screenshot-all -> review PNGs -> fix -> repeat
```

Automated by the `Stop` hook in `.claude/settings.json`, which runs `scripts/Invoke-PbipVerify.ps1`. You normally arrive here because that hook blocked the turn and handed you screenshot paths.

**Fix budget is one round.** Round 1 you review and fix. Round 2 you review the confirmation screenshots and **report only — no further edits**. Say plainly what is still wrong rather than starting another fix cycle.

### Running it by hand

```powershell
powershell -NoProfile -File scripts\Test-PbipBridge.ps1              # preflight
powershell -NoProfile -File scripts\Invoke-PbipVerify.ps1 -Mode Review
```

---

## How to review

1. **Read every screenshot with the Read tool.** All of them, every round. A page you skip is a page you did not verify — never infer a page's state from another page or from the JSON.
2. Work the checklist below per page.
3. Fix the **PBIR/TMDL source**, never the PNG.
4. Report findings by **page display name**, not page id — the id means nothing to the user.

Screenshots include the right-hand filter pane (`outspacePane`). Its presence is normal and not a defect.

---

## Checklist

### A. Layout & overlap

- [ ] **Visual does not overlap its SVG card title.** `card_with_title()` draws the label at `card_y + 24`, so a visual's `y` must be at least `card_y + 30`. *This is the highest-value check in the whole file: it is pure geometry, invisible to JSON validation, and the single most common rendering defect in this template.* (rule 16)
- [ ] No visual is clipped by the page edge or unintentionally overlapping another.
- [ ] Category labels, legends, and data labels are fully legible — not truncated, not rotated to illegibility, no ellipses.
- [ ] Card and KPI values show in full (no `…`).
- [ ] Textboxes have no scrollbars; slicers render their full control.
- [ ] Spacing reads as deliberate; visuals align to the SVG background's card grid.
- [ ] X-axis title width above 40% where the chart needs the room. (rule 15)

### B. Data rendering

- [ ] Charts contain actual marks — bars, lines, points. An empty plot area is a failure even when the JSON is valid.
- [ ] Tables and matrices have data rows.
- [ ] No error banners, no "Can't display this visual", no missing-field warnings.
- [ ] Blanks and nulls are explainable, not accidental.
- [ ] Slicers list selectable values.
- [ ] Where the SVG label promises a Top N, the visual is actually filtered to that N. (rule 14)

### C. Numbers & labels

- [ ] No decimal points anywhere — whole numbers only. (rule 1)
- [ ] Thousand separators on every measure and visual. (rule 2)
- [ ] Data labels **on** for all charts: 0 decimals, comma-separated, full numbers — never K/M abbreviations. (rule 4)
- [ ] Clean names — no "Sum of", no underscores in tooltips or column headers. (rule 3)
- [ ] Sorted descending by value unless the visual is a time series. (rule 5)
- [ ] Month visuals run Jan→Dec by month number, displayed as MMM. (rule 6)

### D. Chrome & theming

- [ ] **No visual container title** — titles come from the SVG background canvas. A visible Power BI title means duplicated text. (rule 10)
- [ ] No visual background. (rule 7)
- [ ] No visual border. (rule 8)
- [ ] No drop shadow. (rule 9)
- [ ] No axis titles on either axis. (rule 11)
- [ ] Value axis hidden — only data labels carry the numbers. (rule 12)
- [ ] Category axis visible. (rule 13)
- [ ] Theme colors, fonts, and page background match design intent; series are distinguishable and contrast adequately against the background.

---

## Known caveats

These produce screenshots that lie. Check them before concluding a fix failed.

**Theme cache.** Power BI Desktop caches theme JSON. After editing a theme in `StaticResources/RegisteredResources/`, a reload shows **stale colors**. Rename the theme file with a new suffix and update its `report.json` registration, or close and reopen Desktop. The verify script warns when it sees a recently modified theme file.

**Semantic model / TMDL.** `file.reload/v1` takes `reloadModelDefinition` (default `true`), so measure changes usually do apply. When a visual still shows stale or missing measure values, reopen rather than reload:

```powershell
powerbi-desktop open "<project>.pbip"
```

This matters here because the build scripts rewrite `_SVG_Measures.tmdl` on nearly every run.

**One operation at a time.** The bridge runs a single operation per instance. Never issue a reload and a screenshot concurrently against the same PID — the documented result is a `Cancelled` error. `Invoke-PbipVerify.ps1` already serializes them.

**Right instance.** An idle *Untitled* Desktop window reports `connected` but fails every operation with `REPORT_DIR_REQUIRED`. The scripts select the PID whose `currentFilePath` matches this project.

**Preview API.** Both CLIs are public preview. After a Power BI Desktop update, re-check the method surface:

```powershell
powerbi-desktop manifest --pid <pid>
```

---

## When verification is skipped

If the hook reports that verification was skipped (Desktop closed, bridge down, CLI missing), the loop **fails open by design** — a hook that blocked on a broken bridge would make the session impossible to end. Tell the user the report was not visually verified and why. Do not claim a page renders correctly on the strength of JSON validation alone.
