# Project Instructions

## Repo Identity

- **Account:** personal `lhc7970` (SSH alias `github-lhc7970`), default `gh` configuration.
- **Merge policy:** self-merge.
- **Base branch:** `main`.
- **Purpose:** Collect Bing wallpapers with bilingual XMP metadata and generate captioned copies for macOS desktop rotation.
- **Validation:** Run the complete [README validation block](README.md#validation) on macOS from the repository root.
- **Automated reviewers:** Codex (request with `@codex review`).

## Surfaces

- **Documentation surfaces:** `README.md`, `docs/design.md`, and `CHANGELOG.md` for release history.
- **Compatibility surfaces:** shell entry points, config keys and precedence, collection and archive layout, filename policy, embedded XMP fields, and rename/restore JSONL records.

## Coordination

- Backlog surface: **GitHub Issues on this repo**.

## Startup

- Read [README.md](README.md) for current settings, validation, and recovery commands. Read [docs/design.md](docs/design.md) for the rationale behind date-based deduplication, metadata, and rotation.

## Data

- **Location:** The downloading Mac (`tars` in the current setup) writes originals with embedded XMP to `~/Library/Mobile Documents/com~apple~CloudDocs/Bing_Wallpaper` by default. iCloud Drive syncs the collection, including archived originals and the `.bing-downloaded` date ledger. Other Macs run rotation only. A collection argument takes precedence over `BING_WALLPAPER_DIR`, then the config value, then the default. For a custom path, sync depends on its location.
- **Rotation:** Each Mac rebuilds its captioned copies in `~/Pictures/Bing_Wallpaper` (override `BING_ROTATION_DIR`). This folder is local by default. It also holds `.caption-version` and the narrowest screen aspect observed by that Mac.
- **Configuration:** Each Mac reads `~/.config/bing-wallpaper-captions/config` by default. Set `BING_CONFIG` to read another file. Environment settings take precedence over file values.
- **Recovery records:** `./rename.sh <collection> --apply <log>` takes an explicit path for a new private JSONL log outside the collection. Pass that same log to `--restore`. Existing migration logs and SHA-256 baselines are kept locally on `tars` under `~/.local/state/bing-wallpaper-captions/`. Keep them while rollback or verification is needed. The logs record renames and the baselines identify file contents by hash. Recovering image bytes requires a copy of the originals.
- **Backup:** Independent NAS and external-disk coverage is unverified for both the originals and the recovery records. The repository provides no backup job. iCloud propagates collection changes, including deletions. Rotation copies can be regenerated from the originals.
