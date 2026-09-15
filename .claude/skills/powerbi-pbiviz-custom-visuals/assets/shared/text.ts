/**
 * Text measurement for SVG labels.
 *
 * SVG has no ellipsis, so labels are trimmed against a measured width using a
 * single module-level offscreen canvas context - cheap, and accurate enough
 * for axis ticks and legends.
 */

let ctx: CanvasRenderingContext2D | null | undefined;

function context(): CanvasRenderingContext2D | null {
    if (ctx === undefined) {
        const canvas = document.createElement("canvas");
        ctx = canvas.getContext("2d");
    }
    return ctx;
}

export function measureText(text: string, fontSize: number, fontFamily: string): number {
    const c = context();
    if (!c) {
        // Fallback: Segoe UI averages a little over half its point size per glyph.
        return text.length * fontSize * 0.55;
    }
    c.font = `${fontSize}px ${fontFamily}`;
    return c.measureText(text).width;
}

/**
 * Trim to fit `maxWidth`, appending an ellipsis. `maxChars` applies first as a
 * cheap hard cap so very long categories never dominate the axis.
 */
export function truncateToWidth(
    text: string,
    maxWidth: number,
    fontSize: number,
    fontFamily: string,
    maxChars = 0
): string {
    let s = text ?? "";
    if (maxChars > 0 && s.length > maxChars) {
        s = s.slice(0, maxChars - 1) + "…";
    }
    if (maxWidth <= 0) { return s; }
    if (measureText(s, fontSize, fontFamily) <= maxWidth) { return s; }

    const ell = "…";
    let lo = 0;
    let hi = s.length;
    while (lo < hi) {
        const mid = Math.floor((lo + hi + 1) / 2);
        if (measureText(s.slice(0, mid) + ell, fontSize, fontFamily) <= maxWidth) {
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    return lo <= 0 ? ell : s.slice(0, lo) + ell;
}
