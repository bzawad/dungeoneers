#!/usr/bin/env bash
# Mirror dungeon_explorer raster art into dungeoneers/assets/explorer/images/
# (full priv/static/images tree: tilesets, fog, doors, stairs, UI icons, characters, monsters, special_features, …).
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DNG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Default: dungeon_games/dungeon_explorer next to dungeoneers
EXPLORER_ROOT="${EXPLORER_ROOT:-$(cd "$DNG_ROOT/../dungeon_explorer" && pwd)}"
DST="$DNG_ROOT/assets/explorer/images"

if [[ ! -d "$EXPLORER_ROOT/priv/static/images" ]]; then
	echo "ERROR: Explorer raster bundle not found: $EXPLORER_ROOT/priv/static/images" >&2
	echo "Use a full dungeon_explorer checkout (this directory is absent in some partial trees)." >&2
	echo "Set EXPLORER_ROOT to the repo root that contains priv/static/images/." >&2
	exit 1
fi

SRC="$EXPLORER_ROOT/priv/static/images"
mkdir -p "$DST"
# Trailing slash: copy directory contents; preserve subdirs (doors/, tilesets/, …).
rsync -a --delete --exclude='.DS_Store' "$SRC/" "$DST/"
echo "sync_explorer_assets: OK -> $DST (mirrored from $SRC)"
