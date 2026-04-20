#!/bin/bash
# Headless ENet listen server with auto-restart (same pattern as gama/start_server.sh).
# Usage: ./start_server.sh
# Optional extra Godot args for Main.tscn (after --server is already set):
#   ./start_server.sh -- --seed 42 --theme up --server-exit-after 120

echo "Starting Dungeoneers headless listen server with auto-restart..."

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

RESTART_COUNT=0
STOP_REQUESTED=false

cleanup() {
	echo ""
	echo "Stopping headless server loop..."
	STOP_REQUESTED=true
	if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
		kill "$SERVER_PID" 2>/dev/null || true
		sleep 1
		kill -9 "$SERVER_PID" 2>/dev/null || true
	fi
	rm -f .server_pid
	echo "Games served in this session: $RESTART_COUNT"
	exit 0
}

trap cleanup SIGINT SIGTERM

while [ "$STOP_REQUESTED" = false ]; do
	RESTART_COUNT=$((RESTART_COUNT + 1))
	echo ""
	echo "Starting game #$RESTART_COUNT (listen server)..."

	godot4 --path . --headless --server Main.tscn "${EXTRA_GODOT_ARGS[@]}" &
	SERVER_PID=$!
	echo "$SERVER_PID" >.server_pid
	echo "Server PID: $SERVER_PID"

	wait "$SERVER_PID" 2>/dev/null
	EXIT_CODE=$?
	rm -f .server_pid

	if [ "$EXIT_CODE" -eq 0 ]; then
		echo "Game #$RESTART_COUNT exited 0; restarting..."
		sleep 1
	else
		echo "Server stopped with exit code $EXIT_CODE; not auto-restarting."
		exit "$EXIT_CODE"
	fi
done
