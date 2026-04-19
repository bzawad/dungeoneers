#!/bin/bash
# Launch editor/player build in single-player stub mode (pattern from gama/start_single_player.sh).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if command -v godot4 &> /dev/null; then
	GODOT_CMD="godot4"
elif command -v godot &> /dev/null; then
	GODOT_CMD="godot"
else
	echo "ERROR: Godot not found in PATH"
	exit 1
fi

echo "Launching Dungeoneers single-player stub..."
exec "$GODOT_CMD" --path . --single-player Main.tscn
