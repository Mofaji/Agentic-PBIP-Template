# Power BI Reporting Boilerplate — SKILL for GitHub

Purpose
: Provide a concise, repo-level boilerplate for implementing Power BI report replication (Python + HTML email or extract scripts). This document is intended to be used as a reusable `SKILL.md` or `README` in any repository that implements automated Power BI report extracts or email reports.

Guiding Principles
- Always treat the Power BI semantic model and page JSON as the source of truth. Do not infer filter logic or aggregation behavior.
- Replicate page-level filters explicitly in your Python totals and distinct counts.
- Compute totals at the correct granularity: when in doubt, compute totals from the source fact table scoped to the valid keys, not by summing merged detail rows.

How to use this boilerplate


1) Read the semantic model first
- Open `_Measures.tmdl` and the specific fact/dim `.tmdl` files that define the visuals you replicate.
- Confirm SQL, Power Query steps (key-field renames, row filters), and DAX expressions used by visuals.

2) Read page-level filters and visuals
- Open the page's `page.json` and the `visual.json` files for each visual to identify filters and which DAX measure each visual uses.
- Build a `valid_keys` set from the dimension(s) the page filters restrict (e.g. `valid_location_keys`, `valid_entity_keys`).

3) Five mandatory checks before coding a measure
 - Source table: which fact/dim does the DAX measure use?
 - CALCULATE filters: list every filter in the DAX (`<sales_amount_col><>0`, etc.)
 - Aggregation type: SUM / DISTINCTCOUNT / SUMX / AVERAGEX — replicate aggregation semantics
 - Context modifiers: ALL/REMOVEFILTERS/TREATAS — replicate by scoping or not scoping your DataFrames
 - Granularity: ensure totals are computed from an appropriately-granular source

4) Common bug patterns (boilerplate fixes)
- Granularity duplication: totals for `<entity_key>`-level metrics must come from `<entity_key>`-level sources filtered to `valid_entity_keys`.
- Page filter omission: totals must apply page filters; build and use `valid_keys` rather than summing across all fetched rows.
- Wrong source table: double-check which source table each card or column visual uses — multiple fact tables may exist with different scopes.
- Using filtered detail for totals: totals often must use fact tables scoped to `valid_location_keys` directly, not from summing `detail` rows.
- Type mismatches: normalise key columns (e.g. `<LOCATION_KEY>`) to string and apply the same replacement logic after fetch.

5) Totals decision tree (quick)
- Metric granularity = `<entity_key>` only → total from `<entity_key>` source filtered to `valid_entity_keys`.
- Metric granularity = `<location_key>` → total from `<FactTable>` scoped to `valid_location_keys`.
- Target-dependent metrics → sum from target table (detail) only.

6) Actuals behavior guidance (boilerplate rule)
- If actuals should only show where a target exists, zero-out `actual_metric` for rows with `target_metric == 0`.
- If specific `<LOCATION_KEY>` values must be exempt, add a documented exception rule.
- Totals for actuals should be computed from the fact table filtered to locations that either have targets or are explicitly exempt.

7) Minimal Python structure (standardized)
- Phase 1 — Config: constants at top (`DB`, `SMTP`, recipients)
- Phase 2 — Helpers: `safe_div`, formatters, `resolve_month`
- Phase 3 — Fetch: one `fetch_*()` per model table; normalise keys immediately (`astype(str)`, `<LOCATION_KEY>` replacements)
- Phase 4 — Compute: `compute_<page>_measures(...)` which returns `(detail_df, totals_dict)` for MTD/YTD variants
- Phase 5 — HTML builders: small composable helpers (`kpi_card`, `build_data_table`)
- Phase 6 — Send/Preview: `--preview` writes HTML; otherwise send via SMTP with BCC pattern

8) Testing and validation
- Add a small `validate_<report>.py` script to surface common discrepancies (orphan `<LOCATION_KEY>` values, locations with fact data but no target, diff between unfiltered and page-filtered totals).
- Use CI to run a lightweight validation (no secrets) that loads sample CSV fixtures and asserts totals match expected values.

9)
- PR checklist (add to PR template):
  - [ ] Read `_Measures.tmdl` and page `page.json`
  - [ ] Normalised keys after every fetch
  - [ ] Implemented `valid_keys` for page filters
  - [ ] Totals computed from correct source and scoped correctly
  - [ ] Added/updated `validate_<report>.py` tests or fixture checks

10) Quick template commit message
"chore(report): implement <ReportName> measures — follow repository visual formatting rules (validate totals and page filters)"

11) Minimal SKILL usage snippet for developers
1. Review the *Visual Formatting Rules* and *General Dashboard Formatting Rules* sections of `copilot-instructions.md`.
2. Run validation locally:
```bash
python validate_<report>.py --month 202604
```
3. Run preview to inspect UI:
```bash
python <report_script>.py --preview --month 202604
```

Contact and maintenance
- Add issues against this SKILL for any new bug patterns discovered. Keep the SKILL concise and authoritative — it should be the first stop for anyone implementing or changing report logic.

---
End of boilerplate SKILL.
# Automated Email Report Template — Universal Instructions
## For AI Agents: Read this file completely before writing ANY Python or HTML for this project.

---

## PART A — MANDATORY: DAX-to-Python Validation Protocol

> **These rules exist because value discrepancies of 200k–400k were discovered between Power BI and Python output. Every bug below was real and caused by skipping one of these steps.**

---

### A1. Always Read the Semantic Model First

Before implementing or modifying ANY metric, read these files in order:

1. `{report_name}.SemanticModel/definition/tables/_Measures.tmdl`  
   → All KPI card measures and table column measures. This is the source of truth.



**Never guess what a measure does. Always read the DAX.**

---

### A2. Always Read the Page JSON Before Computing Totals

Every Power BI page has page-level filters in its `page.json`. These are invisible WHERE clauses that apply to every visual on the page. They cascade through **bidirectional relationships** to all connected fact tables.

**Read the `page.json` file for the page you are replicating:**

```
Report.Report/definition/pages/{page_folder_id}/page.json
```

Look for `"filterConfig"` → `"filters"` → the `"field"` and `"type"` entries.

Also read the visual JSON files for any slicer visuals on the page — slicers that have a saved selection act as additional filters on all non-slicer visuals.

**Page filter summary (confirmed from reading page.json files):**

| Page | Folder ID | Active Filter | Effect |
|---|---|---|---|
| Page 1 "{Page 1 Name}" | `{page_1_folder_id}` | `<DimEntityTable>[<visibility_flag_col>] = 1` | Entities where target > 0 only |
| Page 2 "{Page 2 Name}" | `{page_2_folder_id}` | `<DimLocationTable>[<location_category_col>]` slicer | Filtered location category only via `<FactTable>`→`<DimLocationTable>` relationship |
| Page 3 "{Page 3 Name}" | `{page_3_folder_id}` | `<FactTable>[<segment_col>] = '<segment_value>'` | Specific segment only |

**Rule:** Python totals must explicitly replicate each page filter. Do not assume the SQL data already matches — the SQL fetches broader data and PBI applies these filters at query time.

---

### A3. Five Mandatory Checks for Every DAX Measure

For each metric you implement, answer all five:

| # | Check | Why It Matters |
|---|---|---|
| 1 | **Source table** | Multiple fact tables may exist (e.g. invoice-level, line-level). They have DIFFERENT scopes. Confirm which one the DAX measure uses — never mix them. |
| 2 | **CALCULATE filters** | Read every `CALCULATE` filter in the measure (e.g. `<txn_type_col> = '<delivery_code>'`, `<status_col> = '<cleared_code>'`). Missing even one produces wrong totals. |
| 3 | **Aggregation type** | `SUM` vs `DISTINCTCOUNT` vs `SUMX` vs `AVERAGEX` all behave differently in totals rows. `AVERAGEX(VALUES(<invoice_key_col>), DISTINCTCOUNT(<product_col>))` is not the same as a flat average — it averages per-invoice distinct counts. |
| 4 | **Context modifiers** | `ALL(Table)` removes all filters on a table. `ALL(DimDate)` means the measure ignores the date slicer — replicate this in Python by NOT filtering the source DataFrame by date. |
| 5 | **Granularity mismatch in totals** | If a per-`<ENTITY_KEY>` metric is merged into a `<ENTITY_KEY>+<LOCATION_KEY>` detail table, summing that column in the totals row will multiply-count. See Bug Pattern 1 below. |

---

### A4. Confirmed Bug Patterns (Every One Was Hit in This Project)

#### Bug Pattern 1 — Granularity Duplication in Totals

**Symptom:** Python sales total is 2×–3× higher than Power BI.

**Cause:** A metric computed at `<ENTITY_KEY>` granularity (one row per entity) is merged into a `detail` DataFrame at `<ENTITY_KEY>+<LOCATION_KEY>` granularity (one row per entity per location). An entity with targets in 3 locations now has their value in 3 rows. Summing `detail['metric_a']` triple-counts.

**Rule:** For any metric that is grouped at a coarser granularity than `detail`, compute the total directly from the source DataFrame, NOT from the merged `detail` column.

```python
# WRONG — metric is at <ENTITY_KEY> level but detail is <ENTITY_KEY>+<LOCATION_KEY> level
totals['metric_a'] = detail['metric_a'].sum()  # multiplies by location count

# CORRECT — go back to the source, scoped to valid keys only
totals['metric_a'] = (
    df_fact2[df_fact2['<ENTITY_KEY>'].isin(valid_entity_keys)]['metric_a'].sum()
)
```

---

#### Bug Pattern 2 — Page Filter Not Replicated in Python Totals

**Symptom:** Python totals include salesmen or plants that Power BI excludes.

**Cause:** Power BI's page filter (e.g. `<visibility_flag_col> = 1`) silently excludes rows with no target. Python fetches all rows from SQL and doesn't apply this filter.

**Rule:** Always build a `valid_keys` set from whichever dimension the page filter restricts, and apply it before computing totals.

```python
# Pattern 1 — entities with target > 0 only
valid_entity_keys = set(df_target[df_target['<target_value_col>'] > 0]['<ENTITY_KEY>'].unique())

totals['active_customers'] = int(
    df_fact_month[
        df_fact_month['<ENTITY_KEY>'].isin(valid_entity_keys) &
        (df_fact_month['<sales_amount_col>'] != 0)
    ]['<customer_col>'].nunique()
)
totals['customer_base'] = int(
    df_dim_customer[df_dim_customer['<ENTITY_KEY>'].isin(valid_entity_keys)]['<customer_master_col>'].nunique()
)
```

```python
# Pattern 2 — filtered location category only
valid_location_keys = set(
    df_dim_location[
        df_dim_location['<location_category_col>'] == '<location_category_value>'
    ]['<LOCATION_KEY>'].astype(str)
)
df_fact_filtered = df_fact[df_fact['<LOCATION_KEY>'].astype(str).isin(valid_location_keys)]
totals['fact_metric'] = float(df_fact_filtered['<sales_amount_col>'].sum())
```

---

#### Bug Pattern 3 — Sourcing KPI Card Value from Wrong Table

**Symptom:** KPI card value differs from Power BI card by a consistent offset. Table rows match but card does not.

**Cause:** Power BI's KPI card visual may use a different measure than the table columns. For example:
- **Table column** may use `Metric A = SUM(<FactTable>[<sales_amount_col>])` — all lines from the main fact table.
- **KPI card** may use `Metric A = SUM(<FactPerfTable>[<perf_amount_col>]) WHERE <txn_type_col>='<delivery_code>'` — filtered rows from a different fact table.

These are different source tables with different scope.

**Rule:** For every visual on the page (card, table, chart), read its `visual.json` to confirm which DAX measure it references. Do not assume card and table use the same measure just because they have the same label.

```python
# WRONG for KPI card if card uses <FactPerfTable>:
card_value = mt['metric_from_fact']    # <FactTable> source

# CORRECT — card uses filtered <FactPerfTable> source:
card_value = mt['metric_from_perf']    # <FactPerfTable> source
```

---

#### Bug Pattern 4 — Using `detail` Sum for Totals When `detail` Is Filtered

**Symptom:** Python grand total is lower than Power BI total.

**Cause:** `detail` is built from only locations/entities that have a target > 0. Some locations may have real fact-table activity but no target entry. Their rows never appear in `detail`. Summing `detail['fact_metric']` silently omits them.

**Rule:** For metrics that come from fact tables — compute the grand total directly from the fact DataFrames scoped to the valid dimension, NOT from summing `detail` rows.

```python
# WRONG — excludes locations with activity but no target:
totals['fact_metric'] = detail['fact_metric'].sum()

# CORRECT — sum from <FactTable> for all valid locations:
totals['fact_metric']   = float(df_fact_filtered['<sales_amount_col>'].sum())
totals['gross_profit']  = float((df_fact_filtered['<sales_amount_col>'] - df_fact_filtered['<cost_col>']).sum())
totals['collection']    = float(df_collection_filtered['<receipts_col>'].sum())
```

Note: target metrics SHOULD still come from `detail` — the target table naturally excludes zero-target entries by definition.

---

#### Bug Pattern 5 — DISTINCTCOUNT Scope Mismatch

**Symptom:** `active_customers` or `active_products` count is higher than Power BI.

**Cause:** Python counts distinct values across ALL locations/entities in the fetched data. Power BI's context (page filter or slicer) restricts which locations/entities are in scope before counting.

**Rule:** Always scope DISTINCTCOUNT metrics to the filtered dimension set:

```python
# WRONG — counts across all entities in the data:
totals['active_customers'] = int(df_fact['<customer_col>'].nunique())

# CORRECT — scoped to the dimension that the page filter restricts:
totals['active_customers'] = int(
    df_fact[
        df_fact['<LOCATION_KEY>'].astype(str).isin(valid_location_keys) &
        (df_fact['<sales_amount_col>'] != 0)
    ]['<customer_col>'].nunique()
)
```

---

#### Bug Pattern 6 — Secondary Metric Mapped to Wrong Location

**Symptom:** Returns (or other secondary metric) total per location doesn't match Power BI.

**Cause:** `<FactPerfTable>` has no `<LOCATION_KEY>` column — it's an `<ENTITY_KEY>`+invoice table. To map returns to locations, Python must join via an `<ENTITY_KEY>`→`<LOCATION_KEY>` lookup derived from `<FactTable>`. If the lookup uses an incomplete method (e.g. first-match only), some values get mis-attributed.

**Rule:** Build `<ENTITY_KEY>`→`<LOCATION_KEY>` mapping from `<FactTable>` by taking the location with the highest `<sales_amount_col>` per entity:

```python
entity_location_map = (
    df_fact.groupby(['<ENTITY_KEY>', '<LOCATION_KEY>'], as_index=False)['<sales_amount_col>'].sum()
    .sort_values('<sales_amount_col>', ascending=False)
    .drop_duplicates(subset='<ENTITY_KEY>', keep='first')[['<ENTITY_KEY>', '<LOCATION_KEY>']]
)
df_returns = df_returns.merge(entity_location_map, on='<ENTITY_KEY>', how='left')
```

Then for grand totals, filter `df_returns` to only the valid locations before summing.

---

#### Bug Pattern 7 — Hardcoded Date Range in Fact Table SQL

**Symptom:** Fact data is missing for months outside the hardcoded range in the semantic model SQL.

**Cause:** Power BI's M query may have a hardcoded start date (e.g. `'<hardcoded_start_yyyymmdd>'`). Python must NOT copy this hardcoded date. Python must always use a dynamic date range computed from the `--month` argument.

**Rule:** All Python `fetch_*()` functions must accept `year_start` and `next_ym` as parameters and use them to build the WHERE clause dynamically:

```python
def fetch_fact(conn, year_start: str, next_ym: str) -> pd.DataFrame:
    sql = f"""
    SELECT ...
    WHERE <date_col> >= '{year_start}01'
      AND <date_col> <  '{next_ym}01'
    ...
    """
```

---

#### Bug Pattern 8 — Key Column Type Mismatch Silently Drops Rows

**Symptom:** Merge results in unexpected NaN rows or zero values for some locations.

**Cause:** `<LOCATION_KEY>` comes from SQL as a string in some tables and as integer in others. After key normalisation (e.g. `str.replace('<old_code>', '<new_code>')`), some comparisons fail silently because `int(<new_code>) != str('<new_code>')`.

**Rule:** Always normalise key columns to string after every fetch and before every merge:

```python
df['<LOCATION_KEY>'] = df['<LOCATION_KEY>'].astype(str).str.replace('<old_code>', '<new_code>', regex=False)
```

Apply this immediately after `run_query()` for every table that contains `<LOCATION_KEY>`.

---

### A5. Confirmed Measure-to-Python Mappings

> These are verified against `_Measures.tmdl`. Do not deviate.

---

### A6. Totals Row Decision Tree

Always ask: at what granularity is this metric grouped? How does that compare to `detail`?

---

## PART B — HTML Email Style

### B1. Outlook Desktop Compatibility Rules

Outlook Desktop uses the Word rendering engine — it ignores many CSS properties.

| ❌ Do NOT use | ✅ Use instead |
|---|---|
| `background:` shorthand | `background-color:` |
| `background: linear-gradient(...)` | `bgcolor="..."` attribute + `background-color:` inline style |
| `border-radius:` | Omit it — not rendered in Outlook |
| `box-shadow:` | Not supported — omit |
| `max-width:` on `<table>` | Use `width="{px}"` HTML attribute directly |
| `<div>` for layout or backgrounds | Use `<table><tr><td>` structure |
| `<div style="text-align:center">` | `<td align="center">` |
| `<div style="background:...">` for section headers | `<td bgcolor="...">` |
| `display:flex` or `display:grid` | Table-based layout only |

---

### B2. Email Outer Wrapper

The outer wrapper creates the page background and centers the email card. The inner table is the email card at a fixed pixel width. Choose width based on content density:
- Dense tables with many columns → `600px`
- KPI cards + moderate tables → `720px`

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>{Report Title}</title>
</head>
<body style="margin:0;padding:0;background-color:#f0f2f5;font-family:'Segoe UI',Arial,sans-serif;">

<table width="100%" cellpadding="0" cellspacing="0" border="0"
       bgcolor="#f0f2f5" style="background-color:#f0f2f5;">
<tr><td align="center" style="padding:16px 8px;">

  <table width="{EMAIL_WIDTH}" cellpadding="0" cellspacing="0" border="0"
         style="width:{EMAIL_WIDTH}px;">
    <!-- all sections as <tr> rows go here -->
  </table>

</td></tr></table>
</body>
</html>
```

---

### B3. Section Components

#### Header Strip

```html
<tr>
  <td bgcolor="#0d3b6e" style="background-color:#0d3b6e;padding:22px 28px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr>
        <td>
          <div style="font-size:20px;font-weight:700;color:#ffffff;letter-spacing:.5px;">
            <span style="color:#64b5f6;">{org_name}</span> {Report Title}
          </div>
          <div style="font-size:12px;color:#90caf9;margin-top:3px;">
            {Subtitle} &nbsp;|&nbsp; {Month Year} &nbsp;|&nbsp; Generated at {HH:MM}
          </div>
        </td>
        <td align="right">
          <span style="background-color:#1e5ba8;color:#ffffff;padding:5px 12px;
                       font-size:11px;font-weight:600;">(All values in {currency})</span>
        </td>
      </tr>
    </table>
  </td>
</tr>
```

#### Filter/Info Bar

```html
<tr>
  <td bgcolor="#f8f9fa"
      style="background-color:#f8f9fa;padding:8px 24px;border-bottom:1px solid #e8e8e8;">
    <span style="font-size:10px;color:#666;">
      {filter description 1} &nbsp;|&nbsp; {filter description 2} &nbsp;|&nbsp; {context}
    </span>
  </td>
</tr>
```

#### Section Header Bar

```html
<tr>
  <td bgcolor="#0d3b6e" style="background-color:#0d3b6e;padding:8px 24px;">
    <span style="color:#ffffff;font-size:12px;font-weight:700;letter-spacing:.5px;">
      &#9632; {SECTION TITLE} &mdash; {Date or Context}
    </span>
  </td>
</tr>
```

#### KPI Card

Each card is a nested table. Background color, border, and text color reflect whether the metric met its threshold. Pill badges must use the card's background color (not transparent) with a colored border.

```html
<!-- Single KPI card cell — repeat inside a <tr> with appropriate width percentage -->
<td width="{25|33|50}%" style="padding:{N}px;" valign="top">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="height:100%;">
    <tr>
      <td bgcolor="{bg_color}"
          style="background-color:{bg_color};border:1px solid {border_color};
                 padding:7px 8px;vertical-align:top;">
        <table width="100%" cellpadding="0" cellspacing="0" border="0">
          <tr>
            <td>
              <div style="font-size:9px;color:#777;text-transform:uppercase;
                          letter-spacing:.4px;font-weight:600;">{Label}</div>
            </td>
            <td align="right" style="white-space:nowrap;">
              <!-- Pill badge: background MUST match card bg (not transparent) -->
              <span style="background-color:{bg_color};color:{value_color};
                           border:1px solid {value_color};padding:1px 5px;
                           font-size:8px;font-weight:700;white-space:nowrap;">
                {Achieved}: {pct}%
              </span>
            </td>
          </tr>
          <tr>
            <td style="padding-top:4px;" valign="top">
              <div style="font-size:15px;font-weight:800;color:{value_color};
                          letter-spacing:-.5px;">{formatted_value}</div>
              <div style="font-size:9px;color:#555;">{sub_label}</div>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</td>
```

**KPI Threshold Color Logic:**

| Condition | bg_color | border_color | value_color |
|---|---|---|---|
| Met threshold (≥ threshold) | `#eef8f0` | `#b8dcc0` | `#28A745` (green) |
| Below threshold | `#fdf2f2` | `#f0c8c8` | `#DC3545` (red) |

**Standard thresholds (configurable):** define per metric based on business requirements (e.g. actuals vs target = 80%, coverage = 60%, margin % = 15%).

#### Data Table

Alternating row colors. Bold totals row. Borders on all cells.

```html
<tr>
  <td style="padding:0 10px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0"
           style="border-collapse:collapse;">
      <!-- Header row -->
      <tr bgcolor="#2C6E49" style="background-color:#2C6E49;">
        <td style="padding:6px 8px;font-size:10px;color:#ffffff;font-weight:700;
                   border:1px solid #B8E4C4;white-space:nowrap;">{Column Header}</td>
        <!-- repeat for each column -->
      </tr>
      <!-- Data rows — alternate #E0F3E8 / #FFFFFF -->
      <tr bgcolor="{#E0F3E8 or #FFFFFF}" style="background-color:{...};">
        <td style="padding:5px 8px;font-size:10px;color:#333;
                   border:1px solid #B8E4C4;white-space:nowrap;">{value}</td>
        <!-- repeat for each column -->
      </tr>
      <!-- Totals row -->
      <tr bgcolor="#ECF6F0" style="background-color:#ECF6F0;">
        <td style="padding:6px 8px;font-size:10px;color:#333;font-weight:700;
                   border:1px solid #B8E4C4;white-space:nowrap;">{total}</td>
      </tr>
    </table>
  </td>
</tr>
```

#### Period Label (between MTD and YTD blocks)

```html
<tr>
  <td style="padding:3px 24px;background-color:#f0f5f2;">
    <span style="font-size:9px;font-weight:900;color:#2C6E49;letter-spacing:.8px;
                 text-transform:uppercase;">
      &#9472; {MTD / YTD (Jan &ndash; {Month} {Year})} &#9472;
    </span>
  </td>
</tr>
```

#### Note Strip

```html
<tr>
  <td bgcolor="#e8f4fd"
      style="background-color:#e8f4fd;padding:10px 24px;border-top:1px solid #bee3f8;">
    <span style="font-size:11px;color:#1565c0;">
      <strong>&#128206; {Note text here}</strong>
    </span>
  </td>
</tr>
```

#### Footer

```html
<tr>
  <td bgcolor="#0d3b6e"
      style="background-color:#0d3b6e;padding:14px 28px;text-align:center;">
    <div style="font-size:11px;color:#90caf9;margin-bottom:4px;">
      For any changes contact:
      <a href="mailto:{contact_email}"
         style="color:#64b5f6;text-decoration:none;font-weight:700;">{contact_email}</a>
      <span style="color:#5c8ab8;margin:0 8px;">|</span>
      &copy; {Year} Org &mdash; Automated Report
    </div>
    <div style="font-size:9px;color:#5c8ab8;">
      Source: {source_tables} &nbsp;|&nbsp; Currency: {currency} &nbsp;|&nbsp; {generated_datetime}
    </div>
  </td>
</tr>
```

---

### B4. Color Reference

| Usage | Hex |
|---|---|
| Primary dark blue (header / footer / section bars) | `#0d3b6e` |
| Header button / badge bg | `#1e5ba8` |
| Header link / accent blue | `#64b5f6` |
| Header subtitle text | `#90caf9` |
| Footer secondary text | `#5c8ab8` |
| Good / green value | `#28A745` |
| Bad / red value | `#DC3545` |
| Warning orange | `#e65100` |
| Table header green | `#2C6E49` |
| Table alt row (even) | `#E0F3E8` |
| Table alt row (odd) | `#FFFFFF` |
| Table totals row bg | `#ECF6F0` |
| Table border | `#B8E4C4` |
| Good card bg | `#eef8f0` |
| Good card border | `#b8dcc0` |
| Bad card bg | `#fdf2f2` |
| Bad card border | `#f0c8c8` |
| Page background | `#f0f2f5` |
| Filter bar bg | `#f8f9fa` |
| Note strip bg | `#e8f4fd` |
| Note strip border | `#bee3f8` |
| Period label text | `#2C6E49` |
| Period label bg | `#f0f5f2` |

---

## PART C — Python Structure Guidelines

### C1. Script Phase Structure

Every email script must follow this order:

```
Phase 1 — Configuration (DB, SMTP, recipients at top of file as constants)
Phase 2 — Helper functions (safe_div, fmt, fmt_pct, resolve_month)
Phase 3 — Database fetch functions (one function per source table)
Phase 4 — Compute function (one per report page; takes conn + ym params; returns totals + detail)
Phase 5 — HTML build function (helpers: kpi_card, section_header, build_data_table, row_bg)
Phase 6 — Email send function (MIMEMultipart, starttls, BCC pattern)
Phase 7 — Main (argparse with --preview and --month flags)
```

### C2. `safe_div` — Always Use Instead of Raw Division

```python
def safe_div(a, b):
    """Replicates DAX DIVIDE(a, b, 0) — returns 0.0 if denominator is zero or NaN."""
    if not b or (isinstance(b, float) and pd.isna(b)):
        return 0.0
    return a / b
```

### C3. `fmt` and `fmt_pct` — Always Use `abs()` for Display

```python
def fmt(v, decimals=0):
    """Format a number for display. Always shows absolute value (negatives shown as positive)."""
    if v is None or (isinstance(v, float) and np.isnan(v)):
        return '0'
    return f'{abs(v):,.{decimals}f}'

def fmt_pct(v, decimals=1):
    """Format a 0-1 ratio as percentage string."""
    if v is None or (isinstance(v, float) and np.isnan(v)):
        return f'0.{"0" * decimals}%'
    return f'{v * 100:,.{decimals}f}%'
```

### C4. `resolve_month` — Dynamic Date Range

```python
def resolve_month(override: str | None):
    """
    Returns (ym, next_ym, month_name, year, year_start_ym).
    override: 'YYYYMM' string from --month arg, or None to use current month.
    """
    ym = override or datetime.now().strftime('%Y%m')
    year  = int(ym[:4])
    month = int(ym[4:6])
    month_name = datetime(year, month, 1).strftime('%B')
    next_ym    = f"{year + 1}01" if month == 12 else f"{year}{month + 1:02d}"
    year_start = f"{year}01"
    return ym, next_ym, month_name, year, year_start
```

### C5. Email Send Pattern

```python
def send_email(html: str, subject: str):
    msg = MIMEMultipart('related')
    msg['Subject'] = subject
    msg['From']    = SMTP_EMAIL
    msg['To']      = SMTP_EMAIL          # sender listed as To
    msg['Bcc']     = ', '.join(TO_LIST)  # actual recipients in BCC only

    alt = MIMEMultipart('alternative')
    msg.attach(alt)
    alt.attach(MIMEText(html, 'html'))

    # Inline image attachment pattern (if needed):
    # img = MIMEImage(png_bytes)
    # img.add_header('Content-ID', '<{cid_name}>')
    # img.add_header('Content-Disposition', 'inline')
    # msg.attach(img)

    with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
        server.ehlo()
        server.starttls()
        server.ehlo()
        server.login(SMTP_EMAIL, SMTP_PASSWORD)
        server.sendmail(SMTP_EMAIL, TO_LIST, msg.as_string())
```

### C6. Preview Mode Pattern

```python
if args.preview:
    preview_path = Path(__file__).parent / f'preview_{report_name}_{ym}.html'
    preview_path.write_text(html, encoding='utf-8')
    print(f'Preview saved: {preview_path}')
else:
    send_email(html, subject)
    print('Email sent.')
```

### C7. `row_bg` Helper

```python
def row_bg(i: int) -> str:
    """Alternating row background for data tables."""
    return '#E0F3E8' if i % 2 == 0 else '#FFFFFF'
```

---

## PART D — Chart Style Guidelines (if charts are included)

| Chart type | Library | Colormap | Figure size |
|---|---|---|---|
| Heatmap (sales/positive) | seaborn | `Greens` | `(14, max(6, rows × 0.25))` |
| Heatmap (returns/negative) | seaborn | `Reds_r` | `(14, max(6, rows × 0.25))` |
| Bar chart | seaborn barplot | skyblue / salmon | `(10, 7)` |

- DPI: `150`
- Save: `bbox_inches='tight'`
- Heatmaps: `tight_layout(rect=[0, 0, 1, 0.93])` (room for title and total labels)
- Bar charts: `tight_layout(rect=[0, 0, 1, 0.95])`, `set_ylim(0, ylim * 1.18)` for annotation headroom
- Heatmap zeros: mask with white overlay + annotate `'0'` in black text
- Heatmap non-zero: annotate `f'{int(v):,}'` — white text for high values, black for low, `fontsize=7`
- Embed in email: `cid:{name}` for sent email, `data:image/png;base64,{b64}` for preview file

---

## PART E — Project Reference

### E1. Database

```
Server:   
Database: 
Driver:   
```

### E2. SMTP

```
Server:   {smtp_server}  (e.g. smtp.office365.com)
Port:     587 (STARTTLS)
Sender:   {sender_email}
```

### E3. Power BI Pages

| Page | Folder ID | Python Script |
|---|---|---|
| Page 1 — {Page 1 Name} | `{page_1_folder_id}` | `<page1_email.py>` |
| Page 2 — {Page 2 Name} | `{page_2_folder_id}` | `<page2_email.py>` |
| Page 3 — {Page 3 Name} | `{page_3_folder_id}` | *(to be built)* |



# HTML Email Style & Body Instructions
## Organisation Automated Report Template

---

## 0. MANDATORY — DAX-to-Python Validation (Read This First)

**BEFORE writing or modifying any Python compute function, you MUST:**

### Step 1 — Read the DAX measures from the semantic model
Always read the relevant `.tmdl` files before implementing any metric:
- `{report_name}.SemanticModel/definition/tables/_Measures.tmdl` — all KPI card and table column measures


### Step 2 — Read page-level filters from `page.json`
Every PBI page has filters that act as invisible WHERE clauses on ALL visuals on that page.
Always read the page JSON before computing totals:
- `{report_name}.Report/definition/pages/{page_1_folder_id}/page.json` → **Page 1 "{Page 1 Name}"** — read the `filterConfig` to identify active filters and the dimension/column they restrict
- `{report_name}.Report/definition/pages/{page_2_folder_id}/page.json` → **Page 2 "{Page 2 Name}"** — read the `filterConfig` and any slicer visuals with saved selections
- `{report_name}.Report/definition/pages/{page_3_folder_id}/page.json` → **Page 3 "{Page 3 Name}"** — read the `filterConfig` to identify active segment or category filters

These page filters cascade via **bidirectional relationships** and affect every measure on the page. Python totals must replicate these filters explicitly.

### Step 3 — Map each DAX measure to its Python equivalent

For every metric in `_Measures.tmdl`, verify these 5 things before coding:

| Check | Question to answer |
|---|---|
| **Source table** | Which table does the DAX use? Confirm which fact or dim table — multiple fact tables may exist with different scopes. |
| **Filter condition** | What `CALCULATE` filter or page filter applies? (e.g., `<txn_type_col>='<delivery_code>'`, `<status_col>='<cleared_code>'`, `<sales_amount_col> <> 0`) |
| **Aggregation** | Is it `SUM`, `DISTINCTCOUNT`, `SUMX`, `AVERAGEX`? |
| **Context modifiers** | Does it use `ALL()`, `ALLSELECTED()`, `REMOVEFILTERS()`, `TREATAS()`? These remove or replace filter context. |
| **Granularity of totals** | Is the measure computed per-row (per `<ENTITY_KEY>`, per `<LOCATION_KEY>`) and then summed, or globally? Merging a per-`<ENTITY_KEY>` value into a `<ENTITY_KEY>+<LOCATION_KEY>` `detail` table and then summing causes duplication. |

### Step 4 — Known validated mappings (DO NOT DEVIATE once confirmed)

> Read `_Measures.tmdl` for your project and populate this table before writing any Python. The examples below show the pattern — replace with your actual table/column/filter names.

| Metric | DAX Source & Logic | Python Implementation |
|---|---|---|
| **`<Metric A>`** | `SUM(<FactPerfTable>[<perf_amount_col>]) WHERE <txn_type_col>='<delivery_code>'` | `df_fact_perf[df_fact_perf['<txn_type_col>']=='<delivery_code>'].groupby('<ENTITY_KEY>')['<perf_amount_col>'].sum()` |
| **`<Metric B (negative)>`** | `SUM(<FactPerfTable>[<perf_amount_col>]) WHERE <txn_type_col>='<return_code>'` | `df_fact_perf[df_fact_perf['<txn_type_col>']=='<return_code>'].groupby('<ENTITY_KEY>')['<perf_amount_col>'].sum()` |
| **`<Metric B (abs)>`** | `ABS(SUM(<FactPerfTable>[<perf_amount_col>])) WHERE <txn_type_col>='<return_code>'` | `abs(metric_b)` |
| **`<Metric C>`** | `SUM(<FactTable>[<sales_amount_col>])` | `df_fact.groupby(['<ENTITY_KEY>','<LOCATION_KEY>'])['<sales_amount_col>'].sum()` |
| **`<Metric D>`** | `SUMX(<FactTable>, <sales_amount_col> - <cost_col>)` | `(df_fact['<sales_amount_col>'] - df_fact['<cost_col>']).groupby(...)` |
| **`<Metric D %>`** | `DIVIDE([<Metric D>], [<Metric C>])` | `safe_div(metric_d, metric_c)` |
| **`<Metric E>`** | `SUM(<FactCollectionTable>[<receipts_col>]) WHERE <status_col>='<cleared_code>'` | `df_collection[df_collection['<status_col>']=='<cleared_code>'].groupby(['<ENTITY_KEY>','<collection_location_col>'])['<receipts_col>'].sum()` |
| **`Active <customers>`** | `DISTINCTCOUNT(<FactTable>[<customer_col>]) WHERE <sales_amount_col><>0` | `df_fact[df_fact['<sales_amount_col>']!=0].groupby('<ENTITY_KEY>')['<customer_col>'].nunique()` |
| **`<Customer Base>`** | `DISTINCTCOUNT(<DimCustomerTable>[<customer_master_col>])` with `ALL(DimDate)` — ignores date filter | `df_dim_customer.groupby('<ENTITY_KEY>')['<customer_master_col>'].nunique()` (no date filter on fetch) |
| **`Active <products>`** | `DISTINCTCOUNT(<FactTable>[<product_col>]) WHERE <sales_amount_col><>0` | `df_fact[df_fact['<sales_amount_col>']!=0]['<product_col>'].nunique()` |
| **`Total <products>`** | `DISTINCTCOUNT(<DimProductTable>[<product_master_col>])` | `df_dim_product['<product_master_col>'].nunique()` |
| **`<Sales Target>`** | `SUM(<TargetTable>[<sales_target_col>]) WHERE > 0 AND NOT BLANK` | `df_target.groupby(['<ENTITY_KEY>','<LOCATION_KEY>'])['<sales_target_col>'].sum()` (filter `> 0`) |
| **`<Collection Target>`** | `SUM(<TargetTable>[<collection_target_col>])` | `df_target.groupby(['<ENTITY_KEY>','<LOCATION_KEY>'])['<collection_target_col>'].sum()` |
| **`<Sales Achieved %>`** | `DIVIDE([<Metric C>], [<Sales Target>])` | `safe_div(metric_c, sales_target)` |
| **`<Collection Achieved %>`** | `DIVIDE([<Metric E>], [<Collection Target>])` | `safe_div(metric_e, collection_target)` |
| **`<Return %>`** | `DIVIDE(ABS([<Metric B>]), ABS([<Metric C>]))` | `safe_div(abs(metric_b), abs(metric_c))` |

### Step 5 — Totals row duplication trap

When a metric is grouped at **`<ENTITY_KEY>`** level (one row per entity) but `detail` is at **`<ENTITY_KEY>+<LOCATION_KEY>`** level (multiple rows per entity), summing `detail['metric_a']` will double-count.

**Rule:** For any metric grouped at `<ENTITY_KEY>`-only granularity, compute the total directly from the source DataFrame filtered to `valid_entity_keys`, NOT by summing the merged `detail` column:
```python
# CORRECT — sum from source, filtered to valid entities
totals['metric_a'] = df_fact_perf[df_fact_perf['<ENTITY_KEY>'].isin(valid_entity_keys)]['metric_a'].sum()

# WRONG — double-counts if entity has targets in multiple locations
totals['metric_a'] = detail['metric_a'].sum()
```

### Step 6 — Page filter replication in Python totals

The PBI page filter `<visibility_flag_col> = 1` means: only show entities where `<target_value_col> > 0`. This cascades to all measures including `<FactTable>`-derived ones (active customers, active products) and dimension master counts.

Python must replicate this by scoping any global DISTINCTCOUNT to `valid_entity_keys`:
```python
valid_entity_keys = set(df_target_mtd['<ENTITY_KEY>'].unique())  # entities with target > 0

# Active customers — scope to valid entities only
totals['active_customers'] = int(
    df_fact_month[
        df_fact_month['<ENTITY_KEY>'].isin(valid_entity_keys) &
        (df_fact_month['<sales_amount_col>'] != 0)
    ]['<customer_col>'].nunique()
)
# Customer base — scope to valid entities only
totals['customer_base'] = int(
    df_dim_customer[
        df_dim_customer['<ENTITY_KEY>'].isin(valid_entity_keys)
    ]['<customer_master_col>'].nunique()
)
```

---

## 1. General Rules (Outlook Desktop Compatibility)

Outlook Desktop uses the **Word rendering engine** — it ignores many CSS properties.
Always follow these rules to ensure the email looks the same in **Outlook Desktop**, **Web Outlook**, and **Gmail**.

| ❌ Do NOT use | ✅ Use instead |
|---|---|
| `background:` shorthand | `background-color:` |
| `background: linear-gradient(...)` | `bgcolor="#0d3b6e"` attribute + `background-color:` inline |
| `border-radius:` | Remove or accept it won't render in Outlook |
| `box-shadow:` | Not supported, skip it |
| `max-width:` on `<table>` | Use `width="720"` HTML attribute directly |
| `<div>` for layout/backgrounds | Use `<table><tr><td>` structure |
| `<div style="text-align:center">` for images | `<td align="center">` |
| `<div style="background:...">` for section headers | `<td bgcolor="...">` |
| `display:flex` or `display:grid` | Table-based layout only |

---

## 2. Email Boilerplate Structure

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>{Report Title}</title>
</head>
<body style="margin:0;padding:0;background-color:#f0f2f5;font-family:'Segoe UI',Arial,sans-serif;">

<!-- Outer wrapper -->
<table width="100%" cellpadding="0" cellspacing="0" border="0"
       bgcolor="#f0f2f5" style="background-color:#f0f2f5;">
<tr><td align="center" style="padding:16px 8px;">

  <!-- Email card (fixed width — 600px for dense tables, 720px for KPI + moderate tables) -->
  <table width="{EMAIL_WIDTH}" cellpadding="0" cellspacing="0" border="0" style="width:{EMAIL_WIDTH}px;">
    <!-- sections go here -->
  </table>

</td></tr></table>
</body>
</html>
```

---

## 3. Section Components

### 3.1 Header Strip
```html
<tr>
  <td bgcolor="#0d3b6e" style="background-color:#0d3b6e;padding:22px 28px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr>
        <td>
          <div style="font-size:20px;font-weight:700;color:#ffffff;letter-spacing:.5px;">
            <span style="color:#64b5f6;">{org_name}</span> {Report Title}
          </div>
          <div style="font-size:12px;color:#90caf9;margin-top:3px;">
            {Subtitle} | {Date} | Generated at {HH:MM}
          </div>
        </td>
        <td align="right">
          <span style="background-color:#1e5ba8;color:#ffffff;padding:5px 12px;
                       font-size:11px;font-weight:600;">(All values in {currency})</span>
        </td>
      </tr>
    </table>
  </td>
</tr>
```

---

### 3.2 KPI Card Row
- Each card uses a nested `<table>` with `bgcolor` on the inner `<td>`
- Do NOT use `<div>` for the card background
- Repeat `<td width="{N}%">` blocks for each metric; adjust column count and widths accordingly

```html
<tr>
  <td bgcolor="#ffffff" style="background-color:#ffffff;padding:4px 10px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr>
        <!-- Metric 1 -->
        <td width="25%" align="center" style="padding:6px;">
          <table width="100%" cellpadding="0" cellspacing="0" border="0">
            <tr>
              <td align="center" bgcolor="{bg_color}"
                  style="background-color:{bg_color};border:1px solid {border_color};padding:18px 10px;">
                <div style="font-size:10px;color:#777;text-transform:uppercase;
                            letter-spacing:.6px;margin-bottom:8px;font-weight:600;">{Metric 1 Label}</div>
                <div style="font-size:24px;font-weight:800;color:{value_color};letter-spacing:-.5px;">
                  {formatted_value}
                </div>
              </td>
            </tr>
          </table>
        </td>
        <!-- repeat for Metric 2, 3, 4 — adjust bg/border/value colors per KPI Color Palette below -->
      </tr>
    </table>
  </td>
</tr>
```

**KPI Color Palette:**

| Card | Value Color | Background | Border |
|---|---|---|---|
| Positive metric (e.g. sales, target met) | `#0d3b6e` or `#1b8a3e` | `#eef3fb` or `#eef8f0` | `#c8d8eb` or `#b8dcc0` |
| Negative metric (e.g. returns, below target) | `#c0392b` or `#DC3545` | `#fdf2f2` | `#f0c8c8` |
| Warning metric (e.g. partial returns) | `#e65100` | `#fef5ee` | `#f0d4b8` |

---

### 3.3 Filter/Info Bar
```html
<tr>
  <td bgcolor="#f8f9fa"
      style="background-color:#f8f9fa;padding:8px 24px;border-bottom:1px solid #e8e8e8;">
    <span style="font-size:10px;color:#666;">
      {filter context 1} &nbsp;|&nbsp;
      {filter context 2} &nbsp;|&nbsp;
      {other context}
    </span>
  </td>
</tr>
```

---

### 3.4 Section Header Bar (before each chart/table)
```html
<table width="100%" cellpadding="0" cellspacing="0" border="0">
  <tr>
    <td bgcolor="#0d3b6e" style="background-color:#0d3b6e;padding:8px 24px;">
      <span style="color:#ffffff;font-size:12px;font-weight:700;letter-spacing:.5px;">
        &#9632; SECTION TITLE &mdash; Date or Context
      </span>
    </td>
  </tr>
</table>
```

---

### 3.5 Embedded Image (CID inline)
```html
<table width="100%" cellpadding="0" cellspacing="0" border="0">
  <tr>
    <td align="center" style="padding:8px;">
      <img src="cid:image_name" alt="Chart Description"
           width="700" style="max-width:100%;height:auto;display:block;margin:0 auto;" />
    </td>
  </tr>
</table>
```
- In the Python `send_email()` function, attach each image as `MIMEImage` with `Content-ID: <image_name>`
- For HTML preview files, replace `cid:image_name` with `data:image/png;base64,{b64string}`

---

### 3.6 Note Strip
```html
<tr>
  <td bgcolor="#e8f4fd"
      style="background-color:#e8f4fd;padding:10px 24px;border-top:1px solid #bee3f8;">
    <span style="font-size:11px;color:#1565c0;">
      <strong>&#128206; Note or attachment info here</strong>
    </span>
  </td>
</tr>
```

---

### 3.7 Footer
```html
<tr>
  <td bgcolor="#0d3b6e"
      style="background-color:#0d3b6e;padding:14px 28px;text-align:center;">
    <div style="font-size:11px;color:#90caf9;margin-bottom:4px;">
      For any changes contact:
      <a href="mailto:{contact_email}"
         style="color:#64b5f6;text-decoration:none;font-weight:700;">{contact_email}</a>
      <span style="color:#5c8ab8;margin:0 8px;">|</span>
      &copy; {year} {org_name} &mdash; Automated Report
    </div>
    <div style="font-size:9px;color:#5c8ab8;">
      Source: {source_tables} &nbsp;|&nbsp; Currency: {currency} &nbsp;|&nbsp; {generated_datetime}
    </div>
  </td>
</tr>
```

---

## 4. Color Reference

| Usage | Hex |
|---|---|
| Primary dark blue (header/footer/section bars) | `#0d3b6e` |
| Header button bg | `#1e5ba8` |
| Link blue | `#64b5f6` |
| Subtitle text | `#90caf9` |
| Footer secondary text | `#5c8ab8` |
| Sales green | `#1b8a3e` |
| Returns red | `#c0392b` |
| MTD Returns orange | `#e65100` |
| Page background | `#f0f2f5` |
| Filter bar bg | `#f8f9fa` |
| Note strip bg | `#e8f4fd` |

---

## 5. Python `build_html()` Prompt

When writing the `build_html(totals)` function in Python, follow this pattern:

```
- Accept a `totals` dict with keys matching your report's metrics (e.g. metric_1, metric_2, metric_3, metric_4)
- Define a fmt(v) helper: return f'{abs(v):,.0f}'  (always abs for display)
- Define a kpi(label, value, color, bg, border_color) helper that returns a <td> containing
  a nested <table><tr><td bgcolor=bg> structure — NOT a <div>
- Define a sec_hdr(title) helper that returns a full <table> with a dark blue <td bgcolor="#0d3b6e">
- Define an img_row(cid, alt) helper that returns a <table><tr><td align="center"> wrapping the <img>
- Build the full HTML string as a Python f-string
- Return the complete HTML string
```

---

## 6. Python `send_email()` Prompt

```
- Use MIMEMultipart('related') as the outer message
- Attach a MIMEMultipart('alternative') inside it
- Attach MIMEText(html, 'html') inside the alternative
- For each chart PNG (bytes), create a MIMEImage, set Content-ID to <cid_name>,
  set Content-Disposition to inline, then attach to the outer 'related' message
- For Excel attachment: use MIMEBase, encode_base64, set Content-Disposition to attachment
- Send via smtplib SMTP office365.com:587 with starttls()
- Use msg['To'] = sender (no-reply) and msg['Bcc'] = ', '.join(to_list)
```

---

## 7. Chart Style Guidelines

| Chart | Type | Colormap | Figure Size |
|---|---|---|---|
| Positive metric heatmap (e.g. sales) | seaborn heatmap | `Greens` | `(14, max(6, rows×0.25))` |
| Negative metric heatmap (e.g. returns) | seaborn heatmap | `Reds_r` | `(14, max(6, rows×0.25))` |
| MTD positive heatmap | seaborn heatmap | `Greens` | `(14, max(12, rows×0.25))` |
| MTD negative heatmap | seaborn heatmap | `Reds_r` | `(14, max(6, rows×0.25))` |
| Daily comparison bar chart | seaborn barplot × 2 | skyblue / salmon | `(10, 7)` |

- DPI: `150`
- Save with `bbox_inches='tight'`
- Use `tight_layout(rect=[0, 0, 1, 0.93])` on heatmaps to avoid title/total-label overlap
- Use `tight_layout(rect=[0, 0, 1, 0.95])` on bar charts
- Add `set_ylim(0, ylim * 1.18)` on bar chart axes for annotation headroom
- Zeros in heatmap: mask with white overlay + annotate '0' in black text
- Non-zero cells: annotate `f'{int(v):,}'` in white (high value) or black (low value), fontsize 7
