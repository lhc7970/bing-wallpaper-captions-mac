#!/bin/bash
# Restore: ./rename.sh [collection] --restore /absolute/log.jsonl
# Preview by default. Apply: ./rename.sh [collection] --apply /absolute/new-log.jsonl
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/config.sh"
load_config
filename_config
root="$(collection_dir "${1:-}")"
if [ "$#" -gt 0 ]; then shift; fi
if [ "$#" -gt 0 ]; then
    [ "$#" -eq 2 ] && { [ "$1" = --apply ] || [ "$1" = --restore ]; } || exit 2
    collection_lock "$root"
    trap collection_unlock EXIT
fi
if [ "${1:-}" = --restore ]; then
    swift "$HERE/bingkit.swift" restore "$root" "$2"
else
    swift "$HERE/bingkit.swift" rename "$root" "$@"
fi
