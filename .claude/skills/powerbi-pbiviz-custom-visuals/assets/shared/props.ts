/**
 * One declarative spec per format-pane card, driving two things:
 *
 *   readCard()   - pulls values straight out of dataView.metadata.objects
 *   buildCard()  - produces the Format pane card
 *
 * Values are read directly rather than through
 * FormattingSettingsService.populateFormattingSettingsModel because every
 * `objects` block in this report is hand-authored in visual.json rather than
 * written by the Desktop UI, and the population path has known quirks there
 * (dropdowns arrive as raw strings, colours need solid.color unwrapping).
 * Reading the objects bag is ~40 lines and exactly predictable.
 *
 * Literal encoding reminder for the hand-authored side (a wrong suffix falls
 * back to the default silently):
 *   text / enum   "'value'"      bool  "true"
 *   integer       "200000L"      fractional / fontSize  "11D"
 *   fill          {"solid":{"color":{"expr":{"Literal":{"Value":"'#E97A63'"}}}}}
 */

import powerbi from "powerbi-visuals-api";
import { formattingSettings } from "powerbi-visuals-utils-formattingmodel";

export type EnumItem = { value: string; displayName: string };

export type PropSpec =
    | { k: "text"; n: string; d: string; label?: string }
    | { k: "bool"; n: string; d: boolean; label?: string }
    | { k: "num"; n: string; d: number; label?: string }
    | { k: "fill"; n: string; d: string; label?: string }
    | { k: "enum"; n: string; d: string; items: EnumItem[]; label?: string };

export type Values = Record<string, string | number | boolean>;

function titleize(name: string): string {
    const spaced = name.replace(/([A-Z])/g, " $1").trim();
    return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}

/** Read one card's properties out of the objects bag, filling defaults. */
export function readCard(
    objects: powerbi.DataViewObjects | undefined,
    cardName: string,
    spec: readonly PropSpec[]
): Values {
    const bag = objects ? (objects[cardName] as powerbi.DataViewObject | undefined) : undefined;
    const out: Values = {};

    for (const p of spec) {
        const raw = bag ? bag[p.n] : undefined;
        if (raw === undefined || raw === null) {
            out[p.n] = p.d;
            continue;
        }

        switch (p.k) {
            case "fill": {
                // Fills arrive as { solid: { color: "#RRGGBB" } }.
                const fill = raw as powerbi.Fill;
                const color = fill && fill.solid ? fill.solid.color : undefined;
                out[p.n] = (typeof color === "string" && color) ? color : p.d;
                break;
            }
            case "bool":
                out[p.n] = typeof raw === "boolean" ? raw : String(raw) === "true";
                break;
            case "num": {
                const n = typeof raw === "number" ? raw : parseFloat(String(raw));
                out[p.n] = isFinite(n) ? n : p.d;
                break;
            }
            case "enum":
            case "text":
            default: {
                // A dropdown can arrive as a bare string or as { value: ... }.
                const asAny = raw as unknown as { value?: unknown };
                const v = (asAny && typeof asAny === "object" && "value" in asAny)
                    ? asAny.value
                    : raw;
                out[p.n] = v === undefined || v === null ? p.d : String(v);
                break;
            }
        }
    }
    return out;
}

/** Build the Format pane card for a spec, seeded with the current values. */
export function buildCard(
    cardName: string,
    displayName: string,
    spec: readonly PropSpec[],
    values: Values
): formattingSettings.SimpleCard {
    const slices: formattingSettings.Slice[] = [];

    for (const p of spec) {
        const label = p.label ?? titleize(p.n);
        switch (p.k) {
            case "text":
                slices.push(new formattingSettings.TextInput({
                    name: p.n, displayName: label,
                    value: String(values[p.n] ?? p.d), placeholder: "",
                }));
                break;
            case "bool":
                slices.push(new formattingSettings.ToggleSwitch({
                    name: p.n, displayName: label, value: Boolean(values[p.n]),
                }));
                break;
            case "num":
                slices.push(new formattingSettings.NumUpDown({
                    name: p.n, displayName: label, value: Number(values[p.n] ?? p.d),
                }));
                break;
            case "fill":
                slices.push(new formattingSettings.ColorPicker({
                    name: p.n, displayName: label,
                    value: { value: String(values[p.n] ?? p.d) },
                }));
                break;
            case "enum": {
                const current = String(values[p.n] ?? p.d);
                const match = p.items.filter((i) => i.value === current)[0] ?? p.items[0];
                slices.push(new formattingSettings.ItemDropdown({
                    name: p.n, displayName: label,
                    items: p.items, value: match,
                }));
                break;
            }
        }
    }

    const card = new formattingSettings.SimpleCard();
    card.name = cardName;
    card.displayName = displayName;
    card.slices = slices;
    return card;
}

export function buildModel(
    cards: formattingSettings.SimpleCard[]
): formattingSettings.Model {
    const model = new formattingSettings.Model();
    model.cards = cards;
    return model;
}

/** Enum item lists reused across visuals. */
export const NUMBER_FORMAT_ITEMS: EnumItem[] = [
    { value: "auto", displayName: "Auto" },
    { value: "short", displayName: "Thousands (K)" },
    { value: "currencyShort", displayName: "Currency, short" },
    { value: "currency", displayName: "Currency, full" },
    { value: "integer", displayName: "Whole number" },
    { value: "decimal2", displayName: "Decimal (2)" },
    { value: "percent0", displayName: "Percent" },
    { value: "percent2", displayName: "Percent (2)" },
];

/** Split a pipe-separated override list, e.g. "Cosmetics|Haircare|Skincare". */
export function splitList(s: string): string[] {
    if (!s) { return []; }
    return s.split("|").map((x) => x.trim()).filter((x) => x.length > 0);
}
