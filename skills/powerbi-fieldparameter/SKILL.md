---
name: fieldparam-report-builder
description: "Builds a complete Power BI PBIP field-parameter-based report page with a Table and Bar Chart visual that share two dynamic field parameters (one for text dimensions, one for numeric measures), plus four toggle buttons and two bookmarks to switch between modes. Use when: building a dynamic pivot page, adding field parameters to a PBIP report, creating a table/bar-chart toggle, setting up bookmark-based view switching."
argument-hint: "Provide SOURCE_TABLE, dimension columns (label+column name), measure fields (label+field name), page ID, and optionally button/background colors"
---

# Field Parameter Report Builder

Generates all PBIP files needed to add a fully wired field-parameter-driven page to any Power BI PBIP project. The result is a page with a `tableEx` and a `clusteredBarChart` that both respond to two slicers — one for text dimensions (e.g. City, Region, Company) and one for numeric measures (e.g. Total Sales, Qty, Profit). Four action buttons toggle between the two views using bookmarks, with active/inactive visual styling.

---

## When to Use

- Adding a "dynamic pivot" page to a PBIP report
- Creating field parameters so users can switch which column appears on an axis or in a table
- Building a bookmark-based Table ↔ Bar Chart toggle
- Replicating the pattern from an existing HSE dashboard page to a new dashboard

---

## Inputs Required from User

Collect these before generating any files. All are required:

| Input | Description | Example |
|---|---|---|
| `SOURCE_TABLE` | Fact/sales table name in the semantic model | `Sales` |
| `DIM_PARAM_NAME` | Name for the new dimension field parameter table | `DimensionParam` |
| `MEASURE_PARAM_NAME` | Name for the new measure field parameter table | `MeasureParam` |
| `DIM_1_LABEL` / `DIM_1_COLUMN` | First dimension: display name + column name | `City` / `City` |
| `DIM_2_LABEL` / `DIM_2_COLUMN` | Second dimension | `Region` / `Region` |
| `DIM_3_LABEL` / `DIM_3_COLUMN` | Third dimension | `Company` / `Company` |
| `MEASURE_1_LABEL` / `MEASURE_1_FIELD` | First measure: display name + measure/column name | `Total Sales` / `Total Sales` |
| `MEASURE_2_LABEL` / `MEASURE_2_FIELD` | Second measure | `Qty` / `Qty` |
| `MEASURE_3_LABEL` / `MEASURE_3_FIELD` | Third measure | `Profit` / `Profit` |
| `PAGE_ID` | Existing page folder ID (20-char hex) | `1310d213c71292d6a266` |
| `COLOR_ACTIVE_BG` | Active button background (dark hex) | `#003153` |
| `COLOR_ACTIVE_TEXT` | Active button text (light hex) | `#FFFFFF` |
| `COLOR_INACTIVE_BG` | Inactive button background (light hex) | `#D9E1F2` |
| `COLOR_INACTIVE_TEXT` | Inactive button text (dark hex) | `#003153` |

---

## Architecture

```
Two Field Parameter slicers
  └─ DimensionParam  ─── controls: row/category axis (text fields)
  └─ MeasureParam    ─── controls: value column / bar axis (numeric measures)

Two stacked main visuals (same x/y/w/h, toggled by bookmarks)
  └─ tableEx              ─── shown in TABLE mode
  └─ clusteredBarChart    ─── shown in BAR CHART mode

Four action buttons (two pairs, swapped by bookmarks)
  TABLE MODE visible:      [Table ← active: dark bg/light text]  [Bar Chart → inactive: light bg/dark text]
  BAR CHART MODE visible:  [Table ← inactive: light bg/dark text] [Bar Chart → active: dark bg/light text]

Two bookmarks
  └─ BM_TABLE     ─── shows: tableEx, TableActive btn, BarChartInactive btn
  └─ BM_BARCHART  ─── shows: clusteredBarChart, BarChartActive btn, TableInactive btn
```

---

## Procedure

### Step 1 — Generate All IDs First

Run this PowerShell and assign the output to the ID variables below before writing any file:

```powershell
Write-Host "=== TMDL GUIDs ==="
1..10 | ForEach-Object { [guid]::NewGuid().ToString() }

Write-Host "=== Visual IDs (20-char hex) ==="
1..8 | ForEach-Object { -join ((1..20) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) }) }

Write-Host "=== Bookmark IDs (20-char hex) ==="
1..2 | ForEach-Object { -join ((1..20) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) }) }
```

Assign generated values:

| Variable | Role |
|---|---|
| GUID 1–5 | `DIM_PARAM_NAME` table: lineageTags (×4) + PBI_Id |
| GUID 6–10 | `MEASURE_PARAM_NAME` table: lineageTags (×4) + PBI_Id |
| Visual ID 1 | `VISUAL_ID_TABLE` — tableEx folder name |
| Visual ID 2 | `VISUAL_ID_BAR` — clusteredBarChart folder name |
| Visual ID 3 | `VISUAL_ID_DIM_SLICER` — dimension slicer folder name |
| Visual ID 4 | `VISUAL_ID_MEASURE_SLICER` — measure slicer folder name |
| Visual ID 5 | `BTN_TABLE_ACTIVE` folder name |
| Visual ID 6 | `BTN_BARCHART_INACTIVE` folder name |
| Visual ID 7 | `BTN_TABLE_INACTIVE` folder name |
| Visual ID 8 | `BTN_BARCHART_ACTIVE` folder name |
| Bookmark ID 1 | `BM_TABLE` |
| Bookmark ID 2 | `BM_BARCHART` |

---

### Step 2 — Create Dimension Field Parameter Table

**File:** `{YourReport}.SemanticModel/definition/tables/{DIM_PARAM_NAME}.tmdl`

```tmdl
table '{DIM_PARAM_NAME}'
	lineageTag: {GUID_1}

	column '{DIM_PARAM_NAME}'
		lineageTag: {GUID_2}
		summarizeBy: none
		sourceColumn: [Value1]
		sortByColumn: '{DIM_PARAM_NAME} Order'

		relatedColumnDetails
			groupByColumn: '{DIM_PARAM_NAME} Fields'

		annotation SummarizationSetBy = Automatic

	column '{DIM_PARAM_NAME} Fields'
		isHidden
		lineageTag: {GUID_3}
		summarizeBy: none
		sourceColumn: [Value2]
		sortByColumn: '{DIM_PARAM_NAME} Order'

		extendedProperty ParameterMetadata =
				{
				  "version": 3,
				  "kind": 2
				}

		annotation SummarizationSetBy = Automatic

	column '{DIM_PARAM_NAME} Order'
		isHidden
		formatString: 0
		lineageTag: {GUID_4}
		summarizeBy: sum
		sourceColumn: [Value3]

		annotation SummarizationSetBy = Automatic

	partition '{DIM_PARAM_NAME}' = calculated
		mode: import
		source = ```
				{
				    ("{DIM_1_LABEL}", NAMEOF('{SOURCE_TABLE}'[{DIM_1_COLUMN}]), 0),
				    ("{DIM_2_LABEL}", NAMEOF('{SOURCE_TABLE}'[{DIM_2_COLUMN}]), 1),
				    ("{DIM_3_LABEL}", NAMEOF('{SOURCE_TABLE}'[{DIM_3_COLUMN}]), 2)
				}
				```

	annotation PBI_Id = {GUID_5}
```

---

### Step 3 — Create Measure Field Parameter Table

**File:** `{YourReport}.SemanticModel/definition/tables/{MEASURE_PARAM_NAME}.tmdl`

```tmdl
table '{MEASURE_PARAM_NAME}'
	lineageTag: {GUID_6}

	column '{MEASURE_PARAM_NAME}'
		lineageTag: {GUID_7}
		summarizeBy: none
		sourceColumn: [Value1]
		sortByColumn: '{MEASURE_PARAM_NAME} Order'

		relatedColumnDetails
			groupByColumn: '{MEASURE_PARAM_NAME} Fields'

		annotation SummarizationSetBy = Automatic

	column '{MEASURE_PARAM_NAME} Fields'
		isHidden
		lineageTag: {GUID_8}
		summarizeBy: none
		sourceColumn: [Value2]
		sortByColumn: '{MEASURE_PARAM_NAME} Order'

		extendedProperty ParameterMetadata =
				{
				  "version": 3,
				  "kind": 2
				}

		annotation SummarizationSetBy = Automatic

	column '{MEASURE_PARAM_NAME} Order'
		isHidden
		formatString: 0
		lineageTag: {GUID_9}
		summarizeBy: sum
		sourceColumn: [Value3]

		annotation SummarizationSetBy = Automatic

	partition '{MEASURE_PARAM_NAME}' = calculated
		mode: import
		source = ```
				{
				    ("{MEASURE_1_LABEL}", NAMEOF('{SOURCE_TABLE}'[{MEASURE_1_FIELD}]), 0),
				    ("{MEASURE_2_LABEL}", NAMEOF('{SOURCE_TABLE}'[{MEASURE_2_FIELD}]), 1),
				    ("{MEASURE_3_LABEL}", NAMEOF('{SOURCE_TABLE}'[{MEASURE_3_FIELD}]), 2)
				}
				```

	annotation PBI_Id = {GUID_10}
```

---

### Step 4 — Register Tables in model.tmdl

In `{YourReport}.SemanticModel/definition/model.tmdl`, add inside the `ref table` block:

```tmdl
ref table '{DIM_PARAM_NAME}'
ref table '{MEASURE_PARAM_NAME}'
```

Also append both names to the `annotation PBI_QueryOrder` JSON array string.

---

### Step 5 — Create Table Visual

**File:** `{YourReport}.Report/definition/pages/{PAGE_ID}/visuals/{VISUAL_ID_TABLE}/visual.json`

Position: x=182, y=118, z=1000, w=1096, h=600. Adjust to fit your canvas.

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.5.0/schema.json",
  "name": "{VISUAL_ID_TABLE}",
  "position": { "x": 182, "y": 118, "z": 1000, "height": 600, "width": 1096, "tabOrder": 1000 },
  "visual": {
    "visualType": "tableEx",
    "query": {
      "queryState": {
        "Values": {
          "projections": [
            {
              "field": { "Column": { "Expression": { "SourceRef": { "Entity": "{SOURCE_TABLE}" } }, "Property": "{DIM_1_COLUMN}" } },
              "queryRef": "{SOURCE_TABLE}.{DIM_1_COLUMN}", "nativeQueryRef": "{DIM_1_LABEL}", "displayName": "{DIM_1_LABEL}"
            },
            {
              "field": { "Measure": { "Expression": { "SourceRef": { "Entity": "{SOURCE_TABLE}" } }, "Property": "{MEASURE_1_FIELD}" } },
              "queryRef": "{SOURCE_TABLE}.{MEASURE_1_FIELD}", "nativeQueryRef": "{MEASURE_1_LABEL}", "displayName": "{MEASURE_1_LABEL}"
            }
          ],
          "fieldParameters": [
            {
              "parameterExpr": { "Column": { "Expression": { "SourceRef": { "Entity": "{DIM_PARAM_NAME}" } }, "Property": "{DIM_PARAM_NAME}" } },
              "index": 0, "length": 1
            },
            {
              "parameterExpr": { "Column": { "Expression": { "SourceRef": { "Entity": "{MEASURE_PARAM_NAME}" } }, "Property": "{MEASURE_PARAM_NAME}" } },
              "index": 1, "length": 1
            }
          ]
        }
      }
    },
    "objects": {
      "grid": [{ "properties": { "gridHorizontalColor": { "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 2, "Percent": 0.6 } } } } } }],
      "columnHeaders": [{ "properties": {
        "fontColor": { "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 0, "Percent": 0 } } } } },
        "backColor": { "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 2, "Percent": 0.4 } } } } },
        "bold": { "expr": { "Literal": { "Value": "true" } } }
      }}],
      "values": [{ "properties": {
        "fontColor": { "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 1, "Percent": 0 } } } } },
        "alternatingRowsColor": { "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 2, "Percent": 0.6 } } } } }
      }}]
    },
    "visualContainerObjects": {
      "title": [{ "properties": {
        "show": { "expr": { "Literal": { "Value": "true" } } },
        "titleWrap": { "expr": { "Literal": { "Value": "true" } } },
        "bold": { "expr": { "Literal": { "Value": "true" } } },
        "alignment": { "expr": { "Literal": { "Value": "'center'" } } },
        "fontColor": { "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 3, "Percent": 0.2 } } } } },
        "background": { "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 0, "Percent": 0 } } } } }
      }}],
      "background": [{ "properties": { "show": { "expr": { "Literal": { "Value": "true" } } }, "transparency": { "expr": { "Literal": { "Value": "0D" } } } }}],
      "border": [{ "properties": { "width": { "expr": { "Literal": { "Value": "1D" } } } }}]
    },
    "drillFilterOtherVisuals": true
  }
}
```

---

### Step 6 — Create Bar Chart Visual

**File:** `{YourReport}.Report/definition/pages/{PAGE_ID}/visuals/{VISUAL_ID_BAR}/visual.json`

Same x/y/w/h as the table. Use z=20000 so it renders on top when both are technically present.

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.5.0/schema.json",
  "name": "{VISUAL_ID_BAR}",
  "position": { "x": 182, "y": 118, "z": 20000, "height": 600, "width": 1096, "tabOrder": 20000 },
  "visual": {
    "visualType": "clusteredBarChart",
    "query": {
      "queryState": {
        "Category": {
          "projections": [{
            "field": { "Column": { "Expression": { "SourceRef": { "Entity": "{SOURCE_TABLE}" } }, "Property": "{DIM_1_COLUMN}" } },
            "queryRef": "{SOURCE_TABLE}.{DIM_1_COLUMN}", "nativeQueryRef": "{DIM_1_LABEL}", "active": true
          }],
          "fieldParameters": [{
            "parameterExpr": { "Column": { "Expression": { "SourceRef": { "Entity": "{DIM_PARAM_NAME}" } }, "Property": "{DIM_PARAM_NAME}" } },
            "index": 0, "length": 1
          }]
        },
        "Y": {
          "projections": [{
            "field": { "Measure": { "Expression": { "SourceRef": { "Entity": "{SOURCE_TABLE}" } }, "Property": "{MEASURE_1_FIELD}" } },
            "queryRef": "{SOURCE_TABLE}.{MEASURE_1_FIELD}", "nativeQueryRef": "{MEASURE_1_LABEL}"
          }],
          "fieldParameters": [{
            "parameterExpr": { "Column": { "Expression": { "SourceRef": { "Entity": "{MEASURE_PARAM_NAME}" } }, "Property": "{MEASURE_PARAM_NAME}" } },
            "index": 0, "length": 1, "sortDirection": "Descending"
          }]
        }
      },
      "sortDefinition": {
        "sort": [{ "queryRef": "{SOURCE_TABLE}.{MEASURE_1_FIELD}", "direction": "Descending" }],
        "isDefaultSort": true
      }
    },
    "objects": {
      "dataPoint": [{ "properties": { "defaultColor": { "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 3, "Percent": 0 } } } } } }],
      "labels": [{ "properties": {
        "show": { "expr": { "Literal": { "Value": "true" } } },
        "color": { "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 1, "Percent": 0 } } } } },
        "fontSize": { "expr": { "Literal": { "Value": "9D" } } }
      }}]
    },
    "visualContainerObjects": {
      "title": [{ "properties": {
        "show": { "expr": { "Literal": { "Value": "true" } } },
        "titleWrap": { "expr": { "Literal": { "Value": "true" } } },
        "bold": { "expr": { "Literal": { "Value": "true" } } },
        "alignment": { "expr": { "Literal": { "Value": "'center'" } } },
        "fontColor": { "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 3, "Percent": 0.2 } } } } },
        "background": { "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 0, "Percent": 0 } } } } }
      }}],
      "background": [{ "properties": { "show": { "expr": { "Literal": { "Value": "true" } } }, "transparency": { "expr": { "Literal": { "Value": "0D" } } } }}],
      "border": [{ "properties": { "width": { "expr": { "Literal": { "Value": "1D" } } } }}],
      "display": { "mode": "hidden" }
    },
    "drillFilterOtherVisuals": true
  }
}
```

> The `"display": { "mode": "hidden" }` inside `visualContainerObjects` makes this visual hidden on page load (Table is the default).

---

### Step 7 — Create Four Button Visuals

**Button placement** (two pairs at same x/y, toggled by bookmarks):
- Pair A (TABLE mode visible): `BTN_TABLE_ACTIVE` at x=30 y=60 | `BTN_BARCHART_INACTIVE` at x=135 y=60
- Pair B (BAR CHART mode visible): `BTN_TABLE_INACTIVE` at x=30 y=60 | `BTN_BARCHART_ACTIVE` at x=135 y=60

**ACTIVE button template** — dark background, light bold text. Use for `BTN_TABLE_ACTIVE` (label=`'Table'`, target=`{BM_BARCHART}`) and `BTN_BARCHART_ACTIVE` (label=`'Bar Chart'`, target=`{BM_TABLE}`):

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.5.0/schema.json",
  "name": "{BTN_ID}",
  "position": { "x": 30, "y": 60, "z": 24000, "height": 32, "width": 100, "tabOrder": 24000 },
  "visual": {
    "visualType": "actionButton",
    "objects": {
      "icon": [{ "properties": { "shapeType": { "expr": { "Literal": { "Value": "'blank'" } } } }, "selector": { "id": "default" } }],
      "text": [
        { "properties": { "show": { "expr": { "Literal": { "Value": "true" } } } } },
        { "properties": {
            "text": { "expr": { "Literal": { "Value": "'{BTN_LABEL}'" } } },
            "fontColor": { "solid": { "color": { "expr": { "Literal": { "Value": "'{COLOR_ACTIVE_TEXT}'" } } } } },
            "bold": { "expr": { "Literal": { "Value": "true" } } },
            "fontSize": { "expr": { "Literal": { "Value": "11D" } } }
          }, "selector": { "id": "default" }
        }
      ],
      "fill": [
        { "properties": { "show": { "expr": { "Literal": { "Value": "true" } } } } },
        { "properties": {
            "fillColor": { "solid": { "color": { "expr": { "Literal": { "Value": "'{COLOR_ACTIVE_BG}'" } } } } },
            "transparency": { "expr": { "Literal": { "Value": "0D" } } }
          }, "selector": { "id": "default" }
        }
      ],
      "outline": [{ "properties": { "lineColor": { "solid": { "color": { "expr": { "Literal": { "Value": "'{COLOR_ACTIVE_BG}'" } } } } } }, "selector": { "id": "default" } }]
    },
    "visualContainerObjects": {
      "visualLink": [{ "properties": {
        "show": { "expr": { "Literal": { "Value": "true" } } },
        "type": { "expr": { "Literal": { "Value": "'Bookmark'" } } },
        "bookmark": { "expr": { "Literal": { "Value": "'{BM_TARGET}'" } } }
      }}],
      "background": [{ "properties": { "show": { "expr": { "Literal": { "Value": "false" } } } }}],
      "border": [{ "properties": { "width": { "expr": { "Literal": { "Value": "1D" } } } }}],
      "visualHeader": [{ "properties": { "show": { "expr": { "Literal": { "Value": "false" } } } }}]
    },
    "drillFilterOtherVisuals": true
  }
}
```

**INACTIVE button template** — light background, dark non-bold text. Use for `BTN_BARCHART_INACTIVE` (label=`'Bar Chart'`, target=`{BM_BARCHART}`) and `BTN_TABLE_INACTIVE` (label=`'Table'`, target=`{BM_TABLE}`). Same JSON as above with these two changes:

- `fontColor` → `'{COLOR_INACTIVE_TEXT}'`
- `fillColor` → `'{COLOR_INACTIVE_BG}'`
- `bold` → `"false"`
- `lineColor` → `'{COLOR_INACTIVE_TEXT}'`

Also add to `visualContainerObjects` for the two hidden-by-default buttons (`BTN_TABLE_INACTIVE`, `BTN_BARCHART_ACTIVE`):
```json
"display": { "mode": "hidden" }
```

---

### Step 8 — Create Two Slicers

**Dimension slicer** — `{VISUAL_ID_DIM_SLICER}/visual.json`, single-select, shows `{DIM_PARAM_NAME}` column:

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.5.0/schema.json",
  "name": "{VISUAL_ID_DIM_SLICER}",
  "position": { "x": 0, "y": 150, "z": 5000, "height": 190, "width": 164, "tabOrder": 5000 },
  "visual": {
    "visualType": "slicer",
    "query": {
      "queryState": {
        "Values": {
          "projections": [{
            "field": { "Column": { "Expression": { "SourceRef": { "Entity": "{DIM_PARAM_NAME}" } }, "Property": "{DIM_PARAM_NAME}" } },
            "queryRef": "{DIM_PARAM_NAME}.{DIM_PARAM_NAME}", "nativeQueryRef": "{DIM_PARAM_NAME}", "active": true
          }]
        }
      }
    },
    "objects": {
      "data": [{ "properties": { "mode": { "expr": { "Literal": { "Value": "'Basic'" } } } } }],
      "selection": [{ "properties": { "singleSelect": { "expr": { "Literal": { "Value": "true" } } } } }],
      "header": [{ "properties": {
        "fontColor": { "solid": { "color": { "expr": { "Literal": { "Value": "'#ffffff'" } } } } },
        "textSize": { "expr": { "Literal": { "Value": "9D" } } }
      }}]
    },
    "visualContainerObjects": {
      "background": [{ "properties": { "show": { "expr": { "Literal": { "Value": "false" } } } }}]
    },
    "drillFilterOtherVisuals": true
  }
}
```

**Measure slicer** — identical structure; replace `{DIM_PARAM_NAME}` → `{MEASURE_PARAM_NAME}` everywhere, and set `"y": 350`.

---

### Step 9 — Create Bookmark: TABLE MODE

**File:** `{YourReport}.Report/definition/bookmarks/{BM_TABLE}.bookmark.json`

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.0.0/schema.json",
  "displayName": "Table Mode",
  "name": "{BM_TABLE}",
  "options": { "targetVisualNames": ["{BTN_TABLE_ACTIVE}", "{BTN_BARCHART_INACTIVE}"] },
  "explorationState": {
    "version": "1.40",
    "activeSection": "{PAGE_ID}",
    "sections": {
      "{PAGE_ID}": {
        "visualContainers": {
          "{VISUAL_ID_TABLE}":        { "singleVisual": { "display": { "mode": "visible" } } },
          "{VISUAL_ID_BAR}":          { "singleVisual": { "display": { "mode": "hidden"  } } },
          "{BTN_TABLE_ACTIVE}":       { "singleVisual": { "display": { "mode": "visible" } } },
          "{BTN_BARCHART_INACTIVE}":  { "singleVisual": { "display": { "mode": "visible" } } },
          "{BTN_TABLE_INACTIVE}":     { "singleVisual": { "display": { "mode": "hidden"  } } },
          "{BTN_BARCHART_ACTIVE}":    { "singleVisual": { "display": { "mode": "hidden"  } } }
        }
      }
    }
  }
}
```

---

### Step 10 — Create Bookmark: BAR CHART MODE

**File:** `{YourReport}.Report/definition/bookmarks/{BM_BARCHART}.bookmark.json`

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.0.0/schema.json",
  "displayName": "Bar Chart Mode",
  "name": "{BM_BARCHART}",
  "options": { "targetVisualNames": ["{BTN_TABLE_INACTIVE}", "{BTN_BARCHART_ACTIVE}"] },
  "explorationState": {
    "version": "1.40",
    "activeSection": "{PAGE_ID}",
    "sections": {
      "{PAGE_ID}": {
        "visualContainers": {
          "{VISUAL_ID_TABLE}":        { "singleVisual": { "display": { "mode": "hidden"  } } },
          "{VISUAL_ID_BAR}":          { "singleVisual": { "display": { "mode": "visible" } } },
          "{BTN_TABLE_ACTIVE}":       { "singleVisual": { "display": { "mode": "hidden"  } } },
          "{BTN_BARCHART_INACTIVE}":  { "singleVisual": { "display": { "mode": "hidden"  } } },
          "{BTN_TABLE_INACTIVE}":     { "singleVisual": { "display": { "mode": "visible" } } },
          "{BTN_BARCHART_ACTIVE}":    { "singleVisual": { "display": { "mode": "visible" } } }
        }
      }
    }
  }
}
```

---

### Step 11 — Register Bookmarks

In `{YourReport}.Report/definition/bookmarks/bookmarks.json`, append to the `items` array:

```json
{ "name": "{BM_TABLE}" },
{ "name": "{BM_BARCHART}" }
```

---

## File Checklist

```
SemanticModel/definition/tables/
  ├── {DIM_PARAM_NAME}.tmdl              ← Step 2
  └── {MEASURE_PARAM_NAME}.tmdl         ← Step 3
SemanticModel/definition/
  └── model.tmdl                        ← Step 4 (2 ref table lines added)

Report/definition/pages/{PAGE_ID}/visuals/
  ├── {VISUAL_ID_TABLE}/visual.json     ← Step 5
  ├── {VISUAL_ID_BAR}/visual.json       ← Step 6  (hidden by default)
  ├── {BTN_TABLE_ACTIVE}/visual.json    ← Step 7  (active style)
  ├── {BTN_BARCHART_INACTIVE}/visual.json ← Step 7 (inactive style)
  ├── {BTN_TABLE_INACTIVE}/visual.json  ← Step 7  (inactive style, hidden by default)
  ├── {BTN_BARCHART_ACTIVE}/visual.json ← Step 7  (active style, hidden by default)
  ├── {VISUAL_ID_DIM_SLICER}/visual.json  ← Step 8
  └── {VISUAL_ID_MEASURE_SLICER}/visual.json ← Step 8

Report/definition/bookmarks/
  ├── {BM_TABLE}.bookmark.json          ← Step 9
  ├── {BM_BARCHART}.bookmark.json       ← Step 10
  └── bookmarks.json                    ← Step 11 (2 entries appended)
```

---

## Button Wiring Logic

```
[Table Active]        onClick → BM_BARCHART   (user switches to bar chart)
[BarChart Inactive]   onClick → BM_BARCHART   (same, both buttons in the pair trigger same bookmark)

[Table Inactive]      onClick → BM_TABLE      (user switches back to table)
[BarChart Active]     onClick → BM_TABLE      (same)
```

**Rule:** Each button's `{BM_TARGET}` is the bookmark for the *opposite* mode — clicking always switches away from the current view.
