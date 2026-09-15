"use strict";

/**
 * Variance table template - IBCS statement table.
 *
 * Starter template. Copy via
 * tools/new_visual.py --template varianceTable, then adapt.
 *
 * Two layouts, chosen by whether the Period role is bound:
 *   variance   Rows | PM | AC | ΔPM bar | ΔPM% pin      (Monthly pages)
 *   cross-tab  Rows | one column per period | Total      (YTD pages)
 *
 * Statement logic the source visual computed itself:
 *   groupTotal = running  top-level groups show the running result, so
 *                         "Gross Margin" = Net Revenue + Cost of Sales
 *   showRatios            each result after the first gets a "<name> %" row,
 *                         the running result over the first group
 *
 * Values are read from a flat table dataView and aggregated here. That is only
 * correct for additive measures, which is what both statements bind.
 *
 * Interactions: chevron expands/collapses, row click cross-filters,
 * Ctrl/Shift+click multi-selects, click on empty space clears.
 */

import powerbi from "powerbi-visuals-api";
import { FormattingSettingsService } from "powerbi-visuals-utils-formattingmodel";

import DataView = powerbi.DataView;
import DataViewTable = powerbi.DataViewTable;
import IVisual = powerbi.extensibility.visual.IVisual;
import VisualConstructorOptions = powerbi.extensibility.visual.VisualConstructorOptions;
import VisualUpdateOptions = powerbi.extensibility.visual.VisualUpdateOptions;
import IVisualHost = powerbi.extensibility.visual.IVisualHost;
import ISelectionId = powerbi.visuals.ISelectionId;

import { T } from "./shared/tokens";
import { el, svg, svgText, clear } from "./shared/dom";
import { fmtValue, fmtDelta, fmtPct, fmtDeltaPct, fmtDeltaPp, fmtMonth, Unit } from "./shared/format";
import { readCard, buildCard, buildModel, splitList, PropSpec, Values } from "./shared/props";
import { Interactions, TooltipRow } from "./shared/interaction";
import { truncateToWidth } from "./shared/text";

import "./../style/visual.less";

const STATEMENT_SPEC: readonly PropSpec[] = [
    {
        k: "enum", n: "groupTotal", d: "sum", label: "Group totals",
        items: [
            { value: "sum", displayName: "Sum of children" },
            { value: "running", displayName: "Running result (P&L)" },
        ],
    },
    { k: "bool", n: "showRatios", d: false, label: "Ratio rows (% of first group)" },
    { k: "text", n: "ratioSuffix", d: " %", label: "Ratio row suffix" },
    { k: "text", n: "collapsed", d: "", label: "Collapsed groups (pipe separated)" },
    { k: "bool", n: "hideEmpty", d: true, label: "Hide empty rows" },
];

const DISPLAY_SPEC: readonly PropSpec[] = [
    {
        k: "enum", n: "unit", d: "K", label: "Unit",
        items: [
            { value: "K", displayName: "Thousands" },
            { value: "M", displayName: "Millions" },
            { value: "none", displayName: "None" },
        ],
    },
    { k: "num", n: "fontSize", d: 11, label: "Text size" },
    { k: "num", n: "rowHeight", d: 22, label: "Row height" },
    { k: "text", n: "acLabel", d: "AC", label: "Actual label" },
    { k: "text", n: "pmLabel", d: "PM", label: "Comparison label" },
    { k: "bool", n: "showTotalColumn", d: true, label: "Total column (cross-tab)" },
];

const COLOR_SPEC: readonly PropSpec[] = [
    { k: "fill", n: "positive", d: T.pos, label: "Positive variance" },
    { k: "fill", n: "negative", d: T.neg, label: "Negative variance" },
    { k: "fill", n: "accent", d: T.accent, label: "Accent" },
];

type Kind = "group" | "leaf" | "ratio";

interface Node {
    key: string;
    label: string;
    depth: number;
    order: number;
    kind: Kind;
    children: Node[];
    childMap: Map<string, Node>;
    /** period key -> value; "" is the only key in variance layout */
    ac: Map<string, number>;
    pm: Map<string, number>;
    rows: number[];
    /** top-level position, for running results */
    topIndex: number;
}

interface Period { key: string; label: string; sort: number; }

interface Model {
    roots: Node[];
    periods: Period[];
    hasPeriod: boolean;
    hasPm: boolean;
    levels: string[];
    acName: string;
    pmName: string;
}

function newNode(key: string, label: string, depth: number, order: number, kind: Kind): Node {
    return {
        key, label, depth, order, kind,
        children: [], childMap: new Map(),
        ac: new Map(), pm: new Map(), rows: [], topIndex: -1,
    };
}

function add(map: Map<string, number>, k: string, v: number): void {
    map.set(k, (map.get(k) ?? 0) + v);
}

function total(map: Map<string, number>): number | null {
    if (map.size === 0) { return null; }
    let s = 0;
    map.forEach((v) => { s += v; });
    return s;
}

function num(v: powerbi.PrimitiveValue): number | null {
    if (v === null || v === undefined || v === "") { return null; }
    const n = typeof v === "number" ? v : Number(v);
    return isFinite(n) ? n : null;
}

export class Visual implements IVisual {
    private host: IVisualHost;
    private element: HTMLElement;
    private interactions: Interactions;
    private formattingService: FormattingSettingsService;
    private cards: Values[] = [];

    private table: DataViewTable | null = null;
    private lastOptions: VisualUpdateOptions | null = null;

    /** Groups the user toggled, relative to the configured default. */
    private toggled = new Set<string>();
    private scrollTop = 0;

    constructor(options: VisualConstructorOptions) {
        this.host = options.host;
        this.element = options.element;
        this.interactions = new Interactions(options.host, options.element);
        this.formattingService = new FormattingSettingsService();
    }

    public update(options: VisualUpdateOptions): void {
        this.lastOptions = options;
        this.interactions.renderingStarted(options);
        try {
            this.render();
            this.interactions.renderingFinished(options);
        } catch (e) {
            this.interactions.renderingFailed(options, String(e));
        }
    }

    public getFormattingModel(): powerbi.visuals.FormattingModel {
        const [statement, display, colors] = this.cards.length ? this.cards : [{}, {}, {}];
        return this.formattingService.buildFormattingModel(buildModel([
            buildCard("statement", "Statement", STATEMENT_SPEC, statement),
            buildCard("display", "Display", DISPLAY_SPEC, display),
            buildCard("colors", "Colours", COLOR_SPEC, colors),
        ]));
    }

    // ------------------------------------------------------------ data ---

    private readModel(dataView: DataView): Model | null {
        const table = dataView.table;
        if (!table || !table.columns || !table.rows) { return null; }
        this.table = table;

        const idx = (role: string) => table.columns
            .map((c, i) => ({ c, i }))
            .filter((x) => x.c.roles && x.c.roles[role]);

        const rowCols = idx("rows");
        const orderCols = idx("rowOrder");
        const periodCol = idx("period")[0];
        const acCol = idx("ac")[0];
        const pmCol = idx("pm")[0];
        if (rowCols.length === 0 || !acCol) { return null; }

        const roots = new Map<string, Node>();
        const periods = new Map<string, Period>();

        table.rows.forEach((row, r) => {
            const ac = num(row[acCol.i]);
            const pm = pmCol ? num(row[pmCol.i]) : null;
            if (ac === null && pm === null) { return; }

            let pKey = "";
            if (periodCol) {
                const raw = row[periodCol.i];
                const d = raw instanceof Date ? raw : new Date(String(raw));
                const isDate = !isNaN(d.getTime()) && typeof raw !== "number";
                pKey = isDate ? d.toISOString() : String(raw);
                if (!periods.has(pKey)) {
                    periods.set(pKey, {
                        key: pKey,
                        label: isDate ? fmtMonth(d) : String(raw),
                        sort: isDate ? d.getTime() : (num(raw) ?? periods.size),
                    });
                }
            }

            let level = roots;
            let path = "";
            for (let depth = 0; depth < rowCols.length; depth++) {
                const rawLabel = row[rowCols[depth].i];
                // A blank inner level means the outer row is itself the leaf.
                if (depth > 0 && (rawLabel === null || rawLabel === undefined || rawLabel === "")) { break; }
                const label = rawLabel === null || rawLabel === undefined ? "(Blank)" : String(rawLabel);
                path = path + "␟" + label;
                const orderRaw = orderCols[depth] ? num(row[orderCols[depth].i]) : null;
                let node = level.get(label);
                if (!node) {
                    node = newNode(path, label, depth, orderRaw ?? Number.MAX_SAFE_INTEGER, "leaf");
                    level.set(label, node);
                }
                if (orderRaw !== null && orderRaw < node.order) { node.order = orderRaw; }
                if (ac !== null) { add(node.ac, pKey, ac); }
                if (pm !== null) { add(node.pm, pKey, pm); }
                node.rows.push(r);
                level = node.childMap;
            }
        });

        const finish = (map: Map<string, Node>): Node[] => {
            const list = Array.from(map.values());
            list.sort((a, b) => a.order - b.order || a.label.localeCompare(b.label));
            for (const n of list) {
                n.children = finish(n.childMap);
                if (n.children.length > 0) { n.kind = "group"; }
            }
            return list;
        };
        const rootList = finish(roots);
        rootList.forEach((n, i) => { n.topIndex = i; });

        return {
            roots: rootList,
            periods: Array.from(periods.values()).sort((a, b) => a.sort - b.sort),
            hasPeriod: Boolean(periodCol),
            hasPm: Boolean(pmCol),
            levels: rowCols.map((x) => x.c.displayName),
            acName: acCol.c.displayName,
            pmName: pmCol ? pmCol.c.displayName : "",
        };
    }

    /**
     * Running results and ratio rows for the P&L.
     * Returns the rows to display in order; ratio rows are synthesised here.
     */
    private applyStatement(model: Model, statement: Values): void {
        if (String(statement.groupTotal) !== "running") { return; }
        const runAc = new Map<string, number>();
        const runPm = new Map<string, number>();
        const first = { ac: new Map<string, number>(), pm: new Map<string, number>() };
        const suffix = String(statement.ratioSuffix ?? " %");

        model.roots.forEach((g, i) => {
            g.ac.forEach((v, k) => add(runAc, k, v));
            g.pm.forEach((v, k) => add(runPm, k, v));
            g.ac = new Map(runAc);
            g.pm = new Map(runPm);
            if (i === 0) {
                first.ac = new Map(runAc);
                first.pm = new Map(runPm);
                return;
            }
            if (Boolean(statement.showRatios)) {
                const ratio = newNode(g.key + "␟%", g.label + suffix, 1, Number.MAX_SAFE_INTEGER, "ratio");
                const div = (m: Map<string, number>, base: Map<string, number>) => {
                    const out = new Map<string, number>();
                    m.forEach((v, k) => {
                        const b = base.get(k);
                        if (b) { out.set(k, v / b); }
                    });
                    return out;
                };
                ratio.ac = div(runAc, first.ac);
                ratio.pm = div(runPm, first.pm);
                // Totals of a ratio are ratios of totals, not sums of ratios.
                const ta = total(runAc), fa = total(first.ac);
                const tp = total(runPm), fp = total(first.pm);
                ratio.ac.set("∑", ta !== null && fa ? ta / fa : NaN);
                ratio.pm.set("∑", tp !== null && fp ? tp / fp : NaN);
                ratio.rows = g.rows.slice();
                g.children.push(ratio);
            }
        });
    }

    // ---------------------------------------------------------- render ---

    private render(): void {
        const options = this.lastOptions;
        if (!options) { return; }
        const dataView = options.dataViews && options.dataViews[0];
        const objects = dataView && dataView.metadata ? dataView.metadata.objects : undefined;

        const statement = readCard(objects, "statement", STATEMENT_SPEC);
        const display = readCard(objects, "display", DISPLAY_SPEC);
        const colors = readCard(objects, "colors", COLOR_SPEC);
        this.cards = [statement, display, colors];

        const prevBody = this.element.querySelector(".cv-body");
        if (prevBody) { this.scrollTop = (prevBody as HTMLElement).scrollTop; }
        clear(this.element);

        const model = dataView ? this.readModel(dataView) : null;
        if (!model || model.roots.length === 0) {
            this.element.appendChild(el("div", "cv-empty", "No data for the current selection"));
            return;
        }
        this.applyStatement(model, statement);

        const root = el("div", "cv-table");
        root.style.fontSize = `${Number(display.fontSize)}px`;
        this.element.appendChild(root);

        const collapsedDefault = new Set(splitList(String(statement.collapsed)));
        const isCollapsed = (n: Node) => collapsedDefault.has(n.label) !== this.toggled.has(n.key);

        const visible: Node[] = [];
        const walk = (nodes: Node[]) => {
            for (const n of nodes) {
                if (Boolean(statement.hideEmpty) && n.kind !== "ratio" && this.isEmpty(n)) { continue; }
                visible.push(n);
                if (n.kind === "group") {
                    if (isCollapsed(n)) {
                        // Ratio rows stay visible: they are results, not detail.
                        n.children.filter((c) => c.kind === "ratio").forEach((c) => visible.push(c));
                    } else {
                        walk(n.children);
                    }
                }
            }
        };
        walk(model.roots);

        const width = Math.max(200, options.viewport.width);
        const ctx = {
            model, statement, display, colors, visible, isCollapsed,
            unit: String(display.unit) as Unit,
            rowH: Math.max(16, Number(display.rowHeight)),
            fontSize: Number(display.fontSize),
            width: width - 10,
        };

        if (model.hasPeriod) {
            this.renderCrossTab(root, ctx);
        } else {
            this.renderVariance(root, ctx);
        }

        const body = root.querySelector(".cv-body") as HTMLElement | null;
        if (body) { body.scrollTop = this.scrollTop; }
    }

    private isEmpty(n: Node): boolean {
        let any = false;
        n.ac.forEach((v) => { if (Math.abs(v) >= 0.5) { any = true; } });
        n.pm.forEach((v) => { if (Math.abs(v) >= 0.5) { any = true; } });
        return !any;
    }

    private labelCell(n: Node, ctx: RenderCtx, width: number): HTMLElement {
        const cell = el("div", "cv-cell cv-label");
        const indent = 6 + n.depth * 14;
        cell.style.paddingLeft = `${indent}px`;

        if (n.kind === "group") {
            const chevron = el("span", "cv-chevron", ctx.isCollapsed(n) ? "▸" : "▾");
            chevron.addEventListener("click", (e) => {
                e.stopPropagation();
                if (this.toggled.has(n.key)) { this.toggled.delete(n.key); } else { this.toggled.add(n.key); }
                this.render();
            });
            cell.appendChild(chevron);
        } else {
            cell.appendChild(el("span", "cv-chevron cv-chevron-blank", ""));
        }
        const text = truncateToWidth(n.label, width - indent - 22, ctx.fontSize, T.font);
        const span = el("span", "cv-label-text", text);
        if (text !== n.label) { span.title = n.label; }
        cell.appendChild(span);
        return cell;
    }

    private rowClasses(n: Node, i: number, ctx: RenderCtx): string {
        const cls = ["cv-row", `cv-${n.kind}`, `cv-depth-${n.depth}`];
        if (n.depth === 0 && String(ctx.statement.groupTotal) === "running" && i > 0) { cls.push("cv-result"); }
        return cls.join(" ");
    }

    private bindRow(row: HTMLElement, n: Node, tooltip: () => TooltipRow[]): void {
        const ids = this.idsFor(n);
        this.interactions.bindMark(row, ids, tooltip, (multi) => this.interactions.select(ids, multi));
    }

    private idsFor(n: Node): ISelectionId[] {
        const table = this.table;
        if (!table) { return []; }
        return n.rows.map((r) => this.host.createSelectionIdBuilder().withTable(table, r).createSelectionId());
    }

    // ------------------------------------------------- variance layout ---

    private renderVariance(root: HTMLElement, ctx: RenderCtx): void {
        const W = ctx.width;
        const labelW = Math.max(150, Math.round(W * 0.30));
        const valW = Math.round(W * 0.115);
        const pctW = Math.round(W * 0.2);
        const barW = Math.max(60, W - labelW - valW * 2 - pctW);
        const template = `${labelW}px ${valW}px ${valW}px ${barW}px ${pctW}px`;
        const pos = String(ctx.colors.positive);
        const neg = String(ctx.colors.negative);
        const acLabel = String(ctx.display.acLabel);
        const pmLabel = String(ctx.display.pmLabel);

        const head = el("div", "cv-head");
        head.style.gridTemplateColumns = template;
        head.appendChild(el("div", "cv-cell cv-label", ""));
        head.appendChild(this.scenarioHead(pmLabel, false));
        head.appendChild(this.scenarioHead(acLabel, true));
        head.appendChild(el("div", "cv-cell cv-center", `Δ${pmLabel}`));
        head.appendChild(el("div", "cv-cell cv-center", `Δ${pmLabel}%`));
        root.appendChild(head);

        const body = el("div", "cv-body");
        root.appendChild(body);

        const val = (n: Node, m: Map<string, number>) =>
            n.kind === "ratio" ? (m.has("∑") ? m.get("∑")! : total(m)) : total(m);

        // One scale per column across every visible value row, so bar length
        // compares honestly between rows (IBCS scaling rule).
        let maxAbs = 0;
        let maxPct = 0;
        for (const n of ctx.visible) {
            if (n.kind === "ratio") { continue; }
            const a = total(n.ac), p = total(n.pm);
            if (a === null || p === null) { continue; }
            maxAbs = Math.max(maxAbs, Math.abs(a - p));
            if (Math.abs(p) > 0.5) { maxPct = Math.max(maxPct, Math.abs((a - p) / Math.abs(p))); }
        }
        maxPct = Math.min(Math.max(maxPct, 0.05), 1);

        ctx.visible.forEach((n, i) => {
            const row = el("div", this.rowClasses(n, i, ctx));
            row.style.gridTemplateColumns = template;
            row.style.height = `${ctx.rowH}px`;

            const a = val(n, n.ac);
            const p = val(n, n.pm);
            const isRatio = n.kind === "ratio";
            const delta = a !== null && p !== null && isFinite(a) && isFinite(p) ? a - p : null;
            const deltaPct = !isRatio && delta !== null && p !== null && Math.abs(p) > 0.5 ? delta / Math.abs(p) : null;

            row.appendChild(this.labelCell(n, ctx, labelW));
            const fmt = (v: number | null) => isRatio ? fmtPct(v) : fmtValue(v, ctx.unit);
            row.appendChild(el("div", "cv-cell cv-num cv-pm", fmt(p)));
            row.appendChild(el("div", "cv-cell cv-num cv-ac", fmt(a)));

            // ΔPM bar
            const barCell = el("div", "cv-cell cv-viz");
            const bs = svg("svg", { width: barW, height: ctx.rowH });
            const axisX = Math.round(barW / 2) + 0.5;
            bs.appendChild(svg("line", { x1: axisX, x2: axisX, y1: 0, y2: ctx.rowH, stroke: T.strong, "stroke-width": 1 }));
            if (delta !== null) {
                const color = delta >= 0 ? pos : neg;
                const text = isRatio ? fmtDeltaPp(delta) : fmtDelta(delta, ctx.unit);
                const room = barW / 2 - 44;
                if (!isRatio && maxAbs > 0) {
                    const len = Math.max(Math.abs(delta) > 0.5 ? 1 : 0, (Math.abs(delta) / maxAbs) * room);
                    const bh = Math.max(6, Math.round(ctx.rowH * 0.5));
                    bs.appendChild(svg("rect", {
                        x: delta >= 0 ? axisX : axisX - len, y: (ctx.rowH - bh) / 2,
                        width: len, height: bh, fill: color,
                    }));
                    bs.appendChild(svgText(text, {
                        x: delta >= 0 ? axisX + len + 4 : axisX - len - 4, y: ctx.rowH / 2 + ctx.fontSize * 0.35,
                        "text-anchor": delta >= 0 ? "start" : "end",
                        "font-size": ctx.fontSize - 1, "font-family": T.font, fill: T.ink,
                    }));
                } else {
                    bs.appendChild(svgText(text, {
                        x: delta >= 0 ? axisX + 6 : axisX - 6, y: ctx.rowH / 2 + ctx.fontSize * 0.35,
                        "text-anchor": delta >= 0 ? "start" : "end",
                        "font-size": ctx.fontSize - 1, "font-family": T.font, fill: color, "font-weight": 600,
                    }));
                }
            }
            barCell.appendChild(bs);
            row.appendChild(barCell);

            // ΔPM% pin
            const pinCell = el("div", "cv-cell cv-viz");
            const ps = svg("svg", { width: pctW, height: ctx.rowH });
            const px = Math.round(pctW / 2) + 0.5;
            ps.appendChild(svg("line", { x1: px, x2: px, y1: 0, y2: ctx.rowH, stroke: T.strong, "stroke-width": 1 }));
            if (deltaPct !== null) {
                const color = deltaPct >= 0 ? pos : neg;
                const room = pctW / 2 - 60;
                const clipped = Math.abs(deltaPct) > maxPct;
                const len = (Math.min(Math.abs(deltaPct), maxPct) / maxPct) * room;
                const end = deltaPct >= 0 ? px + len : px - len;
                const cy = ctx.rowH / 2;
                ps.appendChild(svg("line", { x1: px, x2: end, y1: cy, y2: cy, stroke: color, "stroke-width": 2 }));
                if (clipped) {
                    const dir = deltaPct >= 0 ? 1 : -1;
                    ps.appendChild(svg("path", {
                        d: `M ${end} ${cy - 4} L ${end + dir * 6} ${cy} L ${end} ${cy + 4} Z`, fill: color,
                    }));
                } else {
                    ps.appendChild(svg("rect", { x: end - 3.5, y: cy - 3.5, width: 7, height: 7, fill: color }));
                }
                ps.appendChild(svgText(fmtDeltaPct(deltaPct), {
                    x: deltaPct >= 0 ? end + (clipped ? 9 : 6) : end - (clipped ? 9 : 6), y: cy + ctx.fontSize * 0.35,
                    "text-anchor": deltaPct >= 0 ? "start" : "end",
                    "font-size": ctx.fontSize - 1, "font-family": T.font, fill: T.inkSoft,
                }));
            }
            pinCell.appendChild(ps);
            row.appendChild(pinCell);

            this.bindRow(row, n, () => [
                { displayName: ctx.model.levels[Math.min(n.depth, ctx.model.levels.length - 1)] ?? "", value: n.label },
                { displayName: acLabel, value: isRatio ? fmtPct(a) : fmtValue(a, "none") },
                { displayName: pmLabel, value: isRatio ? fmtPct(p) : fmtValue(p, "none") },
                { displayName: `Δ${pmLabel}`, value: isRatio ? fmtDeltaPp(delta) : fmtDelta(delta, "none"), color: (delta ?? 0) >= 0 ? pos : neg },
            ]);
            body.appendChild(row);
        });
    }

    private scenarioHead(label: string, solid: boolean): HTMLElement {
        const cell = el("div", "cv-cell cv-num cv-scenario");
        const mark = el("span", solid ? "cv-mark cv-mark-ac" : "cv-mark cv-mark-pm");
        cell.appendChild(mark);
        cell.appendChild(el("span", "", label));
        return cell;
    }

    // ------------------------------------------------ cross-tab layout ---

    private renderCrossTab(root: HTMLElement, ctx: RenderCtx): void {
        const W = ctx.width;
        const periods = ctx.model.periods.filter((p) =>
            ctx.visible.some((n) => n.kind !== "ratio" && Math.abs(n.ac.get(p.key) ?? 0) >= 0.5));
        const showTotal = Boolean(ctx.display.showTotalColumn);
        const cols = periods.length + (showTotal ? 1 : 0);
        const labelW = Math.max(210, Math.round(W * 0.24));
        const colW = Math.max(40, Math.floor((W - labelW) / Math.max(1, cols)));
        const template = `${labelW}px repeat(${cols}, ${colW}px)`;

        const head = el("div", "cv-head");
        head.style.gridTemplateColumns = template;
        head.appendChild(el("div", "cv-cell cv-label", ""));
        for (const p of periods) { head.appendChild(el("div", "cv-cell cv-num", p.label)); }
        if (showTotal) { head.appendChild(el("div", "cv-cell cv-num cv-total-col", "Total")); }
        root.appendChild(head);

        const body = el("div", "cv-body");
        root.appendChild(body);

        ctx.visible.forEach((n, i) => {
            const row = el("div", this.rowClasses(n, i, ctx));
            row.style.gridTemplateColumns = template;
            row.style.height = `${ctx.rowH}px`;
            row.appendChild(this.labelCell(n, ctx, labelW));
            const isRatio = n.kind === "ratio";
            const f = (v: number | null | undefined) =>
                v === undefined || v === null ? "" : isRatio ? fmtPct(v) : fmtValue(v, ctx.unit);

            for (const p of periods) {
                row.appendChild(el("div", "cv-cell cv-num", f(n.ac.get(p.key))));
            }
            if (showTotal) {
                const t = isRatio ? n.ac.get("∑") : total(n.ac);
                row.appendChild(el("div", "cv-cell cv-num cv-total-col", f(t)));
            }
            this.bindRow(row, n, () => [
                { displayName: ctx.model.levels[Math.min(n.depth, ctx.model.levels.length - 1)] ?? "", value: n.label },
                { displayName: "Total", value: isRatio ? fmtPct(n.ac.get("∑")) : fmtValue(total(n.ac), "none") },
            ]);
            body.appendChild(row);
        });
    }
}

interface RenderCtx {
    model: Model;
    statement: Values;
    display: Values;
    colors: Values;
    visible: Node[];
    isCollapsed: (n: Node) => boolean;
    unit: Unit;
    rowH: number;
    fontSize: number;
    width: number;
}
