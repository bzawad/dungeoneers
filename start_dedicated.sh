#!/bin/bash
# GUI or headless dedicated host (P7-10). Same networking as Main.tscn --server; default: no auto-exit.
# Pattern: gama/start_server.sh + dungeoneers/start_server.sh (CLI uses Main.tscn).
#
# Usage:
#   ./start_dedicated.sh
#   ./start_dedicated.sh -- --headless --server-exit-after 120 --seed 42 --theme up --port 12345
#   ./start_dedicated.sh -- --headless --metrics-interval-sec 30 --metrics-file /tmp/dng_metrics.log
#
# Connect clients with: ./start_client.sh <host> <role>  (still uses Main.tscn --client)

echo "Starting Dungeoneers dedicated server scene..."

if ! command -v godot4 &> /dev/null; then
	echo "ERROR: godot4 not found. Run ./setup_cli.sh first."
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

EXTRA_GODOT_ARGS=()
if [[ "${1:-}" == "--" ]]; then
	shift
	EXTRA_GODOT_ARGS=("$@")
fi

exec godot4 --path . DedicatedServer.tscn "${EXTRA_GODOT_ARGS[@]}"
