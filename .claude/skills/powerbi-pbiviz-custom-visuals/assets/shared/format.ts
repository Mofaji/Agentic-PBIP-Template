/**
 * Number formatting for finance statements.
 *
 * Values arrive in EUR. Statements and charts show EUR thousands with no
 * decimals (the unit is stated once in the card title, never per number);
 * ratios show one decimal; variances carry an explicit sign.
 */

export type Unit = "K" | "M" | "none";

const MINUS = "−";

function grouped(n: number, dp: number): string {
    return Math.abs(n).toLocaleString("en-US", {
        minimumFractionDigits: dp,
        maximumFractionDigits: dp,
    });
}

function divisor(unit: Unit): number {
    return unit === "K" ? 1e3 : unit === "M" ? 1e6 : 1;
}

/** 826,379 -> "826" (K). Blank for null. Negative uses a true minus sign. */
export function fmtValue(v: number | null | undefined, unit: Unit, dp = 0): string {
    if (v === null || v === undefined || !isFinite(v)) { return ""; }
    const scaled = v / divisor(unit);
    const s = grouped(scaled, dp);
    if (s === grouped(0, dp)) { return s; }
    return (scaled < 0 ? MINUS : "") + s;
}

/** Variance with an explicit sign: "+12", "−4". */
export function fmtDelta(v: number | null | undefined, unit: Unit, dp = 0): string {
    if (v === null || v === undefined || !isFinite(v)) { return ""; }
    const scaled = v / divisor(unit);
    const s = grouped(scaled, dp);
    if (s === grouped(0, dp)) { return s; }
    return (scaled > 0 ? "+" : MINUS) + s;
}

/** 0.7188 -> "71.9%". */
export function fmtPct(v: number | null | undefined, dp = 1): string {
    if (v === null || v === undefined || !isFinite(v)) { return ""; }
    const s = grouped(v * 100, dp);
    return (v < 0 && s !== grouped(0, dp) ? MINUS : "") + s + "%";
}

/** Relative variance with sign: "+12.4%". */
export function fmtDeltaPct(v: number | null | undefined, dp = 1): string {
    if (v === null || v === undefined || !isFinite(v)) { return ""; }
    const s = grouped(v * 100, dp);
    if (s === grouped(0, dp)) { return s + "%"; }
    return (v > 0 ? "+" : MINUS) + s + "%";
}

/** Percentage-point variance: "+3.1pp". */
export function fmtDeltaPp(v: number | null | undefined, dp = 1): string {
    if (v === null || v === undefined || !isFinite(v)) { return ""; }
    const s = grouped(v * 100, dp);
    if (s === grouped(0, dp)) { return s + "pp"; }
    return (v > 0 ? "+" : MINUS) + s + "pp";
}

/** Month label from a date or ISO string: "Dec-22". */
export function fmtMonth(v: unknown): string {
    const d = v instanceof Date ? v : new Date(String(v));
    if (isNaN(d.getTime())) { return String(v ?? ""); }
    const m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getMonth()];
    return `${m}-${String(d.getFullYear()).slice(-2)}`;
}
