# Embedding a `.pbiviz` in a PBIP report

A PBIP report can carry a custom visual's bundle inline, so the project opens complete on any machine with nothing to import. Three things must line up. Get one wrong and the visual renders as an empty box with **no error dialog**.

```
1. payload       <Project>.Report/CustomVisuals/<guid>/package.json
                 <Project>.Report/CustomVisuals/<guid>/resources/<guid>.pbiviz.json
2. registration  <Project>.Report/definition/report.json -> resourcePackages[] (type "CustomVisual")
3. reference     <page>/visuals/<id>/visual.json -> visual.visualType == <guid>
```

`tools/sync-visuals.mjs` does 1 and 2 and verifies 3. The rest of this file explains the mechanics for when something breaks.

---

## The GUID is the identity

`pbiviz.json > visual.guid` has the form `<name><32 uppercase hex>`, e.g. `finVarianceTable2F77965E58BB44A39B097765978DBE59`.

- It is the folder name under `CustomVisuals/`, the `resourcePackages[].name`, the resource file name, and every `visualType`.
- **Never change it** once a report references it. Renaming a visual means changing `displayName`, not `name` or `guid`.
- `tools/new_visual.py` generates it once and records it in `tools/visuals.json`. Every other script reads it from there.

## 1. Payload

`pbiviz package --resources --no-pbiviz` writes exactly the two payload files to `dist/`:

```
dist/package.json                         -> CustomVisuals/<guid>/package.json
dist/resources/<guid>.pbiviz.json         -> CustomVisuals/<guid>/resources/<guid>.pbiviz.json
```

- The `.pbiviz.json` holds the whole bundle in `content.js` as a single 30–200 KB line. **Byte-copy it.** Never parse and re-serialise it: that reformatting corrupts the bundle.
- A `.pbiviz` archive (from `--pbiviz-too`) is just a ZIP of those same two files. It is only needed for *Import a visual from a file* in another report.

## 2. Registration (`report.json`)

```json
"resourcePackages": [
  { "name": "RegisteredResources", "type": "RegisteredResources", "items": [ ... ] },
  {
    "name": "finVarianceTable2F77965E58BB44A39B097765978DBE59",
    "type": "CustomVisual",
    "items": [
      {
        "name": "finVarianceTable2F77965E58BB44A39B097765978DBE59.pbiviz.json",
        "path": "finVarianceTable2F77965E58BB44A39B097765978DBE59.pbiviz.json",
        "type": "CustomVisualMetadata"
      }
    ]
  }
]
```

- Resource items for `CustomVisual` packages resolve under `CustomVisuals/<guid>/resources/`, **not** `StaticResources/`. `scripts/validate-pbip.ps1` knows this.
- Third-party marketplace visuals are **not** embedded. They are listed in `report.json > publicCustomVisuals` and Desktop fetches them. That is also why their licence can expire on you.
- `sync-visuals.mjs` rewrites only the `CustomVisual` entries whose GUID is in `tools/visuals.json`. It keeps `RegisteredResources` and any other custom visual.

## 3. Reference (`visual.json`)

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.12.0/schema.json",
  "name": "a1b2c3d4e5f6a7b8c9d0",
  "position": { "x": 26, "y": 202, "z": 2000, "height": 498, "width": 760, "tabOrder": 2000 },
  "visual": {
    "visualType": "finVarianceTable2F77965E58BB44A39B097765978DBE59",
    "query": {
      "queryState": {
        "rows": { "projections": [
          { "field": { "Column": { "Expression": { "SourceRef": { "Entity": "Account Hierarchy" } }, "Property": "Level 1" } },
            "queryRef": "Account Hierarchy.Level 1", "nativeQueryRef": "Level 1" }
        ] },
        "ac": { "projections": [
          { "field": { "Measure": { "Expression": { "SourceRef": { "Entity": "_Measures" } }, "Property": "Actual" } },
            "queryRef": "_Measures.Actual", "nativeQueryRef": "Actual", "displayName": "AC" }
        ] }
      }
    },
    "objects": {
      "display": [ { "properties": { "unit": { "expr": { "Literal": { "Value": "'K'" } } } } } ]
    },
    "visualContainerObjects": {
      "background": [ { "properties": { "show": { "expr": { "Literal": { "Value": "false" } } } } } ],
      "border":     [ { "properties": { "show": { "expr": { "Literal": { "Value": "false" } } } } } ],
      "dropShadow": [ { "properties": { "show": { "expr": { "Literal": { "Value": "false" } } } } } ],
      "title":      [ { "properties": { "show": { "expr": { "Literal": { "Value": "false" } } } } } ]
    },
    "drillFilterOtherVisuals": true
  }
}
```

Rules:

| Rule | Consequence if broken |
| --- | --- |
| Every `queryState` key is a `dataRoles[].name` from `capabilities.json` | Field silently not delivered; visual shows its empty state |
| Every `objects` key and property exists in `capabilities.json > objects` | Setting silently ignored |
| Projection order inside a role is the order the visual receives columns | Hierarchy levels arrive in the wrong order |
| `displayName` on a projection renames the column in the dataView (tooltips, headers) | — |
| Use the schema version the installed Desktop writes (check an existing `visual.json`) | "Property not in declared schema" on load |
| Never write `"selector": null` | Load error |

`tools/pbir_helpers.py` builds this structure and `check_against_capabilities()` catches the first two rows before Desktop does.

**Literal encoding** (a wrong suffix falls back to the default, silently):

| Type in capabilities | Literal |
| --- | --- |
| `text`, `enumeration` | `"'value'"` |
| `bool` | `"true"` / `"false"` |
| `integer` | `"5L"` |
| `numeric`, `formatting.fontSize` | `"11D"` |
| `fill` | `{"solid": {"color": {"expr": {"Literal": {"Value": "'#1F2328'"}}}}}` |

## Version bump and the bundle cache

Desktop caches a bundle by **guid + version**. Re-embedding a changed bundle under the same version serves the old code, and your fix appears to do nothing. `sync-visuals.mjs` increments the 4th version part on every build. If you package by hand, bump it yourself.

After re-embedding, **close and reopen** Desktop (`powerbi-desktop open "<project>.pbip"`). `file.reload` does not reliably pick up a new bundle.

## Desktop must be closed while syncing

Desktop rewrites PBIP files on save. A sync that runs while Desktop has the project open can be overwritten by the next save. Check `powerbi-desktop status` → no instance with this project's `currentFilePath`.

## Shared code across visuals

- `visuals/shared/*.ts` is authored once. `sync-visuals.mjs` copies it into each `visuals/<name>/src/shared/` before building. Cross-project TS imports (`../../shared`) fail with TS2307 because `powerbi-visuals-api` only resolves inside a project with `node_modules`.
- `src/shared/` is therefore a **build artefact**. Edit `visuals/shared/`, never the copy.
- Less is different: `style/visual.less` imports `../../shared/base.less` directly, because webpack resolves it from disk.

## Repo layout this skill assumes

```
<Project>.pbip
<Project>.Report/CustomVisuals/<guid>/...     embedded payloads (generated)
visuals/
  shared/                                     tokens.ts, dom.ts, format.ts, props.ts, interaction.ts, scale.ts, text.ts, paths.ts, base.less
  <name>/                                     one pbiviz project per visual
    capabilities.json  pbiviz.json  package.json  tsconfig.json  eslint.config.mjs
    src/visual.ts      src/shared/ (generated)    style/visual.less   assets/icon.png
tools/
  visuals.json        { "<name>": "<guid>" }
  sync-visuals.mjs    build -> embed -> register -> verify
  pbir_helpers.py     visual.json builders + capabilities check
```

Add to the **dashboard repo's** `.gitignore` (not the template's):

```
visuals/*/node_modules/
visuals/*/dist/
visuals/*/.tmp/
visuals/*/src/shared/
```

Commit `CustomVisuals/` — it is what makes the report open complete.
