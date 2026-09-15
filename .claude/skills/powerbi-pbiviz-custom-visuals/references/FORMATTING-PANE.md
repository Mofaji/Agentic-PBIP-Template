# Format pane properties

Every property a report author (or a build script) can set on the visual is declared twice:

1. **`capabilities.json > objects`**: what exists, its type, its display name.
2. **`src/visual.ts`**: a `PropSpec[]` per card that `shared/props.ts` uses to *read* values and *build* the Format pane.

The two must list the same names. A property in `visual.json` that is not in capabilities is silently dropped. A property in capabilities that is not in the spec never reaches the visual.

---

## Declaring (`capabilities.json`)

```json
"objects": {
  "display": {
    "displayName": "Display",
    "properties": {
      "unit":      { "displayName": "Unit", "type": { "enumeration": [
                     { "value": "K", "displayName": "Thousands" },
                     { "value": "none", "displayName": "None" } ] } },
      "fontSize":  { "displayName": "Text size", "type": { "formatting": { "fontSize": true } } },
      "rowHeight": { "displayName": "Row height", "type": { "numeric": true } },
      "acLabel":   { "displayName": "Actual label", "type": { "text": true } },
      "showTotal": { "displayName": "Total column", "type": { "bool": true } },
      "positive":  { "displayName": "Positive variance", "type": { "fill": { "solid": { "color": true } } } }
    }
  }
}
```

## Reading and building (`shared/props.ts`)

```ts
const DISPLAY_SPEC: readonly PropSpec[] = [
    { k: "enum", n: "unit", d: "K", label: "Unit", items: [
        { value: "K", displayName: "Thousands" }, { value: "none", displayName: "None" } ] },
    { k: "num",  n: "fontSize", d: 11, label: "Text size" },
    { k: "num",  n: "rowHeight", d: 22, label: "Row height" },
    { k: "text", n: "acLabel", d: "AC", label: "Actual label" },
    { k: "bool", n: "showTotal", d: true, label: "Total column" },
    { k: "fill", n: "positive", d: T.pos, label: "Positive variance" },
];

// in update():
const display = readCard(dv?.metadata?.objects, "display", DISPLAY_SPEC);   // defaults filled in
this.cards = [display];

// Format pane:
public getFormattingModel() {
    return this.formattingService.buildFormattingModel(
        buildModel([buildCard("display", "Display", DISPLAY_SPEC, this.cards[0] ?? {})]));
}
```

Why not `FormattingSettingsService.populateFormattingSettingsModel`: the objects in these reports are written by Python build scripts, not the Desktop UI. The populate path has quirks with hand-authored objects: dropdowns arrive as bare strings, fills need unwrapping. Reading the objects bag directly is about 40 lines and entirely predictable.

## Writing from a build script (`visual.json`)

```python
"objects": {
    "display": props(unit=s("K"), fontSize=d(11), rowHeight=d(22), acLabel=s("AC"),
                     showTotal=b(True), positive=fill("#2FA36B")),
}
```

Encoding table: see `PBIP-EMBEDDING.md` → *Literal encoding*.

## Conventions

- Group properties into a few cards by purpose (`display`, `colors`, `statement`, `chart`), not one card per property.
- Every property needs a sensible default in the spec. A visual bound with no `objects` at all must still look finished.
- Colours default to `shared/tokens.ts`. Expose the brand accent and the variance colours; do not expose every grey.
- Keep a hidden `debug…` bool if you need to dump settings while developing (e.g. `debugShowSettings`). Default it to `false`.
- Report-wide house rules (whole numbers, no K/M) apply to native visuals. A custom visual that shows EUR K must say so in its card title, and the deviation must be recorded in the spec's *Exceptions requested*.
