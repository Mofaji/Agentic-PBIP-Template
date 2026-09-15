/**
 * Design tokens shared by every custom visual in a dashboard repo.
 *
 * Brand-neutral greys plus IBCS scenario and variance colours. Per project,
 * change `accent` (and `accentSoft`) to the client's brand colour and keep
 * shared/base.less in step. Keep IBCS semantics intact: actuals solid dark,
 * comparison outlined, positive green, negative red.
 *
 * The page SVG background, theme JSON and SVG KPI measures should use the same
 * values so the report reads as one system.
 */

export const T = {
    // surfaces
    card: "#FFFFFF",
    rowHover: "#F4F6F8",
    band: "#F7F8FA",

    // type
    ink: "#1F2328",
    inkSoft: "#5B6168",
    muted: "#8C9197",

    // lines
    grid: "#ECEEF1",
    divider: "#E3E6EA",
    strong: "#1F2328",

    // IBCS scenarios
    ac: "#404448",      // actual: solid
    pm: "#A5AAAF",      // previous period / plan: outlined

    // variances
    pos: "#2FA36B",
    neg: "#E5484D",

    // brand slot - swap per client
    accent: "#3A7BD5",
    accentSoft: "#E6EFFB",

    font: '"Segoe UI", wf_standard-font, -apple-system, BlinkMacSystemFont, sans-serif',
} as const;

export const SVG_NS = "http://www.w3.org/2000/svg";
