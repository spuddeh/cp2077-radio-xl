"""Writes src/world/layouts.json and src/assets/world/<part>.png from the four world radio screens.

Each layout is a tree of positioned widgets, computed from the widget libraries in the ink
archive's database the way an inkCanvasWidget places its children. The four screens use only
canvas, image, text, mask and rectangle widgets, so no panel layout is needed. Textures are the
atlases' 4K slots, uncooked to PNG with the wolvenkit MCP.

    python scripts/world-radios.py <radio_ui.png> <atlas_scanner.png> [path/to/ink.db]
"""
import json
import sqlite3
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
DEFAULT_DB = HERE.parents[3] / "cp2077-ink-archive" / "data" / "ink.db"
OUT_JSON = HERE.parent / "src" / "world" / "layouts.json"
OUT_PARTS = HERE.parent / "src" / "assets" / "world"

B = "\\"
RADIO = "base" + B + "gameplay" + B + "gui" + B + "world" + B + "radio" + B
LAYOUTS = {
    "square": RADIO + "radio_ui.inkwidget",
    "long": RADIO + "radio_ui_long-hori.inkwidget",
    "tall": RADIO + "radio_ui_long-vert.inkwidget",
    "boombox": RADIO + "radio_ui_short-hori.inkwidget",
}
STYLE = RADIO + "radio_ui.inkstyle"
ANIMATIONS = RADIO + "radio_ui_animations.inkanim"
# The sequences RadioInkGameController plays while a radio is on.
PLAYED = ("eqLoop2", "eqLoop3", "eqLoop5", "eqLoop7")
MAIN_COLORS = "base" + B + "gameplay" + B + "gui" + B + "common" + B + "main_colors.inkstyle"
ATLASES = {
    RADIO + "radio_ui.inkatlas": 1,
    "base" + B + "gameplay" + B + "gui" + B + "widgets" + B + "scanning" + B + "scanner_tooltip" + B
    + "atlas_scanner.inkatlas": 2,
}
STATION_ATLAS = "base" + B + "gameplay" + B + "gui" + B + "common" + B + "icons" + B + "radiostations_icons.inkatlas"

ANCHORS = {
    "TopLeft": (0, 0, 0, 0), "TopCenter": (.5, 0, .5, 0), "TopRight": (1, 0, 1, 0),
    "CenterLeft": (0, .5, 0, .5), "Centered": (.5, .5, .5, .5), "CenterRight": (1, .5, 1, .5),
    "BottomLeft": (0, 1, 0, 1), "BottomCenter": (.5, 1, .5, 1), "BottomRight": (1, 1, 1, 1),
    "Fill": (0, 0, 1, 1), "TopFillHorizontaly": (0, 0, 1, 0), "BottomFillHorizontaly": (0, 1, 1, 1),
    "CenterFillHorizontaly": (0, .5, 1, .5), "LeftFillVerticaly": (0, 0, 0, 1),
    "RightFillVerticaly": (1, 0, 1, 1), "CenterFillVerticaly": (.5, 0, .5, 1),
}


def kebab(name):
    import re
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "-", name.replace("Fullscreen_", "Fs")).lower().replace("_", "-")


class Ink:
    def __init__(self, db):
        self.db = db

    def q(self, sql, *args):
        return self.db.execute(sql, args).fetchall()

    def style(self, path, state="Default"):
        data = json.loads(self.q("SELECT data FROM files WHERE path = ?", path)[0][0])
        out = {}
        for style in data["styles"]:
            if style.get("state", "Default") == state:
                for prop in style["properties"]:
                    out[prop["propertyPath"]] = prop["value"]
        return out

    def parts(self, atlas):
        data = json.loads(self.q("SELECT data FROM files WHERE path = ?", atlas)[0][0])
        return {p["partName"]: p["clippingRectInUVCoords"] for p in data["slots"]["Elements"][0]["parts"]}

    def bindings(self, cid):
        for (to,) in self.q("SELECT to_cid FROM refs WHERE from_cid = ?", cid):
            cls, data = self.q("SELECT class, data FROM chunks WHERE cid = ?", to)[0]
            if cls == "inkPropertyManager":
                return {b["propertyName"]: b["stylePath"] for b in json.loads(data).get("bindings", [])}
        return {}


def main():
    radio_png, scanner_png = sys.argv[1], sys.argv[2]
    ink = Ink(sqlite3.connect(sys.argv[3] if len(sys.argv) > 3 else DEFAULT_DB))
    radio_style = ink.style(STYLE)
    main_style = ink.style(MAIN_COLORS)
    textures = {1: Image.open(radio_png).convert("RGBA"), 2: Image.open(scanner_png).convert("RGBA")}
    atlas_parts = {path: ink.parts(path) for path in ATLASES}
    used_parts = set()

    def resolve(path):
        """A style path's value: a CSS colour variable, or a number."""
        value = radio_style.get(path) or main_style.get(path)
        inner = value.get("Value", value) if value else None
        if isinstance(inner, dict) and "referencedPath" in inner:
            ref = inner["referencedPath"]
            if ref.startswith("MainColors."):
                return "var(--%s)" % kebab(ref.split(".", 1)[1])
            return resolve(ref)
        if isinstance(inner, (int, float)):
            return float(inner)
        return None

    def part_size(atlas, part):
        if atlas == STATION_ATLAS:
            return None
        uv = atlas_parts[atlas][part]
        tex = textures[ATLASES[atlas]]
        return ((uv["Right"] - uv["Left"]) * tex.width, (uv["Bottom"] - uv["Top"]) * tex.height)

    def node(cid, pw, ph):
        cls, name, data = ink.q("SELECT class, name, data FROM chunks WHERE cid = ?", cid)[0]
        d = json.loads(data)
        if not d.get("visible", 1):
            return None
        layout = d.get("layout", {})
        anchor = ANCHORS.get(layout.get("anchor", "TopLeft"), ANCHORS["TopLeft"])
        point = layout.get("anchorPoint", {"X": 0, "Y": 0})
        margin = layout.get("margin", {})
        ml, mt, mr, mb = (margin.get(k, 0) for k in ("left", "top", "right", "bottom"))
        size = d.get("size", {"X": 0, "Y": 0})
        w, h = size["X"], size["Y"]
        atlas = (d.get("textureAtlas") or {}).get("DepotPath")
        atlas = atlas.get("$v") if isinstance(atlas, dict) else atlas
        part = d.get("texturePart")
        if cls in ("inkImageWidget", "inkMaskWidget") and atlas in atlas_parts and part not in atlas_parts[atlas]:
            return None  # a part missing from its atlas draws nothing in game
        if cls in ("inkImageWidget", "inkMaskWidget") and d.get("fitToContent", 1) and atlas in atlas_parts and part:
            w, h = part_size(atlas, part)

        def axis(lo, hi, parent, m_lo, m_hi, own, pivot):
            if lo != hi:
                return lo * parent + m_lo, (hi - lo) * parent - m_lo - m_hi
            offset = m_lo if lo == 0 else -m_hi if lo == 1 else m_lo - m_hi
            return lo * parent + offset - pivot * own, own

        x, w = axis(anchor[0], anchor[2], pw, ml, mr, w, point["X"])
        y, h = axis(anchor[1], anchor[3], ph, mt, mb, h, point["Y"])
        transform = d.get("renderTransform", {})
        translation = transform.get("translation", {"X": 0, "Y": 0})
        scale = transform.get("scale", {"X": 1, "Y": 1})
        out = {
            "name": name, "x": round(x + translation["X"], 2), "y": round(y + translation["Y"], 2),
            "w": round(w, 2), "h": round(h, 2),
        }
        if translation["Y"]:
            out["restY"] = round(y, 2)  # where an animated translation is measured from
        if scale["X"] != 1 or scale["Y"] != 1:
            out["scale"] = [round(scale["X"], 3), round(scale["Y"], 3)]
        if transform.get("rotation"):
            out["rotation"] = transform["rotation"]

        bindings = ink.bindings(cid)
        opacity = d.get("opacity", 1)
        if "opacity" in bindings and isinstance(resolve(bindings["opacity"]), float):
            opacity = resolve(bindings["opacity"])
        if opacity < 1:
            out["opacity"] = round(opacity, 3)
        if opacity <= 0:
            return None
        color = resolve(bindings["tintColor"]) if "tintColor" in bindings else None
        if color is None and "tintColor" in d:
            t = d["tintColor"]
            color = "#%02x%02x%02x" % tuple(min(255, round(t.get(k, 0) * 255)) for k in ("Red", "Green", "Blue"))
        if color and cls != "inkCanvasWidget":
            out["color"] = color

        if cls == "inkImageWidget":
            out["kind"] = "image"
            if atlas == STATION_ATLAS:
                out["role"] = "logo"
            else:
                out["part"] = part
                used_parts.add((atlas, part))
        elif cls == "inkMaskWidget":
            out["kind"] = "mask"
        elif cls == "inkRectangleWidget":
            out["kind"] = "rect"
        elif cls == "inkTextWidget":
            out.update(kind="text", text=d.get("text", ""), fontSize=d.get("fontSize", 20),
                       weight=d.get("fontStyle", "Medium"), upper=d.get("letterCase") == "UpperCase",
                       align=d.get("textHorizontalAlignment", "Left"), fit=bool(d.get("fitToContent", 0)))
            if name == "radioName":
                out["role"] = "name"
            if d.get("textOverflowPolicy") == "AutoScroll":
                out["scroll"] = {"speed": d.get("scrollTextSpeed"), "delay": d.get("scrollDelay")}
        else:
            out["kind"] = "canvas"
            kids = []
            for (child,) in ink.q("SELECT child_cid FROM widget_tree WHERE parent_cid = ? ORDER BY ord", cid):
                kid = node(child, w, h)
                if kid:
                    kids.append(kid)
            out["children"] = kids
        return out

    layouts = {}
    for key, path in LAYOUTS.items():
        root = ink.q("SELECT root_widget_cid FROM items_v WHERE path = ? AND name = 'Root'", path)[0][0]
        tree = node(root, 0, 0)
        layouts[key] = tree
        print(key, tree["w"], "x", tree["h"])

    layouts["equaliser"] = equaliser(ink)

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(layouts, indent=1), encoding="utf-8")
    OUT_PARTS.mkdir(parents=True, exist_ok=True)
    for atlas, part in sorted(used_parts):
        uv = atlas_parts[atlas][part]
        tex = textures[ATLASES[atlas]]
        box = (round(uv["Left"] * tex.width), round(uv["Top"] * tex.height),
               round(uv["Right"] * tex.width), round(uv["Bottom"] * tex.height))
        alpha = tex.crop(box).getchannel("A")
        mask = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
        mask.putalpha(alpha)
        mask.save(OUT_PARTS / (part.replace(" ", "_") + ".png"), optimize=True)
        print("part", part, box)


def equaliser(ink):
    """Each equaliser column's loop: its period and the Y translation keyframes of its bar.

    A sequence targets EQ (root child 3), column N, bar (child 0). Every definition is a rise and a
    fall; the whole sequence restarts once its last interpolator ends (loopType Cycle).
    """
    fid = ink.q("SELECT fid FROM files WHERE path = ?", ANIMATIONS)[0][0]
    chunks = {cid: json.loads(data) for cid, data in ink.q("SELECT chunk_id, data FROM chunks WHERE fid = ?", fid)}

    def expand(value):
        if isinstance(value, dict):
            if set(value) == {"$ref"}:
                return expand(chunks[value["$ref"]])
            return {k: expand(v) for k, v in value.items()}
        if isinstance(value, list):
            return [expand(v) for v in value]
        return value

    columns = {}
    for data in chunks.values():
        if data.get("$type") != "inkanimSequence" or data.get("name") not in PLAYED:
            continue
        seq = expand(data)
        steps = [[(i["startDelay"], i["duration"], i["startValue"]["Y"], i["endValue"]["Y"])
                  for i in definition["interpolators"]] for definition in seq["definitions"]]
        period = max(delay + duration for s in steps for delay, duration, _, _ in s)
        for target, definition in zip(seq["targets"], steps):
            path = target["path"]
            assert path[0] == 3 and path[2] == 0, path
            frames = []
            for delay, duration, start, end in sorted(definition):
                frames.append([round(delay / period, 4), start])
                frames.append([round((delay + duration) / period, 4), end])
            if frames[0][0] > 0:
                frames.insert(0, [0, frames[0][1]])
            if frames[-1][0] < 1:
                frames.append([1, frames[-1][1]])
            columns[path[1]] = {"sequence": seq["name"], "period": round(period, 4), "frames": frames}
    return [columns[i] for i in sorted(columns)]


if __name__ == "__main__":
    main()
