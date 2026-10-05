"""Test stations for the broadcast channel ceiling (#69), and the analysis of a recording of them.

usage:
  python tools/channel-test.py make <MO2 mod folder> [--count 16]
  python tools/channel-test.py report <recording.wav> [--window 2]

make     writes <count> stations, Chan Test A, B, ... under <folder>/red4ext/plugins/RadioXL/stations/.
         Each plays one 60-second 48 kHz 16-bit WAV: a sine on the left channel and a different sine
         on the right, so every station's two channels can be told apart from every other station's.
         Left of station i is 250 + 50 i Hz (300 to 1050), right is 1600 + 100 i Hz (1700 to 3200).
report   reads a recording made with measure-loudness.py record, takes an FFT of each channel per
         window, and prints each run of windows with the test tones present on each side. A station
         that bleeds into another's channel shows as a second tone on that side.

A station's left channel number is its internal id + 220, so from internal id 36 (the 15th custom
station) it passes 255, the last point of every send's channel curve. The roster order is in the
RadioXL log ("slot N (enum N, internal id N): name"). A shared channel is heard only while BOTH
stations play, so the test needs two of them active at once: one on the Radioport, one on a world
radio out of earshot.
"""
from __future__ import annotations

import json
import math
import pathlib
import string
import subprocess
import sys
import wave

RATE = 48000
SECONDS = 60


def left_hz(i: int) -> int:
    return 250 + 50 * i


def right_hz(i: int) -> int:
    return 1600 + 100 * i


def make(folder: pathlib.Path, count: int) -> None:
    root = folder / "red4ext" / "plugins" / "RadioXL" / "stations"
    for i in range(1, count + 1):
        letter = string.ascii_uppercase[i - 1]
        station = root / f"ChanTest{letter}"
        audio = station / "audio"
        audio.mkdir(parents=True, exist_ok=True)
        out = audio / "tone.wav"
        subprocess.run([
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "lavfi", "-t", str(SECONDS), "-i", f"sine=frequency={left_hz(i)}:sample_rate={RATE}",
            "-f", "lavfi", "-t", str(SECONDS), "-i", f"sine=frequency={right_hz(i)}:sample_rate={RATE}",
            "-filter_complex", "[0:a][1:a]join=inputs=2:channel_layout=stereo,volume=0.25[a]",
            "-map", "[a]", "-ar", str(RATE), "-c:a", "pcm_s16le", str(out)], check=True)
        manifest = {
            "name": f"radio_station_chantest_{letter.lower()}",
            "frequency": round(60.0 + i / 10, 1),
            "displayName": f"Chan Test {letter}",
            "tracks": [{"file": "audio/tone.wav", "title": f"Left {left_hz(i)} Hz, right {right_hz(i)} Hz"}],
        }
        (station / "station.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(f"Chan Test {letter}  {manifest['frequency']}  left {left_hz(i)} Hz  right {right_hz(i)} Hz")


def report(path: pathlib.Path, window: float) -> None:
    import numpy as np

    with wave.open(str(path), "rb") as w:
        rate, channels, width = w.getframerate(), w.getnchannels(), w.getsampwidth()
        frames = w.readframes(w.getnframes())
    if width != 2 or channels < 2:
        sys.exit("needs a 16-bit recording with at least two channels")
    data = np.frombuffer(frames, dtype="<i2").reshape(-1, channels)[:, :2].astype(np.float64) / 32768.0
    size = int(rate * window)
    hann = np.hanning(size)
    freqs = np.fft.rfftfreq(size, 1 / rate)

    # A tone counts when its bin is within 30 dB of the loudest test tone on that side and above
    # an absolute floor, so silence and the other side's leakage are not read as a station.
    floor = size * 1e-4

    def present(spectrum: np.ndarray, targets: dict[int, int]) -> list[int]:
        peaks = {}
        for station, hz in targets.items():
            k = int(round(hz / (rate / size)))
            peaks[station] = spectrum[max(k - 1, 0):k + 2].max()
        top = max(peaks.values())
        if top < floor:
            return []
        return [s for s, p in peaks.items() if p >= floor and 20 * math.log10(p / top) > -30]

    lefts = {i: left_hz(i) for i in range(1, 27)}
    rights = {i: right_hz(i) for i in range(1, 27)}
    runs: list[list] = []
    for n in range(len(data) // size):
        chunk = data[n * size:(n + 1) * size]
        l = present(np.abs(np.fft.rfft(chunk[:, 0] * hann)), lefts)
        r = present(np.abs(np.fft.rfft(chunk[:, 1] * hann)), rights)
        key = (tuple(l), tuple(r))
        if runs and runs[-1][2] == key:
            runs[-1][1] = (n + 1) * window
        else:
            runs.append([n * window, (n + 1) * window, key])
    start = path.with_suffix(path.suffix + ".start")
    if start.exists():
        print(f"recording started {start.read_text().strip()}")
    for a, b, (l, r) in runs:
        if not l and not r:
            continue
        name = lambda s: ",".join(string.ascii_uppercase[i - 1] for i in s) or "-"
        flag = "   <-- more than one station" if len(l) > 1 or len(r) > 1 else ""
        print(f"{a:7.1f}-{b:7.1f} s  left {name(l):10} right {name(r):10}{flag}")


def main() -> None:
    args = sys.argv[1:]
    if len(args) >= 2 and args[0] == "make":
        count = int(args[args.index("--count") + 1]) if "--count" in args else 16
        make(pathlib.Path(args[1]), count)
    elif len(args) >= 2 and args[0] == "report":
        window = float(args[args.index("--window") + 1]) if "--window" in args else 2.0
        report(pathlib.Path(args[1]), window)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
