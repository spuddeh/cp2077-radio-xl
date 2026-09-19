# Releasing

This repo publishes to **GitHub Releases** and **Nexus Mods** through
[`.github/workflows/release.yml`](.github/workflows/release.yml), driven by
[`release-manifest.json`](release-manifest.json). The workflow is the shared copy from
`MyMods/_shared/release/release.yml`; edit it there, never here.

## Artifacts

| Artifact id | What | Nexus mod | File on Nexus |
| --- | --- | --- | --- |
| `radioxl` | The framework: `archive`, `r6` and `red4ext`, the same 22 files `deploy-mod` ships | 33983 | main |
| `builder` | The station builder's README and changelog, from `site/nexus-file/` | 33983 | miscellaneous |

The builder is a web page on GitHub Pages, deployed on every push to `site/**`. Its Nexus file
exists so that followers are told when the builder changes and can read the notes on the Files tab.
`python site/scripts/nexus-builder-file.py` writes `site/nexus-file/` from `site/README.md` and
`site/CHANGELOG.md`; commit that output before tagging a builder release.

## One-time setup

1. **API key, a real secret.** A Nexus personal API key from
   <https://www.nexusmods.com/settings/api-keys>, stored as the repository secret
   **`NEXUSMODS_API_KEY`** (Settings > Secrets and variables > Actions > Secrets).

2. **File ids, repository VARIABLES, not secrets, and not in this repo.**

   | Artifact | Variable |
   | --- | --- |
   | `radioxl` | **`NEXUS_FILE_ID_RADIOXL`** |
   | `builder` | **`NEXUS_FILE_ID_BUILDER`** |

   A file id does not exist until that artifact's first file has been uploaded to the mod page by
   hand, so the pipeline publishes an artifact's updates, never its first file. Get the id from
   the mod page's Files tab > API Info, where Nexus labels it "Group ID". Not from the public v1
   API: that is a different id space and the wrong value looks entirely plausible. Until the
   variable is set the workflow hard-fails rather than uploading into the void.

## Cutting a release

1. Bump the version in the source headers and `plugin/src/Main.cpp` (`RED4EXT_V1_SEMVER`), rebuild
   the plugin and commit the DLL, move the `[Unreleased]` entries in `@changelog.md` and
   `nexus_changelog.md` under the version, and set `currentVersion` in the manifest. For the
   builder: `site/package.json`, `site/CHANGELOG.md`, then `nexus-builder-file.py`.
2. `release-check`, `redscript-check -BothConfigs`, and `deploy-mod -Instance Testing`, then the
   in-game checks.
3. Push `main`.
4. Create a GitHub Release whose **tag** is `<artifact>-v<version>`: `radioxl-v0.4.0`,
   `builder-v0.2.0`. The body feeds two Nexus fields, split by one marker:

   ```
   <file description, 255 characters at most>
   <!-- nexus-description-end -->
   <one plain line per change, no headings, no bullets>
   ```

   Nexus renders neither field as Markdown. The workflow flattens what it can, but plain lines are
   the convention.
5. The workflow builds the zip, attaches it to the release, uploads it to Nexus, sets the page
   version (for `radioxl` only) and appends the changelog to the mod page. The page description
   stays manual: `nexus_description.bbc` is pasted by hand.

## Order for a release that changes the manifest format

The builder deploys the moment `site/**` is pushed, and it writes whatever manifest fields the
current plugin reads. A RadioXL that does not know a field ignores it, so publish the `radioxl`
release first, or in the same hour, before pushing a builder that writes the new field.
