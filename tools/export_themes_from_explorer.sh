#!/usr/bin/env bash
# Regenerate dungeoneers/dungeon/data/themes.json from Explorer `Dungeon.Themes.get_themes/0`
# (source: dungeon_explorer/lib/dungeon/themes.ex). Requires `mix` on PATH.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DNG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPLORER="$(cd "$DNG_ROOT/../dungeon_explorer" && pwd)"
OUT="${1:-$DNG_ROOT/dungeon/data/themes.json}"

if ! command -v mix &>/dev/null; then
	echo "ERROR: mix not found (install Elixir / run from dev env)." >&2
	exit 1
fi

(
	cd "$EXPLORER"
	mix run --no-start tools/export_dungeoneers_data.exs themes "$OUT"
)

echo "Wrote $OUT"
