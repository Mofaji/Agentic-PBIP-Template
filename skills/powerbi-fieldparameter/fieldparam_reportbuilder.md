# Power BI PBIP — Field Parameter based report builder Boilerplate
## (Table ↔ Bar Chart with 4-Button Mode Switch)

> **How to use this doc in a new Copilot chat:**
> Paste this file into the chat, replace every `{PLACEHOLDER}` with your real values, and ask Copilot to generate the files. All file paths are relative to your `.Report` / `.SemanticModel` root.

---

## Placeholders — Fill These In First

| Placeholder | What to replace with | Example |
|---|---|---|
| `{SOURCE_TABLE}` | Your fact/sales table name in the semantic model | `Sales` |
| `{DIM_PARAM_NAME}` | Name for the dimension field parameter table | `DimensionParam` |
| `{MEASURE_PARAM_NAME}` | Name for the measure field parameter table | `MeasureParam` |
| `{DIM_1_LABEL}` | First dimension display label | `City` |
| `{DIM_1_COLUMN}` | First dimension column name in `{SOURCE_TABLE}` | `City` |
| `{DIM_2_LABEL}` | Second dimension display label | `Region` |
| `{DIM_2_COLUMN}` | Second dimension column name | `Region` |
| `{DIM_3_LABEL}` | Third dimension display label | `Company` |
| `{DIM_3_COLUMN}` | Third dimension column name | `Company` |
| `{MEASURE_1_LABEL}` | First measure display label | `Total Sales` |
| `{MEASURE_1_FIELD}` | First measure column/measure name | `Total Sales` |
| `{MEASURE_2_LABEL}` | Second measure display label | `Qty` |
| `{MEASURE_2_FIELD}` | Second measure column/measure name | `Qty` |
| `{MEASURE_3_LABEL}` | Third measure display label | `Profit` |
| `{MEASURE_3_FIELD}` | Third measure column/measure name | `Profit` |
| `{PAGE_ID}` | Your page folder name (alphanumeric ID) | `1310d213c71292d6a234` |
| `{COLOR_ACTIVE_BG}` | Active button background hex | `#003153` |
| `{COLOR_ACTIVE_TEXT}` | Active button text hex (light) | `#FFFFFF` |
| `{COLOR_INACTIVE_BG}` | Inactive button background hex | `#D9E1F2` |
| `{COLOR_INACTIVE_TEXT}` | Inactive button text hex (dark) | `#003153` |

---

## Architecture Overview

```
Two Field Parameter slicers (left/right panel)
  └─ DimensionParam  ─── controls: rows in table / Y-axis in bar chart
  └─ MeasureParam    ─── controls: value column in table / X-axis in bar chart

Two main visuals (stacked, same position)
  └─ tableEx         ─── visible in TABLE mode
  └─ clusteredBarChart ─ visible in BAR CHART mode

Four buttons (two pairs, each pair visible in one mode)
  TABLE MODE visible:      [Table ← active dark]   [Bar Chart → inactive light]
  BAR CHART MODE visible:  [Table ← inactive light] [Bar Chart → active dark]

Two bookmarks
  └─ BM_TABLE_MODE     ─── shows tableEx + TableActive btn + BarChartInactive btn
  └─ BM_BARCHART_MODE  ─── shows clusteredBarChart + BarChartActive btn + TableInactive btn
```

---

## STEP 1 — Semantic Model: Dimension Field Parameter Table

**File:** `{YourReport}.SemanticModel/definition/tables/{DIM_PARAM_NAME}.tmdl`

```tmdl
table '{DIM_PARAM_NAME}'
	lineageTag: {GENERATE_GUID_1}

	column '{DIM_PARAM_NAME}'
		lineageTag: {GENERATE_GUID_2}
		summarizeBy: none
		sourceColumn: [Value1]
		sortByColumn: '{DIM_PARAM_NAME} Order'

		relatedColumnDetails
			groupByColumn: '{DIM_PARAM_NAME} Fields'

		annotation SummarizationSetBy = Automatic

	column '{DIM_PARAM_NAME} Fields'
		isHidden
		lineageTag: {GENERATE_GUID_3}
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
		lineageTag: {GENERATE_GUID_4}
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

	annotation PBI_Id = {GENERATE_GUID_5}
```

> **Note:** `lineageTag` and `PBI_Id` values must each be a unique lowercase UUID (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`). Generate them with `[guid]::NewGuid().ToString()` in PowerShell.

---

## STEP 2 — Semantic Model: Measure Field Parameter Table

**File:** `{YourReport}.SemanticModel/definition/tables/{MEASURE_PARAM_NAME}.tmdl`

```tmdl
table '{MEASURE_PARAM_NAME}'
	lineageTag: {GENERATE_GUID_6}

	column '{MEASURE_PARAM_NAME}'
		lineageTag: {GENERATE_GUID_7}
		summarizeBy: none
		sourceColumn: [Value1]
		sortByColumn: '{MEASURE_PARAM_NAME} Order'

		relatedColumnDetails
			groupByColumn: '{MEASURE_PARAM_NAME} Fields'

		annotation SummarizationSetBy = Automatic

	column '{MEASURE_PARAM_NAME} Fields'
		isHidden
		lineageTag: {GENERATE_GUID_8}
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
		lineageTag: {GENERATE_GUID_9}
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

	annotation PBI_Id = {GENERATE_GUID_10}
```

---

## STEP 3 — Register Both Tables in model.tmdl

**File:** `{YourReport}.SemanticModel/definition/model.tmdl`

Add these two lines inside the `ref table` block (order does not matter):

```tmdl
ref table '{DIM_PARAM_NAME}'
ref table '{MEASURE_PARAM_NAME}'
```

Also add them to the `annotation PBI_QueryOrder` array (append to the end of the JSON array string).

---

## STEP 4 — Report: Table Visual (tableEx)

**File:** `{YourReport}.Report/definition/pages/{PAGE_ID}/visuals/{VISUAL_ID_TABLE}/visual.json`

Use a new unique 20-char hex ID for `{VISUAL_ID_TABLE}`.  
Position this visual in your main canvas area (example: x=182, y=118, w=1096, h=600).

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.5.0/schema.json",
  "name": "{VISUAL_ID_TABLE}",
  "position": {
    "x": 182,
    "y": 118,
    "z": 1000,
    "height": 600,
    "width": 1096,
    "tabOrder": 1000
  },
  "visual": {
    "visualType": "tableEx",
    "query": {
      "queryState": {
        "Values": {
          "projections": [
            {
              "field": {
                "Column": {
                  "Expression": { "SourceRef": { "Entity": "{SOURCE_TABLE}" } },
                  "Property": "{DIM_1_COLUMN}"
                }
              },
              "queryRef": "{SOURCE_TABLE}.{DIM_1_COLUMN}",
              "nativeQueryRef": "{DIM_1_LABEL}",
              "displayName": "{DIM_1_LABEL}"
            },
            {
              "field": {
                "Measure": {
                  "Expression": { "SourceRef": { "Entity": "{SOURCE_TABLE}" } },
                  "Property": "{MEASURE_1_FIELD}"
                }
              },
              "queryRef": "{SOURCE_TABLE}.{MEASURE_1_FIELD}",
              "nativeQueryRef": "{MEASURE_1_LABEL}",
              "displayName": "{MEASURE_1_LABEL}"
            }
          ],
          "fieldParameters": [
            {
              "parameterExpr": {
                "Column": {
                  "Expression": { "SourceRef": { "Entity": "{DIM_PARAM_NAME}" } },
                  "Property": "{DIM_PARAM_NAME}"
                }
              },
              "index": 0,
              "length": 1
            },
            {
              "parameterExpr": {
                "Column": {
                  "Expression": { "SourceRef": { "Entity": "{MEASURE_PARAM_NAME}" } },
                  "Property": "{MEASURE_PARAM_NAME}"
                }
              },
              "index": 1,
              "length": 1
            }
          ]
        }
      }
    },
    "objects": {
      "grid": [
        {
          "properties": {
            "gridHorizontalColor": {
              "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 2, "Percent": 0.6 } } } }
            }
          }
        }
      ],
      "columnHeaders": [
        {
          "properties": {
            "fontColor": {
              "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 0, "Percent": 0 } } } }
            },
            "backColor": {
              "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 2, "Percent": 0.4 } } } }
            },
            "bold": { "expr": { "Literal": { "Value": "true" } } }
          }
        }
      ],
      "values": [
        {
          "properties": {
            "fontColor": {
              "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 1, "Percent": 0 } } } }
            },
            "alternatingRowsColor": {
              "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 2, "Percent": 0.6 } } } }
            }
          }
        }
      ]
    },
    "visualContainerObjects": {
      "title": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "true" } } },
            "titleWrap": { "expr": { "Literal": { "Value": "true" } } },
            "bold": { "expr": { "Literal": { "Value": "true" } } },
            "alignment": { "expr": { "Literal": { "Value": "'center'" } } },
            "fontColor": {
              "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 3, "Percent": 0.2 } } } }
            },
            "background": {
              "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 0, "Percent": 0 } } } }
            }
          }
        }
      ],
      "background": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "true" } } },
            "transparency": { "expr": { "Literal": { "Value": "0D" } } }
          }
        }
      ],
      "border": [
        {
          "properties": {
            "width": { "expr": { "Literal": { "Value": "1D" } } }
          }
        }
      ]
    },
    "drillFilterOtherVisuals": true
  }
}
```

---

## STEP 5 — Report: Bar Chart Visual (clusteredBarChart)

**File:** `{YourReport}.Report/definition/pages/{PAGE_ID}/visuals/{VISUAL_ID_BAR}/visual.json`

Place at same x/y/w/h as the table so they overlap (toggled by bookmarks).  
Set `z` higher than the table (e.g. `z: 20000`) so it renders on top when visible.

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.5.0/schema.json",
  "name": "{VISUAL_ID_BAR}",
  "position": {
    "x": 182,
    "y": 118,
    "z": 20000,
    "height": 600,
    "width": 1096,
    "tabOrder": 20000
  },
  "visual": {
    "visualType": "clusteredBarChart",
    "query": {
      "queryState": {
        "Category": {
          "projections": [
            {
              "field": {
                "Column": {
                  "Expression": { "SourceRef": { "Entity": "{SOURCE_TABLE}" } },
                  "Property": "{DIM_1_COLUMN}"
                }
              },
              "queryRef": "{SOURCE_TABLE}.{DIM_1_COLUMN}",
              "nativeQueryRef": "{DIM_1_LABEL}",
              "active": true
            }
          ],
          "fieldParameters": [
            {
              "parameterExpr": {
                "Column": {
                  "Expression": { "SourceRef": { "Entity": "{DIM_PARAM_NAME}" } },
                  "Property": "{DIM_PARAM_NAME}"
                }
              },
              "index": 0,
              "length": 1
            }
          ]
        },
        "Y": {
          "projections": [
            {
              "field": {
                "Measure": {
                  "Expression": { "SourceRef": { "Entity": "{SOURCE_TABLE}" } },
                  "Property": "{MEASURE_1_FIELD}"
                }
              },
              "queryRef": "{SOURCE_TABLE}.{MEASURE_1_FIELD}",
              "nativeQueryRef": "{MEASURE_1_LABEL}"
            }
          ],
          "fieldParameters": [
            {
              "parameterExpr": {
                "Column": {
                  "Expression": { "SourceRef": { "Entity": "{MEASURE_PARAM_NAME}" } },
                  "Property": "{MEASURE_PARAM_NAME}"
                }
              },
              "index": 0,
              "length": 1,
              "sortDirection": "Descending"
            }
          ]
        }
      },
      "sortDefinition": {
        "sort": [
          {
            "queryRef": "{SOURCE_TABLE}.{MEASURE_1_FIELD}",
            "direction": "Descending"
          }
        ],
        "isDefaultSort": true
      }
    },
    "objects": {
      "dataPoint": [
        {
          "properties": {
            "defaultColor": {
              "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 3, "Percent": 0 } } } }
            }
          }
        }
      ],
      "labels": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "true" } } },
            "color": {
              "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 1, "Percent": 0 } } } }
            },
            "fontSize": { "expr": { "Literal": { "Value": "9D" } } }
          }
        }
      ]
    },
    "visualContainerObjects": {
      "title": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "true" } } },
            "titleWrap": { "expr": { "Literal": { "Value": "true" } } },
            "bold": { "expr": { "Literal": { "Value": "true" } } },
            "alignment": { "expr": { "Literal": { "Value": "'center'" } } },
            "fontColor": {
              "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 3, "Percent": 0.2 } } } }
            },
            "background": {
              "solid": { "color": { "expr": { "ThemeDataColor": { "ColorId": 0, "Percent": 0 } } } }
            }
          }
        }
      ],
      "background": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "true" } } },
            "transparency": { "expr": { "Literal": { "Value": "0D" } } }
          }
        }
      ],
      "border": [
        {
          "properties": {
            "width": { "expr": { "Literal": { "Value": "1D" } } }
          }
        }
      ]
    },
    "drillFilterOtherVisuals": true
  }
}
```

---

## STEP 6 — Report: Four Button Visuals

### Button Roles

| ID Variable | Label | Style | Visible In | Bookmark Action |
|---|---|---|---|---|
| `{BTN_TABLE_ACTIVE}` | Table | **Dark BG / Light text** (active) | TABLE mode | `{BM_BARCHART}` (switches to bar chart) |
| `{BTN_BARCHART_INACTIVE}` | Bar Chart | Light BG / Dark text (inactive) | TABLE mode | `{BM_BARCHART}` |
| `{BTN_TABLE_INACTIVE}` | Table | Light BG / Dark text (inactive) | BAR CHART mode | `{BM_TABLE}` |
| `{BTN_BARCHART_ACTIVE}` | Bar Chart | **Dark BG / Light text** (active) | BAR CHART mode | `{BM_TABLE}` (switches to table) |

Position buttons side by side. Example: each 100×32, placed at the top-left of your sidebar or header.  
- `{BTN_TABLE_ACTIVE}` x=30 y=60  
- `{BTN_BARCHART_INACTIVE}` x=135 y=60  
- `{BTN_TABLE_INACTIVE}` x=30 y=60 *(same position — hidden when other pair visible)*  
- `{BTN_BARCHART_ACTIVE}` x=135 y=60  

### Template — ACTIVE button (dark bg, light text)

Replace `{BTN_LABEL}` with `'Table'` or `'Bar Chart'`, `{BTN_ID}` with a new unique ID, `{BM_TARGET}` with the bookmark ID this button navigates to, and `{TAB_Z}` with a unique z-order number.

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.5.0/schema.json",
  "name": "{BTN_ID}",
  "position": {
    "x": 30,
    "y": 60,
    "z": {TAB_Z},
    "height": 32,
    "width": 100,
    "tabOrder": {TAB_Z}
  },
  "visual": {
    "visualType": "actionButton",
    "objects": {
      "icon": [
        {
          "properties": {
            "shapeType": { "expr": { "Literal": { "Value": "'blank'" } } }
          },
          "selector": { "id": "default" }
        }
      ],
      "text": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "true" } } }
          }
        },
        {
          "properties": {
            "text": { "expr": { "Literal": { "Value": "{BTN_LABEL}" } } },
            "fontColor": {
              "solid": { "color": { "expr": { "Literal": { "Value": "'{COLOR_ACTIVE_TEXT}'" } } } }
            },
            "bold": { "expr": { "Literal": { "Value": "true" } } },
            "fontSize": { "expr": { "Literal": { "Value": "11D" } } }
          },
          "selector": { "id": "default" }
        }
      ],
      "fill": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "true" } } }
          }
        },
        {
          "properties": {
            "fillColor": {
              "solid": { "color": { "expr": { "Literal": { "Value": "'{COLOR_ACTIVE_BG}'" } } } }
            },
            "transparency": { "expr": { "Literal": { "Value": "0D" } } }
          },
          "selector": { "id": "default" }
        }
      ],
      "outline": [
        {
          "properties": {
            "lineColor": {
              "solid": { "color": { "expr": { "Literal": { "Value": "'{COLOR_ACTIVE_BG}'" } } } }
            }
          },
          "selector": { "id": "default" }
        }
      ]
    },
    "visualContainerObjects": {
      "visualLink": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "true" } } },
            "type": { "expr": { "Literal": { "Value": "'Bookmark'" } } },
            "bookmark": { "expr": { "Literal": { "Value": "'{BM_TARGET}'" } } }
          }
        }
      ],
      "background": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "false" } } }
          }
        }
      ],
      "border": [
        {
          "properties": {
            "width": { "expr": { "Literal": { "Value": "1D" } } }
          }
        }
      ],
      "visualHeader": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "false" } } }
          }
        }
      ]
    },
    "drillFilterOtherVisuals": true
  }
}
```

### Template — INACTIVE button (light bg, dark text)

Same structure — only the color values change:

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.5.0/schema.json",
  "name": "{BTN_ID}",
  "position": {
    "x": 135,
    "y": 60,
    "z": {TAB_Z},
    "height": 32,
    "width": 100,
    "tabOrder": {TAB_Z}
  },
  "visual": {
    "visualType": "actionButton",
    "objects": {
      "icon": [
        {
          "properties": {
            "shapeType": { "expr": { "Literal": { "Value": "'blank'" } } }
          },
          "selector": { "id": "default" }
        }
      ],
      "text": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "true" } } }
          }
        },
        {
          "properties": {
            "text": { "expr": { "Literal": { "Value": "{BTN_LABEL}" } } },
            "fontColor": {
              "solid": { "color": { "expr": { "Literal": { "Value": "'{COLOR_INACTIVE_TEXT}'" } } } }
            },
            "bold": { "expr": { "Literal": { "Value": "false" } } },
            "fontSize": { "expr": { "Literal": { "Value": "11D" } } }
          },
          "selector": { "id": "default" }
        }
      ],
      "fill": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "true" } } }
          }
        },
        {
          "properties": {
            "fillColor": {
              "solid": { "color": { "expr": { "Literal": { "Value": "'{COLOR_INACTIVE_BG}'" } } } }
            },
            "transparency": { "expr": { "Literal": { "Value": "0D" } } }
          },
          "selector": { "id": "default" }
        }
      ],
      "outline": [
        {
          "properties": {
            "lineColor": {
              "solid": { "color": { "expr": { "Literal": { "Value": "'{COLOR_INACTIVE_TEXT}'" } } } }
            }
          },
          "selector": { "id": "default" }
        }
      ]
    },
    "visualContainerObjects": {
      "visualLink": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "true" } } },
            "type": { "expr": { "Literal": { "Value": "'Bookmark'" } } },
            "bookmark": { "expr": { "Literal": { "Value": "'{BM_TARGET}'" } } }
          }
        }
      ],
      "background": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "false" } } }
          }
        }
      ],
      "border": [
        {
          "properties": {
            "width": { "expr": { "Literal": { "Value": "1D" } } }
          }
        }
      ],
      "visualHeader": [
        {
          "properties": {
            "show": { "expr": { "Literal": { "Value": "false" } } }
          }
        }
      ]
    },
    "drillFilterOtherVisuals": true
  }
}
```

---

## STEP 7 — Report: Two Slicers for Field Parameters

Each slicer lets the user pick which dimension/measure to show. Place them in your sidebar or header.

### Dimension Slicer

**File:** `{YourReport}.Report/definition/pages/{PAGE_ID}/visuals/{VISUAL_ID_DIM_SLICER}/visual.json`

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
          "projections": [
            {
              "field": {
                "Column": {
                  "Expression": { "SourceRef": { "Entity": "{DIM_PARAM_NAME}" } },
                  "Property": "{DIM_PARAM_NAME}"
                }
              },
              "queryRef": "{DIM_PARAM_NAME}.{DIM_PARAM_NAME}",
              "nativeQueryRef": "{DIM_PARAM_NAME}",
              "active": true
            }
          ]
        }
      }
    },
    "objects": {
      "data": [
        { "properties": { "mode": { "expr": { "Literal": { "Value": "'Basic'" } } } } }
      ],
      "selection": [
        { "properties": { "singleSelect": { "expr": { "Literal": { "Value": "true" } } } } }
      ],
      "header": [
        {
          "properties": {
            "fontColor": { "solid": { "color": { "expr": { "Literal": { "Value": "'#ffffff'" } } } } },
            "textSize": { "expr": { "Literal": { "Value": "9D" } } }
          }
        }
      ]
    },
    "visualContainerObjects": {
      "background": [
        { "properties": { "show": { "expr": { "Literal": { "Value": "false" } } } } }
      ]
    },
    "drillFilterOtherVisuals": true
  }
}
```

### Measure Slicer

Same structure as above — change `{DIM_PARAM_NAME}` → `{MEASURE_PARAM_NAME}`, and set y position below the dimension slicer (e.g. `y: 350`).

---

## STEP 8 — Report: Bookmark JSON — TABLE MODE

**File:** `{YourReport}.Report/definition/bookmarks/{BM_TABLE}.bookmark.json`

This bookmark is triggered when the user clicks "Table". It shows the table visual + the active-Table button + the inactive-BarChart button; and hides the bar chart + its button pair.

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.0.0/schema.json",
  "displayName": "Table Mode",
  "name": "{BM_TABLE}",
  "options": {
    "targetVisualNames": [
      "{BTN_TABLE_ACTIVE}",
      "{BTN_BARCHART_INACTIVE}"
    ]
  },
  "explorationState": {
    "version": "1.40",
    "activeSection": "{PAGE_ID}",
    "sections": {
      "{PAGE_ID}": {
        "visualContainers": {
          "{VISUAL_ID_TABLE}": {
            "singleVisual": { "display": { "mode": "visible" } }
          },
          "{VISUAL_ID_BAR}": {
            "singleVisual": { "display": { "mode": "hidden" } }
          },
          "{BTN_TABLE_ACTIVE}": {
            "singleVisual": { "display": { "mode": "visible" } }
          },
          "{BTN_BARCHART_INACTIVE}": {
            "singleVisual": { "display": { "mode": "visible" } }
          },
          "{BTN_TABLE_INACTIVE}": {
            "singleVisual": { "display": { "mode": "hidden" } }
          },
          "{BTN_BARCHART_ACTIVE}": {
            "singleVisual": { "display": { "mode": "hidden" } }
          }
        }
      }
    }
  }
}
```

---

## STEP 9 — Report: Bookmark JSON — BAR CHART MODE

**File:** `{YourReport}.Report/definition/bookmarks/{BM_BARCHART}.bookmark.json`

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.0.0/schema.json",
  "displayName": "Bar Chart Mode",
  "name": "{BM_BARCHART}",
  "options": {
    "targetVisualNames": [
      "{BTN_TABLE_INACTIVE}",
      "{BTN_BARCHART_ACTIVE}"
    ]
  },
  "explorationState": {
    "version": "1.40",
    "activeSection": "{PAGE_ID}",
    "sections": {
      "{PAGE_ID}": {
        "visualContainers": {
          "{VISUAL_ID_TABLE}": {
            "singleVisual": { "display": { "mode": "hidden" } }
          },
          "{VISUAL_ID_BAR}": {
            "singleVisual": { "display": { "mode": "visible" } }
          },
          "{BTN_TABLE_ACTIVE}": {
            "singleVisual": { "display": { "mode": "hidden" } }
          },
          "{BTN_BARCHART_INACTIVE}": {
            "singleVisual": { "display": { "mode": "hidden" } }
          },
          "{BTN_TABLE_INACTIVE}": {
            "singleVisual": { "display": { "mode": "visible" } }
          },
          "{BTN_BARCHART_ACTIVE}": {
            "singleVisual": { "display": { "mode": "visible" } }
          }
        }
      }
    }
  }
}
```

---

## STEP 10 — Register Bookmarks in bookmarks.json

**File:** `{YourReport}.Report/definition/bookmarks/bookmarks.json`

Add both bookmark names to the `items` array:

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmarksMetadata/1.0.0/schema.json",
  "items": [
    { "name": "{BM_TABLE}" },
    { "name": "{BM_BARCHART}" }
  ]
}
```

If the file already exists, append the two entries to the existing `items` array.

---

## STEP 11 — Default Visibility: Set Starting Mode

To make **TABLE MODE** the default when the page loads, ensure in each visual's `visual.json`:
- `{VISUAL_ID_TABLE}` — no `display` property (visible by default)
- `{VISUAL_ID_BAR}` — add to `visualContainerObjects`:
  ```json
  "display": { "mode": "hidden" }
  ```
- `{BTN_TABLE_ACTIVE}` + `{BTN_BARCHART_INACTIVE}` — visible (no display override)
- `{BTN_TABLE_INACTIVE}` + `{BTN_BARCHART_ACTIVE}` — add `"display": { "mode": "hidden" }` to their `visualContainerObjects`

---

## Quick Reference — All IDs to Generate

Run this PowerShell to generate all the UUIDs / visual IDs you need:

```powershell
# Semantic model GUIDs (for TMDL lineageTags)
1..10 | ForEach-Object { [guid]::NewGuid().ToString() }

# Report visual IDs (20-char hex)
1..8 | ForEach-Object { -join ((1..20) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) }) }

# Bookmark IDs (20-char hex)
1..2 | ForEach-Object { -join ((1..20) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) }) }
```

### Assign generated values:

| Variable | Role | Assign from |
|---|---|---|
| `{GENERATE_GUID_1..10}` | TMDL lineageTags & PBI_Id | PowerShell GUIDs |
| `{VISUAL_ID_TABLE}` | tableEx visual folder name | 20-char hex |
| `{VISUAL_ID_BAR}` | clusteredBarChart visual folder name | 20-char hex |
| `{VISUAL_ID_DIM_SLICER}` | Dimension param slicer folder name | 20-char hex |
| `{VISUAL_ID_MEASURE_SLICER}` | Measure param slicer folder name | 20-char hex |
| `{BTN_TABLE_ACTIVE}` | Table button (active) folder name | 20-char hex |
| `{BTN_BARCHART_INACTIVE}` | Bar Chart button (inactive) folder name | 20-char hex |
| `{BTN_TABLE_INACTIVE}` | Table button (inactive) folder name | 20-char hex |
| `{BTN_BARCHART_ACTIVE}` | Bar Chart button (active) folder name | 20-char hex |
| `{BM_TABLE}` | TABLE MODE bookmark file name | 20-char hex |
| `{BM_BARCHART}` | BAR CHART MODE bookmark file name | 20-char hex |

---

## File Checklist

```
SemanticModel/definition/tables/
  ├── {DIM_PARAM_NAME}.tmdl              ← STEP 1
  └── {MEASURE_PARAM_NAME}.tmdl         ← STEP 2
SemanticModel/definition/
  └── model.tmdl                        ← STEP 3 (add 2 ref table lines)

Report/definition/pages/{PAGE_ID}/visuals/
  ├── {VISUAL_ID_TABLE}/visual.json     ← STEP 4
  ├── {VISUAL_ID_BAR}/visual.json       ← STEP 5
  ├── {VISUAL_ID_DIM_SLICER}/visual.json  ← STEP 7
  ├── {VISUAL_ID_MEASURE_SLICER}/visual.json ← STEP 7
  ├── {BTN_TABLE_ACTIVE}/visual.json    ← STEP 6 (active template)
  ├── {BTN_BARCHART_INACTIVE}/visual.json ← STEP 6 (inactive template)
  ├── {BTN_TABLE_INACTIVE}/visual.json  ← STEP 6 (inactive template)
  └── {BTN_BARCHART_ACTIVE}/visual.json ← STEP 6 (active template)

Report/definition/bookmarks/
  ├── {BM_TABLE}.bookmark.json          ← STEP 8
  ├── {BM_BARCHART}.bookmark.json       ← STEP 9
  └── bookmarks.json                    ← STEP 10 (add 2 entries)
```

---

## Button Wiring Summary

```
[Table Active]       onClick → BM_BARCHART  (switches to bar chart)
[BarChart Inactive]  onClick → BM_BARCHART  (same — either button works)

[Table Inactive]     onClick → BM_TABLE     (switches back to table)
[BarChart Active]    onClick → BM_TABLE     (same)
```

**BM_TABLE shows:** table + TableActive + BarChartInactive  
**BM_BARCHART shows:** bar chart + BarChartActive + TableInactive
Take transparancy of buttons 0 , it should be 100% opique and do not double repeat buttons in SVG BG Canvas