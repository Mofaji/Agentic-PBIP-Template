/**
 * SVG path geometry.
 *
 * Written by hand rather than via d3-shape: the reference dashboard's bars are
 * rounded on the top two corners only, and its donut is a plain two-arc ring,
 * both of which are easier to match exactly than to coax out of a generator.
 */

/** Bar with only its top two corners rounded, anchored on the baseline. */
export function roundedTopBar(
    x: number, y: number, w: number, h: number, r: number
): string {
    const rr = Math.max(0, Math.min(r, w / 2, h));
    if (h <= 0) { return ""; }
    return [
        `M ${x} ${y + h}`,
        `L ${x} ${y + rr}`,
        `Q ${x} ${y} ${x + rr} ${y}`,
        `L ${x + w - rr} ${y}`,
        `Q ${x + w} ${y} ${x + w} ${y + rr}`,
        `L ${x + w} ${y + h}`,
        "Z",
    ].join(" ");
}

const TAU = Math.PI * 2;

function polar(cx: number, cy: number, r: number, angle: number): [number, number] {
    return [cx + r * Math.cos(angle), cy + r * Math.sin(angle)];
}

/**
 * Donut ring segment between two angles (radians, 0 = 3 o'clock, clockwise).
 * Outer arc runs forward, inner arc runs back, closing the band.
 */
export function donutArc(
    cx: number, cy: number,
    outer: number, inner: number,
    a0: number, a1: number
): string {
    const sweep = a1 - a0;
    if (Math.abs(sweep) < 1e-6) { return ""; }
    const large = Math.abs(sweep) > Math.PI ? 1 : 0;

    const [ox0, oy0] = polar(cx, cy, outer, a0);
    const [ox1, oy1] = polar(cx, cy, outer, a1);
    const [ix1, iy1] = polar(cx, cy, inner, a1);
    const [ix0, iy0] = polar(cx, cy, inner, a0);

    return [
        `M ${ox0} ${oy0}`,
        `A ${outer} ${outer} 0 ${large} 1 ${ox1} ${oy1}`,
        `L ${ix1} ${iy1}`,
        `A ${inner} ${inner} 0 ${large} 0 ${ix0} ${iy0}`,
        "Z",
    ].join(" ");
}

export { polar, TAU };

/**
 * Map pin: a circle of radius r whose bottom is drawn out to a point that sits
 * on the anchor. Returned centred on (0,0) at the tip, so translate to place.
 */
export function pinTeardrop(r: number): string {
    const top = -2.1 * r;
    return [
        "M 0 0",
        `C ${-0.73 * r} ${-1.1 * r} ${-r} ${-1.6 * r} ${-r} ${top}`,
        `A ${r} ${r} 0 1 1 ${r} ${top}`,
        `C ${r} ${-1.6 * r} ${0.73 * r} ${-1.1 * r} 0 0`,
        "Z",
    ].join(" ");
}
