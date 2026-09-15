# Interactivity

**Default for this repo: interactive.** Build static replicas only when the user explicitly asks for them. `shared/interaction.ts` wraps the three host services every visual needs, so each visual only decides *what* a mark selects.

| Behaviour | API | Helper |
| --- | --- | --- |
| Click a mark → cross-filter the page | `ISelectionManager.select(ids, multi)` | `interactions.select(ids, multi)` |
| Ctrl / Shift / ⌘ + click → multi-select | same, `multi = true` | `bindMark` passes the modifier state |
| Click empty space → clear | `selectionManager.clear()` | full-bleed rect with `class = CLEAR_CATCHER` |
| Hover tooltip | `host.tooltipService.show/move/hide` | `bindMark(node, ids, () => rows, onClick)` |
| Right-click context menu | `selectionManager.showContextMenu` | wired in the `Interactions` constructor |
| Dim when another visual selects | `supportsHighlight` + `highlights[]` | `markOpacity(hasHighlights, value)` |
| Export to PDF/PPT waits for render | `eventService.renderingStarted/Finished/Failed` | `interactions.renderingStarted(options)` … |

---

## Selection IDs

A selection ID is what gets filtered. Build one per data point, from the column that the mark represents.

```ts
// categorical mapping
const id = host.createSelectionIdBuilder().withCategory(categoryColumn, index).createSelectionId();

// table mapping - one id per underlying row; a group row selects all of its rows
const ids = node.rows.map((r) => host.createSelectionIdBuilder().withTable(dataView.table, r).createSelectionId());

// series (legend) in categorical
host.createSelectionIdBuilder().withCategory(cat, i).withSeries(dv.categorical.values, valueGroup).createSelectionId();
```

A mark that aggregates several rows (a bar that sums a group, a statement subtotal) must select **all** of them. Otherwise the cross-filter shows less than the mark did.

## The standard update() shape

```ts
public update(options: VisualUpdateOptions): void {
    this.interactions.renderingStarted(options);
    try {
        this.render(options);
        this.interactions.renderingFinished(options);
    } catch (e) {
        this.interactions.renderingFailed(options, String(e));
    }
}
```

Without `renderingFinished`, *Export to PDF / PowerPoint* and the Desktop Bridge screenshot can capture a half-drawn visual.

## Visual-local state (expand/collapse, drill)

State the host does not own (expanded groups, drill path) lives on the class and must survive `update()` calls:

- Store **keys**, not indices (`Set<string>` of group paths). Data order changes between updates.
- Store the *difference from the default* (`toggled`), so changing the default in the Format pane still works.
- Clamp state when bindings change. A drill path deeper than the current hierarchy must be trimmed.
- Preserve scroll position across re-renders (`scrollTop` captured before `clear()`).
- Call your own `render()` after a local state change. Do not wait for the host.

## Page interactions are set in page.json, not the visual

Whether a slicer or another visual filters yours is `page.json > visualInteractions`:

```json
"visualInteractions": [
  { "source": "<slicer visual name>", "target": "<chart visual name>", "type": "NoFilter" }
]
```

Typical finance page: the period slicer filters the statement table and KPI cards but **not** the monthly trend charts (`NoFilter`), so the charts always show the full year.

## Keyboard and accessibility (optional)

Not implemented in the templates. If a client needs certification or keyboard navigation, add `"supportsKeyboardFocus": true` to capabilities, give marks `tabindex` and `aria-label`, and handle Enter/Space as click. `pbiviz package` lists these as recommended features. The warnings are informational, not failures.
