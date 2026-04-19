#!/usr/bin/env bash
# Mirror dungeon_explorer MP3 SFX + music into dungeoneers/assets/explorer/audio/
# (full priv/static/audio tree; same basenames as LiveView / assets/js/app.js).
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DNG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPLORER_ROOT="${EXPLORER_ROOT:-$(cd "$DNG_ROOT/../dungeon_explorer" && pwd)}"
DST="$DNG_ROOT/assets/explorer/audio"

if [[ ! -d "$EXPLORER_ROOT/priv/static/audio" ]]; then
	echo "ERROR: Explorer audio bundle not found: $EXPLORER_ROOT/priv/static/audio" >&2
	echo "Set EXPLORER_ROOT to the repo root that contains priv/static/audio/." >&2
	exit 1
fi

SRC="$EXPLORER_ROOT/priv/static/audio"
mkdir -p "$DST"
rsync -a --delete --exclude='.DS_Store' "$SRC/" "$DST/"
echo "sync_explorer_audio: OK -> $DST (mirrored from $SRC)"
