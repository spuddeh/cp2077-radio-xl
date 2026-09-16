"""Builds the RadioXL Example Station zip for the Nexus optional files.

The package is example-station/station.json and README.txt from this repo, plus three short
generated audio files so the station plays as installed: two 24-second tracks and a 4-second ident,
made with ffmpeg from tones and noise, so nothing in the zip is anyone's recording.

    python tools/make-example-station.py            -> example-station/build/RadioXL Example Station.zip

Needs ffmpeg on PATH. The build folder is gitignored.
"""
from __future__ import annotations

import pathlib
import shutil
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "example-station"
BUILD = SOURCE / "build"
STATION = "RadioXLExampleStation"
INSIDE = pathlib.Path("red4ext/plugins/RadioXL/stations") / STATION

# Each track is a few sine voices over a soft noise bed, faded in and out, so it reads as music
# rather than a test tone. Frequencies are a chord; the second track is a different chord.
TRACKS = {
    "track_01.mp3": ("24", ["220", "277.18", "329.63", "440"]),
    "track_02.mp3": ("24", ["196", "246.94", "293.66", "392"]),
    "ident.mp3": ("4", ["523.25", "659.25", "783.99"]),
}


def render(path: pathlib.Path, seconds: str, voices: list[str]) -> None:
    inputs: list[str] = []
    for f in voices:
        inputs += ["-f", "lavfi", "-t", seconds, "-i", f"sine=frequency={f}:sample_rate=44100"]
    inputs += ["-f", "lavfi", "-t", seconds, "-i", "anoisesrc=colour=pink:amplitude=0.02:sample_rate=44100"]
    n = len(voices) + 1
    mix = "".join(f"[{i}:a]" for i in range(n)) + f"amix=inputs={n}:normalize=0,volume=0.35," \
          f"afade=t=in:d=1.5,afade=t=out:st={float(seconds) - 2.0}:d=2[a]"
    cmd = ["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", mix, "-map", "[a]",
           "-codec:a", "libmp3lame", "-b:a", "96k", str(path)]
    subprocess.run(cmd, check=True)


def main() -> int:
    if shutil.which("ffmpeg") is None:
        print("ffmpeg is not on PATH", file=sys.stderr)
        return 1
    if BUILD.exists():
        shutil.rmtree(BUILD)
    station = BUILD / INSIDE
    (station / "audio").mkdir(parents=True)
    shutil.copy(SOURCE / "station.json", station / "station.json")
    shutil.copy(SOURCE / "README.txt", BUILD / "README.txt")
    for name, (seconds, voices) in TRACKS.items():
        render(station / "audio" / name, seconds, voices)
    out = BUILD / "RadioXL Example Station.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for file in sorted(BUILD.rglob("*")):
            if file.is_file() and file != out:
                z.write(file, file.relative_to(BUILD).as_posix())
    size = out.stat().st_size
    print(f"{out} ({size / 1024:.0f} KB)")
    with zipfile.ZipFile(out) as z:
        for info in z.infolist():
            print(f"  {info.file_size:>8}  {info.filename}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
