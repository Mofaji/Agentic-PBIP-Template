"use strict";

/**
 * Blank template - one category, one measure, horizontal bars.
 *
 * Deliberately small: it exists to show every pattern a new visual needs in
 * one place, so you can delete the drawing code and keep the plumbing.
 *
 *   capabilities.json roles  -> readPoints()          (dataView parsing)
 *   capabilities.json objects -> DISPLAY_SPEC          (Format pane, via shared/props)
 *   Interactions               -> click / Ctrl+click / tooltip / clear
 *   supportsHighlight          -> dim unhighlighted marks
 *   renderingStarted/Finished  -> required for PDF / PowerPoint export
 *
 * DOM is built with createElement / textContent only - the pbiviz lint step
 * rejects innerHTML.
 */

import powerbi from "powerbi-visuals-api";
import { FormattingSettingsService } from "powerbi-visuals-utils-formattingmodel";

import IVisual = powerbi.extensibility.visual.IVisual;
import VisualConstructorOptions = powerbi.extensibility.visual.VisualConstructorOptions;
import VisualUpdateOptions = powerbi.extensibility.visual.VisualUpdateOptions;
import IVisualHost = powerbi.extensibility.visual.IVisualHost;

import { T } from "./shared/tokens";
import { el, svg, svgText, clear } from "./shared/dom";
import { fmtValue } from "./shared/format";
import { readCard, buildCard, buildModel, PropSpec, Values } from "./shared/props";
import { Interactions, markOpacity, CLEAR_CATCHER } from "./shared/interaction";
import { truncateToWidth } from "./shared/text";
import { linearScale } from "./shared/scale";

import "./../style/visual.less";

const DISPLAY_SPEC: readonly PropSpec[] = [
    { k: "fill", n: "barColor", d: T.ac, label: "Bar colour" },
    { k: "num", n: "fontSize", d: 10, label: "Text size" },
    {
        k: "enum", n: "sortBy", d: "valueDesc", label: "Sort by",
        items: [
            { value: "valueDesc", displayName: "Value, descending" },
            { value: "none", displayName: "Data order" },
        ],
    },
    { k: "bool", n: "showLabels", d: true, label: "Data labels" },
];

interface Point {
    index: number;
    label: string;
    value: number;
    highlight: number | null;
}

export class Visual implements IVisual {
    private host: IVisualHost;
    private element: HTMLElement;
    private interactions: Interactions;
    private formattingService = new FormattingSettingsService();
    private display: Values = {};

    constructor(options: VisualConstructorOptions) {
        this.host = options.host;
        this.element = options.element;
        this.interactions = new Interactions(options.host, options.element);
    }

    public getFormattingModel(): powerbi.visuals.FormattingModel {
        return this.formattingService.buildFormattingModel(buildModel([
            buildCard("display", "Display", DISPLAY_SPEC, this.display),
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
        this.display = readCard(dv && dv.metadata ? dv.metadata.objects : undefined, "display", DISPLAY_SPEC);

        const cat = dv && dv.categorical && dv.categorical.categories && dv.categorical.categories[0];
        const val = dv && dv.categorical && dv.categorical.values && dv.categorical.values[0];
        if (!cat || !val) {
            this.element.appendChild(el("div", "cv-empty", "Add a category and a value"));
            return;
        }

        let points: Point[] = cat.values.map((c, i) => ({
            index: i,
            label: String(c ?? "(Blank)"),
            value: Number(val.values[i] ?? 0),
            highlight: val.highlights ? (val.highlights[i] === null ? null : Number(val.highlights[i])) : null,
        }));
        if (String(this.display.sortBy) === "valueDesc") {
            points = points.slice().sort((a, b) => b.value - a.value);
        }

        const W = Math.max(80, options.viewport.width);
        const H = Math.max(40, options.viewport.height);
        const fs = Number(this.display.fontSize);
        const labelW = Math.min(160, W * 0.35);
        const rowH = Math.max(fs + 8, Math.min(28, H / Math.max(1, points.length)));
        const maxAbs = Math.max(1e-9, ...points.map((p) => Math.abs(p.value)));
        const x = linearScale([0, maxAbs], [0, W - labelW - 56]);
        const hasHighlights = Boolean(val.highlights);

        const root = svg("svg", { width: W, height: H });
        const catcher = svg("rect", { x: 0, y: 0, width: W, height: H, fill: "transparent" });
        catcher.setAttribute("class", CLEAR_CATCHER);
        root.appendChild(catcher);

        points.forEach((p, row) => {
            const y = row * rowH;
            if (y + rowH > H) { return; }
            root.appendChild(svgText(truncateToWidth(p.label, labelW - 8, fs, T.font), {
                x: labelW - 8, y: y + rowH / 2 + fs * 0.35, "text-anchor": "end",
                "font-size": fs, "font-family": T.font, fill: T.inkSoft,
            }));
            const bar = svg("rect", {
                x: labelW, y: y + rowH * 0.2, width: Math.max(1, x(Math.abs(p.value))), height: rowH * 0.6,
                fill: String(this.display.barColor), opacity: markOpacity(hasHighlights, p.highlight),
            });
            const id = this.host.createSelectionIdBuilder().withCategory(cat, p.index).createSelectionId();
            this.interactions.bindMark(bar, [id],
                () => [
                    { displayName: cat.source.displayName, value: p.label },
                    { displayName: val.source.displayName, value: fmtValue(p.value, "none") },
                ],
                (multi) => this.interactions.select([id], multi));
            root.appendChild(bar);
            if (Boolean(this.display.showLabels)) {
                root.appendChild(svgText(fmtValue(p.value, "none"), {
                    x: labelW + x(Math.abs(p.value)) + 4, y: y + rowH / 2 + fs * 0.35,
                    "font-size": fs, "font-family": T.font, fill: T.ink, "pointer-events": "none",
                }));
            }
        });
        this.element.appendChild(root);
    }
}
