#!/bin/bash
# Start a GUI or headless-capable client (stub) against a local or remote server.
# Usage: ./start_client.sh [host] [role]
#   host: default localhost
#   role: default rogue (reserved for future classes)

echo "Starting Dungeoneers client..."

if ! command -v godot4 &> /dev/null; then
	echo "ERROR: godot4 not found. Run ./setup_cli.sh first."
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SERVER_IP=${1:-"localhost"}
ROLE=${2:-"rogue"}

echo "Connecting to $SERVER_IP as role=$ROLE"

godot4 --path . --client --ip "$SERVER_IP" --role "$ROLE" Main.tscn &
CLIENT_PID=$!
sleep 1

if ! kill -0 "$CLIENT_PID" 2>/dev/null; then
	echo "ERROR: client failed to start"
	exit 1
fi

echo "$CLIENT_PID" >.client_pid
echo "Client PID: $CLIENT_PID (kill or use ./stop_multiplayer.sh)"

trap 'echo ""; echo "Client: $(kill -0 "$CLIENT_PID" 2>/dev/null && echo Running || echo Stopped)"' EXIT

while kill -0 "$CLIENT_PID" 2>/dev/null; do
	sleep 2
done

echo "Client process ended"
