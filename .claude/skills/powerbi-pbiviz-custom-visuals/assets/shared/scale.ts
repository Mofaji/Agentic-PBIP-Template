/**
 * Scales and tick generation.
 *
 * Hand-rolled rather than pulling in d3-scale: a static one-shot render needs
 * linear + band and nothing else, which is a few dozen lines.
 */

export interface LinearScale {
    (v: number): number;
    domain: [number, number];
    range: [number, number];
}

export function linearScale(
    domain: [number, number],
    range: [number, number]
): LinearScale {
    const [d0, d1] = domain;
    const [r0, r1] = range;
    const span = d1 - d0 || 1;
    const f = ((v: number) => r0 + ((v - d0) / span) * (r1 - r0)) as LinearScale;
    f.domain = domain;
    f.range = range;
    return f;
}

export interface BandScale {
    (i: number): number;
    bandwidth: number;
    step: number;
}

/**
 * @param padding fraction of each step left as gap between categories
 */
export function bandScale(
    count: number,
    range: [number, number],
    padding = 0.4
): BandScale {
    const [r0, r1] = range;
    const width = r1 - r0;
    const n = Math.max(1, count);
    const step = width / n;
    const bandwidth = step * (1 - padding);
    const offset = (step - bandwidth) / 2;
    const f = ((i: number) => r0 + i * step + offset) as BandScale;
    f.bandwidth = bandwidth;
    f.step = step;
    return f;
}

/** Ticks from an explicit step, so hand-authored axis bounds are honoured exactly. */
export function ticksByStep(min: number, max: number, step: number): number[] {
    if (!(step > 0)) { return [min, max]; }
    const out: number[] = [];
    // Accumulate by index rather than repeated addition to avoid float drift.
    const n = Math.floor((max - min) / step + 1e-9);
    for (let i = 0; i <= n; i++) { out.push(min + i * step); }
    if (out[out.length - 1] < max - 1e-9) { out.push(max); }
    return out;
}

/** A "nice" step (1/2/5 x 10^n) when no explicit step was configured. */
export function niceStep(span: number, targetCount = 5): number {
    if (span <= 0) { return 1; }
    const raw = span / Math.max(1, targetCount);
    const mag = Math.pow(10, Math.floor(Math.log10(raw)));
    const norm = raw / mag;
    let mult: number;
    if (norm <= 1) { mult = 1; }
    else if (norm <= 2) { mult = 2; }
    else if (norm <= 5) { mult = 5; }
    else { mult = 10; }
    return mult * mag;
}

/** Round a maximum up to a whole number of steps so the top gridline is the axis top. */
export function niceMax(max: number, step: number): number {
    if (!(step > 0)) { return max; }
    return Math.ceil(max / step - 1e-9) * step;
}
