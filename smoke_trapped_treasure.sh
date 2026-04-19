#!/usr/bin/env bash
# Headless: server + client; resolve first trapped_treasure cell (detect flow + loot).
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v godot4 &>/dev/null; then
	echo "ERROR: godot4 not found"
	exit 1
fi

pick_free_port() {
	if command -v /usr/bin/python3 &>/dev/null; then
		/usr/bin/python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()"
	else
		echo $((20000 + RANDOM % 45000))
	fi
}

find_seed_with_trapped() {
	local s
	for s in $(seq 1 800); do
		local line
		line="$(godot4 --headless --path . --script res://tools/run_generation.gd -- --seed "$s" --theme up 2>/dev/null | tail -1)"
		if echo "$line" | grep -q '"has_trapped_treasure":true'; then
			echo "$s"
			return 0
		fi
	done
	return 1
}

SEED="$(find_seed_with_trapped || true)"
if [[ -z "${SEED}" ]]; then
	echo "ERROR: no seed 1..800 produced trapped_treasure (run_generation has_trapped_treasure)" >&2
	exit 1
fi

TMP="${TMPDIR:-/tmp}/dng_smoke_ttr_$$"
mkdir -p "$TMP"
PORT="$(pick_free_port)"

godot4 --headless --path . --server Main.tscn --server-exit-after 30 --seed "$SEED" --theme up --port "$PORT" --no-fog 2>&1 | tee "$TMP/srv.log" &
SRV=$!

ready=0
for _ in $(seq 1 120); do
	if grep -qF "ENet server listening on ${PORT}" "$TMP/srv.log" 2>/dev/null; then
		ready=1
		break
	fi
	if ! kill -0 "$SRV" 2>/dev/null; then
		wait "$SRV" || true
		echo "ERROR: server exited early ($TMP/srv.log)" >&2
		exit 1
	fi
	sleep 0.05
done
if [[ "$ready" -ne 1 ]]; then
	kill "$SRV" 2>/dev/null || true
	echo "ERROR: server listen timeout port=$PORT" >&2
	exit 1
fi

godot4 --headless --path . --client --ip 127.0.0.1 --headless --port "$PORT" --no-fog --smoke-trapped-treasure-probe Main.tscn 2>&1 | tee "$TMP/cli.log"
CLI=$?
wait "$SRV" || true

if [[ "$CLI" -ne 0 ]]; then
	echo "ERROR: client exit $CLI" >&2
	exit 1
fi

if ! grep -qE "trapped_treasure_undetected_ack|treasure_trap_disarm_(success|fail)" "$TMP/srv.log"; then
	echo "ERROR: expected trapped treasure trap resolution in server log ($TMP/srv.log)" >&2
	exit 1
fi

if ! grep -qF "treasure_dismiss peer_id=" "$TMP/srv.log"; then
	echo "ERROR: expected treasure_dismiss after trap resolution ($TMP/srv.log)" >&2
	exit 1
fi

echo "smoke_trapped_treasure: OK (port=$PORT seed=$SEED)"
rm -rf "$TMP"
exit 0
