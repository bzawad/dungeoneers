#!/usr/bin/env bash
# Headless: client1 clears first treasure; client2 joins and verifies merged grid (late-join patch replay).
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

TMP="${TMPDIR:-/tmp}/dng_smoke_lj_$$"
mkdir -p "$TMP"
SEED=42
PORT="$(pick_free_port)"

godot4 --headless --path . --server Main.tscn --server-exit-after 55 --seed "$SEED" --theme up --port "$PORT" --no-fog 2>&1 | tee "$TMP/srv.log" &
SRV=$!

ready=0
for _ in $(seq 1 120); do
	if grep -qF "ENet server listening on ${PORT}" "$TMP/srv.log" 2>/dev/null; then
		ready=1
		break
	fi
	if grep -qF "Couldn't create an ENet host" "$TMP/srv.log" 2>/dev/null ||
		grep -qF "stub server: create_server failed" "$TMP/srv.log" 2>/dev/null; then
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

godot4 --headless --path . --client --ip 127.0.0.1 --headless --client-label c1 --port "$PORT" --no-fog --smoke-treasure-probe Main.tscn 2>&1 | tee "$TMP/c1.log" &
C1=$!
wait "$C1" || true

if ! grep -qF "treasure_dismiss peer_id=" "$TMP/srv.log"; then
	wait "$SRV" || true
	echo "ERROR: expected server log treasure_dismiss after client1 ($TMP/srv.log)" >&2
	exit 1
fi

sleep 0.4

godot4 --headless --path . --client --ip 127.0.0.1 --headless --client-label c2 --port "$PORT" --role fighter --no-fog --smoke-late-join-tile-probe Main.tscn 2>&1 | tee "$TMP/c2.log" &
C2=$!
ec2=0
wait "$C2" || ec2=$?
wait "$SRV" || true

if [[ "$ec2" -ne 0 ]]; then
	echo "ERROR: client2 exit $ec2" >&2
	exit 1
fi

if ! grep -qF "late_join_tile_probe ok" "$TMP/c2.log"; then
	echo "ERROR: expected client2 log late_join_tile_probe ok ($TMP/c2.log)" >&2
	exit 1
fi

if ! grep -qF "late_join_replay_patches" "$TMP/srv.log"; then
	echo "ERROR: expected server log late_join_replay_patches ($TMP/srv.log)" >&2
	exit 1
fi

echo "smoke_late_join_tile: OK (port=$PORT)"
rm -rf "$TMP"
exit 0
