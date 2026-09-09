# Spec: Sales Overview

> Worked example shipped with the template. It shows the shape of a filled-in spec; the tables and measures below are illustrative, not part of `Template.SemanticModel`.
> Status: `built` · Date: 2026-09-03 · Author: template

## 1. Goal

A single landing page for regional sales managers: is this month on track, which products and customers are driving it, and where did the trend break. Read in under thirty seconds, on the way into a Monday call. Good means a manager can name the underperforming region without clicking anything.

## 2. Data required

**Source tables**

| Table | Role | Grain | Notes |
| --- | --- | --- | --- |
| `Fact-Sales` | fact | one row per order line | |
| `Dim-Date` | dimension | day | marked as date table; drives time intelligence |
| `Dim-Product` | dimension | product | |
| `Dim-Customer` | dimension | customer | |
| `Dim-Region` | dimension | region | |

**Measures**

| Measure | Home table | Definition (plain English) | Format |
| --- | --- | --- | --- |
| `Total Sales` | `_Measures` | Sum of order line net amount | whole number, thousand separators |
| `Total Sales LY` | `_Measures` | `Total Sales` shifted back one year via `Dim-Date` | whole number, thousand separators |
| `Sales YoY %` | `_Measures` | `Total Sales` against `Total Sales LY`, blank when no prior year | whole percent |
| `Order Count` | `_Measures` | Distinct count of order numbers | whole number, thousand separators |
| `Avg Order Value` | `_Measures` | `Total Sales` over `Order Count` | whole number, thousand separators |
| `P1_Sales_KPI_SVG` | `_SVG_Measures` | KPI card: `Total Sales` with YoY arrow and sparkline | SVG string |
| `P1_Orders_KPI_SVG` | `_SVG_Measures` | KPI card: `Order Count` with YoY arrow | SVG string |
| `P1_AOV_KPI_SVG` | `_SVG_Measures` | KPI card: `Avg Order Value` | SVG string |
| `P1_Customers_KPI_SVG` | `_SVG_Measures` | KPI card: distinct customers billed this period | SVG string |

**Relationships needed that do not exist yet**

| From | To | Cardinality | Cross-filter |
| --- | --- | --- | --- |
| `Fact-Sales[OrderDate]` | `Dim-Date[Date]` | many-to-one | single |
| `Fact-Sales[ProductKey]` | `Dim-Product[ProductKey]` | many-to-one | single |
| `Fact-Sales[CustomerKey]` | `Dim-Customer[CustomerKey]` | many-to-one | single |
| `Dim-Customer[RegionKey]` | `Dim-Region[RegionKey]` | many-to-one | single |

## 3. Pages

### Page: Sales Overview

- **Page id / folder:** `p1-sales-overview`
- **SVG background:** `p1_sales_overview.svg` in `RegisteredResources/`, registered in `report.json`
- **Card grid:** four KPI cards across the top (`card_y = 90`, height 130); two charts side by side at `card_y = 250`; one full-width table at `card_y = 540`.

| Card / region | Visual type | Fields | Sort | Notes |
| --- | --- | --- | --- | --- |
| KPI 1 | image | `P1_Sales_KPI_SVG` | — | `sourceType='imageData'`, measure in `sourceField` |
| KPI 2 | image | `P1_Orders_KPI_SVG` | — | |
| KPI 3 | image | `P1_AOV_KPI_SVG` | — | |
| KPI 4 | image | `P1_Customers_KPI_SVG` | — | |
| Trend | lineChart | axis `Dim-Date[Month]`, value `Total Sales` | month number Jan→Dec, displayed MMM | time series, so not sorted by value |
| Top products | barChart | axis `Dim-Product[Product]`, value `Total Sales` | descending by `Total Sales` | Top 10 filter — the SVG label says "Top 10", so the filter must actually be there |
| Detail | tableEx | Region, Customer, `Total Sales`, `Order Count`, `Sales YoY %` | descending by `Total Sales` | no "Sum of" prefixes, no underscores in headers |

Visual `y` sits at `card_y + 30` or lower in every case, so nothing lands on its SVG card title.

## 4. Rules that apply

- Formatting: whole numbers, thousand separators, data labels on (0 decimals, no K/M abbreviations), no axis titles, value axis hidden, category axis visible
- Sort: descending by value; the trend chart is the exception, ordered by month number
- Chrome: no visual title, no background, no border, no shadow
- Theme: `SalesTheme.json`
- **Exceptions requested:** none

## 5. Build tasks

- [x] Measures added to `_Measures` with descriptions
- [x] SVG KPI measures added to `_SVG_Measures` (`P1_` prefix)
- [x] Theme saved to `RegisteredResources/` and registered in `report.json`
- [x] SVG canvas background generated and registered
- [x] Page created with background wired up
- [x] Visuals built and bound to fields
- [x] Build script updated
- [x] `validate-json.ps1` + `validate-pbip.ps1` pass

## 6. Definition of done

- [x] Both validation scripts pass
- [x] PBIP opens in Desktop with no error dialog — window title shows the project, not *Untitled*
- [x] `powerbi-desktop status` reports the project path
- [x] Verification loop run; both page screenshots reviewed
- [x] No visual overlaps its SVG card title; no truncated labels; no blank charts
- [x] Findings reported by page display name

## 7. Open questions

- [x] Does "customers" mean billed this period or ever active? → billed in the selected period.

## 8. Fold-back

- The `card_y + 30` minimum for visual `y` was a recurring fix across three pages, not a one-off. Moved into `copilot-instructions.md` as rule 16 and into the visual-verify checklist as the top layout check.
- "Where the SVG label promises a Top N, the visual must actually be filtered to that N" generalises. Moved into the rulebook as rule 14.
