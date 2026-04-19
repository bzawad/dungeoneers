#!/bin/bash
# Headless dungeon generation smoke (Phase 1). Usage: ./run_generation.sh [seed] [theme]
# Example: ./run_generation.sh 4242 up
# Optional: pass --dungeon-level N after script args, e.g. godot4 ... -- --seed 1 --theme up --dungeon-level 2

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v godot4 &> /dev/null; then
	echo "ERROR: godot4 not found."
	exit 1
fi

SEED=${1:-1}
THEME=${2:-up}

exec godot4 --headless --path . --log-file "$SCRIPT_DIR/.godot_run_generation.log" \
	--script res://tools/run_generation.gd -- --seed "$SEED" --theme "$THEME"
