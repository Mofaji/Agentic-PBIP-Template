"use strict";

/**
 * Variance chart template - IBCS period chart.
 *
 * Starter template. Copy via
 * tools/new_visual.py --template varianceChart, then adapt.
 *
 *   ┌ variance strip: Δ to previous period, green/red, centred axis ┐
 *   └ main plot: AC columns (or line / area), data labels on        ┘
 *
 * Percent measures (margins) report their variance in percentage points.
 * Column click cross-filters; Ctrl/Shift+click multi-selects; highlights from
 * other visuals dim the unselected periods.
 */

import powerbi from "powerbi-visuals-api";
import { FormattingSettingsService } from "powerbi-visuals-utils-formattingmodel";

import IVisual = powerbi.extensibility.visual.IVisual;
import VisualConstructorOptions = powerbi.extensibility.visual.VisualConstructorOptions;
import VisualUpdateOptions = powerbi.extensibility.visual.VisualUpdateOptions;
import IVisualHost = powerbi.extensibility.visual.IVisualHost;

import { T } from "./shared/tokens";
import { el, svg, svgText, clear } from "./shared/dom";
import { fmtValue, fmtDelta, fmtPct, fmtDeltaPp, fmtMonth, Unit } from "./shared/format";
import { readCard, buildCard, buildModel, PropSpec, Values } from "./shared/props";
import { Interactions, markOpacity, CLEAR_CATCHER } from "./shared/interaction";
import { bandScale, linearScale } from "./shared/scale";
import { roundedTopBar } from "./shared/paths";

import "./../style/visual.less";

const CHART_SPEC: readonly PropSpec[] = [
    {
        k: "enum", n: "chartType", d: "column", label: "Type",
        items: [
            { value: "column", displayName: "Columns" },
            { value: "line", displayName: "Line" },
            { value: "area", displayName: "Area" },
        ],
    },
    {
        k: "enum", n: "valueFormat", d: "K", label: "Value format",
        items: [
            { value: "K", displayName: "Thousands" },
            { value: "M", displayName: "Millions" },
            { value: "none", displayName: "Whole number" },
            { value: "pct", displayName: "Percent" },
        ],
    },
    { k: "bool", n: "showVariance", d: true, label: "Variance to previous" },
    { k: "bool", n: "showLabels", d: true, label: "Data labels" },
    { k: "bool", n: "hideEmpty", d: true, label: "Hide blank periods" },
    { k: "num", n: "fontSize", d: 9, label: "Text size" },
    { k: "bool", n: "invertColors", d: false, label: "Invert variance colours" },
];

const COLOR_SPEC: readonly PropSpec[] = [
    { k: "fill", n: "actual", d: T.ac, label: "Actual" },
    { k: "fill", n: "positive", d: T.pos, label: "Positive variance" },
    { k: "fill", n: "negative", d: T.neg, label: "Negative variance" },
    { k: "fill", n: "accent", d: T.accent, label: "Line / area" },
];

interface Point {
    index: number;
    label: string;
    value: number | null;
    highlight: number | null;
}

export class Visual implements IVisual {
    private host: IVisualHost;
    private element: HTMLElement;
    private interactions: Interactions;
    private formattingService: FormattingSettingsService;
    private cards: Values[] = [];

    constructor(options: VisualConstructorOptions) {
        this.host = options.host;
        this.element = options.element;
        this.interactions = new Interactions(options.host, options.element);
        this.formattingService = new FormattingSettingsService();
    }

    public getFormattingModel(): powerbi.visuals.FormattingModel {
        const [chart, colors] = this.cards.length ? this.cards : [{}, {}];
        return this.formattingService.buildFormattingModel(buildModel([
            buildCard("chart", "Chart", CHART_SPEC, chart),
            buildCard("colors", "Colours", COLOR_SPEC, colors),
        ]));
    }

    public update(options: VisualUpdateOptions): void {
        this.interactions.renderingStarted(options);
        try {
            this.render(options);
            this.interactions.renderingFinished(options);
        } catch (e) {
            this.interactions.renderingFailed(options, String(e));
        }
    }

    private render(options: VisualUpdateOptions): void {
        clear(this.element);
        const dv = options.dataViews && options.dataViews[0];
        const objects = dv && dv.metadata ? dv.metadata.objects : undefined;
        const chart = readCard(objects, "chart", CHART_SPEC);
        const colors = readCard(objects, "colors", COLOR_SPEC);
        this.cards = [chart, colors];

        const cat = dv && dv.categorical && dv.categorical.categories && dv.categorical.categories[0];
        const valCol = dv && dv.categorical && dv.categorical.values && dv.categorical.values[0];
        if (!cat || !valCol) {
            this.element.appendChild(el("div", "cv-empty", "Add a period and a value"));
            return;
        }

        const hasHighlights = Boolean(valCol.highlights);
        let points: Point[] = cat.values.map((raw, i) => {
            const v = valCol.values[i];
            const h = valCol.highlights ? valCol.highlights[i] : null;
            const isDate = raw instanceof Date;
            return {
                index: i,
                label: isDate ? fmtMonth(raw) : String(raw ?? ""),
                value: v === null || v === undefined || v === "" ? null : Number(v),
                highlight: h === null || h === undefined || h === "" ? null : Number(h),
            };
        });
        if (Boolean(chart.hideEmpty)) {
            points = points.filter((p) => p.value !== null && isFinite(p.value));
        }
        if (points.length === 0) {
            this.element.appendChild(el("div", "cv-empty", "No data for the current selection"));
            return;
        }

        const W = Math.max(120, options.viewport.width);
        const H = Math.max(80, options.viewport.height);
        const fs = Number(chart.fontSize);
        const format = String(chart.valueFormat);
        const isPct = format === "pct";
        const unit: Unit = format === "pct" ? "none" : (format as Unit);
        const fmtV = (v: number | null) => isPct ? fmtPct(v) : fmtValue(v, unit);
        const fmtD = (v: number | null) => isPct ? fmtDeltaPp(v) : fmtDelta(v, unit);
        const invert = Boolean(chart.invertColors);
        const good = String(invert ? colors.negative : colors.positive);
        const bad = String(invert ? colors.positive : colors.negative);
        const type = String(chart.chartType);

        const root = svg("svg", { width: W, height: H, viewBox: `0 0 ${W} ${H}` });
        const catcher = svg("rect", { x: 0, y: 0, width: W, height: H, fill: "transparent" });
        catcher.setAttribute("class", CLEAR_CATCHER);
        root.appendChild(catcher);
        this.element.appendChild(root);

        const padX = 6;
        const axisH = fs + 8;
        const showVar = Boolean(chart.showVariance) && points.length > 1;
        const varH = showVar ? Math.max(22, Math.round(H * 0.24)) : 0;
        const labelRoom = Boolean(chart.showLabels) ? fs + 6 : 4;
        const band = bandScale(points.length, [padX, W - padX], type === "column" ? 0.28 : 0);
        const xCenter = (i: number) => band(i) + band.bandwidth / 2;
        const labelEvery = Math.ceil((fs * 3.6) / Math.max(1, band.step));

        // ---- variance strip ---------------------------------------------------
        const deltas: (number | null)[] = points.map((p, i) => {
            if (i === 0) { return null; }
            const prev = points[i - 1].value;
            return p.value !== null && prev !== null ? p.value - prev : null;
        });
        if (showVar) {
            const maxD = Math.max(1e-9, ...deltas.map((d) => Math.abs(d ?? 0)));
            const midY = Math.round(varH / 2) + 0.5;
            const half = varH / 2 - fs - 1;
            root.appendChild(svg("line", { x1: padX, x2: W - padX, y1: midY, y2: midY, stroke: T.divider, "stroke-width": 1 }));
            deltas.forEach((d, i) => {
                if (d === null) { return; }
                const len = Math.max(1, (Math.abs(d) / maxD) * half);
                const w = type === "column" ? band.bandwidth * 0.6 : band.step * 0.5;
                const cx = xCenter(i);
                root.appendChild(svg("rect", {
                    x: cx - w / 2, y: d >= 0 ? midY - len : midY, width: w, height: len,
                    fill: d >= 0 ? good : bad,
                }));
                if (band.step >= fs * 3.2) {
                    root.appendChild(svgText(fmtD(d), {
                        x: cx,
                        y: d >= 0 ? midY - len - 2 : midY + len + fs,
                        "text-anchor": "middle", "font-size": fs - 1, "font-family": T.font, fill: T.inkSoft,
                    }));
                }
            });
        }

        // ---- main plot -------------------------------------------------------
        const top = varH + labelRoom;
        const bottom = H - axisH;
        const vals = points.map((p) => p.value ?? 0);
        let lo = Math.min(0, ...vals);
        let hi = Math.max(0, ...vals);
        if (type !== "column") {
            // Lines read against their own range; a zero baseline flattens them.
            const minV = Math.min(...vals), maxV = Math.max(...vals);
            const pad = (maxV - minV) * 0.12 || Math.abs(maxV) * 0.1 || 1;
            lo = minV >= 0 ? Math.max(0, minV - pad) : minV - pad;
            hi = maxV + pad;
        }
        const negRoom = lo < 0 ? labelRoom : 0;
        const y = linearScale([lo, hi], [bottom - negRoom, top]);
        const zeroY = Math.round(y(Math.max(lo, 0))) + 0.5;

        if (type === "column") {
            points.forEach((p, i) => {
                if (p.value === null) { return; }
                const yv = y(p.value);
                const h = Math.abs(yv - y(0));
                const isNeg = p.value < 0;
                const path = isNeg
                    ? roundedTopBar(band(i), -(y(0) + h), band.bandwidth, h, 2)
                    : roundedTopBar(band(i), yv, band.bandwidth, h, 2);
                const bar = svg("path", {
                    d: path,
                    fill: String(colors.actual),
                    opacity: markOpacity(hasHighlights, p.highlight),
                    transform: isNeg ? "scale(1,-1)" : undefined,
                });
                this.bind(bar, cat, p, fmtV, deltas[i], fmtD);
                root.appendChild(bar);
                if (Boolean(chart.showLabels) && i % labelEvery === 0) {
                    root.appendChild(svgText(fmtV(p.value), {
                        x: xCenter(i), y: isNeg ? yv + fs + 2 : yv - 3,
                        "text-anchor": "middle", "font-size": fs, "font-family": T.font,
                        fill: T.ink, "font-weight": 600, "pointer-events": "none",
                    }));
                }
            });
        } else {
            const pts = points.map((p, i) => [xCenter(i), y(p.value ?? 0)] as [number, number]);
            const accent = String(colors.accent);
            if (type === "area") {
                const d = `M ${pts[0][0]} ${bottom} ` + pts.map(([px, py]) => `L ${px} ${py}`).join(" ") + ` L ${pts[pts.length - 1][0]} ${bottom} Z`;
                root.appendChild(svg("path", { d, fill: accent, "fill-opacity": 0.14 }));
            }
            root.appendChild(svg("polyline", {
                points: pts.map(([px, py]) => `${px},${py}`).join(" "),
                fill: "none", stroke: accent, "stroke-width": 2, "stroke-linejoin": "round",
            }));
            points.forEach((p, i) => {
                const dot = svg("circle", {
                    cx: pts[i][0], cy: pts[i][1], r: 3.2, fill: T.card, stroke: accent, "stroke-width": 2,
                    opacity: markOpacity(hasHighlights, p.highlight),
                });
                this.bind(dot, cat, p, fmtV, deltas[i], fmtD);
                root.appendChild(dot);
                if (Boolean(chart.showLabels) && i % labelEvery === 0) {
                    root.appendChild(svgText(fmtV(p.value), {
                        x: pts[i][0], y: pts[i][1] - 7, "text-anchor": "middle",
                        "font-size": fs, "font-family": T.font, fill: T.ink, "font-weight": 600, "pointer-events": "none",
                    }));
                }
            });
        }

        if (lo < 0 || type === "column") {
            root.appendChild(svg("line", { x1: padX, x2: W - padX, y1: zeroY, y2: zeroY, stroke: T.strong, "stroke-width": 1 }));
        }

        // ---- category axis ----------------------------------------------------
        points.forEach((p, i) => {
            if (i % labelEvery !== 0) { return; }
            root.appendChild(svgText(p.label.split("-")[0], {
                x: xCenter(i), y: H - 3, "text-anchor": "middle",
                "font-size": fs, "font-family": T.font, fill: T.inkSoft,
            }));
        });
    }

    private bind(
        node: SVGElement,
        cat: powerbi.DataViewCategoryColumn,
        p: Point,
        fmtV: (v: number | null) => string,
        delta: number | null,
        fmtD: (v: number | null) => string
    ): void {
        const id = this.host.createSelectionIdBuilder().withCategory(cat, p.index).createSelectionId();
        this.interactions.bindMark(node, [id], () => {
            const rows = [
                { displayName: cat.source.displayName, value: p.label },
                { displayName: "AC", value: fmtV(p.value) },
            ];
            if (delta !== null) { rows.push({ displayName: "Δ previous", value: fmtD(delta) }); }
            return rows;
        }, (multi) => this.interactions.select([id], multi));
    }
}
