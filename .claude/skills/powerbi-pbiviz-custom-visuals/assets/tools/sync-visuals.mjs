#!/usr/bin/env node
/**
 * Build custom visuals and embed them into the PBIP report.
 *
 * PBIP stores custom-visual bundles inline, so the report ships complete with no
 * manual import. Three things must line up:
 *
 *   1. payload       <Project>.Report/CustomVisuals/<guid>/{package.json,
 *                    resources/<guid>.pbiviz.json}
 *   2. registration  report.json resourcePackages entry, type "CustomVisual"
 *   3. reference     visual.json visualType === <guid>
 *
 * `pbiviz package --resources --no-pbiviz` writes exactly the two files (1)
 * needs. --pbiviz-too also emits dist/<name>.pbiviz for "Import a visual from a file".
 *
 * POWER BI DESKTOP MUST BE CLOSED while this runs - it rewrites PBIP files on
 * save, and it caches bundles by guid+version (hence the version bump).
 *
 * Reads tools/visuals.json ({ "<name>": "<guid>" }) written by new_visual.py.
 *
 * Usage:
 *   node tools/sync-visuals.mjs                       build all, embed, register
 *   node tools/sync-visuals.mjs --only myVisual       build one
 *   node tools/sync-visuals.mjs --check               verify references only
 *   node tools/sync-visuals.mjs --pbiviz-too          also write .pbiviz archives
 *   node tools/sync-visuals.mjs --project "Sales"     pick the .pbip when several exist
 */

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.dirname(HERE);
const VISUALS = path.join(ROOT, "visuals");
const SHARED = path.join(VISUALS, "shared");
const MANIFEST = path.join(HERE, "visuals.json");

const argv = process.argv.slice(2);
const opt = (flag) => (argv.includes(flag) ? argv[argv.indexOf(flag) + 1] : null);
const only = opt("--only");
const projectArg = opt("--project");
const checkOnly = argv.includes("--check");
const alsoPbiviz = argv.includes("--pbiviz-too");

const GUID_SHAPE = /^[A-Za-z][A-Za-z0-9]*[0-9A-F]{32}$/;

function findProject() {
    const pbips = fs.readdirSync(ROOT).filter((f) => f.endsWith(".pbip"));
    if (projectArg) {
        const want = projectArg.endsWith(".pbip") ? projectArg : `${projectArg}.pbip`;
        if (!pbips.includes(want)) { throw new Error(`${want} not found in ${ROOT}`); }
        return want.slice(0, -5);
    }
    if (pbips.length !== 1) {
        throw new Error(`expected exactly one .pbip in ${ROOT}, found ${pbips.length}; pass --project`);
    }
    return pbips[0].slice(0, -5);
}

/** PBIP JSON convention: 2-space indent, CRLF, UTF-8 without BOM. */
function writePbip(file, obj) {
    fs.writeFileSync(file, JSON.stringify(obj, null, 2).replace(/\r?\n/g, "\r\n"), "utf8");
}

const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8"));

/**
 * Copy shared TypeScript into <project>/src/shared. Shared code imports
 * powerbi-visuals-api, which only resolves inside a project with node_modules;
 * importing across ../../shared fails with TS2307. Less imports stay relative
 * (../../shared/base.less) because webpack resolves those from disk.
 */
function syncShared(name) {
    const dest = path.join(VISUALS, name, "src", "shared");
    fs.rmSync(dest, { recursive: true, force: true });
    fs.mkdirSync(dest, { recursive: true });
    let n = 0;
    for (const f of fs.readdirSync(SHARED)) {
        if (f.endsWith(".ts")) { fs.copyFileSync(path.join(SHARED, f), path.join(dest, f)); n++; }
    }
    return n;
}

/** Desktop caches bundles by guid+version: bump the build number every run. */
function bumpBuildNumber(cwd) {
    const file = path.join(cwd, "pbiviz.json");
    const j = readJson(file);
    const parts = j.visual.version.split(".").map(Number);
    parts[3] += 1;
    j.visual.version = parts.join(".");
    j.version = j.visual.version;
    fs.writeFileSync(file, JSON.stringify(j, null, 2) + "\n", "utf8");
    return j.visual.guid;
}

function buildOne(name) {
    const cwd = path.join(VISUALS, name);
    const copied = syncShared(name);
    const guid = bumpBuildNumber(cwd);
    const args = ["package", "--resources", "--no-stats"];
    if (!alsoPbiviz) { args.push("--no-pbiviz"); }

    console.log(`\n=== ${name} (${copied} shared files) ===`);
    execFileSync("pbiviz", args, { cwd, stdio: "inherit", shell: process.platform === "win32" });

    const resDir = path.join(cwd, "dist", "resources");
    const file = fs.readdirSync(resDir).find((f) => f.endsWith(".pbiviz.json"));
    if (!file) { throw new Error(`${name}: no .pbiviz.json produced`); }
    if (file !== `${guid}.pbiviz.json`) { throw new Error(`${name}: guid drift (${file} vs ${guid})`); }
    return { name, guid, pkg: path.join(cwd, "dist", "package.json"), res: path.join(resDir, file) };
}

/** Byte-copy only: content.js is one 30-200 KB line; reformatting corrupts it. */
function embed(cv, { guid, pkg, res }) {
    const dest = path.join(cv, guid);
    fs.rmSync(dest, { recursive: true, force: true });
    fs.mkdirSync(path.join(dest, "resources"), { recursive: true });
    fs.copyFileSync(pkg, path.join(dest, "package.json"));
    fs.copyFileSync(res, path.join(dest, "resources", `${guid}.pbiviz.json`));
}

/** Register our guids; keep every other package (RegisteredResources, and any
 *  CustomVisual we do not own) untouched. */
function register(report, ownGuids, embedded) {
    const file = path.join(report, "definition", "report.json");
    const r = readJson(file);
    const kept = (r.resourcePackages ?? []).filter((p) => !(p.type === "CustomVisual" && ownGuids.includes(p.name)));
    r.resourcePackages = [
        ...kept,
        ...embedded.map((g) => ({
            name: g,
            type: "CustomVisual",
            items: [{ name: `${g}.pbiviz.json`, path: `${g}.pbiviz.json`, type: "CustomVisualMetadata" }],
        })),
    ];
    writePbip(file, r);
}

/** A visual.json naming an unregistered guid renders as a blank box with no
 *  diagnostic - the highest-value silent failure to catch. */
function verifyReferences(report) {
    const r = readJson(path.join(report, "definition", "report.json"));
    const known = new Set([
        ...(r.resourcePackages ?? []).filter((p) => p.type === "CustomVisual").map((p) => p.name),
        ...(r.publicCustomVisuals ?? []),
    ]);
    const pagesDir = path.join(report, "definition", "pages");
    const bad = [];
    for (const page of fs.readdirSync(pagesDir, { withFileTypes: true })) {
        if (!page.isDirectory()) { continue; }
        const vdir = path.join(pagesDir, page.name, "visuals");
        if (!fs.existsSync(vdir)) { continue; }
        for (const v of fs.readdirSync(vdir)) {
            const vf = path.join(vdir, v, "visual.json");
            if (!fs.existsSync(vf)) { continue; }
            const t = readJson(vf)?.visual?.visualType;
            if (t && GUID_SHAPE.test(t) && !known.has(t)) { bad.push(`${page.name}/${v}: ${t}`); }
        }
    }
    if (bad.length) { throw new Error("visual.json references unregistered custom visuals:\n  " + bad.join("\n  ")); }
}

// ---------------------------------------------------------------- main ---

const PROJECT = findProject();
const REPORT = path.join(ROOT, `${PROJECT}.Report`);
const CV = path.join(REPORT, "CustomVisuals");
const manifest = readJson(MANIFEST);
const NAMES = Object.keys(manifest);
const OWN = Object.values(manifest);

if (checkOnly) {
    verifyReferences(REPORT);
    console.log(`References OK (${PROJECT}): ${NAMES.join(", ")}`);
    process.exit(0);
}

const targets = only ? [only] : NAMES;
for (const t of targets) { if (!NAMES.includes(t)) { throw new Error(`unknown visual: ${t}`); } }

const built = targets.map(buildOne);
fs.mkdirSync(CV, { recursive: true });
if (!only) {
    for (const g of OWN) { fs.rmSync(path.join(CV, g), { recursive: true, force: true }); }
}
built.forEach((b) => embed(CV, b));

const embedded = OWN.filter((g) => fs.existsSync(path.join(CV, g)));
register(REPORT, OWN, embedded);
verifyReferences(REPORT);

console.log(`\nEmbedded ${embedded.length} visual(s) into ${path.relative(ROOT, CV)}`);
for (const b of built) { console.log(`  ${b.name}  ${b.guid}`); }
