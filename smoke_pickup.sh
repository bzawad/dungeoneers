#!/usr/bin/env bash
# Headless: server + client; path-move to a torch/food/potion cell and pickup_dismiss (Phase 5.7).
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

TMP="${TMPDIR:-/tmp}/dng_smoke_pk_$$"
mkdir -p "$TMP"
PORT="$(pick_free_port)"
FOUND=0

for SEED in 42 0 1 2 3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71 73 79 83 89 97; do
	rm -f "$TMP/srv.log" "$TMP/cli.log"
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
			break
		fi
		sleep 0.05
	done
	if [[ "$ready" -ne 1 ]]; then
		kill "$SRV" 2>/dev/null || true
		wait "$SRV" 2>/dev/null || true
		PORT="$(pick_free_port)"
		continue
	fi

	godot4 --headless --path . --client --ip 127.0.0.1 --headless --port "$PORT" --no-fog --seed "$SEED" --smoke-pickup-probe Main.tscn 2>&1 | tee "$TMP/cli.log"
	CLI=$?
	wait "$SRV" 2>/dev/null || true

	if [[ "$CLI" -ne 0 ]]; then
		PORT="$(pick_free_port)"
		continue
	fi

	if grep -qE 'food_pickup peer_id=|healing_potion_pickup peer_id=|torch_pickup peer_id=' "$TMP/srv.log" 2>/dev/null; then
		FOUND=1
		echo "smoke_pickup: OK (port=$PORT seed=$SEED)"
		rm -rf "$TMP"
		exit 0
	fi
	PORT="$(pick_free_port)"
done

echo "ERROR: no seed produced a reachable pickup + dismiss in server log ($TMP)" >&2
exit 1
