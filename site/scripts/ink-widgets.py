"""Writes src/ink/<key>.json and src/assets/ink/<part>.png for the game widgets the page redraws.

Each widget is one library item from the ink archive's database, exported as a tree of positioned
nodes (the way inkCanvasWidget, inkHorizontalPanelWidget and inkFlexWidget place their children),
together with the animation sequences it plays, converted to keyframes per widget and property.
Textures are the atlases' 4K slots, uncooked to PNG with the wolvenkit MCP into one folder that
mirrors their depot paths; a missing one is named and the script stops.

    python scripts/ink-widgets.py <uncooked texture root> [path/to/ink.db]
"""
import json
import re
import sqlite3
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
DEFAULT_DB = HERE.parents[3] / "cp2077-ink-archive" / "data" / "ink.db"
OUT_JSON = HERE.parent / "src" / "ink"
OUT_PARTS = HERE.parent / "src" / "assets" / "ink"

B = "\\"
GUI = "base" + B + "gameplay" + B + "gui" + B
MAIN_COLORS = GUI + "common" + B + "main_colors.inkstyle"

WIDGETS = {
    "progress": {
        "file": GUI + "widgets" + B + "hud_progress_bar" + B + "hud_progress_bar.inkwidget",
        "item": "Root",
        "animations": GUI + "widgets" + B + "hud_progress_bar" + B + "hud_progress_bar_animations.inkanim",
        "sequences": ["Quickhack_Intro", "Quickhack_Outro", "Quickhack_Outro_Failed"],
        # The upload bar and its text; the per-hack icon canvases stay out.
        "keep": ["wrapper/Quickhack_Elements_Canvas", "wrapper/Personal_Link_Main_Elements_Canvas"],
    },
    "toast": {
        "file": GUI + "widgets" + B + "notifications" + B + "items_update.inkwidget",
        "item": "Item_Received_SMALL",
        "animations": GUI + "widgets" + B + "notifications" + B + "items_update_animations.inkanim",
        "sequences": ["Item_Received_SMALL"],
        "keep": None,
    },
}

ANCHORS = {
    "TopLeft": (0, 0, 0, 0), "TopCenter": (.5, 0, .5, 0), "TopRight": (1, 0, 1, 0),
    "CenterLeft": (0, .5, 0, .5), "Centered": (.5, .5, .5, .5), "CenterRight": (1, .5, 1, .5),
    "BottomLeft": (0, 1, 0, 1), "BottomCenter": (.5, 1, .5, 1), "BottomRight": (1, 1, 1, 1),
    "Fill": (0, 0, 1, 1), "TopFillHorizontaly": (0, 0, 1, 0), "BottomFillHorizontaly": (0, 1, 1, 1),
    "CenterFillHorizontaly": (0, .5, 1, .5), "LeftFillVerticaly": (0, 0, 0, 1),
    "RightFillVerticaly": (1, 0, 1, 1), "CenterFillVerticaly": (.5, 0, .5, 1),
}

# ink interpolation curves as CSS cubic-beziers (the standard easing set these names describe).
CURVES = {
    ("Sinusoidal", "EasyIn"): (.12, 0, .39, 0), ("Sinusoidal", "EasyOut"): (.61, 1, .88, 1),
    ("Sinusoidal", "EasyInOut"): (.37, 0, .63, 1),
    ("Quadratic", "EasyIn"): (.11, 0, .5, 0), ("Quadratic", "EasyOut"): (.5, 1, .89, 1),
    ("Quadratic", "EasyInOut"): (.45, 0, .55, 1),
    ("Qubic", "EasyIn"): (.32, 0, .67, 0), ("Qubic", "EasyOut"): (.33, 1, .68, 1), ("Qubic", "EasyInOut"): (.65, 0, .35, 1),
    ("Quartic", "EasyIn"): (.5, 0, .75, 0), ("Quartic", "EasyOut"): (.25, 1, .5, 1), ("Quartic", "EasyInOut"): (.76, 0, .24, 1),
    ("Quintic", "EasyIn"): (.64, 0, .78, 0), ("Quintic", "EasyOut"): (.22, 1, .36, 1), ("Quintic", "EasyInOut"): (.83, 0, .17, 1),
    ("Exponential", "EasyIn"): (.7, 0, .84, 0), ("Exponential", "EasyOut"): (.16, 1, .3, 1),
    ("Exponential", "EasyInOut"): (.87, 0, .13, 1),
}


def easing(kind, mode):
    if kind in (None, "Linear"):
        return "linear"
    curve = CURVES.get((kind, mode)) or CURVES.get((kind, "EasyOut"))
    return "cubic-bezier(%g, %g, %g, %g)" % curve if curve else "linear"


def kebab(name):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "-", name.replace("Fullscreen_", "Fs")).lower().replace("_", "-")


class Ink:
    def __init__(self, db):
        self.db = db
        self.styles = {}

    def q(self, sql, *args):
        return self.db.execute(sql, args).fetchall()

    def style(self, path):
        if path not in self.styles:
            row = self.q("SELECT data FROM files WHERE path = ?", path)
            props = {}
            if row:
                for style in json.loads(row[0][0])["styles"]:
                    if style.get("state", "Default") == "Default":
                        for prop in style["properties"]:
                            props[prop["propertyPath"]] = prop["value"]
            self.styles[path] = props
        return self.styles[path]

    def resolve(self, style_path, prop):
        """A bound style property: a CSS colour variable, a number, or None."""
        for sheet in (style_path, MAIN_COLORS):
            if not sheet:
                continue
            value = self.style(sheet).get(prop)
            if value is None:
                continue
            inner = value.get("Value", value)
            if isinstance(inner, dict) and "referencedPath" in inner:
                ref = inner["referencedPath"]
                if ref.startswith("MainColors.") and isinstance(self.style(MAIN_COLORS).get(ref, {}).get("Value"), dict):
                    return "var(--%s)" % kebab(ref.split(".", 1)[1])
                return self.resolve(style_path, ref)
            if isinstance(inner, dict) and "Red" in inner:
                return "#%02x%02x%02x" % tuple(min(255, round(inner[k] * 255)) for k in ("Red", "Green", "Blue"))
            if isinstance(inner, (int, float)):
                return float(inner)
        return None

    def bindings(self, cid):
        for (to,) in self.q("SELECT to_cid FROM refs WHERE from_cid = ?", cid):
            cls, data = self.q("SELECT class, data FROM chunks WHERE cid = ?", to)[0]
            if cls == "inkPropertyManager":
                return {b["propertyName"]: b["stylePath"] for b in json.loads(data).get("bindings", [])}
        return {}

    def atlas_parts(self, atlas):
        row = self.q("SELECT data FROM files WHERE path = ?", atlas)
        if not row:
            return None, {}
        slot = json.loads(row[0][0])["slots"]["Elements"][0]
        texture = slot["texture"]["DepotPath"]
        texture = texture.get("$v") if isinstance(texture, dict) else texture
        return texture, {p["partName"]: p["clippingRectInUVCoords"] for p in slot["parts"]}


def export(ink, spec, textures, used):
    file_row = ink.q("SELECT fid FROM files WHERE path = ?", spec["file"])[0][0]
    root = ink.q("SELECT root_widget_cid FROM items_v WHERE path = ? AND name = ?", spec["file"], spec["item"])[0][0]

    def size_of_part(atlas, part):
        texture, parts = ink.atlas_parts(atlas)
        if part not in parts:
            return None
        png = textures / (texture.replace(B, "/").rsplit(".", 1)[0] + ".png")
        if not png.exists():
            sys.exit("uncook %s to %s first" % (texture, png))
        with Image.open(png) as im:
            uv = parts[part]
            used.add((atlas, part, str(png)))
            return ((uv["Right"] - uv["Left"]) * im.width, (uv["Bottom"] - uv["Top"]) * im.height)

    def kept(path):
        keep = spec["keep"]
        return keep is None or not path or any(k.startswith(path) or path.startswith(k) for k in keep)

    def node(cid, pw, ph, path, placed=None):
        cls, name, data = ink.q("SELECT class, name, data FROM chunks WHERE cid = ?", cid)[0]
        d = json.loads(data)
        own = (path + "/" + name) if path else name
        rel = own.split("/", 1)[1] if "/" in own else ""
        if not d.get("visible", 1) or cls == "inkBorderWidget" or not kept(rel):
            return None
        style_path = ink.q("SELECT style FROM widgets WHERE cid = ?", cid)
        style_path = style_path[0][0] if style_path else None
        layout = d.get("layout", {})
        margin = layout.get("margin", {})
        ml, mt, mr, mb = (margin.get(k, 0) for k in ("left", "top", "right", "bottom"))
        size = d.get("size", {"X": 0, "Y": 0})
        w, h = size["X"], size["Y"]
        atlas = (d.get("textureAtlas") or {}).get("DepotPath")
        atlas = atlas.get("$v") if isinstance(atlas, dict) else atlas
        part = d.get("texturePart")
        if cls in ("inkImageWidget", "inkMaskWidget") and atlas and part:
            native = size_of_part(atlas, part)
            if native is None:
                return None
            if d.get("fitToContent", 1):
                w, h = native

        if cls == "inkFlexWidget" and not placed:
            # A flex widget takes its parent's area and lays its children over it.
            x, y, w, h = 0, 0, pw, ph
        elif placed:  # a panel child: the panel has already decided where it goes
            x, y = placed
            x += ml
            y += mt
        else:
            anchor = ANCHORS.get(layout.get("anchor", "TopLeft"), ANCHORS["TopLeft"])
            point = layout.get("anchorPoint", {"X": 0, "Y": 0})

            def axis(lo, hi, parent, m_lo, m_hi, own_size, pivot):
                if lo != hi:
                    return lo * parent + m_lo, (hi - lo) * parent - m_lo - m_hi
                offset = m_lo if lo == 0 else -m_hi if lo == 1 else m_lo - m_hi
                return lo * parent + offset - pivot * own_size, own_size

            x, w = axis(anchor[0], anchor[2], pw, ml, mr, w, point["X"])
            y, h = axis(anchor[1], anchor[3], ph, mt, mb, h, point["Y"])

        transform = d.get("renderTransform", {})
        translation = transform.get("translation", {"X": 0, "Y": 0})
        scale = transform.get("scale", {"X": 1, "Y": 1})
        out = {"path": rel, "name": name, "x": round(x, 2), "y": round(y, 2), "w": round(w, 2), "h": round(h, 2)}
        if translation["X"] or translation["Y"]:
            out["translate"] = [translation["X"], translation["Y"]]
        if scale["X"] != 1 or scale["Y"] != 1:
            out["scale"] = [round(scale["X"], 3), round(scale["Y"], 3)]
        if transform.get("rotation"):
            out["rotation"] = transform["rotation"]
        pivot = d.get("renderTransformPivot")
        if pivot and (pivot["X"], pivot["Y"]) != (0.5, 0.5):
            out["pivot"] = [pivot["X"], pivot["Y"]]

        bindings = ink.bindings(cid)
        opacity = d.get("opacity", 1)
        if "opacity" in bindings and isinstance(ink.resolve(style_path, bindings["opacity"]), float):
            opacity = ink.resolve(style_path, bindings["opacity"])
        if opacity < 1:
            out["opacity"] = round(opacity, 3)
        color = ink.resolve(style_path, bindings["tintColor"]) if "tintColor" in bindings else None
        if not isinstance(color, str) and "tintColor" in d:
            t = d["tintColor"]
            color = "#%02x%02x%02x" % tuple(min(255, round(t.get(k, 0) * 255)) for k in ("Red", "Green", "Blue"))
        if color and color != "#ffffff" or cls in ("inkImageWidget", "inkTextWidget", "inkRectangleWidget"):
            out["color"] = color or "#ffffff"

        if cls == "inkImageWidget":
            out.update(kind="image", part=part)
        elif cls == "inkRectangleWidget":
            out["kind"] = "rect"
        elif cls == "inkMaskWidget":
            return None
        elif cls == "inkTextWidget":
            font_size = d.get("fontSize", 20)
            if "fontSize" in bindings and isinstance(ink.resolve(style_path, bindings["fontSize"]), float):
                font_size = ink.resolve(style_path, bindings["fontSize"])
            out.update(kind="text", text=d.get("text", ""), fontSize=font_size,
                       weight=d.get("fontStyle", "Medium"), upper=d.get("letterCase") == "UpperCase",
                       align=d.get("textHorizontalAlignment", "Left"), fit=bool(d.get("fitToContent", 0)))
        else:
            out["kind"] = "canvas"
            kids = [c for (c,) in ink.q("SELECT child_cid FROM widget_tree WHERE parent_cid = ? ORDER BY ord", cid)]
            children = []
            if cls in ("inkHorizontalPanelWidget", "inkVerticalPanelWidget"):
                horizontal = cls == "inkHorizontalPanelWidget"
                cursor = 0
                for kid in kids:
                    child = node(kid, w, h, own, placed=(cursor, 0) if horizontal else (0, cursor))
                    if child:
                        children.append(child)
                        cursor += (child["w"] if horizontal else child["h"]) + (child["x"] - cursor if horizontal else child["y"] - cursor)
            elif cls == "inkFlexWidget":
                for kid in kids:
                    child = node(kid, w, h, own)
                    if child:
                        children.append(child)
            else:
                for kid in kids:
                    child = node(kid, w, h, own)
                    if child:
                        children.append(child)
            out["children"] = children
        return out

    tree = node(root, 0, 0, "")
    return tree


def sequences(ink, spec):
    """Each sequence as keyframes per target widget path and property, times in seconds."""
    fid = ink.q("SELECT fid FROM files WHERE path = ?", spec["animations"])[0][0]
    chunks = {c: json.loads(d) for c, d in ink.q("SELECT chunk_id, data FROM chunks WHERE fid = ?", fid)}
    root = ink.q("SELECT root_widget_cid FROM items_v WHERE path = ? AND name = ?", spec["file"], spec["item"])[0][0]

    def expand(v):
        if isinstance(v, dict):
            if set(v) == {"$ref"}:
                return expand(chunks.get(v["$ref"]))
            return {k: expand(x) for k, x in v.items()}
        if isinstance(v, list):
            return [expand(x) for x in v]
        return v

    def name_path(indices):
        cid, names = root, []
        for i in indices:
            kids = ink.q("SELECT child_cid FROM widget_tree WHERE parent_cid = ? ORDER BY ord", cid)
            if i >= len(kids):
                return None
            cid = kids[i][0]
            names.append(ink.q("SELECT name FROM chunks WHERE cid = ?", cid)[0][0])
        return "/".join(names)

    out = {}
    for data in chunks.values():
        if not data or data.get("$type") != "inkanimSequence" or data.get("name") not in spec["sequences"]:
            continue
        seq = expand(data)
        targets, length = {}, 0
        for target, definition in zip(seq["targets"], seq["definitions"]):
            if not target or not definition or not target["path"]:
                continue
            path = name_path(target["path"])
            if path is None:
                continue
            tracks = targets.setdefault(path, {})
            for it in definition["interpolators"]:
                if not it:
                    continue
                kind = it["$type"][len("inkanim"):-len("Interpolator")]
                prop = {"Transparency": "opacity", "Translation": "translate", "Scale": "scale", "Size": "size"}.get(kind)
                if not prop:
                    continue
                start, end = it["startValue"], it["endValue"]
                if isinstance(start, dict):
                    start, end = [start["X"], start["Y"]], [end["X"], end["Y"]]
                delay, duration = it["startDelay"], it["duration"]
                length = max(length, delay + duration)
                tracks.setdefault(prop, []).append({
                    "at": round(delay, 4), "to": round(delay + duration, 4), "from": start, "value": end,
                    "easing": easing(it.get("interpolationType"), it.get("interpolationMode")),
                })
        for tracks in targets.values():
            for steps in tracks.values():
                steps.sort(key=lambda s: s["at"])
        out[seq["name"]] = {"duration": round(length, 4), "targets": targets}
    return out


def main():
    textures = Path(sys.argv[1])
    ink = Ink(sqlite3.connect(sys.argv[2] if len(sys.argv) > 2 else DEFAULT_DB))
    used = set()
    OUT_JSON.mkdir(parents=True, exist_ok=True)
    for key, spec in WIDGETS.items():
        result = {"tree": export(ink, spec, textures, used), "sequences": sequences(ink, spec)}
        (OUT_JSON / (key + ".json")).write_text(json.dumps(result, indent=1), encoding="utf-8")
        print(key, "sequences", {k: v["duration"] for k, v in result["sequences"].items()})
    OUT_PARTS.mkdir(parents=True, exist_ok=True)
    for atlas, part, png in sorted(used):
        _, parts = ink.atlas_parts(atlas)
        uv = parts[part]
        with Image.open(png) as im:
            tex = im.convert("RGBA")
        box = (round(uv["Left"] * tex.width), round(uv["Top"] * tex.height),
               round(uv["Right"] * tex.width), round(uv["Bottom"] * tex.height))
        alpha = tex.crop(box).getchannel("A")
        mask = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
        mask.putalpha(alpha)
        mask.save(OUT_PARTS / (part.replace(" ", "_") + ".png"), optimize=True)
        print("part", part, box)


if __name__ == "__main__":
    main()
