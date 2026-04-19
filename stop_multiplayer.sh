#!/bin/bash
# Stop Dungeoneers Godot processes for this project directory (pattern from gama/stop_multiplayer.sh).

echo "Stopping Dungeoneers Godot processes..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

kill_from_pidfile() {
	local file=$1
	local label=$2
	if [ -f "$file" ]; then
		local pid
		pid=$(tr -d ' \n\r' <"$file")
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			echo "Stopping $label (PID $pid)..."
			kill "$pid" 2>/dev/null || true
			sleep 1
			kill -9 "$pid" 2>/dev/null || true
		fi
		rm -f "$file"
	fi
}

kill_from_pidfile .server_pid "server (pidfile)"
kill_from_pidfile .client_pid "client (pidfile)"

# Fallback: any godot4 whose command line references this project path
for pid in $(pgrep godot4 2>/dev/null || true); do
	cmd=$(ps -p "$pid" -o command= 2>/dev/null || true)
	if echo "$cmd" | grep -q "$SCRIPT_DIR"; then
		echo "Stopping Godot PID $pid (matched project path)"
		kill "$pid" 2>/dev/null || true
	fi
done

sleep 1
echo "Stop script finished."
