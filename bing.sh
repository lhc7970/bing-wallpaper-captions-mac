#!/bin/bash
# bing.sh — downloads the Bing image of the day (UHD) into a collection folder.
# Fetches the Bing images of the last 15 days and saves any that are missing.
#
# Usage:  ./bing.sh [download-folder]
# Folder: argument > $BING_WALLPAPER_DIR > config file > iCloud Drive/Bing_Wallpaper
# (settings: config.sh and README)
#
# Needs only what macOS ships with: bash 3.2, curl, sed, plutil.
# On Linux (no plutil) it falls back to jq.
# With swift (Xcode Command Line Tools) it also writes the title, description,
# credit, date, link and English text into each image as XMP (bingkit.swift).

set -euo pipefail

HOST="https://cn.bing.com"
MAX_ITEMS=8 # Bing returns at most 8 images per request
PAGES="0 7" # idx=7 reaches 7 days further back: the last 15 days in all
HERE="$(cd "$(dirname "$0")" && pwd)"
BINGKIT="$HERE/bingkit.swift"
# shellcheck source=config.sh
. "$HERE/config.sh"
load_config
DEST_DIR="$(collection_dir "${1:-}")" || exit 1
SEP=$'\037' # field separator for the English text table
# English text appears about 15 hours after the Chinese text. A new image
# waits for it this long at most; after that it is saved without English.
WAIT_HOURS=24

if command -v plutil >/dev/null 2>&1; then
    JSON_TOOL=plutil
elif command -v jq >/dev/null 2>&1; then
    JSON_TOOL=jq
else
    echo "error: need plutil (macOS) or jq to parse JSON" >&2
    exit 2
fi

# /usr/bin/swift exists on every Mac, but only works with Command Line Tools.
if [ -f "$BINGKIT" ] && xcrun --find swift >/dev/null 2>&1; then
    XMP=1
else
    XMP=0
    echo "note: swift not found, images are saved without XMP (see README)" >&2
fi

# Print the string at a dotted key path (e.g. images.0.urlbase) from a JSON
# file. Fails if the path does not exist.
json_get() {
    if [ "$JSON_TOOL" = plutil ]; then
        plutil -extract "$2" raw -o - "$1"
    else
        jq -er --arg p "$2" 'getpath($p | split(".") | map(tonumber? // .)) | strings' "$1"
    fi
}

# File name rules: drop "(" and ")", "/" -> ", ", ":" -> " - ", then remove
# characters that are invalid in macOS or Windows file names.
clean_name() {
    printf '%s' "$1" | sed -e 's/[()]//g' -e 's#/#, #g' -e 's/:/ - /g' -e 's/[\\*?"<>|]//g'
}

# Split Bing's "<description> (© <credit>)" into $desc and $credit.
split_copyright() {
    case "$1" in
        *" (©"*")")
            desc="${1% (©*}"
            credit="${1##* (}"
            credit="${credit%)}"
            ;;
        *) desc="$1" credit="" ;;
    esac
}

# Image ID shared by all markets: /th?id=OHR.FrankfurtHalloween_ZH-CN59… -> FrankfurtHalloween
image_id() {
    local id="${1#*OHR.}"
    printf '%s' "${id%%_*}"
}

# One image per date: succeeds if <dir> has any image of <date> (YYYY-MM-DD),
# whatever the rest of its name. This covers captions Bing edited later,
# copies iCloud made on a sync conflict ("<name> 2.jpg") and placeholders for
# files kept only in iCloud (".<name>.jpg.icloud", macOS 13 and earlier).
have_date() {
    local f
    for f in "$1/$2 "*.jpg "$1/.$2 "*.jpg.icloud; do
        [ -e "$f" ] && return 0
    done
    return 1
}

fetch() { curl -fsSL --retry 3 -o "$1" "$2"; }

# Seconds since 1970 for a UTC time YYYYMMDDHHMM (BSD date, then GNU date).
epoch_utc() {
    date -u -j -f '%Y%m%d%H%M%S' "${1}00" +%s 2>/dev/null ||
        date -u -d "${1:0:8} ${1:8:2}:${1:10:2}" +%s 2>/dev/null
}

# Dates already downloaded, one YYYY-MM-DD per line, so an image you
# deleted is not downloaded again. Only Bing's window matters (15 days); older
# lines are dropped at the end of each run.
RECORD="$DEST_DIR/.bing-downloaded"
recorded() { grep -qx -- "$1" "$RECORD" 2>/dev/null; }
record() { recorded "$1" || printf '%s\n' "$1" >>"$RECORD"; }

# Work files live outside the download folder so iCloud never syncs a
# half-downloaded image. Same volume as $HOME on macOS, so mv is a rename.
work_dir="$(mktemp -d)"
# shellcheck disable=SC2329 # invoked via trap
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

mkdir -p "$DEST_DIR"
# Under launchd, macOS privacy protection can block listing ~/Documents.
# Stop here instead of taking it for an empty folder and downloading again.
if ! ls -A "$DEST_DIR" >/dev/null 2>&1; then
    echo "error: cannot read $DEST_DIR (macOS privacy protection? see README, Permission)" >&2
    exit 1
fi

failed=0
lists=""
for page in $PAGES; do
    list="$work_dir/zh-$page.json"
    if fetch "$list" "$HOST/HPImageArchive.aspx?format=js&idx=$page&n=$MAX_ITEMS"; then
        lists="$lists $list"
    elif [ "$page" = 0 ]; then
        echo "error: failed to fetch image list" >&2
        exit 1
    else
        echo "warning: failed to fetch older images (idx=$page)" >&2
        failed=1
    fi
done

# English text by image ID (the English market's date can be one day later).
en_text="$work_dir/en.txt"
: >"$en_text"
en_ok=0 # the newest English list arrived, so a missing image is not yet there
if [ "$XMP" = 1 ]; then
    for page in $PAGES; do
        list="$work_dir/en-$page.json"
        if ! fetch "$list" "$HOST/HPImageArchive.aspx?format=js&idx=$page&n=$MAX_ITEMS&ensearch=1"; then
            echo "warning: failed to fetch English text (idx=$page)" >&2
            continue
        fi
        [ "$page" = 0 ] && en_ok=1
        j=0
        while [ "$j" -lt "$MAX_ITEMS" ]; do
            url_base="$(json_get "$list" "images.$j.urlbase" 2>/dev/null)" || break
            title="$(json_get "$list" "images.$j.title" 2>/dev/null)" || title=""
            copyright="$(json_get "$list" "images.$j.copyright" 2>/dev/null)" || copyright=""
            split_copyright "$copyright"
            printf '%s%s%s%s%s\n' "$(image_id "$url_base")" "$SEP" "$title" "$SEP" "$desc" >>"$en_text"
            j=$((j + 1))
        done
    done
fi
has_english() { awk -F "$SEP" -v id="$1" '$1 == id { found = 1 } END { exit !found }' "$en_text"; }
now="$(date -u +%s)"

images=0
for list in $lists; do
    i=0
    while [ "$i" -lt "$MAX_ITEMS" ]; do
        start_date="$(json_get "$list" "images.$i.startdate" 2>/dev/null)" || break
        url_base="$(json_get "$list" "images.$i.urlbase")"
        copyright="$(json_get "$list" "images.$i.copyright")"
        title="$(json_get "$list" "images.$i.title" 2>/dev/null)" || title=""
        link="$(json_get "$list" "images.$i.copyrightlink" 2>/dev/null)" || link=""
        published="$(json_get "$list" "images.$i.fullstartdate" 2>/dev/null)" || published=""
        i=$((i + 1))
        images=$((images + 1))

        date="${start_date:0:4}-${start_date:4:2}-${start_date:6:2}"
        if recorded "$date"; then
            continue
        fi
        if have_date "$DEST_DIR" "$date"; then
            record "$date"
            continue
        fi

        # Not yet in English: leave it for a later run (not downloaded, not
        # recorded) until it is WAIT_HOURS old.
        id="$(image_id "$url_base")"
        if [ "$XMP" = 1 ] && [ "$en_ok" = 1 ] && ! has_english "$id"; then
            published="$(epoch_utc "$published" || true)"
            if [ -n "$published" ] && [ $((now - published)) -lt $((WAIT_HOURS * 3600)) ]; then
                echo "note: $date waits for its English text (published $(((now - published) / 3600)) h ago)" >&2
                continue
            fi
        fi

        url="$HOST${url_base}_UHD.jpg"
        dest="$DEST_DIR/$date $(clean_name "$copyright").jpg"
        part="$work_dir/download.jpg"
        echo "Downloading $url -> $dest"
        if ! curl -fsSL --retry 3 -o "$part" "$url"; then
            echo "warning: failed to download $url" >&2
            rm -f "$part"
            failed=1
            continue
        fi

        if [ "$XMP" = 1 ]; then
            title_en="" desc_en=""
            IFS="$SEP" read -r _ title_en desc_en < <(awk -F "$SEP" -v id="$id" '$1 == id { print; exit }' "$en_text") || true
            split_copyright "$copyright"
            if swift "$BINGKIT" tag "$part" "$work_dir/tagged.jpg" \
                "dc:title=$title" "dc:description=$desc" "dc:rights=$credit" \
                "photoshop:DateCreated=$date" "bing:id=$id" "bing:link=$link" \
                "bing:titleEn=$title_en" "bing:descriptionEn=$desc_en"; then
                mv -f "$work_dir/tagged.jpg" "$part"
            else
                echo "warning: saved without XMP: $dest" >&2
            fi
        fi
        mv -f "$part" "$dest"
        record "$date"
    done
done

# Keep only dates Bing can still return (16 days, one spare for time zones).
if [ -f "$RECORD" ]; then
    cutoff="$(date -v-16d +%Y-%m-%d 2>/dev/null || date -d '16 days ago' +%Y-%m-%d)"
    awk -v cutoff="$cutoff" '$0 >= cutoff' "$RECORD" | LC_ALL=C sort -u >"$work_dir/record"
    mv -f "$work_dir/record" "$RECORD"
fi

# A list we cannot parse (an HTML page, broken JSON) ends the loop at once;
# that is a failure, not "nothing new".
if [ "$images" -eq 0 ]; then
    echo "error: image list has no images" >&2
    exit 1
fi

exit "$failed"
