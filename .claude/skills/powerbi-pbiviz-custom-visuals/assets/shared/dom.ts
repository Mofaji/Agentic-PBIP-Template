/**
 * DOM builders.
 *
 * Everything goes through createElement / createElementNS + textContent.
 * `pbiviz package` runs eslint-plugin-powerbi-visuals, which hard-fails the
 * build on innerHTML / outerHTML / document.write / eval, so there is no
 * innerHTML fallback anywhere in this codebase by design.
 */

import { SVG_NS } from "./tokens";

type Styles = Partial<Record<string, string | number>>;

export function el(
    tag: string,
    className?: string,
    text?: string,
    style?: Styles
): HTMLElement {
    const node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text !== undefined) { node.textContent = text; }
    if (style) { applyStyle(node, style); }
    return node;
}

export function applyStyle(node: HTMLElement, style: Styles): void {
    for (const key of Object.keys(style)) {
        const v = style[key];
        if (v !== undefined && v !== null) {
            node.style.setProperty(kebab(key), String(v));
        }
    }
}

function kebab(s: string): string {
    return s.replace(/[A-Z]/g, (m) => "-" + m.toLowerCase());
}

/** SVG element with attributes. Numbers are stringified for you. */
export function svg(
    tag: string,
    attrs?: Record<string, string | number | undefined>
): SVGElement {
    const node = document.createElementNS(SVG_NS, tag);
    if (attrs) {
        for (const key of Object.keys(attrs)) {
            const v = attrs[key];
            if (v !== undefined && v !== null) {
                node.setAttribute(key, String(v));
            }
        }
    }
    return node;
}

/** SVG <text>. Content set via textContent, never markup. */
export function svgText(
    content: string,
    attrs: Record<string, string | number | undefined>
): SVGElement {
    const node = svg("text", attrs);
    node.textContent = content;
    return node;
}

export function clear(node: Element): void {
    while (node.firstChild) {
        node.removeChild(node.firstChild);
    }
}

export function append<T extends Node>(parent: Node, ...children: T[]): Node {
    for (const c of children) { parent.appendChild(c); }
    return parent;
}
