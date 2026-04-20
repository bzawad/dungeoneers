#!/bin/bash
# Start headless server plus N clients (pattern from gama/start_multiplayer.sh).
# Usage: ./start_multiplayer.sh [num_clients] [host]
#
# Logs: each client prints my_peer_id=… then Client replicated … checksum=… player_id=…
# (distinct player_id per client). Server logs Sent authority dungeon to peer_id=…

echo "Starting Dungeoneers multiplayer test environment..."

if ! command -v godot4 &> /dev/null; then
	echo "ERROR: godot4 not found. Run ./setup_cli.sh first."
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NUM_CLIENTS=${1:-1}
HOST=${2:-"localhost"}

if ! [[ "$NUM_CLIENTS" =~ ^[1-9][0-9]*$ ]] || [ "$NUM_CLIENTS" -gt 10 ]; then
	echo "ERROR: num_clients must be 1-10"
	echo "Usage: ./start_multiplayer.sh [num_clients] [host]"
	exit 1
fi

# Fixed seed + long window so every client in this session sees the same dungeon.
./start_server.sh -- --seed 4242 --theme up --server-exit-after 120 &
SERVER_SCRIPT_PID=$!
sleep 2

if ! kill -0 "$SERVER_SCRIPT_PID" 2>/dev/null; then
	echo "ERROR: server loop failed to start"
	exit 1
fi

CLIENT_PIDS=()
for i in $(seq 1 "$NUM_CLIENTS"); do
	echo "Starting client $i/$NUM_CLIENTS..."
	godot4 --path . --client --ip "$HOST" --role rogue Main.tscn &
	CLIENT_PID=$!
	sleep 1
	if ! kill -0 "$CLIENT_PID" 2>/dev/null; then
		echo "ERROR: failed to start client $i"
		kill "$SERVER_SCRIPT_PID" 2>/dev/null || true
		for pid in "${CLIENT_PIDS[@]}"; do
			kill "$pid" 2>/dev/null || true
		done
		exit 1
	fi
	CLIENT_PIDS+=("$CLIENT_PID")
	echo "Client $i PID: $CLIENT_PID"
done

echo ""
echo "Server loop PID: $SERVER_SCRIPT_PID"
echo "Client PIDs: ${CLIENT_PIDS[*]}"
echo "Press Ctrl+C to stop; or run ./stop_multiplayer.sh in another terminal"

cleanup() {
	echo ""
	echo "Stopping multiplayer test..."
	kill "$SERVER_SCRIPT_PID" 2>/dev/null || true
	sleep 1
	kill -9 "$SERVER_SCRIPT_PID" 2>/dev/null || true
	for pid in "${CLIENT_PIDS[@]}"; do
		kill "$pid" 2>/dev/null || true
	done
	rm -f .server_pid .client_pid
	exit 0
}

trap cleanup SIGINT SIGTERM

while true; do
	if ! kill -0 "$SERVER_SCRIPT_PID" 2>/dev/null; then
		echo "Server loop ended"
		break
	fi
	for pid in "${CLIENT_PIDS[@]}"; do
		if ! kill -0 "$pid" 2>/dev/null; then
			echo "A client process ended"
			break 2
		fi
	done
	sleep 3
done

cleanup
