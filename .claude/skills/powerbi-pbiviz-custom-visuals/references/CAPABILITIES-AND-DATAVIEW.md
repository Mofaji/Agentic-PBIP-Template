# `capabilities.json` and reading the dataView

`capabilities.json` is the contract between the report and the visual. It declares what fields the visual accepts (`dataRoles`), how Power BI shapes the query result (`dataViewMappings`), and what appears in the Format pane (`objects`).

---

## dataRoles

```json
"dataRoles": [
  { "displayName": "Rows (hierarchy, outer to inner)", "name": "rows", "kind": "Grouping" },
  { "displayName": "Actual (AC)", "name": "ac", "kind": "Measure" }
]
```

- `name` is what `visual.json` uses as the `queryState` key. Keep names short, lowercase, stable. Renaming one breaks every report binding.
- `kind`: `Grouping` (columns you group by), `Measure` (aggregated values), `GroupingOrMeasure`.
- `description` shows as a hint in the field well. Use it for anything non-obvious ("one index column per Rows level, same order").

## Choosing a dataViewMapping

| Mapping | Use when | Shape you receive |
| --- | --- | --- |
| `categorical` | One category axis (optionally a series) × measures. Charts. | `categories[]` columns + `values[]` measure columns aligned by index; `highlights[]` when `supportsHighlight` |
| `table` | Several grouping columns at once (hierarchies, cross-tabs) and you aggregate yourself | `table.columns[]` + `table.rows[][]`, one row per distinct grouping combination |
| `matrix` | You want Power BI's own row/column hierarchy with subtotals | Nested `rows.root.children` / `columns.root.children` trees |

Pick the simplest one that works. The variance table template uses `table` and aggregates in TypeScript. That is only correct for **additive** measures. A ratio bound to a `table` mapping and summed up a hierarchy is wrong. Compute ratios from summed components (as the template does for margin % rows), or use `matrix` so Power BI computes subtotals.

### categorical

```json
"dataViewMappings": [{
  "conditions": [ { "category": { "max": 1 }, "measure": { "max": 1 } } ],
  "categorical": {
    "categories": { "for": { "in": "category" }, "dataReductionAlgorithm": { "top": { "count": 120 } } },
    "values": { "select": [ { "bind": { "to": "measure" } } ] }
  }
}]
```

Series (legend) variant: `"values": { "group": { "by": "series", "select": [{ "bind": { "to": "measure" } }] } }`.

Reading:

```ts
const dv = options.dataViews?.[0];
const cat = dv?.categorical?.categories?.[0];        // DataViewCategoryColumn
const val = dv?.categorical?.values?.[0];            // DataViewValueColumn
cat.values[i]; val.values[i]; val.highlights?.[i];   // aligned by i
cat.source.displayName; val.source.displayName;      // honours projection displayName
```

### table

```json
"dataViewMappings": [{
  "conditions": [ { "rows": { "min": 1, "max": 3 }, "period": { "max": 1 }, "ac": { "max": 1 } } ],
  "table": {
    "rows": {
      "select": [ { "for": { "in": "rows" } }, { "for": { "in": "period" } }, { "for": { "in": "ac" } } ],
      "dataReductionAlgorithm": { "window": { "count": 30000 } }
    }
  }
}]
```

Reading: find columns by role, not by position. Optional roles shift positions.

```ts
const table = dv.table!;
const byRole = (role: string) => table.columns.map((c, i) => ({ c, i })).filter((x) => x.c.roles?.[role]);
const rowCols = byRole("rows");           // in projection order = hierarchy order
const acCol = byRole("ac")[0];
table.rows.forEach((row, r) => { const v = row[acCol.i]; /* ... */ });
```

Rows where every measure is blank are not returned. A category with no data simply does not appear.

### Sort order

Without help, grouping values arrive alphabetically. When the business order matters (statement lines, custom month order), add an optional role such as `rowOrder` for index columns and sort by it in the visual (see the variance table template). Do not rely on the model's *Sort by column* reaching a custom visual through a `table` mapping.

## conditions

`conditions` restricts how many fields each role accepts. Several condition objects are OR-ed. Put `max` on every role. Without it, users can drop 10 measures into a visual that draws one.

## dataReductionAlgorithm

Caps rows per query. `top` for categories (keeps the first N by the query's order), `window` for tables (supports paging via `fetchMoreData`, which the templates do not use). Set it deliberately: the default is 1,000 categories, and a P&L × 12 months cross-tab easily exceeds that in a `categorical` mapping.

## Dates arrive as Date objects

A date column's values are JS `Date` instances in local time. Format them yourself (`shared/format.ts > fmtMonth`). Do not rely on the model format string: custom visuals receive raw values, and `source.format` is only a hint.

## supportsHighlight

`"supportsHighlight": true` changes behaviour when **another** visual is clicked. Instead of filtering your data, Power BI sends the full data plus a `highlights[]` array (non-null = part of the selection). Draw the whole shape, emphasise the highlighted part (`shared/interaction.ts > markOpacity`). Without it, cross-filtering reduces your data to the selection.

Table-mapped visuals get no `highlights`. Leave it `false` there and accept filtering.

## privileges

Keep `"privileges": []`. The templates make no network calls, and a visual that needs `WebAccess` cannot be certified and is blocked by many tenants.
