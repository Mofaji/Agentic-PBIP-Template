/**
 * Selection, tooltips and render events.
 *
 * Wraps the three host services the visuals share so each one does not
 * re-derive the same plumbing:
 *
 *   ISelectionManager  click-to-cross-filter, Ctrl+click multi-select
 *   ITooltipService    hover tooltips
 *   IVisualEventService  renderingStarted/Finished, without which an export to
 *                        PDF or PowerPoint can capture a half-drawn visual
 */

import powerbi from "powerbi-visuals-api";
import ISelectionId = powerbi.visuals.ISelectionId;
import ISelectionManager = powerbi.extensibility.ISelectionManager;
import IVisualHost = powerbi.extensibility.visual.IVisualHost;
import DataViewCategoryColumn = powerbi.DataViewCategoryColumn;
import VisualUpdateOptions = powerbi.extensibility.visual.VisualUpdateOptions;

/** Give a full-bleed transparent background rect this class: clicking it clears the selection. */
export const CLEAR_CATCHER = "cv-clear-catcher";

export interface TooltipRow {
    displayName: string;
    value: string;
    color?: string;
}

export class Interactions {
    private host: IVisualHost;
    private selectionManager: ISelectionManager;
    private tooltipShown = false;

    constructor(host: IVisualHost, root: HTMLElement) {
        this.host = host;
        this.selectionManager = host.createSelectionManager();

        // Clicking empty space clears the cross-filter, which is the behaviour
        // users expect from every native visual.
        root.addEventListener("click", (e) => {
            if (e.target === root || (e.target as Element).classList?.contains(CLEAR_CATCHER)) {
                this.clear();
            }
        });
        root.addEventListener("contextmenu", (e) => {
            const mouse = e as MouseEvent;
            this.selectionManager.showContextMenu({}, { x: mouse.clientX, y: mouse.clientY });
            e.preventDefault();
        });
    }

    /**
     * One selection id covering every dataView row folded into a bar.
     * Grouped bars span several rows, so selecting the array keeps the
     * cross-filter faithful to what the bar actually shows.
     */
    public idsFor(column: DataViewCategoryColumn, rowIndices: number[]): ISelectionId[] {
        return rowIndices.map((i) =>
            this.host.createSelectionIdBuilder().withCategory(column, i).createSelectionId());
    }

    public select(ids: ISelectionId[], multiSelect: boolean): void {
        if (ids.length === 0) { return; }
        this.selectionManager.select(ids, multiSelect);
    }

    public clear(): void {
        this.selectionManager.clear();
        this.hideTooltip();
    }

    public hasSelection(): boolean {
        return this.selectionManager.getSelectionIds().length > 0;
    }

    public showTooltip(event: MouseEvent, rows: TooltipRow[], ids?: ISelectionId[]): void {
        this.host.tooltipService.show({
            coordinates: [event.clientX, event.clientY],
            dataItems: rows.map((r) => ({
                displayName: r.displayName,
                value: r.value,
                color: r.color,
                header: undefined,
            })),
            identities: ids ?? [],
            isTouchEvent: false,
        });
        this.tooltipShown = true;
    }

    public moveTooltip(event: MouseEvent, rows: TooltipRow[], ids?: ISelectionId[]): void {
        if (!this.tooltipShown) { this.showTooltip(event, rows, ids); return; }
        this.host.tooltipService.move({
            coordinates: [event.clientX, event.clientY],
            dataItems: rows.map((r) => ({
                displayName: r.displayName,
                value: r.value,
                color: r.color,
                header: undefined,
            })),
            identities: ids ?? [],
            isTouchEvent: false,
        });
    }

    public hideTooltip(): void {
        if (!this.tooltipShown) { return; }
        this.host.tooltipService.hide({ immediately: false, isTouchEvent: false });
        this.tooltipShown = false;
    }

    /**
     * Attach hover + click to one mark. `onClick` receives whether a modifier
     * was held, so callers can drill on a plain click and multi-select on
     * Ctrl / Shift + click.
     */
    public bindMark(
        node: Element,
        ids: ISelectionId[],
        tooltip: () => TooltipRow[],
        onClick: (multiSelect: boolean) => void
    ): void {
        (node as SVGElement).style.cursor = "pointer";

        node.addEventListener("mouseover", (e) => this.showTooltip(e as MouseEvent, tooltip(), ids));
        node.addEventListener("mousemove", (e) => this.moveTooltip(e as MouseEvent, tooltip(), ids));
        node.addEventListener("mouseout", () => this.hideTooltip());
        node.addEventListener("click", (e) => {
            const mouse = e as MouseEvent;
            e.stopPropagation();
            onClick(mouse.ctrlKey || mouse.metaKey || mouse.shiftKey);
        });
    }

    public renderingStarted(options: VisualUpdateOptions): void {
        this.host.eventService.renderingStarted(options);
    }

    public renderingFinished(options: VisualUpdateOptions): void {
        this.host.eventService.renderingFinished(options);
    }

    public renderingFailed(options: VisualUpdateOptions, reason?: string): void {
        this.host.eventService.renderingFailed(options, reason);
    }
}

/**
 * Opacity for a mark when the host is highlighting.
 * Unhighlighted marks dim rather than disappear, so the shape of the whole
 * category set stays readable while another visual filters.
 */
export function markOpacity(hasHighlights: boolean, highlighted: number | null): number {
    if (!hasHighlights) { return 1; }
    return highlighted !== null && highlighted !== 0 ? 1 : 0.28;
}
