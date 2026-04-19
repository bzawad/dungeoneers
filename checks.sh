#!/bin/bash
# Godot GDScript project check (mirrors gama/checks.sh).
# Requires a writable project dir: Godot uses --log-file below and may write user://
# data. Read-only sandboxes or CI without a writable tree can fail spuriously.
#
# Optional Elixir drift gate (from this dir, when mix + sibling dungeon_explorer exist):
#   ./tools/export_themes_from_explorer.sh && ./tools/export_special_feature_registry_from_explorer.sh
#   git diff --exit-code dungeon/data/themes.json dungeon/data/special_feature_registry.json
set -e
echo "Running Godot GDScript check for dungeoneers..."

if ! command -v godot4 &> /dev/null; then
	echo "ERROR: godot4 not found. Run ./setup_cli.sh or add Godot to PATH."
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_FILE="$SCRIPT_DIR/.godot_checks.log"
rm -f "$LOG_FILE"

# Godot requires --script with --check-only; see `godot4 --help`.
if timeout 30s godot4 --headless --path . --log-file "$LOG_FILE" \
	--script res://tools/check_parse.gd --check-only --quit; then
	:
else
	exit_code=$?
	if [ "$exit_code" -eq 124 ]; then
		echo "ERROR: Godot check timed out"
		exit 1
	fi
	echo "ERROR: Godot check failed with exit code $exit_code"
	exit "$exit_code"
fi

if timeout 30s godot4 --headless --path . --log-file "$LOG_FILE" \
	--script res://tools/check_grid_tile_patch_codec.gd --quit; then
	echo "Godot check completed successfully"
	exit 0
fi

codec_exit=$?
if [ "$codec_exit" -eq 124 ]; then
	echo "ERROR: grid tile patch codec check timed out"
	exit 1
fi
echo "ERROR: grid tile patch codec check failed with exit code $codec_exit"
exit "$codec_exit"
