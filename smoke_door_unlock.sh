#!/usr/bin/env bash
# Headless: server + client with --smoke-door-unlock-probe (adjacent locked door: move fail → unlock → move ok, or skip).
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v godot4 &>/dev/null; then
	echo "ERROR: godot4 not found"
	exit 1
fi

pick_free_port() {
	if command -v python3 &>/dev/null; then
		python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()"
	else
		echo $((20000 + RANDOM % 45000))
	fi
}

TMP="${TMPDIR:-/tmp}/dng_smoke_door_$$"
mkdir -p "$TMP"
# Picked by `godot4 --headless --path . --script res://tools/find_adjacent_locked_door_seed.gd` (spawn has ortho locked door).
SEED=45
PORT="$(pick_free_port)"

godot4 --headless --path . --server Main.tscn --server-exit-after 25 --seed "$SEED" --theme up --port "$PORT" 2>&1 | tee "$TMP/srv.log" &
SRV=$!

ready=0
for _ in $(seq 1 120); do
	if grep -qF "ENet server listening on ${PORT}" "$TMP/srv.log" 2>/dev/null; then
		ready=1
		break
	fi
	if grep -qF "Couldn't create an ENet host" "$TMP/srv.log" 2>/dev/null ||
		grep -qF "minimal server: create_server failed" "$TMP/srv.log" 2>/dev/null; then
		wait "$SRV" || true
		echo "ERROR: server bind failed (see $TMP/srv.log)" >&2
		exit 1
	fi
	if ! kill -0 "$SRV" 2>/dev/null; then
		wait "$SRV" || true
		echo "ERROR: server exited early ($TMP/srv.log)" >&2
		exit 1
	fi
	sleep 0.05
done
if [[ "$ready" -ne 1 ]]; then
	echo "ERROR: server listen timeout port=$PORT" >&2
	kill "$SRV" 2>/dev/null || true
	exit 1
fi

godot4 --headless --path . --client --ip 127.0.0.1 --headless --port "$PORT" --smoke-door-unlock-probe Main.tscn 2>&1 | tee "$TMP/cli.log"
CLI=$?
wait "$SRV" || true

if [[ "$CLI" -ne 0 ]]; then
	echo "ERROR: client exit $CLI" >&2
	exit 1
fi

if ! grep -qF "move rejected: not walkable" "$TMP/srv.log"; then
	echo "ERROR: expected blocked move onto locked door ($TMP/srv.log)" >&2
	exit 1
fi

if ! grep -qF "door unlock accepted" "$TMP/srv.log"; then
	echo "ERROR: expected server log 'door unlock accepted' ($TMP/srv.log)" >&2
	exit 1
fi

if ! grep -qF "move accepted" "$TMP/srv.log"; then
	echo "ERROR: expected at least one 'move accepted' on server ($TMP/srv.log)" >&2
	exit 1
fi

echo "smoke_door_unlock: OK (port=$PORT)"
rm -rf "$TMP"
exit 0
