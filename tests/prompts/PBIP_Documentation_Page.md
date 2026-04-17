# Copilot Execution Prompt: PBIP Documentation Page Generator

Use this prompt when you want Copilot to summarize the PBIP project and create a dedicated Power BI Documentation page with an SVG canvas background.

## How to run with Copilot

In Copilot Chat, send:

`Execute the instructions in PBIP_Documentation_Page.md exactly.`

---

## Objective

Create a new report page named `Documentation` that visually documents the PBIP project.

The page background must be an SVG canvas generated from project metadata and registered in `RegisteredResources`.

---

## Hard Requirements

1. Read and summarize the current PBIP folder before generating assets.
2. Add a new page named `Documentation` in report definitions.
3. Generate one SVG documentation canvas and use it as `page.json -> objects.background.image`.
4. Follow the Material Details documentation-page pattern for layout and background binding.
5. Keep existing schema/version compatibility; do not force unrelated migrations.
6. Do not modify business DAX or semantic model logic for this task.
7. Produce a markdown summary file alongside the visual page output.

---

## Material Details Reference Pattern (Use This Structure)

Use this as the page pattern baseline:

- `displayOption: "ActualSize"`
- `height: 2740`
- `width: 816`
- `objects.outspace.color: '#FBF7F2'`
- `objects.background.image.url.expr.ResourcePackageItem`
  - `PackageName: "RegisteredResources"`
  - `PackageType: 1`
  - `ItemName: <exact registered resource item name>`
- `objects.background.image.scaling: 'Fill'`
- `objects.background.transparency: 0D`

Optional tiny helper visual is allowed (for example a 12x12 card at bottom), but not required.

---

## Execution Steps

### Phase 1: Discover artifacts

Locate and read:

- `*.pbip`
- `*.Report/definition/report.json`
- `*.Report/definition/version.json`
- `*.Report/definition/pages/pages.json`
- `*.Report/definition/pages/*/page.json`
- `*.Report/definition/pages/*/visuals/*/visual.json`
- `*.SemanticModel/definition/model.tmdl`
- `*.SemanticModel/definition/relationships.tmdl` (if present)
- `*.SemanticModel/definition/tables/*.tmdl`

Stop and report missing artifacts if any required path is absent.

### Phase 2: Build documentation summary data

Collect at minimum:

1. PBIP project name
2. Report schema/version info
3. Semantic model annotation summary (`__PBI_TimeIntelligenceEnabled`, cultures)
4. Table count and table list
5. Measure count and measure-home table distribution
6. Relationship count and bidirectional count
7. Page count and page names
8. Visual count and visual type distribution
9. Registered resources summary (`Image`, `CustomTheme`, etc.)

### Phase 3: Generate SVG documentation canvas

Create one SVG that includes:

- Title block (`Project Documentation`)
- Project info section
- Semantic model section
- Report/pages/visuals section
- Resource package section
- Timestamp (`Generated On`)

Write SVG to:

- `*.Report/StaticResources/RegisteredResources/DocumentationPageCanvas.svg`

If that file already exists, update it in place.

### Phase 4: Register SVG in report resources

Update `*.Report/definition/report.json`:

- Ensure `resourcePackages` includes `RegisteredResources`
- Add or update item entry:
  - `name`: `DocumentationPageCanvas.svg`
  - `path`: `DocumentationPageCanvas.svg`
  - `type`: `Image`

### Phase 5: Create Documentation page definition

1. Add a new page id folder under `*.Report/definition/pages/<new-page-id>/`
2. Create `page.json` with:
   - `displayName`: `Documentation`
   - `displayOption`: `ActualSize`
   - `width`: `816`
   - `height`: `2740`
   - `objects.outspace` and `objects.background` using the Material Details reference pattern
3. Point `ResourcePackageItem.ItemName` to `DocumentationPageCanvas.svg`

### Phase 6: Update pages metadata

Update `*.Report/definition/pages/pages.json`:

- Append the new page id to `pageOrder`
- Keep existing `activePageName` unchanged unless user requested otherwise

### Phase 7: Produce markdown documentation summary

Create or update:

- `docs/PBIP-DOCUMENTATION-PAGE.md`

Include:

- What was discovered
- What files were created/updated
- New page id and display name
- SVG resource mapping details
- Any compatibility assumptions

---

## Output Contract

After execution, these outputs must exist:

1. SVG canvas file in `RegisteredResources`
2. Updated `report.json` resource registration
3. New `Documentation` page folder with `page.json`
4. Updated `pages.json` page order
5. `docs/PBIP-DOCUMENTATION-PAGE.md` summary report

Do not change unrelated visuals/pages/model logic.
