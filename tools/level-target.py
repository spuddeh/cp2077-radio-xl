r"""Derive the level target for a RadioXL track from the game's own radio tracks, offline.

A radio track's level at a receiver is its file's loudness, then the Wwise chain: the segment's own
volume if it has one, and the station's send trim. Every station playlist in radio.bnk mutes its dry
output at -96 dB and is heard only through its two CPR Voice Broadcast Sends, a stereo one for world
devices and vehicles and a mono one for the Radioport, each with a fixed trim per station. A custom
station on `radioxl_radio` cites one vanilla station's pair, so from the send onwards it takes the
same path as that station, and its file can be put on the same scale:

    level on a route = file loudness (LUFS) + segment volume (dB) + that route's send trim (dB)

usage:
  python level-target.py dump     [--game DIR] [--work DIR] [--wwiser PYZ]
  python level-target.py export   [--game DIR] [--work DIR] [--wwtools DLL]
  python level-target.py measure  [--work DIR] [--jobs N]
  python level-target.py report   [--work DIR] [--out DIR]
  python level-target.py all      (the four above, in order)
  python level-target.py check    <capture.json> [--out DIR] [--tolerance 1.0]
  python level-target.py align    <capture.wav> --route mono|stereo [--station DIR]... [--track NN=<audio>]... [--json OUT]
  python level-target.py file     <audio>... [--out DIR] [--margin 1.0]

dump     pulls radio.bnk, cp_music.bnk, init.bnk and eventsmetadata.json out of the game's archives,
         dumps the banks with wwiser, and writes work/stations.json: every station container with its
         bus and both send trims, every radio event walked back to its segment, track and .wem, and
         each segment's own volume.
export   pulls every one of those .wem files out of audio_2_soundbanks.archive and decodes it to Ogg
         Vorbis through wwtools.dll, the converter WolvenKit's own audio player uses, into work/ogg/.
measure  runs ffmpeg's ebur128 filter over every .ogg: integrated loudness, loudness range and true
         peak, into work/measure.json.
report   joins the two and writes the table and the target into --out: vanilla-levels.json (every
         track), vanilla-levels.md (the readable table) and target.json (what the builder reads).
check    compares the model against a capture made in game with measure-loudness.py: for every
         station in the capture, the level the model predicts on that route against the level
         measured. The prediction only has to hold to within about 1 LU RELATIVE to the other
         stations in the same capture; the absolute offset is the player's volume settings.
         measure-loudness.py report --json writes the capture in the shape this reads.
align    checks the model track by track, from the capture alone. It finds which track is playing
         when by matching a spectral fingerprint of every decoded vanilla track (and every file of
         each --station) against the recording, then measures the capture and the source over the
         SAME stretch of the song. The difference is the chain: segment volume plus the route's
         trim for a vanilla track, gain plus the routing trim plus the RadioXL path's own
         RADIOXL_PATH_DB for a RadioXL one (a residual there is a change in that term). Station medians
         are useless here (a station's own tracks spread 3 to 8 dB), and no probe log is needed.
         Needs numpy and scipy. --route is the receiver: mono is the Radioport, stereo a vehicle
         or world device. --track NN=<audio> adds a file another mod plays on vanilla station NN
         (Hardest to Be on Growl FM is 12=<762143559.ogg>). The recording's floor (its quietest
         second) is measured too: a passage the room would lift by more than 1 dB is reported but
         not counted.
file     measures any audio file the way the builder will and prints the gain that puts it on the
         target, bounded by the file's own peak: AudioXL scales 16-bit samples and a value past
         full scale wraps, so peak + gain stays under 0 dBFS by --margin.

Needs: Python 3.11+, ffmpeg on PATH, wwiser (https://github.com/bnnm/wwiser, the .pyz), and a
wwtools.dll (ships with WolvenKit); `align` also needs numpy and scipy. Nothing here writes into
the game directory.

A file's own loudness says nothing about its level in game until the chain is applied: a track that
measured within 1 dB of its neighbours in the file was 15 dB louder in game, and all 15 dB were in
the chain. Do not shortcut the send trim.
"""
from __future__ import annotations

import argparse
import ctypes
import json
import math
import os
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_GAME = Path(r"D:\Games\GOG Galaxy\Games\Cyberpunk 2077")
DEFAULT_WWISER = Path(r"D:\Modding\Tools\wwiser\wwiser.pyz")
DEFAULT_WORK = HERE / "level-target" / "work"
DEFAULT_OUT = HERE / "level-target"
WWTOOLS_CANDIDATES = [
    Path(r"D:\Modding\WolvenKit\wwtools.dll"),
    HERE.parent.parent.parent / "wolvenkit-mcp" / "bin" / "Release" / "net10.0" / "win-x64" / "wwtools.dll",
    Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "WolvenKit" / "wwtools.dll",
]

AUDIO_ARCHIVE = "archive/pc/content/audio_2_soundbanks.archive"
GAME_FILES = {
    "radio.bnk": r"base\sound\soundbanks\radio.bnk",
    "cp_music.bnk": r"base\sound\soundbanks\cp_music.bnk",
    "init.bnk": r"base\sound\soundbanks\init.bnk",
}
EVENTS_METADATA = r"base\sound\event\eventsmetadata.json"
MEDIA = r"base\sound\soundbanks\media\{}.wem"

# The CPR Voice Broadcast Send plugin ids, and the RTPC whose curve at x = 0 is the station's trim.
SEND_STEREO = 338339   # 0x000529A3 - world devices and vehicles
SEND_MONO = 207267     # 0x000329A3 - the Radioport
MUTE_RTPC = "1631578750"  # radio_broadcast_mute: 0 is unmuted, 1 is -96 dB

# The vanilla pair `radioxl_radio` cites: Radio Vexelstrom's, mid-dial on both sends. Read from
# tools/make_routing_bank.py; if that changes, this must change with it.
ROUTING_STATION = "02"

# The most a manifest may ask for: plugin/src/Manifest.hpp kMaxGain. Keep the two the same.
MAX_GAIN = 4.0

# What the RadioXL path adds on top of the send trim, in dB: a row at gain 1 on Vexelstrom's copied
# pair lands this much above where a vanilla track on the same trim lands. Measured with `align` on
# the Radioport, three Tool FM passages against four vanilla ones (+3.0, +1.6, +1.8; the method is
# good to about 1 LU per passage). The cause is on the sound side of the send and is not read out of
# the banks yet; the stereo route is not measured and is assumed the same. Re-measure after a
# change to the routing bank or to AudioXL's feed, and after a game patch.
RADIOXL_PATH_DB = 2.0

# Dial names by the number in the event name. Frequencies from the game's own station list.
DIAL = {
    "01": ("Morro Rock Radio", 107.3), "02": ("Radio Vexelstrom", 89.3), "03": ("Night FM", 92.9),
    "04": ("The Dirge", 101.9), "05": ("Body Heat Radio", 98.7), "06": ("Samizdat Radio", 95.2),
    "07": ("Radio PEBKAC", 103.5), "08": ("Royal Blue Radio", 91.9), "09": ("Pacific Dreams", 88.9),
    "10": ("30 Principales", 106.9), "11": ("Ritual FM", 96.1), "12": ("Growl FM", 89.7),
    "13": ("Dark Star", 107.5), "14": ("Impulse", 99.9),
}


def fnv1a64(text: str) -> int:
    h = 0xCBF29CE484222325
    for b in text.encode("utf-8"):
        h ^= b
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def curve_db(value: float) -> float:
    """wwiser writes a dB-scaled curve point as 10^(dB/20) - 1."""
    return 20.0 * math.log10(value + 1.0)


# ---------------------------------------------------------------------------------------------
# The game archive. Every entry in audio_2_soundbanks.archive is stored uncompressed, so no Oodle.


class Archive:
    MAGIC = 1380009042  # "RDAR"

    def __init__(self, path: Path):
        self.path = path
        self.file = open(path, "rb")
        magic, _version, index_pos, _index_size, _dpos, _dsize, _fsize = struct.unpack("<IIQIQIQ", self.file.read(40))
        if magic != self.MAGIC:
            raise SystemExit(f"{path} is not a REDengine archive")
        self.file.seek(index_pos)
        _off, _size, _crc, entries, segments, _deps = struct.unpack("<IIQIII", self.file.read(28))
        raw = self.file.read(entries * 56)
        self.entries: dict[int, tuple[int, int]] = {}
        for i in range(entries):
            name_hash, _ts, _inline, s0, s1, _d0, _d1 = struct.unpack_from("<QqIIIII", raw, i * 56)
            self.entries.setdefault(name_hash, (s0, s1))
        raw = self.file.read(segments * 16)
        self.segments = [struct.unpack_from("<QII", raw, i * 16) for i in range(segments)]

    def read(self, game_path: str) -> bytes:
        key = fnv1a64(game_path.lower())
        if key not in self.entries:
            raise KeyError(game_path)
        s0, s1 = self.entries[key]
        out = bytearray()
        for offset, zsize, size in self.segments[s0:s1]:
            if zsize != size:
                raise SystemExit(f"{game_path} is compressed in the archive; this reader only handles stored entries")
            self.file.seek(offset)
            out += self.file.read(size)
        return bytes(out)


# ---------------------------------------------------------------------------------------------
# wwtools: two C exports, the same call WolvenKit.Core/Wwise/Wem.cs makes.


def load_wwtools(explicit: str | None) -> ctypes.CDLL:
    candidates = [Path(explicit)] if explicit else WWTOOLS_CANDIDATES
    for c in candidates:
        if c.is_file():
            dll = ctypes.CDLL(str(c))
            dll.get_wem_to_ogg_size.restype = ctypes.c_uint64
            dll.get_wem_to_ogg_size.argtypes = [ctypes.c_char_p, ctypes.c_uint64]
            dll.wem_to_ogg.restype = None
            dll.wem_to_ogg.argtypes = [ctypes.c_char_p, ctypes.c_uint64, ctypes.c_char_p]
            return dll
    raise SystemExit("no wwtools.dll found; pass --wwtools <path> (it ships with WolvenKit)")


def wem_to_ogg(dll: ctypes.CDLL, wem: bytes) -> bytes:
    size = dll.get_wem_to_ogg_size(wem, len(wem))
    if size == 0:
        raise ValueError("wwtools could not size this wem")
    out = ctypes.create_string_buffer(size)
    dll.wem_to_ogg(wem, len(wem), out)
    return out.raw


# ---------------------------------------------------------------------------------------------
# The bank dump. wwiser's XML nests objects; the fields this needs are found by name under each
# HIRC object, never by offset.


def wwiser_dump(wwiser: Path, bank: Path) -> Path:
    xml = bank.with_suffix(bank.suffix + ".xml")
    if xml.is_file() and xml.stat().st_mtime >= bank.stat().st_mtime:
        return xml
    print(f"wwiser: dumping {bank.name}")
    subprocess.run([sys.executable, str(wwiser), "-d", "xml", bank.name], cwd=bank.parent, check=True,
                   stdout=subprocess.DEVNULL)
    if not xml.is_file():
        raise SystemExit(f"wwiser wrote no {xml.name}")
    return xml


def hirc_objects(xml_path: Path):
    """Yield (name, element) for every top-level HIRC object, without holding the whole tree."""
    depth = 0
    hirc_depth = None
    for event, el in ET.iterparse(xml_path, events=("start", "end")):
        if event == "start":
            depth += 1
            if el.tag == "list" and el.get("name") == "listLoadedItem":
                hirc_depth = depth
            continue
        if hirc_depth is not None and depth == hirc_depth + 1 and el.tag == "object":
            yield el.get("name"), el
            el.clear()
        elif el.tag == "list" and el.get("name") == "listLoadedItem":
            hirc_depth = None
        depth -= 1


def field(el, name, default=None):
    for f in el.iter("field"):
        if f.get("name") == name:
            return f.get("value")
    return default


def fields(el, name):
    return [f.get("value") for f in el.iter("field") if f.get("name") == name]


def own_props(el) -> dict[str, float]:
    """The object's own AkPropBundle<AkPropValue> - Volume, Pitch, Loop... - by label."""
    props = {}
    for bundle in el.iter("object"):
        if not bundle.get("name", "").startswith("AkPropBundle<AkPropValue"):
            continue
        for item in bundle.iter("object"):
            if item.get("name") != "AkPropBundle":
                continue
            pid = next((f.get("valuefmt") for f in item.iter("field") if f.get("name") == "pID"), None)
            val = field(item, "pValue")
            if pid and val is not None:
                label = pid.split("[", 1)[1].rstrip("]") if "[" in pid else pid
                props[label] = float(val)
        break  # the first bundle is the node's own; nested objects (RTPC curves) come later
    return props


def send_trim(fx_el) -> float | None:
    """The trim on a CPR Voice Broadcast Send: its radio_broadcast_mute curve at x = 0, in dB."""
    for rtpc in fx_el.iter("object"):
        if rtpc.get("name") != "RTPC" or field(rtpc, "RTPCID") != MUTE_RTPC:
            continue
        points = [p for p in rtpc.iter("object") if p.get("name") == "AkRTPCGraphPoint"]
        for p in points:
            if float(field(p, "From")) == 0.0:
                return round(curve_db(float(field(p, "To"))), 2)
    return None


def read_banks(xmls: list[Path]) -> dict:
    events, actions, segments, tracks, containers, sends, buses = {}, {}, {}, {}, {}, {}, {}
    for xml_path in xmls:
        bank = xml_path.name.split(".")[0]
        for name, el in hirc_objects(xml_path):
            uid = field(el, "ulID")
            if name == "CAkEvent":
                events[uid] = {"bank": bank, "actions": fields(el, "ulActionID")}
            elif name == "CAkActionPlay":
                actions[uid] = {"bank": bank, "target": field(el, "idExt"), "targetBank": field(el, "bankID")}
            elif name == "CAkMusicSegment":
                segments[uid] = {
                    "bank": bank, "parent": field(el, "DirectParentID"), "children": fields(el, "ulChildID"),
                    "props": own_props(el), "durationMs": float(field(el, "fDuration", 0.0)),
                    "overrideFx": field(el, "bIsOverrideParentFX"), "bus": field(el, "OverrideBusId"),
                }
            elif name == "CAkMusicTrack":
                srcs = [s for s in el.iter("object") if s.get("name") == "AkTrackSrcInfo"]
                tracks[uid] = {
                    "bank": bank, "parent": field(el, "DirectParentID"), "props": own_props(el),
                    "sources": [{
                        "sourceId": field(s, "sourceID"), "playAtMs": float(field(s, "fPlayAt", 0)),
                        "beginTrimMs": float(field(s, "fBeginTrimOffset", 0)), "endTrimMs": float(field(s, "fEndTrimOffset", 0)),
                        "srcDurationMs": float(field(s, "fSrcDuration", 0)),
                    } for s in srcs],
                    "streamType": field(el, "StreamType"),
                }
            elif name == "CAkMusicRanSeqCntr":
                containers[uid] = {
                    "bank": bank, "bus": field(el, "OverrideBusId"), "props": own_props(el),
                    "fx": [field(c, "fxID") for c in el.iter("object") if c.get("name") == "FXChunk"],
                    "children": fields(el, "ulChildID"),
                }
            elif name in ("CAkFxCustom", "CAkFxShareSet"):
                plugin = field(el, "fxID")
                if plugin in (str(SEND_STEREO), str(SEND_MONO)):
                    sends[uid] = {"bank": bank, "kind": name, "route": "stereo" if plugin == str(SEND_STEREO) else "mono",
                                  "trimDb": send_trim(el)}
            elif name == "CAkBus":
                buses[uid] = {
                    "bank": bank, "parent": field(el, "OverrideBusId"), "props": own_props(el),
                    "fx": [f.get("valuefmt") or f.get("value") for f in el.iter("field") if f.get("name") == "fxID"],
                    "hdr": field(el, "bIsHdrBus"),
                }
    return {"events": events, "actions": actions, "segments": segments, "tracks": tracks,
            "containers": containers, "sends": sends, "buses": buses}


def radio_events(events_json: Path) -> dict[str, dict]:
    """Name -> wwiseId for every mus_radio_* event, from the cooked event metadata."""
    data = json.loads(events_json.read_text(encoding="utf-8"))
    root = data["Data"]["RootChunk"]["root"]["Data"]
    out = {}
    for key, value in root.items():
        if not isinstance(value, list):
            continue
        for e in value:
            if isinstance(e, dict) and "redId" in e and str(e["redId"].get("$value", "")).startswith("mus_radio_"):
                out[e["redId"]["$value"]] = {"wwiseId": str(e["wwiseId"]), "maxDuration": e.get("maxDuration", 0)}
    return out


def cmd_dump(args) -> None:
    work = Path(args.work)
    banks = work / "banks"
    banks.mkdir(parents=True, exist_ok=True)
    archive = Archive(Path(args.game) / AUDIO_ARCHIVE)
    for name, game_path in GAME_FILES.items():
        target = banks / name
        if not target.is_file():
            target.write_bytes(archive.read(game_path))
            print(f"extracted {name}")
    # eventsmetadata.json is a CR2W resource; its wwiseId/redId pairs are needed as JSON. The
    # basegame archive is compressed, so this goes through WolvenKit rather than the reader above.
    events_json = banks / "eventsmetadata.wk.json"
    if not events_json.is_file():
        raise SystemExit(
            f"{events_json} is missing. Convert base\\sound\\event\\eventsmetadata.json to WolvenKit JSON\n"
            "(WolvenKit: open the file and Save As JSON; or the wolvenkit MCP's convert_to_json with\n"
            f"output_path) and save it there, then run dump again.")
    xmls = [wwiser_dump(Path(args.wwiser), banks / n) for n in ("radio.bnk", "cp_music.bnk", "init.bnk")]
    b = read_banks(xmls)
    names = radio_events(events_json)

    # Walk every radio event to its segment, tracks and sources.
    resolved, unresolved = [], []
    for name, meta in sorted(names.items()):
        ev = b["events"].get(meta["wwiseId"])
        if ev is None:
            unresolved.append((name, "no CAkEvent in the banks read"))
            continue
        targets = [b["actions"][a]["target"] for a in ev["actions"] if a in b["actions"]]
        segs = [t for t in targets if t in b["segments"]]
        if not segs:
            unresolved.append((name, f"play targets {targets} are not MusicSegments"))
            continue
        for seg_id in segs:
            seg = b["segments"][seg_id]
            container = b["containers"].get(seg["parent"])
            for track_id in seg["children"]:
                track = b["tracks"].get(track_id)
                if track is None:
                    unresolved.append((name, f"segment {seg_id} child {track_id} is not a MusicTrack"))
                    continue
                for src in track["sources"]:
                    resolved.append({
                        "event": name, "eventId": meta["wwiseId"], "segmentId": seg_id, "trackId": track_id,
                        "containerId": seg["parent"], "sourceId": src["sourceId"],
                        "segmentVolumeDb": seg["props"].get("Volume", 0.0),
                        "segmentOverridesFx": seg["overrideFx"], "segmentProps": seg["props"],
                        "trackProps": track["props"], "srcDurationMs": src["srcDurationMs"],
                        "beginTrimMs": src["beginTrimMs"], "endTrimMs": src["endTrimMs"],
                        "bank": seg["bank"], "containerFound": container is not None,
                    })

    stations = {}
    used = {r["containerId"] for r in resolved}
    for cid, c in b["containers"].items():
        if cid not in used:
            continue  # cp_music.bnk holds a thousand score containers; only the radio ones matter here
        trims = {"stereo": None, "mono": None}
        for fx in c["fx"]:
            s = b["sends"].get(fx)
            if s:
                trims[s["route"]] = s["trimDb"]
        evs = sorted({r["event"] for r in resolved if r["containerId"] == cid})
        # A container's station is the number most of its events carry: Radio PEBKAC's playlist
        # holds three events numbered 08 beside its own 07s.
        numbers = [m.group(1) for e in evs if (m := re.match(r"mus_radio_(\d\d)_", e))]
        stations[cid] = {
            "bank": c["bank"], "bus": c["bus"], "dryVolumeDb": c["props"].get("Volume"),
            "stereoTrimDb": trims["stereo"], "monoTrimDb": trims["mono"],
            "stationNumber": max(set(numbers), key=numbers.count) if numbers else None,
            "events": evs, "kind": ("blips" if evs and all("blip" in e for e in evs) else "music") if evs else "unused",
        }
    out = {
        "game": str(args.game), "stations": stations, "tracks": resolved,
        "unresolved": unresolved, "buses": b["buses"],
    }
    (work / "stations.json").write_text(json.dumps(out, indent=1), encoding="utf-8")
    print(f"{len(resolved)} track sources from {len(names)} radio events; {len(unresolved)} unresolved; "
          f"{len(stations)} containers -> {work / 'stations.json'}")
    for name, why in unresolved:
        print(f"  unresolved: {name}: {why}")


def cmd_export(args) -> None:
    work = Path(args.work)
    data = json.loads((work / "stations.json").read_text(encoding="utf-8"))
    ogg_dir = work / "ogg"
    ogg_dir.mkdir(parents=True, exist_ok=True)
    archive = Archive(Path(args.game) / AUDIO_ARCHIVE)
    dll = load_wwtools(args.wwtools)
    ids = sorted({t["sourceId"] for t in data["tracks"]})
    done = failed = 0
    for sid in ids:
        target = ogg_dir / f"{sid}.ogg"
        if target.is_file():
            done += 1
            continue
        try:
            wem = archive.read(MEDIA.format(sid))
            target.write_bytes(wem_to_ogg(dll, wem))
            done += 1
        except (KeyError, ValueError) as e:
            failed += 1
            print(f"  {sid}: {e}")
    print(f"{done} of {len(ids)} decoded to {ogg_dir}; {failed} failed")


EBUR = {
    "I": re.compile(r"^\s*I:\s+(-?[\d.]+) LUFS", re.M),
    "LRA": re.compile(r"^\s*LRA:\s+(-?[\d.]+) LU", re.M),
    "Peak": re.compile(r"^\s*Peak:\s+(-?[\d.]+) dBFS", re.M),
    "time": re.compile(r"time=(\d+):(\d+):([\d.]+)"),
}


def measure_one(path: Path, start: float | None = None, length: float | None = None) -> dict:
    excerpt = [] if start is None else ["-ss", f"{start:.3f}", "-t", f"{length:.3f}"]
    cmd = ["ffmpeg", "-nostats", "-hide_banner", *excerpt, "-i", str(path), "-filter_complex",
           "ebur128=peak=true:framelog=quiet", "-f", "null", "-"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    text = r.stderr
    out = {"file": path.name}
    for key in ("I", "LRA", "Peak"):
        m = EBUR[key].search(text)
        out[key] = float(m.group(1)) if m else None
    return out


def cmd_measure(args) -> None:
    work = Path(args.work)
    oggs = sorted((work / "ogg").glob("*.ogg"))
    if not oggs:
        raise SystemExit("nothing in work/ogg - run export first")
    results = {}
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for r in pool.map(measure_one, oggs):
            results[r["file"].split(".")[0]] = {"lufs": r["I"], "lra": r["LRA"], "truePeakDb": r["Peak"]}
    (work / "measure.json").write_text(json.dumps(results, indent=1), encoding="utf-8")
    missing = [k for k, v in results.items() if v["lufs"] is None]
    print(f"{len(results)} measured -> {work / 'measure.json'}; {len(missing)} without a reading {missing[:5]}")


def median(xs: list[float]) -> float:
    s = sorted(xs)
    n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2


def cmd_report(args) -> None:
    work, out_dir = Path(args.work), Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    data = json.loads((work / "stations.json").read_text(encoding="utf-8"))
    measure = json.loads((work / "measure.json").read_text(encoding="utf-8"))
    stations = data["stations"]
    rows = []
    for t in data["tracks"]:
        st = stations.get(t["containerId"])
        m = measure.get(t["sourceId"])
        if st is None or m is None or m["lufs"] is None:
            continue
        if m["truePeakDb"] is None or m["lufs"] <= -60.0:
            # A silent placeholder (ffmpeg reports -70 LUFS and a peak of -inf) has no level.
            data.setdefault("unresolved", []).append((t["event"], f"source {t['sourceId']} is silent"))
            continue
        if t["segmentVolumeDb"] <= -60.0:
            # A segment muted at -96 dB is a track switched off, not a quiet one.
            data.setdefault("unresolved", []).append((t["event"], f"segment {t['segmentId']} is muted at {t['segmentVolumeDb']} dB"))
            continue
        stereo, mono = st["stereoTrimDb"], st["monoTrimDb"]
        if stereo is None or mono is None:
            continue
        number = st["stationNumber"] or "--"
        name = DIAL.get(number, ("(no dial position)", None))[0]
        rows.append({
            "station": number, "stationName": name, "kind": st["kind"], "event": t["event"],
            "sourceId": t["sourceId"], "lufs": m["lufs"], "lra": m["lra"], "truePeakDb": m["truePeakDb"],
            "segmentVolumeDb": t["segmentVolumeDb"], "stereoTrimDb": stereo, "monoTrimDb": mono,
            "stereoLevel": round(m["lufs"] + t["segmentVolumeDb"] + stereo, 1),
            "monoLevel": round(m["lufs"] + t["segmentVolumeDb"] + mono, 1),
            "stereoPeak": round(m["truePeakDb"] + t["segmentVolumeDb"] + stereo, 1),
            "monoPeak": round(m["truePeakDb"] + t["segmentVolumeDb"] + mono, 1),
        })
    rows.sort(key=lambda r: (r["station"], r["kind"], r["event"]))

    music = [r for r in rows if r["kind"] == "music" and r["station"] != "--"]
    routing = next((s for s in stations.values() if s["stationNumber"] == ROUTING_STATION and s["kind"] == "music"), None)
    if routing is None:
        raise SystemExit(f"no music container for station {ROUTING_STATION}")

    def stats(xs):
        return {"min": round(min(xs), 1), "median": round(median(xs), 1), "max": round(max(xs), 1), "count": len(xs)}

    per_station = {}
    for number in sorted({r["station"] for r in music}):
        xs = [r for r in music if r["station"] == number]
        per_station[number] = {
            "name": DIAL[number][0], "frequency": DIAL[number][1], "tracks": len(xs),
            "fileLufs": stats([r["lufs"] for r in xs]),
            "stereoLevel": stats([r["stereoLevel"] for r in xs]), "monoLevel": stats([r["monoLevel"] for r in xs]),
            "stereoTrimDb": xs[0]["stereoTrimDb"], "monoTrimDb": xs[0]["monoTrimDb"],
        }
    game = {
        "fileLufs": stats([r["lufs"] for r in music]), "lra": stats([r["lra"] for r in music]),
        "truePeakDb": stats([r["truePeakDb"] for r in music]),
        "stereoLevel": stats([r["stereoLevel"] for r in music]), "monoLevel": stats([r["monoLevel"] for r in music]),
        "stereoPeak": stats([r["stereoPeak"] for r in music]), "monoPeak": stats([r["monoPeak"] for r in music]),
    }
    # The target: a custom track on radioxl_radio takes the routing station's trims, so the file
    # level that lands it on the game's median is the median chain level minus that trim, per route.
    # The RadioXL path then adds RADIOXL_PATH_DB on top of the trim, so the file aims that much lower.
    stereo_target = round(game["stereoLevel"]["median"] - routing["stereoTrimDb"] - RADIOXL_PATH_DB, 1)
    mono_target = round(game["monoLevel"]["median"] - routing["monoTrimDb"] - RADIOXL_PATH_DB, 1)
    target = {
        "fileLufsTarget": round((stereo_target + mono_target) / 2, 1),
        "fileLufsTargetByRoute": {"stereo": stereo_target, "mono": mono_target},
        "radioxlPathDb": RADIOXL_PATH_DB,
        "chainLevelMedian": {"stereo": game["stereoLevel"]["median"], "mono": game["monoLevel"]["median"]},
        "chainLevelBand": {"stereo": [game["stereoLevel"]["min"], game["stereoLevel"]["max"]],
                           "mono": [game["monoLevel"]["min"], game["monoLevel"]["max"]]},
        "routingStation": {"number": ROUTING_STATION, "name": DIAL[ROUTING_STATION][0],
                           "stereoTrimDb": routing["stereoTrimDb"], "monoTrimDb": routing["monoTrimDb"]},
        # Headroom before the send output reaches 0 dBFS: a custom file's true peak plus its gain
        # in dB must stay below this on the tighter route, the stereo one.
        "peakHeadroomDb": {"stereo": round(-routing["stereoTrimDb"], 1), "mono": round(-routing["monoTrimDb"], 1)},
        "maxGain": MAX_GAIN,
        "vanilla": {"music": game, "stations": per_station, "tracks": len(music)},
    }
    (out_dir / "vanilla-levels.json").write_text(json.dumps({"tracks": rows, "target": target}, indent=1), encoding="utf-8")
    (out_dir / "target.json").write_text(json.dumps(target, indent=1), encoding="utf-8")
    write_markdown(out_dir / "vanilla-levels.md", rows, per_station, game, target, data)
    print(f"{len(rows)} rows; music tracks {len(music)}")
    print(f"file LUFS      {game['fileLufs']}")
    print(f"stereo level   {game['stereoLevel']}")
    print(f"mono level     {game['monoLevel']}")
    print(f"target file LUFS on radioxl_radio: {target['fileLufsTarget']} (stereo {stereo_target}, mono {mono_target})")
    print(f"-> {out_dir}")


def write_markdown(path: Path, rows, per_station, game, target, data) -> None:
    L = []
    L.append("# Vanilla radio track levels\n")
    L.append("Generated by `tools/level-target.py report`. Every station's tracks measured from the game's own files "
             "(EBU R128 through ffmpeg), then put on the chain: file loudness + the segment's own volume + the station's send trim. "
             "`stereo` is the world-device and vehicle route, `mono` the Radioport.\n")
    L.append("## The target\n")
    L.append(f"A custom track on `radioxl_radio` rides {target['routingStation']['name']}'s sends "
             f"({target['routingStation']['stereoTrimDb']:+.1f} dB stereo, {target['routingStation']['monoTrimDb']:+.1f} dB mono). "
             f"The RadioXL path adds {RADIOXL_PATH_DB:+.1f} dB on top of that trim (measured on the Radioport). "
             f"To land on the game's median it should measure **{target['fileLufsTarget']} LUFS** in the file "
             f"(stereo route {target['fileLufsTargetByRoute']['stereo']}, mono route {target['fileLufsTargetByRoute']['mono']}). "
             f"Its true peak plus its gain in dB must stay below {target['peakHeadroomDb']['stereo']:+.1f} dB on the stereo route.\n")
    L.append("## Across the game (music containers only)\n")
    L.append("| | min | median | max |\n| --- | --- | --- | --- |")
    for key, label in (("fileLufs", "file LUFS"), ("lra", "loudness range LU"), ("truePeakDb", "file true peak dBTP"),
                       ("stereoLevel", "stereo route level"), ("monoLevel", "mono route level"),
                       ("stereoPeak", "stereo route peak"), ("monoPeak", "mono route peak")):
        s = game[key]
        L.append(f"| {label} | {s['min']} | {s['median']} | {s['max']} |")
    L.append("\n## Per station\n")
    L.append("| # | station | tracks | file LUFS min / median / max | stereo trim | stereo level median | mono trim | mono level median |")
    L.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for number, s in sorted(per_station.items(), key=lambda kv: -kv[1]["stereoLevel"]["median"]):
        f = s["fileLufs"]
        L.append(f"| {number} | {s['name']} {s['frequency']} | {s['tracks']} | {f['min']} / {f['median']} / {f['max']} | "
                 f"{s['stereoTrimDb']:+.1f} | {s['stereoLevel']['median']} | {s['monoTrimDb']:+.1f} | {s['monoLevel']['median']} |")
    L.append("\n## Every track\n")
    L.append("| # | kind | event | source | file LUFS | LRA | true peak | segment vol | stereo level | mono level |")
    L.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for r in rows:
        L.append(f"| {r['station']} | {r['kind']} | {r['event']} | {r['sourceId']} | {r['lufs']} | {r['lra']} | {r['truePeakDb']} | "
                 f"{r['segmentVolumeDb']:+.1f} | {r['stereoLevel']} | {r['monoLevel']} |")
    if data.get("unresolved"):
        L.append("\n## Not resolved\n")
        for name, why in data["unresolved"]:
            L.append(f"- `{name}`: {why}")
    path.write_text("\n".join(L) + "\n", encoding="utf-8")


def cmd_check(args) -> None:
    """A capture report from measure-loudness.py is a table of station -> LUFS on one route. The
    model's prediction for each vanilla station is its median chain level on that route; for a
    RadioXL station, its file loudness plus the routing trims. Only the differences between stations
    can be compared, because the absolute level is the player's volume settings."""
    out_dir = Path(args.out)
    target = json.loads((out_dir / "target.json").read_text(encoding="utf-8"))
    capture = json.loads(Path(args.capture).read_text(encoding="utf-8"))
    route = capture.get("route", "mono")
    key = "stereoLevel" if route == "stereo" else "monoLevel"
    trim = target["routingStation"]["stereoTrimDb" if route == "stereo" else "monoTrimDb"]
    by_number = target["vanilla"]["stations"]
    by_name = {s["name"].lower(): s for s in by_number.values()}
    rows = []
    for entry in capture["stations"]:
        name = entry["station"]
        measured = float(entry["lufs"])
        if "fileLufs" in entry:
            predicted = float(entry["fileLufs"]) + 20 * math.log10(float(entry.get("gain", 1.0))) + trim + target.get("radioxlPathDb", 0.0)
        else:
            # A vanilla station by its CName (radio_station_12_growl) or by its dial name.
            m = re.match(r"radio_station_(\d\d)_", name)
            s = by_number.get(m.group(1)) if m else by_name.get(name.lower())
            if s is None:
                print(f"  {name}: not a vanilla station and no fileLufs given - skipped")
                continue
            predicted = s[key]["median"]
        rows.append((name, measured, predicted))
    if len(rows) < 2:
        raise SystemExit("need at least two stations to compare")
    offset = median([m - p for _, m, p in rows])
    print(f"route {route}; player offset (measured - predicted, median) {offset:+.1f} dB")
    print(f"{'station':28} {'measured':>9} {'predicted':>10} {'residual':>9}")
    worst = 0.0
    for name, m, p in rows:
        residual = m - (p + offset)
        worst = max(worst, abs(residual))
        print(f"{name:28} {m:9.1f} {p + offset:10.1f} {residual:+9.1f}")
    print(f"worst residual {worst:.1f} LU - {'within' if worst <= args.tolerance else 'OUTSIDE'} {args.tolerance} LU")


# ---------------------------------------------------------------------------------------------
# align: which track plays when in a capture, by fingerprint, and the chain measured per passage.

ALIGN_SR = 8000          # the fingerprint works on a mono downmix at this rate
ALIGN_FRAME = 512        # 64 ms analysis frames ...
ALIGN_HOP = 200          # ... every 25 ms
ALIGN_BANDS = 32         # log-spaced bands, 80 Hz to 3.8 kHz: what survives a car or a world device
ALIGN_CHUNK_S = 20.0     # a source is matched in 20 s pieces, every 10 s, so a partial play still lands
ALIGN_CHUNK_HOP_S = 10.0
ALIGN_MIN_SCORE = 0.35   # normalised correlation; a wrong track sits under 0.3, a right one above 0.4
ALIGN_ROOM_DB = 1.0      # a passage the room lifts by more than this is not counted


def decode_pcm(path: Path, sr: int = ALIGN_SR):
    import numpy as np
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(sr), "-"],
                       capture_output=True, check=True)
    return np.frombuffer(r.stdout, dtype=np.float32)


def fingerprint(pcm):
    """Log band energies every 25 ms with a 2 s moving mean removed per band: the shape of the
    music, not its level or the receiver's colour. Bands x frames."""
    import numpy as np
    n = (len(pcm) - ALIGN_FRAME) // ALIGN_HOP + 1
    if n < 1:
        return np.zeros((ALIGN_BANDS, 0))
    idx = np.arange(ALIGN_FRAME)[None, :] + ALIGN_HOP * np.arange(n)[:, None]
    spec = np.abs(np.fft.rfft(pcm[idx] * np.hanning(ALIGN_FRAME).astype(np.float32), axis=1)) ** 2
    bins = np.fft.rfftfreq(ALIGN_FRAME, 1 / ALIGN_SR)
    edges = np.geomspace(80, 3800, ALIGN_BANDS + 1)
    bands = []
    for lo, hi in zip(edges[:-1], edges[1:]):
        a = int(np.searchsorted(bins, lo))
        b = max(a + 1, int(np.searchsorted(bins, hi)))
        bands.append(spec[:, a:b].mean(axis=1))
    db = 10 * np.log10(np.stack(bands) + 1e-10)
    k = int(2 * ALIGN_SR / ALIGN_HOP)
    if db.shape[1] < k:
        return db - db.mean(axis=1, keepdims=True)
    # A moving mean whose window shrinks at the edges; zero padding there turns silence into a ramp.
    kern = np.ones(k)
    count = np.convolve(np.ones(db.shape[1]), kern, mode="same")
    mean = np.apply_along_axis(lambda r: np.convolve(r, kern, mode="same") / count, 1, db)
    return (db - mean).astype(np.float64)


def find_passages(cap_fp, src_fp, label: str) -> list[dict]:
    """Every stretch of the source that appears in the capture: 20 s chunks of the source are
    correlated against the whole capture, and chunks that land at one lag are one passage."""
    import numpy as np
    from scipy.signal import fftconvolve
    fps = ALIGN_SR / ALIGN_HOP
    L, hop = int(ALIGN_CHUNK_S * fps), int(ALIGN_CHUNK_HOP_S * fps)
    if cap_fp.shape[1] < L or src_fp.shape[1] < L:
        return []
    ce = np.concatenate([[0.0], np.cumsum((cap_fp ** 2).sum(axis=0))])
    energy = np.sqrt(np.maximum(ce[L:] - ce[:-L], 1e-9))
    # Silence and near-silence in the capture correlate with anything; keep them out of the argmax.
    quiet = energy < 0.2 * np.median(energy)
    passages: list[dict] = []
    for s0 in range(0, src_fp.shape[1] - L + 1, hop):
        t = src_fp[:, s0:s0 + L]
        t = t - t.mean()
        tn = float(np.linalg.norm(t))
        if tn < 1e-6:
            continue
        score = fftconvolve(cap_fp, t[::-1, ::-1], mode="valid")[0] / (tn * energy)
        score[quiet] = 0.0
        i = int(np.argmax(score))
        sc = float(score[i])
        if sc < ALIGN_MIN_SCORE:
            continue
        src_t, cap_t = s0 / fps, i / fps
        lag = cap_t - src_t
        for p in passages:
            if abs(p["lag"] - lag) < 0.15:
                p["srcStart"] = min(p["srcStart"], src_t); p["srcEnd"] = max(p["srcEnd"], src_t + ALIGN_CHUNK_S)
                p["capStart"] = min(p["capStart"], cap_t); p["capEnd"] = max(p["capEnd"], cap_t + ALIGN_CHUNK_S)
                p["scores"].append(sc)
                break
        else:
            passages.append({"source": label, "lag": lag, "srcStart": src_t, "srcEnd": src_t + ALIGN_CHUNK_S,
                             "capStart": cap_t, "capEnd": cap_t + ALIGN_CHUNK_S, "scores": [sc]})
    # Two chunks at a middling score is what a wrong track with a similar beat produces.
    return [p for p in passages if len(p["scores"]) >= 3 or max(p["scores"]) >= 0.55]


def capture_floor_db(pcm) -> float:
    """The 5th percentile of 1 s block levels: the room between and under the music."""
    import numpy as np
    n = len(pcm) // ALIGN_SR
    if n < 2:
        return float("-inf")
    blocks = pcm[:n * ALIGN_SR].reshape(n, ALIGN_SR)
    rms = np.sqrt((blocks ** 2).mean(axis=1) + 1e-12)
    return float(np.percentile(20 * np.log10(rms), 5))


def passage_rank(p: dict) -> float:
    return p["score"] * min(1.0, len(p["scores"]) / 4)  # a long match outranks a short one


def cmd_align(args) -> None:
    try:
        import numpy as np
        import scipy  # noqa: F401
    except ImportError:
        raise SystemExit("align needs numpy and scipy: pip install numpy scipy")
    work, out_dir = Path(args.work), Path(args.out)
    levels = json.loads((out_dir / "vanilla-levels.json").read_text(encoding="utf-8"))
    target = json.loads((out_dir / "target.json").read_text(encoding="utf-8"))
    route = args.route
    trim_key = "stereoTrimDb" if route == "stereo" else "monoTrimDb"
    routing_trim = float(target["routingStation"][trim_key]) + float(target.get("radioxlPathDb", 0.0))

    # Sources: every decoded vanilla track, with what the chain adds to it on this route.
    sources: dict[str, dict] = {}
    for t in levels["tracks"]:
        ogg = work / "ogg" / f"{t['sourceId']}.ogg"
        if not ogg.is_file():
            continue
        label = f"{t['station']}/{t['event']}"
        sources[label] = {"path": ogg, "station": t["stationName"], "vanilla": True,
                          "predicted": float(t["segmentVolumeDb"]) + float(t[trim_key])}
    # ... and every file of each RadioXL station: manifest gain times the track's own, on the routing trim.
    for station_dir in args.station or []:
        sdir = Path(station_dir)
        manifest = json.loads((sdir / "station.json").read_text(encoding="utf-8"))
        name = manifest.get("displayName") or manifest.get("name") or sdir.name
        station_gain = float(manifest.get("gain", 1.0))
        for tr in manifest.get("tracks", []):
            if "file" not in tr:
                continue  # a stream has no file to match
            gain = station_gain * float(tr.get("gain", 1.0))
            label = f"{name}/{tr.get('title') or Path(tr['file']).stem}"
            sources[label] = {"path": sdir / tr["file"], "station": name, "vanilla": False,
                              "predicted": 20 * math.log10(gain) + routing_trim if gain > 0 else float("-inf")}

    # ... and a file another mod adds to a vanilla station: that station's trim, no segment volume.
    by_number = {t["station"]: t for t in levels["tracks"]}
    for spec in args.track or []:
        number, _, file = spec.partition("=")
        if number not in by_number or not file:
            raise SystemExit(f"--track wants NN=<audio> with NN a dial station number, not {spec!r}")
        t = by_number[number]
        label = f"{number}/{Path(file).stem}"
        sources[label] = {"path": Path(file), "station": t["stationName"], "vanilla": False, "vanillaStation": True,
                          "predicted": float(t[trim_key])}

    # Fingerprints. The vanilla set is cached in the work folder; a station's files are done each run.
    cache_path = work / "fingerprints.npz"
    cache = dict(np.load(cache_path)) if cache_path.is_file() else {}
    fresh = False
    prints: dict[str, object] = {}
    for label, src in sources.items():
        key = src["path"].stem if src["vanilla"] else None
        if key and key in cache:
            prints[label] = cache[key]
            continue
        try:
            fp = fingerprint(decode_pcm(src["path"]))
        except subprocess.CalledProcessError:
            print(f"  {label}: could not decode {src['path']}")
            continue
        prints[label] = fp
        if key:
            cache[key] = fp
            fresh = True
    if fresh:
        np.savez(cache_path, **cache)
        print(f"fingerprints cached -> {cache_path}")

    capture = Path(args.capture)
    pcm = decode_pcm(capture)
    cap_fp = fingerprint(pcm)
    floor = capture_floor_db(pcm)
    print(f"{capture.name}: {len(pcm) / ALIGN_SR:.0f} s, route {route}, floor about {floor:.1f} dBFS; "
          f"matching {len(prints)} tracks")

    found: list[dict] = []
    for label, fp in prints.items():
        for p in find_passages(cap_fp, fp, label):
            p["score"] = float(sum(p["scores"]) / len(p["scores"]))
            p["path"] = str(sources[label]["path"])
            p["station"] = sources[label]["station"]
            p["predicted"] = sources[label]["predicted"]
            p["vanilla"] = sources[label]["vanilla"] or sources[label].get("vanillaStation", False)
            found.append(p)

    # One thing plays at a time: keep the best-ranked passage in any stretch. Two sources holding the
    # same recording (a RadioXL station carrying a vanilla song) land at the same lag with the same
    # score; that passage is ambiguous and is attributed by its neighbours, or left out.
    kept: list[dict] = []
    for p in sorted(found, key=lambda q: -passage_rank(q)):
        clash = None
        for k in kept:
            overlap = min(p["capEnd"], k["capEnd"]) - max(p["capStart"], k["capStart"])
            if overlap > 0.25 * min(p["capEnd"] - p["capStart"], k["capEnd"] - k["capStart"]):
                clash = k
                break
        if clash is None:
            p["alsoMatches"] = []
            kept.append(p)
        elif abs(clash["lag"] - p["lag"]) < 0.3 and abs(clash["score"] - p["score"]) < 0.05 and clash["station"] != p["station"]:
            clash["alsoMatches"].append(p)
    kept.sort(key=lambda q: q["capStart"])
    for i, p in enumerate(kept):
        if not p["alsoMatches"]:
            continue
        candidates = {p["station"]: p, **{q["station"]: q for q in p["alsoMatches"]}}
        neighbours = [kept[j] for j in (i - 1, i + 1) if 0 <= j < len(kept) and not kept[j]["alsoMatches"]
                      and min(abs(kept[j]["capStart"] - p["capEnd"]), abs(p["capStart"] - kept[j]["capEnd"])) < 20]
        pick = next((candidates[n["station"]] for n in neighbours if n["station"] in candidates), None)
        if pick is not None and pick is not p:
            for k in ("source", "path", "station", "predicted", "vanilla"):
                p[k] = pick[k]
            p["attributedBy"] = "neighbour"
        elif pick is None:
            p["ambiguous"] = " or ".join(candidates)
    for p in kept:
        p["alsoMatches"] = [q["source"] for q in p["alsoMatches"]]
    # A passage ends where the next one starts: the last chunk extends past the change of track.
    for a, b in zip(kept, kept[1:]):
        if a["capEnd"] > b["capStart"]:
            a["srcEnd"] -= a["capEnd"] - b["capStart"]
            a["capEnd"] = b["capStart"]

    if not kept:
        raise SystemExit("no track from the decoded set or the given stations was found in this capture")

    # Measure capture and source over the same stretch of the song.
    rows = []
    for p in kept:
        dur = p["capEnd"] - p["capStart"]
        cap = measure_one(capture, p["capStart"], dur)
        src = measure_one(Path(p["path"]), p["srcStart"], dur)
        if cap["I"] is None or src["I"] is None or cap["I"] < -60:
            continue  # nothing was playing there
        p.update({"seconds": round(dur, 1), "captureLufs": cap["I"], "capturePeakDb": cap["Peak"],
                  "sourceLufs": src["I"], "measured": round(cap["I"] - src["I"], 1)})
        # What the room adds to the reading if it sits under the music at the floor level.
        p["roomDb"] = round(10 * math.log10(1 + 10 ** ((floor - cap["I"]) / 10)), 1)
        p["counted"] = p["roomDb"] <= ALIGN_ROOM_DB and "ambiguous" not in p and p["predicted"] > float("-inf")
        rows.append(p)

    # The player's volume is read off the vanilla passages, so a RadioXL residual is the RadioXL path.
    counted = [p for p in rows if p["counted"]]
    anchor = [p for p in counted if p["vanilla"]] or counted
    offset = median([p["measured"] - p["predicted"] for p in anchor]) if anchor else 0.0
    print(f"player offset (measured - predicted, median over {len(anchor)} "
          f"{'vanilla ' if anchor and anchor[0]['vanilla'] else ''}passage(s)) {offset:+.1f} dB" + chr(10))
    print(f"{'capture s':>15}  {'track':44} {'score':>5} {'capture':>8} {'source':>7} {'chain':>6} {'model':>6} {'resid':>6} {'room':>5}")
    worst = 0.0
    for p in rows:
        resid = p["measured"] - (p["predicted"] + offset)
        note = ""
        if "ambiguous" in p:
            note = f"  ambiguous: {p['ambiguous']}"
        elif p["roomDb"] > ALIGN_ROOM_DB:
            note = f"  the room adds up to {p['roomDb']:.1f} dB, not counted"
        elif p.get("attributedBy"):
            note = "  same recording on two stations; taken from its neighbour"
        if p["counted"]:
            worst = max(worst, abs(resid))
        p["residual"] = round(resid, 1)
        print(f"{p['capStart']:7.1f}..{p['capEnd']:6.1f}  {p['source'][:44]:44} {p['score']:5.2f} {p['captureLufs']:8.1f} "
              f"{p['sourceLufs']:7.1f} {p['measured']:+6.1f} {p['predicted'] + offset:+6.1f} {resid:+6.1f} {p['roomDb']:5.1f}{note}")
    if counted:
        stations = sorted({p["station"] for p in counted})
        print(chr(10) + f"worst residual {worst:.1f} LU over {len(counted)} passage(s) on {len(stations)} station(s) - "
              f"{'within' if worst <= args.tolerance else 'OUTSIDE'} {args.tolerance} LU"
              + ("" if len(stations) > 1 else "; one station only, so the trims are untested"))
    if args.json:
        payload = {"capture": capture.name, "route": route, "floorDb": round(floor, 1), "offsetDb": round(offset, 1),
                   "passages": [{k: v for k, v in p.items() if k not in ("scores", "lag")} for p in rows]}
        Path(args.json).write_text(json.dumps(payload, indent=1), encoding="utf-8")
        print(f"wrote {args.json}")


def cmd_file(args) -> None:
    """Measure any audio file the way the builder will, and say what gain puts it on the target.
    The gain is bounded by the file's own peak: AudioXL scales 16-bit samples and a value past
    full scale wraps, so peak + gain must stay under 0 dBFS with a margin."""
    target = json.loads((Path(args.out) / "target.json").read_text(encoding="utf-8"))
    want = target["fileLufsTarget"]
    print(f"target {want} LUFS in the file; peak must stay under {-args.margin:.1f} dBFS after the gain")
    print(f"{'file':50} {'LUFS':>6} {'LRA':>5} {'peak':>6} {'to target':>10} {'gain':>6} {'lands at':>9}")
    for f in args.files:
        m = measure_one(Path(f))
        if m["I"] is None or m["Peak"] is None:
            print(f"{Path(f).name[:50]:50} could not be measured")
            continue
        wanted_db = want - m["I"]
        # Only a RAISE is bounded by the peak: at 1 the samples play as decoded, and a cut cannot
        # wrap. A file whose peak already sits at the margin cannot be raised at all.
        allowed_db = -args.margin - m["Peak"]
        db = max(0.0, min(wanted_db, allowed_db)) if wanted_db > 0 else wanted_db
        gain = round(min(target.get("maxGain", MAX_GAIN), max(0.0, 10 ** (db / 20))), 2)
        lands = m["I"] + 20 * math.log10(gain) if gain > 0 else float("-inf")
        limited = " (peak-limited)" if 0 < wanted_db and allowed_db < wanted_db else ""
        print(f"{Path(f).name[:50]:50} {m['I']:6.1f} {m['LRA']:5.1f} {m['Peak']:6.1f} {wanted_db:+10.1f} {gain:6.2f} {lands:9.1f}{limited}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(sp, game=False, work=True, out=False):
        if game:
            sp.add_argument("--game", default=str(DEFAULT_GAME), help="the game's install directory")
        if work:
            sp.add_argument("--work", default=str(DEFAULT_WORK), help="scratch: banks, dumps, decoded audio")
        if out:
            sp.add_argument("--out", default=str(DEFAULT_OUT), help="where the table and target are written")

    s = sub.add_parser("dump"); common(s, game=True); s.add_argument("--wwiser", default=str(DEFAULT_WWISER))
    s = sub.add_parser("export"); common(s, game=True); s.add_argument("--wwtools", default=None)
    s = sub.add_parser("measure"); common(s); s.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    s = sub.add_parser("report"); common(s, out=True)
    s = sub.add_parser("all"); common(s, game=True, out=True)
    s.add_argument("--wwiser", default=str(DEFAULT_WWISER)); s.add_argument("--wwtools", default=None)
    s.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    s = sub.add_parser("check"); common(s, work=False, out=True)
    s.add_argument("capture", help="JSON: {route: mono|stereo, stations: [{station, lufs[, fileLufs, gain]}]}")
    s.add_argument("--tolerance", type=float, default=1.0)
    s = sub.add_parser("align"); common(s, out=True)
    s.add_argument("capture", help="a loopback recording (WAV) of the game")
    s.add_argument("--route", required=True, choices=["mono", "stereo"], help="mono = Radioport, stereo = vehicle or world device")
    s.add_argument("--station", action="append", help="a RadioXL station folder (holds station.json); repeatable")
    s.add_argument("--track", action="append", help="NN=<audio>: a file another mod plays on vanilla station NN; repeatable")
    s.add_argument("--tolerance", type=float, default=1.0)
    s.add_argument("--json", default=None, help="write every passage and its numbers here")
    s = sub.add_parser("file"); common(s, work=False, out=True)
    s.add_argument("files", nargs="+", help="audio files to measure against the target")
    s.add_argument("--margin", type=float, default=1.0, help="dB the peak stays under full scale after the gain")

    args = p.parse_args()
    if args.cmd == "all":
        cmd_dump(args); cmd_export(args); cmd_measure(args); cmd_report(args)
    else:
        {"dump": cmd_dump, "export": cmd_export, "measure": cmd_measure, "report": cmd_report,
         "check": cmd_check, "align": cmd_align, "file": cmd_file}[args.cmd](args)


if __name__ == "__main__":
    main()
