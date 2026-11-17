# shellcheck shell=bash
# config.sh — settings shared by bing.sh and rotation.sh (sourced, not run).
#
# Order, first match wins: command argument > environment variable >
# config file > built-in default.
#
# Config file: $BING_CONFIG, default ~/.config/bing-wallpaper-captions/config
# One KEY=value per line; "#" starts a comment line; quotes and a leading
# "~/" are allowed. The file is read, not executed: only the keys below are
# accepted.

BING_CONFIG="${BING_CONFIG:-$HOME/.config/bing-wallpaper-captions/config}"
CONFIG_KEYS="BING_WALLPAPER_DIR BING_ROTATION_DIR BING_ROTATION_RECENT BING_ROTATION_RANDOM BING_CAPTION_POSITION BING_FILENAME_LANGUAGE BING_FILENAME_CREDIT"
ICLOUD_DRIVE="$HOME/Library/Mobile Documents/com~apple~CloudDocs"

# Sets every key from the config file that the environment does not set yet.
load_config() {
    [ -f "$BING_CONFIG" ] || return 0
    local line key value n=0
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}" # trim leading space
        case "$line" in '' | '#'*) continue ;; esac
        if [ "${line#*=}" = "$line" ]; then
            echo "warning: $BING_CONFIG:$n: expected KEY=value" >&2
            continue
        fi
        key="${line%%=*}"
        key="${key//[[:space:]]/}"
        value="${line#*=}"
        value="${value#"${value%%[![:space:]]*}"}" # trim leading space
        value="${value%"${value##*[![:space:]]}"}" # trim trailing space
        case "$value" in
            \"*\") value="${value#\"}" value="${value%\"}" ;;
            \'*\') value="${value#\'}" value="${value%\'}" ;;
        esac
        case "$value" in \~) value="$HOME" ;; \~/*) value="$HOME/${value#\~/}" ;; esac
        case " $CONFIG_KEYS " in
            *" $key "*) ;;
            *)
                echo "warning: $BING_CONFIG:$n: unknown setting $key" >&2
                continue
                ;;
        esac
        if [ -z "${!key+set}" ]; then
            export "$key=$value"
        fi
    done <"$BING_CONFIG"
}

# The collection folder: argument > BING_WALLPAPER_DIR > iCloud Drive/Bing_Wallpaper.
# Prints it, or fails when there is no iCloud Drive to default to.
collection_dir() {
    if [ -n "${1:-}" ]; then
        printf '%s' "$1"
    elif [ -n "${BING_WALLPAPER_DIR:-}" ]; then
        printf '%s' "$BING_WALLPAPER_DIR"
    elif [ -d "$ICLOUD_DRIVE" ]; then
        printf '%s' "$ICLOUD_DRIVE/Bing_Wallpaper"
    else
        echo "error: iCloud Drive not found; set BING_WALLPAPER_DIR (see README, Settings)" >&2
        return 1
    fi
}

# Filename options affect names only, never embedded metadata.
filename_config() {
    export BING_FILENAME_LANGUAGE="${BING_FILENAME_LANGUAGE-en}"
    export BING_FILENAME_CREDIT="${BING_FILENAME_CREDIT-0}"
    case "$BING_FILENAME_LANGUAGE" in en|zh) ;; *) echo 'error: BING_FILENAME_LANGUAGE must be en or zh' >&2; return 2 ;; esac
    case "$BING_FILENAME_CREDIT" in 0|1) ;; *) echo 'error: BING_FILENAME_CREDIT must be 0 or 1' >&2; return 2 ;; esac
}

# Serialize collection mutations on this Mac. An interrupted run leaves a
# visible lock rather than risking another writer; remove only after inspection.
collection_lock() {
    local d
    for d in "$1"/{archive,Archive,archived,Archived}; do
        [ ! -L "$d" ] || { echo "error: linked archive directory: $d" >&2; return 1; }
    done
    local candidate="$1/.bing-operation.lock"
    if ! mkdir "$candidate" 2>/dev/null; then
        echo "error: collection busy (or stale lock): $candidate" >&2
        return 1
    fi
    COLLECTION_LOCK="$candidate"
    printf '%s\n' "$$" >"$COLLECTION_LOCK/pid"
}
collection_unlock() {
    [ -n "${COLLECTION_LOCK:-}" ] || return 0
    rm -f "$COLLECTION_LOCK/pid"
    rmdir "$COLLECTION_LOCK"
}
