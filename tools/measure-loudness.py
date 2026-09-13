"""Measure how loud each radio station plays in game, from a loopback recording and the station probe's log.

usage:
  python measure-loudness.py record <out.wav> [--seconds 900] [--device "Game ("]
  python measure-loudness.py report <out.wav> <radiostationprobe log> [--settle 4] [--min 20]
  python measure-loudness.py devices

record   captures a WASAPI loopback device to a 16-bit WAV. The file's start time is written beside it
         (<out.wav>.start), because the report lines the audio up against the probe's timestamps.
         Stop early with Ctrl+C; the WAV is closed cleanly either way.
report   splits the recording into the stretches where one station was on the Radioport or a vehicle
         radio, drops the first --settle seconds of each (tune-in, buffering), and measures every
         station's integrated loudness (EBU R128, LUFS) and true peak with ffmpeg's ebur128 filter.
         Stations with less than --min seconds in total are listed but not measured.

The probe (MyMods/RadioStationProbe) logs a station line with a timestamp whenever its state changes.
The station whose listeners include `pocket_radio_emitter:on` or `vehicle_radio_emitter:on` is the one
the player hears. A world device (`radio:on`) is not counted: its level depends on distance.

A reading is only comparable to another taken with the same volume settings, standing in the same
place. Both vanilla and custom stations change material song to song, so a minute or more per station
is what makes two readings mean anything.
"""
import math
import os
import re
import subprocess
import sys
import time
import wave
from datetime import datetime

STAMP = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\]")
STATION = re.compile(r"(radio_station_\w+) active=(\d).*?listeners=\d+ \[([^\]]*)\]")
HEARD = ("pocket_radio_emitter:on", "vehicle_radio_emitter:on")


def devices():
    import pyaudiowpatch as pyaudio
    audio = pyaudio.PyAudio()
    for d in audio.get_loopback_device_info_generator():
        print(f"{d['index']:>3}  {d['name']}  {int(d['defaultSampleRate'])} Hz  {d['maxInputChannels']} ch")
    audio.terminate()


def record(out, seconds, device):
    import pyaudiowpatch as pyaudio
    audio = pyaudio.PyAudio()
    chosen = None
    for d in audio.get_loopback_device_info_generator():
        if device.lower() in d["name"].lower():
            chosen = d
            break
    if chosen is None:
        print(f"no loopback device matches '{device}' - run: python measure-loudness.py devices")
        sys.exit(1)
    rate = int(chosen["defaultSampleRate"])
    channels = min(2, chosen["maxInputChannels"])
    frames = 1024
    stream = audio.open(format=pyaudio.paInt16, channels=channels, rate=rate, input=True,
                        input_device_index=chosen["index"], frames_per_buffer=frames)
    start = time.time()
    with open(out + ".start", "w") as f:
        f.write(f"{start:.3f}\n")
    print(f"recording {chosen['name']} at {rate} Hz for up to {seconds} s - Ctrl+C to stop")
    wav = wave.open(out, "wb")
    wav.setnchannels(channels)
    wav.setsampwidth(2)
    wav.setframerate(rate)
    # **A loopback device delivers nothing while nothing plays on it**, so a read would block through
    # a menu or a pause and every later sample would sit early against the probe's clock. The file is
    # kept on wall-clock time instead: a gap longer than a fifth of a second is written as silence.
    written = 0
    width = 2 * channels
    try:
        while time.time() - start < seconds:
            available = stream.get_read_available()
            if available > 0:
                data = stream.read(available, exception_on_overflow=False)
                wav.writeframes(data)
                written += len(data) // width
            else:
                time.sleep(0.01)
            behind = int((time.time() - start) * rate) - written
            if behind > rate // 5:
                wav.writeframes(b"\0" * behind * width)
                written += behind
    except KeyboardInterrupt:
        pass
    finally:
        wav.close()
        stream.stop_stream()
        stream.close()
        audio.terminate()
    print(f"wrote {out}, {time.time() - start:.0f} s")


def timeline(log):
    """(start, end, station) for every stretch a station was heard, in epoch seconds."""
    spans = []
    current, since, at = None, None, None
    with open(log, encoding="utf-8", errors="replace") as f:
        for raw in f:
            # A block of station lines carries one timestamp, on its first line.
            stamp = STAMP.match(raw)
            if stamp:
                at = datetime.strptime(stamp.group(1)[:23], "%Y-%m-%d %H:%M:%S.%f").timestamp()
            m = STATION.search(raw)
            if not m or at is None:
                continue
            station, active, listeners = m.group(1), m.group(2) == "1", m.group(3)
            heard = active and any(h in listeners for h in HEARD)
            if heard and station != current:
                if current:
                    spans.append((since, at, current))
                current, since = station, at
            elif not heard and station == current:
                spans.append((since, at, current))
                current, since = None, None
    if current:
        spans.append((since, None, current))
    return spans


def measure(wav, offset, length):
    out = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-ss", f"{offset:.3f}", "-t", f"{length:.3f}",
                          "-i", wav, "-af", "ebur128=peak=true", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    summary = out[out.rfind("Summary:"):]
    lufs = re.search(r"I:\s+(-?[\d.]+|-inf) LUFS", summary)
    peak = re.search(r"Peak:\s+(-?[\d.]+|-inf) dBFS", summary)
    return (float(lufs.group(1)) if lufs else float("nan"), float(peak.group(1)) if peak else float("nan"))


def report(wav, log, settle, minimum):
    start = float(open(wav + ".start").read())
    with wave.open(wav) as w:
        duration = w.getnframes() / w.getframerate()
    totals = {}
    for since, until, station in timeline(log):
        until = start + duration if until is None else until
        a, b = max(since + settle, start), min(until, start + duration)
        if b - a > 1.0:
            totals.setdefault(station, []).append((a - start, b - a))
    if not totals:
        print("no station was heard during the recording - is the probe log from the same session?")
        return
    rows = []
    for station, parts in totals.items():
        seconds = sum(length for _, length in parts)
        if seconds < minimum:
            rows.append((station, seconds, None, None))
            continue
        # One ffmpeg pass per stretch, combined by duration: integrated loudness is an energy
        # average, so the stretches are summed in the power domain rather than as dB.
        energy, peak = 0.0, float("-inf")
        for offset, length in parts:
            lufs, p = measure(wav, offset, length)
            if lufs == lufs and lufs != float("-inf"):
                energy += length * 10 ** (lufs / 10)
            peak = max(peak, p)
        lufs = 10 * math.log10(energy / seconds) if energy > 0 else float("-inf")
        rows.append((station, seconds, lufs, peak))
    measured = [r[2] for r in rows if r[2] is not None and re.match(r"radio_station_(0\d|1[0-4])_", r[0])]
    reference = sorted(measured)[len(measured) // 2] if measured else None
    print(f"{'station':40} {'seconds':>8} {'LUFS':>7} {'peak':>7} {'vs vanilla median':>18}")
    for station, seconds, lufs, peak in sorted(rows, key=lambda r: (r[2] is None, -(r[2] or 0))):
        if lufs is None:
            print(f"{station:40} {seconds:8.0f} {'-':>7} {'-':>7}   under {minimum} s, not measured")
            continue
        delta = f"{lufs - reference:+.1f} dB" if reference is not None else ""
        print(f"{station:40} {seconds:8.0f} {lufs:7.1f} {peak:7.1f} {delta:>18}")
    if reference is not None:
        print(f"\nvanilla median {reference:.1f} LUFS over {len(measured)} station(s). A gain change of "
              f"N dB is a factor of 10^(N/20): -3 dB is x0.71, +3 dB is x1.41.")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    args = sys.argv[1:]

    def option(name, default):
        if name in args:
            i = args.index(name)
            value = args[i + 1]
            del args[i:i + 2]
            return value
        return default

    seconds = float(option("--seconds", "900"))
    device = option("--device", "Game (")
    settle = float(option("--settle", "4"))
    minimum = float(option("--min", "20"))
    if args[:1] == ["devices"]:
        devices()
    elif args[:1] == ["record"] and len(args) == 2:
        record(args[1], seconds, device)
    elif args[:1] == ["report"] and len(args) == 3:
        if not os.path.exists(args[1] + ".start"):
            print(f"{args[1]}.start is missing - the report needs the recording's start time")
            sys.exit(1)
        report(args[1], args[2], settle, minimum)
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
