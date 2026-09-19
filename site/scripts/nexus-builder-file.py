"""Make the Nexus misc file for the station builder, and the text for its description.

The builder is a web page, so the Nexus file that tracks it holds the builder README and changelog
at the builder's version. Re-uploading it with each version is what tells followers the builder
changed; the description on the Files tab carries the newest changelog entry, so they read the
notes without downloading.

usage:
  python scripts/nexus-builder-file.py [--out DIR]

Writes, into --out (default: site/):
  RadioXL Station Builder <version>.zip   README and CHANGELOG, as .md and as .txt, under a folder
                                          named for the builder, so a mod manager that installs
                                          the file by mistake makes an obviously empty mod
  RadioXL Station Builder <version>.txt   the file description: the link, then the newest entry

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


def newest_entry(changelog: str, version: str) -> str:
    """The body of the changelog's entry for `version`, or a failure naming what is missing."""
    match = re.search(rf"^## {re.escape(version)}\n(.*?)(?=^## |\Z)", changelog, re.M | re.S)
    if not match:
        raise SystemExit(f"CHANGELOG.md has no entry for {version}; write it before making the file")
    return match.group(1).strip()


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", default=str(SITE), help="where the zip and the description are written")
    args = p.parse_args()

    version = json.loads((SITE / "package.json").read_text(encoding="utf-8"))["version"]
    readme = SITE / "README.md"
    changelog = SITE / "CHANGELOG.md"
    # The description is plain text on the Files tab, so the entry's code marks are dropped.
    entry = newest_entry(changelog.read_text(encoding="utf-8"), version).replace("`", "")

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    stem = f"RadioXL Station Builder {version}"
    with zipfile.ZipFile(out / f"{stem}.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for source in (readme, changelog):
            z.write(source, f"RadioXL Station Builder/{source.name}")
            # Most Nexus users double-click, and Windows opens .txt and not .md.
            z.writestr(f"RadioXL Station Builder/{source.stem}.txt", source.read_text(encoding="utf-8").replace("`", ""))

    description = "\n".join([
        f"The station builder is a web page: {URL}",
        f"This file is its README and changelog at version {version}; nothing here needs installing.",
        "",
        f"Version {version}",
        entry,
        "",
    ])
    (out / f"{stem}.txt").write_text(description, encoding="utf-8")
    print(f"wrote {out / (stem + '.zip')}\nwrote {out / (stem + '.txt')}")


if __name__ == "__main__":
    main()
