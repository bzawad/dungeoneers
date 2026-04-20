#!/usr/bin/env bash
# Headless: server + client; path-move onto trapped_treasure + adjacent room_trap probes (`--smoke-trap-move-probe`).
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

TMP="${TMPDIR:-/tmp}/dng_smoke_trapmv_$$"
mkdir -p "$TMP"
## Seed 0 reliably includes `trapped_treasure` on legacy `up` maps (see `tools/run_generation.gd` JSON).
SEED=0
PORT="$(pick_free_port)"

godot4 --headless --path . --server Main.tscn --server-exit-after 28 --seed "$SEED" --theme up --port "$PORT" --no-fog 2>&1 | tee "$TMP/srv.log" &
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

godot4 --headless --path . --client --ip 127.0.0.1 --headless --port "$PORT" --no-fog --smoke-trap-move-probe Main.tscn 2>&1 | tee "$TMP/cli.log"
CLI=$?
wait "$SRV" || true

if [[ "$CLI" -ne 0 ]]; then
	echo "ERROR: client exit $CLI" >&2
	exit 1
fi

if ! grep -qF "trap_move_probe finished phase=" "$TMP/cli.log"; then
	echo "ERROR: expected client log 'trap_move_probe finished phase=' ($TMP/cli.log)" >&2
	exit 1
fi

if ! grep -qF "room_trap_adj_move_probe finished phase=" "$TMP/cli.log"; then
	echo "ERROR: expected client log 'room_trap_adj_move_probe finished phase=' ($TMP/cli.log)" >&2
	exit 1
fi

echo "smoke_trap_move: OK (port=$PORT)"
rm -rf "$TMP"
exit 0
