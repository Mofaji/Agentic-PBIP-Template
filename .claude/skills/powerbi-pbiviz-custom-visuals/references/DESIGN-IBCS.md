# Design conventions for custom visuals

The custom visuals sit on the same SVG canvas background as everything else in the report. They must look like part of it, not like an embedded widget.

---

## Chrome

- **The canvas draws the card and its title; the visual draws only content.** Suppress all container chrome in `visual.json` (`background`, `border`, `dropShadow`, `title` → `show: false`) and render on a transparent background.
- Place the visual at `card_y + 30` or lower (rulebook rule 16), with ~10 px inset from the card edges.
- One exception: a visual designed as a free-standing card (a KPI header strip, for example) may draw its own card chrome. Then the canvas must not also draw one. Decide per report and write it in the spec.

## Tokens

`visuals/shared/tokens.ts` and `visuals/shared/base.less` hold every colour and font. Per client:

1. Set `accent` / `@accent` (and `accentSoft`) to the brand colour, sampled from the logo, not guessed.
2. Use the same values in the canvas SVG generator, the theme JSON, and SVG KPI measures.
3. Do not change the IBCS scenario and variance colours to brand colours. Green/red carry meaning.

Never hardcode a hex in a visual's drawing code. Read it from `T` or a Format pane fill.

## IBCS semantics (finance visuals)

| Element | Convention |
| --- | --- |
| Actual (AC) | Solid dark grey (`T.ac`) |
| Previous period / plan (PM, PL, PY) | Outlined or light grey (`T.pm`); header marker is a hollow square |
| Positive variance | Green (`T.pos`) |
| Negative variance | Red (`T.neg`) |
| Cost lines | Invert colours so a cost increase is red (`invertColors`, or sign convention in the data) |
| Absolute variance | Horizontal bar from a centre axis, value label beyond the bar end |
| Relative variance | "Pin": line plus square head; arrow head when clipped |
| Result / subtotal rows | Bold, 1 px dark rule above |
| Ratio rows | Italic, muted, no bars; variance in **pp**, not % |
| Scaling | One scale per column across all visible rows. Never scale each row independently. |
| Units | Stated once in the title ("EUR K"), never repeated per number |
| Negative numbers | True minus sign `−` (U+2212), not hyphen |
| Time axis | Chronological, never sorted by value |

## Numbers

`shared/format.ts`: `fmtValue(v, "K")`, `fmtDelta` (explicit sign), `fmtPct` (1 dp), `fmtDeltaPct`, `fmtDeltaPp`, `fmtMonth`.

The rulebook's "whole numbers, no K/M" targets native visuals. Finance statements conventionally show thousands. When a custom visual uses K/M or 1-dp percentages, record it under *Exceptions requested* in the spec. Do not let it surface as a finding in a screenshot.

## Typography and density

- Segoe UI throughout; body 10–11 px in tables, 9 px in chart labels, 13 px card titles (canvas).
- Tabular numerals (`font-variant-numeric: tabular-nums`) in any column of numbers.
- Truncate long labels with `truncateToWidth` and put the full text in a `title` attribute or tooltip. Never let text overflow into the next column.
- Thin data labels when marks are narrower than about 3.6× the font size (`labelEvery` in the chart template). Overlapping labels are a defect.

## Empty and edge states

- No fields bound → centred muted hint (`.cv-empty`, "Add a category and a value").
- Fields bound, no rows → "No data for the current selection".
- Blank periods from an over-long date table → hidden by default (`hideEmpty`).
- Division by zero in ratios → blank, not `Infinity` or `NaN`.
