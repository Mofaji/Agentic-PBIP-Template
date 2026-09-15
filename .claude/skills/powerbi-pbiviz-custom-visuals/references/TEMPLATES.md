# Starter templates

`tools/new_visual.py --template <name>` copies one of these into `visuals/<name>/`. Each is a complete, building visual. Adapt it; do not start from `pbiviz new`'s sample.

All three share `visuals/shared/` and are interactive (tooltips, cross-filter, clear, render events).

---

## `varianceTable`: IBCS statement table

Statement table for P&L, cash-flow statement, balance sheet, any additive account hierarchy.

**Layouts**, chosen automatically:

| `period` role | Layout | Columns |
| --- | --- | --- |
| empty | variance | Rows · PM · AC · ΔPM bar · ΔPM% pin |
| bound (date column) | cross-tab | Rows · one column per period · Total |

**Roles** (`table` mapping):

| Role | Kind | Max | Notes |
| --- | --- | --- | --- |
| `rows` | Grouping | 3 | Outer → inner hierarchy levels, in projection order |
| `rowOrder` | Grouping | 3 | Index column per level, same order as `rows`. Omit and rows sort A→Z. |
| `period` | Grouping | 1 | Bind to switch to cross-tab. Date values are labelled `Mmm-yy`. |
| `ac` | Measure | 1 | Actual. **Must be additive**; the visual sums it up the hierarchy. |
| `pm` | Measure | 1 | Comparison (previous month, plan, PY). Variance layout only. |

**Objects**:

| Card.property | Default | Effect |
| --- | --- | --- |
| `statement.groupTotal` | `sum` | `running`: top-level groups show the cumulative result (Net Revenue → Gross Margin → … → Net Profit) |
| `statement.showRatios` | `false` | With `running`, adds "<group> %" rows = running result ÷ first group |
| `statement.ratioSuffix` | `" %"` | Label suffix for ratio rows |
| `statement.collapsed` | `""` | Pipe-separated group labels collapsed by default (`EBITDA Margin\|Net Working Capital`) |
| `statement.hideEmpty` | `true` | Hide rows whose values round to 0 |
| `display.unit` | `K` | `K` / `M` / `none`. State the unit in the card title. |
| `display.fontSize` / `rowHeight` | 11 / 22 | |
| `display.acLabel` / `pmLabel` | `AC` / `PM` | Column headers; variance headers become `ΔPM`, `ΔPM%` |
| `display.showTotalColumn` | `true` | Cross-tab total column |
| `colors.positive` / `negative` / `accent` | tokens | |

**Behaviour**: chevron expands/collapses (state kept across updates, default from `collapsed`); row click cross-filters all underlying rows; ratio rows stay visible when a group is collapsed; one bar scale across all visible rows (IBCS); % pins clip at the largest visible change, capped at ±100% with an arrow head; scroll position is preserved.

**Sizing**: ≥ 600 px wide for variance layout; cross-tab needs ~45 px per period at `fontSize` 10.

## `varianceChart`: IBCS period chart

Monthly trend with variance to the previous period.

**Roles** (`categorical`): `category` (Grouping, 1: a date or ordered period column), `measure` (Measure, 1).

**Objects**:

| Card.property | Default | Effect |
| --- | --- | --- |
| `chart.chartType` | `column` | `column` / `line` / `area` (use area for balances) |
| `chart.valueFormat` | `K` | `K` / `M` / `none` / `pct` (pct: labels `71.9%`, variance in `pp`) |
| `chart.showVariance` | `true` | Variance strip above the plot: Δ to previous point, green/red, labelled |
| `chart.showLabels` | `true` | Data labels; thinned automatically when columns are narrow |
| `chart.hideEmpty` | `true` | Drop blank periods (date tables usually extend past the data) |
| `chart.fontSize` | 9 | |
| `chart.invertColors` | `false` | For cost-type measures where up is bad |
| `colors.actual` / `positive` / `negative` / `accent` | tokens | |

**Behaviour**: columns below zero draw downward from a zero line; line/area scale to their own range (not zero-based); highlights dim unselected periods; click cross-filters the period. The axis shows the month part of `Mmm-yy`.

**Sizing**: ≥ 300 × 120 px. Twelve columns need ~36 px each for labels to stay readable.

## `blank`: minimal skeleton

One category × one measure, horizontal bars. Its only job is to show every pattern in ~150 lines: role parsing, `PropSpec` Format pane, selection, tooltip, highlight, render events, empty state, `CLEAR_CATCHER`. Start here for any visual that is neither a statement table nor a period chart (bullet charts, waterfalls, small multiples, KPI strips), keep the plumbing, and replace the drawing.

---

## Example bindings (Python, `tools/pbir_helpers.py`)

```python
from pbir_helpers import *
G = load_guids()

statement = custom_visual("pnlTable", G["finVarianceTable"], 26, 202, 760, 498, 2000,
    roles={
        "rows":     [col("Account Hierarchy", "Level 1"), col("Account Hierarchy", "Level 2")],
        "rowOrder": [col("Account Hierarchy", "Level 1 Index"), col("Account Hierarchy", "Level 2 Index")],
        "ac":       [meas("_Measures", "Actual", display="AC")],
        "pm":       [meas("_Measures", "Actual PM", display="PM")],
    },
    objects={
        "statement": props(groupTotal=s("running"), showRatios=b(True), collapsed=s("Operating Expenses")),
        "display":   props(unit=s("K"), fontSize=d(11), rowHeight=d(22)),
    },
    filters=[categorical_filter("pnlYear", "Dates", "Year", [2025])])
check_against_capabilities(statement, "visuals/finVarianceTable/capabilities.json")

trend = custom_visual("gmTrend", G["finVarianceChart"], 816, 200, 440, 132, 2000,
    roles={"category": [col("Dates", "Month Start")], "measure": [meas("_Measures", "Gross Margin %")]},
    objects={"chart": props(chartType=s("column"), valueFormat=s("pct"), showVariance=b(True))},
    filters=[categorical_filter("gmYear", "Dates", "Year", [2025])])
```
