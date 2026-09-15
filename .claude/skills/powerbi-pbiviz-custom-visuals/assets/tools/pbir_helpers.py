#!/usr/bin/env python3
"""
Helpers for writing visual.json files that bind a custom visual.

Import from a build script:

    from pbir_helpers import *
    G = load_guids()
    v = custom_visual(
        name="salesVariance", guid=G["finVarianceTable"],
        x=26, y=202, w=760, h=500, z=2000,
        roles={
            "rows":  [col("Account Hierarchy", "Level 1"), col("Account Hierarchy", "Level 2")],
            "ac":    [meas("_Measures", "Actual", display="AC")],
        },
        objects={"display": props(unit=s("K"), fontSize=d(11))},
        filters=[categorical_filter("fYear", "Dates", "Year", [2025])],
    )
    write_json(path_to_visual_json, v)

Rules these helpers encode (each one cost a debugging round once):
  * queryState keys are dataRole `name`s from capabilities.json, not display names
  * objects keys/properties must exist in capabilities.json `objects`
  * literal encoding: text/enum "'x'", bool "true", int "5L", number/fontSize "11D"
  * a fill is {"solid": {"color": <literal>}}
  * an image visual's sourceField wraps the measure in {"expr": ...}
  * never write "selector": null
"""

import json
import os

SCHEMA_VIZ = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.12.0/schema.json"


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")


def load_guids(root=None):
    """Load { "<visual name>": "<guid>" } from tools/visuals.json.

    `new_visual.py` writes this file once per visual and never edits an existing
    entry - it is the single source of truth for a guid, and every build script
    should read it through this function rather than re-typing the load line or
    hardcoding a guid.

    Walks up from `root` (default: current directory) looking for tools/visuals.json,
    so this works whether the build script runs from the repo root or a subfolder.
    Raises FileNotFoundError with the paths it checked if none is found - a build
    script should let that stop the run rather than silently binding no guids.
    """
    here = os.path.abspath(root or os.getcwd())
    checked = []
    while True:
        candidate = os.path.join(here, "tools", "visuals.json")
        checked.append(candidate)
        if os.path.isfile(candidate):
            with open(candidate, encoding="utf-8") as f:
                return json.load(f)
        parent = os.path.dirname(here)
        if parent == here:
            break
        here = parent
    raise FileNotFoundError(
        "tools/visuals.json not found. Checked:\n  " + "\n  ".join(checked) +
        "\nRun tools/new_visual.py at least once to create it."
    )


def lit(v):
    return {"expr": {"Literal": {"Value": v}}}


def s(v):
    """Text or enumeration literal."""
    return lit(f"'{v}'")


def b(v):
    return lit("true" if v else "false")


def d(v):
    """Numeric / fontSize literal."""
    return lit(f"{v}D")


def i(v):
    """Integer literal."""
    return lit(f"{int(v)}L")


def fill(color):
    return {"solid": {"color": lit(f"'{color}'")}}


def props(**kw):
    return [{"properties": kw}]


def col(entity, prop, display=None):
    return {"_field": {"Column": {"Expression": {"SourceRef": {"Entity": entity}}, "Property": prop}}, "_display": display}


def meas(entity, prop, display=None):
    return {"_field": {"Measure": {"Expression": {"SourceRef": {"Entity": entity}}, "Property": prop}}, "_display": display}


def _proj(f):
    field = f["_field"]
    k = list(field)[0]
    ent = field[k]["Expression"]["SourceRef"]["Entity"]
    prop = field[k]["Property"]
    p = {"field": field, "queryRef": f"{ent}.{prop}", "nativeQueryRef": prop}
    if f["_display"]:
        p["displayName"] = f["_display"]
    return p


NO_CHROME = {
    "background": props(show=b(False)),
    "border": props(show=b(False)),
    "dropShadow": props(show=b(False)),
    "title": props(show=b(False)),
}


def categorical_filter(name, entity, prop, values):
    def value_lit(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, int):
            return f"{v}L"
        return f"'{v}'"
    return {
        "name": name,
        "field": {"Column": {"Expression": {"SourceRef": {"Entity": entity}}, "Property": prop}},
        "type": "Categorical",
        "filter": {
            "Version": 2,
            "From": [{"Name": "t", "Entity": entity, "Type": 0}],
            "Where": [{"Condition": {"In": {
                "Expressions": [{"Column": {"Expression": {"SourceRef": {"Source": "t"}}, "Property": prop}}],
                "Values": [[{"Literal": {"Value": value_lit(v)}}] for v in values],
            }}}],
        },
        "howCreated": "User",
    }


def custom_visual(name, guid, x, y, w, h, z, roles, objects=None, filters=None, chrome=NO_CHROME):
    """visual.json for an embedded custom visual. `guid` is the visualType."""
    v = {
        "$schema": SCHEMA_VIZ,
        "name": name,
        "position": {"x": x, "y": y, "z": z, "height": h, "width": w, "tabOrder": z},
        "visual": {
            "visualType": guid,
            "query": {"queryState": {role: {"projections": [_proj(f) for f in fields]} for role, fields in roles.items()}},
            "objects": objects or {},
            "visualContainerObjects": chrome,
            "drillFilterOtherVisuals": True,
        },
    }
    if filters:
        v["filterConfig"] = {"filters": filters}
    return v


def check_against_capabilities(visual_json, capabilities_path):
    """Fail fast when a visual.json uses a role or object the visual does not declare.
    Both mistakes load without error and render blank or ignore the setting."""
    caps = json.load(open(capabilities_path, encoding="utf-8"))
    roles = {r["name"] for r in caps.get("dataRoles", [])}
    objs = caps.get("objects", {})
    errors = []
    for role in visual_json["visual"].get("query", {}).get("queryState", {}):
        if role not in roles:
            errors.append(f"queryState role '{role}' not in dataRoles {sorted(roles)}")
    for obj, entries in visual_json["visual"].get("objects", {}).items():
        if obj not in objs:
            errors.append(f"object '{obj}' not declared in capabilities.objects")
            continue
        for e in entries:
            for p in e.get("properties", {}):
                if p not in objs[obj].get("properties", {}):
                    errors.append(f"property '{obj}.{p}' not declared in capabilities")
    if errors:
        raise SystemExit(f"{visual_json['name']}:\n  " + "\n  ".join(errors))
