#!/bin/bash
# Builds the folder the Mac desktop rotates through: copies of the newest
# images plus a random pick of older ones, each with its caption drawn on it.
# Run it on every Mac that shows the wallpapers; only one Mac needs to run
# bing.sh (see README, "One Mac downloads, every Mac shows"). macOS only.
#
# Usage:  ./rotation.sh [collection-folder]
# Collection: argument > $BING_WALLPAPER_DIR > iCloud Drive/Bing_Wallpaper
# Output:     $BING_ROTATION_DIR > ~/Pictures/Bing_Wallpaper
# Each setting can also come from the config file (config.sh, README).
# Counts:     $BING_ROTATION_RECENT (default 8), $BING_ROTATION_RANDOM (8)
#
# The output folder is generated: anything in it may be replaced or removed.
# Needs swift (Xcode Command Line Tools) for bingkit.swift.
#
# Exit codes: 0 ok · 1 a folder cannot be read or a caption failed ·
# 2 swift is missing.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config.sh
. "$HERE/config.sh"
load_config
SRC_DIR="$(collection_dir "${1:-}")" || exit 1
OUT_DIR="${BING_ROTATION_DIR:-$HOME/Pictures/Bing_Wallpaper}"
RECENT="${BING_ROTATION_RECENT:-8}"
RANDOM_PICK="${BING_ROTATION_RANDOM:-8}"
BINGKIT="$HERE/bingkit.swift"
# Bump when the caption look changes, so existing copies are drawn again.
CAPTION_VERSION=5

if ! xcrun --find swift >/dev/null 2>&1; then
    echo "error: rotation needs swift: run xcode-select --install" >&2
    exit 2
fi
if ! ls -A "$SRC_DIR" >/dev/null 2>&1; then
    echo "error: cannot read $SRC_DIR (macOS privacy protection? see README, Permission)" >&2
    exit 1
fi
mkdir -p "$OUT_DIR"

work_dir="$(mktemp -d)"
# shellcheck disable=SC2329 # invoked via trap
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

# Images are named "YYYY-MM-DD …", so name order is date order. Conflict
# copies ("… 2.jpg") and placeholders (".….icloud") are left out.
all="$work_dir/all.txt"
# shellcheck disable=SC2010 # names are matched by pattern, not parsed
ls -1 "$SRC_DIR" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} .*\.jpg$' \
    | grep -Ev ' [0-9]+\.jpg$| \([0-9]+\)\.jpg$' | LC_ALL=C sort >"$all" || true
total="$(wc -l <"$all" | tr -d ' ')"
if [ "$total" -eq 0 ]; then
    echo "error: no images in $SRC_DIR" >&2
    exit 1
fi

# (Files instead of pipes into head: with pipefail, head closing early would
# fail the pipeline. macOS head also rejects -n 0.)
want="$work_dir/want.txt"
: >"$want"
older=$((total > RECENT ? total - RECENT : 0))
if [ "$RECENT" -gt 0 ]; then
    tail -n "$RECENT" "$all" >>"$want"
fi
if [ "$older" -gt 0 ] && [ "$RANDOM_PICK" -gt 0 ]; then
    # The older images change once a day, not on every run: each one is ranked
    # by a hash of today's date and its name. Every run on the same day, and
    # every Mac, picks the same ones, even if the collection gains an image in
    # between. (C locale: the hash works on bytes, whatever the caller's locale.)
    head -n "$older" "$all" | LC_ALL=C awk -v seed="$(date +%Y-%m-%d)" '
        BEGIN { for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i }
        {
            s = seed ":" $0; h = 7
            for (i = 1; i <= length(s); i++) h = (h * 31 + ord[substr(s, i, 1)]) % 2147483647
            printf "%010d\t%s\n", h, $0
        }' | LC_ALL=C sort | cut -f 2- >"$work_dir/older.txt"
    head -n "$RANDOM_PICK" "$work_dir/older.txt" >>"$want"
fi

# Margins depend on the narrowest screen the wallpaper is shown on (a screen
# narrower than the image cuts its sides off). It is remembered, so copies
# drawn while a MacBook runs with the lid closed still fit its own screen.
# Unknown: 1.52, the narrowest MacBook screen.
aspect_file="$OUT_DIR/.screen-aspect"
now="$(swift "$BINGKIT" screens 2>/dev/null || true)"
seen="$(cat "$aspect_file" 2>/dev/null || true)"
aspect="$(awk -v a="$now" -v b="$seen" 'BEGIN {
    if (a == "") a = b; else if (b != "" && b + 0 < a + 0) a = b
    print (a == "" ? "1.52" : a) }')"
printf '%s\n' "$aspect" >"$aspect_file"
export BING_SCREEN_ASPECT="$aspect"

# A new caption look or a narrower screen means every copy is drawn again.
version_file="$OUT_DIR/.caption-version"
version="$CAPTION_VERSION $aspect"
redraw_all=0
if [ "$(cat "$version_file" 2>/dev/null || true)" != "$version" ]; then
    redraw_all=1
fi

# Draw only the copies that are missing or older than their original (for
# example after XMP was added to it).
missing=()
while IFS= read -r name; do
    if [ "$redraw_all" = 1 ] || [ ! -e "$OUT_DIR/$name" ] || [ "$SRC_DIR/$name" -nt "$OUT_DIR/$name" ]; then
        missing+=("$SRC_DIR/$name")
    fi
done <"$want"

failed=0
if [ "${#missing[@]}" -gt 0 ]; then
    mkdir "$work_dir/out"
    swift "$BINGKIT" caption "$work_dir/out" "${missing[@]}" || failed=1
    # New copies first, then remove old ones, so the folder is never empty
    # while the desktop is using it.
    for f in "$work_dir/out"/*.jpg; do
        [ -e "$f" ] && mv -f "$f" "$OUT_DIR/"
    done
fi
if [ "$failed" = 0 ]; then
    printf '%s\n' "$version" >"$version_file"
fi

for f in "$OUT_DIR"/*.jpg; do
    [ -e "$f" ] || continue
    grep -Fxq -- "${f##*/}" "$want" || rm -f "$f"
done

exit "$failed"
