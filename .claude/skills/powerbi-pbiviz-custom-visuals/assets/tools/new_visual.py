#!/usr/bin/env python3
"""
Scaffold a Power BI custom visual project inside a PBIP dashboard repo.

Creates visuals/<name>/ from this skill's starter kit, gives it a fresh GUID,
records the GUID in tools/visuals.json, installs the shared library and the
sync script if the repo does not have them yet, then installs npm dependencies.

    python <skill>/assets/tools/new_visual.py --name finVarianceTable \
        --template varianceTable --display "Variance Table" \
        --description "IBCS statement table" \
        --author-name "Your Team" --author-email "you@example.com"

Offline (no npm registry): pass --node-modules-from <existing visual project>
to copy a working node_modules instead of running npm install.

A GUID is a visual's identity in report.json and every visual.json visualType.
This script never changes an existing one; re-running for an existing name fails.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.dirname(HERE)
TEMPLATES = ("varianceTable", "varianceChart", "blank")
SUPPORT_URL = "https://learn.microsoft.com/power-bi/developer/visuals/"


def write_json(path, obj):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", required=True, help="camelCase, letters/digits, starts with a letter (becomes the GUID prefix)")
    ap.add_argument("--template", choices=TEMPLATES, default="blank")
    ap.add_argument("--display", required=True, help="Display name in the Visualizations pane")
    ap.add_argument("--description", required=True)
    ap.add_argument("--author-name", required=True)
    ap.add_argument("--author-email", required=True)
    ap.add_argument("--support-url", default=SUPPORT_URL)
    ap.add_argument("--root", default=os.getcwd(), help="Dashboard repo root (contains the .pbip)")
    ap.add_argument("--node-modules-from", help="Copy node_modules from this visual project instead of npm install")
    ap.add_argument("--skip-install", action="store_true")
    args = ap.parse_args()

    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]{2,40}", args.name):
        sys.exit("--name must be letters/digits, start with a letter, 3-41 chars (no spaces, dashes or underscores)")

    root = os.path.abspath(args.root)
    visuals = os.path.join(root, "visuals")
    dst = os.path.join(visuals, args.name)
    if os.path.exists(dst):
        sys.exit(f"{dst} already exists - never re-scaffold a visual; its GUID is referenced by the report")

    manifest_path = os.path.join(root, "tools", "visuals.json")
    manifest = {}
    if os.path.exists(manifest_path):
        with open(manifest_path, encoding="utf-8") as f:
            manifest = json.load(f)
    if args.name in manifest:
        sys.exit(f"{args.name} is already registered in tools/visuals.json")

    # 1. project skeleton + template
    shutil.copytree(os.path.join(ASSETS, "project"), dst)
    tpl = os.path.join(ASSETS, "templates", args.template)
    shutil.copytree(tpl, dst, dirs_exist_ok=True)

    # 2. pbiviz.json
    guid = args.name + uuid.uuid4().hex.upper()
    pbiviz_path = os.path.join(dst, "pbiviz.json")
    with open(pbiviz_path, encoding="utf-8") as f:
        text = f.read()
    for k, v in {
        "__NAME__": args.name, "__DISPLAY_NAME__": args.display, "__GUID__": guid,
        "__DESCRIPTION__": args.description, "__SUPPORT_URL__": args.support_url,
        "__AUTHOR_NAME__": args.author_name, "__AUTHOR_EMAIL__": args.author_email,
    }.items():
        text = text.replace(k, json.dumps(v)[1:-1])
    with open(pbiviz_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    pkg_path = os.path.join(dst, "package.json")
    with open(pkg_path, encoding="utf-8") as f:
        pkg = json.load(f)
    pkg["name"] = args.name.lower()
    pkg["description"] = args.description
    write_json(pkg_path, pkg)

    # 3. repo-level shared library and sync tooling (never overwrite project copies)
    shared = os.path.join(visuals, "shared")
    if not os.path.exists(shared):
        shutil.copytree(os.path.join(ASSETS, "shared"), shared)
        print(f"installed shared library -> {shared}")
    tools = os.path.join(root, "tools")
    os.makedirs(tools, exist_ok=True)
    for f in ("sync-visuals.mjs", "pbir_helpers.py"):
        target = os.path.join(tools, f)
        if not os.path.exists(target):
            shutil.copy2(os.path.join(HERE, f), target)
            print(f"installed {f} -> {target}")

    manifest[args.name] = guid
    write_json(manifest_path, manifest)

    # 4. dependencies
    if args.node_modules_from:
        src = os.path.join(os.path.abspath(args.node_modules_from), "node_modules")
        if not os.path.isdir(src):
            sys.exit(f"no node_modules under {args.node_modules_from}")
        # No ignore patterns: packages ship their own src/ folders (powerbi-visuals-api
        # keeps its typings in src/), and filtering "src" silently breaks the build.
        shutil.copytree(src, os.path.join(dst, "node_modules"))
        print("copied node_modules")
    elif not args.skip_install:
        subprocess.run("npm install --no-audit --no-fund", cwd=dst, shell=True, check=True)

    print(f"\n{args.name}  {guid}")
    print(f"template: {args.template}")
    print("next: edit capabilities.json + src/visual.ts, then  node tools/sync-visuals.mjs --only " + args.name)


if __name__ == "__main__":
    main()
