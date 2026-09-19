"""Make the Nexus misc file for the station builder, and the text for its description.

The builder is a web page, so the Nexus file that tracks it holds the builder README and changelog
at the builder's version. Re-uploading it with each version is what tells followers the builder
changed; the description on the Files tab carries the newest changelog entry, so they read the
notes without downloading.

usage:
  python scripts/nexus-builder-file.py [--out DIR]

Writes:
  site/nexus-file/RadioXL Station Builder/   README and CHANGELOG, as .md and as .txt. This is what
                                             the release pipeline zips (release-manifest.json,
                                             artifact `builder`), so commit it before tagging. The
                                             folder name is the point: a mod manager that installs
                                             the file by mistake makes an obviously empty mod.
and, into --out (default: site/), for the first upload, which is by hand:
  RadioXL Station Builder <version>.zip      the same folder, zipped
  RadioXL Station Builder <version>.txt      the file description: the link, then the newest entry

The version is package.json's. Nothing is typed by hand.
"""
from __future__ import annotations

import argparse
import json
import re
import zipfile
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent
URL = "https://spuddeh.github.io/cp2077-radio-xl/"
# The Nexus file version carries this suffix so its changelog entries sort apart from the mod's.
# The page's own version (package.json) does not.
NEXUS_SUFFIX = "sb"


def newest_entry(changelog: str, version: str) -> str:
    """The body of the changelog's entry for `version`, or a failure naming what is missing."""
    match = re.search(rf"^## {re.escape(version)}\n(.*?)(?=^## |\Z)", changelog, re.M | re.S)
    if not match:
        raise SystemExit(f"CHANGELOG.md has no entry for {version}; write it before making the file")
    return match.group(1).strip()


def as_lines(entry: str) -> list[str]:
    """One change per line: each Markdown bullet with its wrapped continuation lines joined, the
    bullet marker and code marks dropped. That is the shape the Nexus changelog box takes."""
    changes: list[str] = []
    for raw in entry.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("- "):
            changes.append(line[2:].strip())
        elif changes:
            changes[-1] += " " + line
    return [c.replace("`", "") for c in changes]


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", default=str(SITE), help="where the zip and the description are written")
    args = p.parse_args()

    version = json.loads((SITE / "package.json").read_text(encoding="utf-8"))["version"]
    readme = SITE / "README.md"
    changelog = SITE / "CHANGELOG.md"
    changes = as_lines(newest_entry(changelog.read_text(encoding="utf-8"), version))

    folder = SITE / "nexus-file" / "RadioXL Station Builder"
    folder.mkdir(parents=True, exist_ok=True)
    for stale in folder.iterdir():
        stale.unlink()
    for source in (readme, changelog):
        (folder / source.name).write_text(source.read_text(encoding="utf-8"), encoding="utf-8", newline="")
        # Most Nexus users double-click, and Windows opens .txt and not .md.
        (folder / f"{source.stem}.txt").write_text(source.read_text(encoding="utf-8").replace("`", ""), encoding="utf-8", newline="")

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    stem = f"RadioXL Station Builder {version}{NEXUS_SUFFIX}"
    with zipfile.ZipFile(out / f"{stem}.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(folder.iterdir()):
            z.write(f, f"RadioXL Station Builder/{f.name}")

    # The Files tab renders BBCode, so the link is one.
    description = "\n".join([
        f"The station builder is a web page: [url={URL}]{URL}[/url]",
        f"This file is its README and changelog at version {version}{NEXUS_SUFFIX}; nothing here needs installing.",
        "",
        f"Version {version}{NEXUS_SUFFIX}",
        *changes,
        "",
    ])
    (out / f"{stem}.txt").write_text(description, encoding="utf-8")
    print(f"wrote {folder}\nwrote {out / (stem + '.zip')}\nwrote {out / (stem + '.txt')}")


if __name__ == "__main__":
    main()
