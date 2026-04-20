#!/usr/bin/env bash
# Phase 3: headless DedicatedServer.tscn + one client; welcome schema 9 + listen_port echoed in client log.
# Usage: ./smoke_dedicated_server.sh
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

TMP="${TMPDIR:-/tmp}/dng_smoke_dedicated_$$"
mkdir -p "$TMP"
SEED=70707
PORT="$(pick_free_port)"

godot4 --headless --path . DedicatedServer.tscn -- \
	--headless \
	--server-exit-after 22 \
	--seed "$SEED" \
	--theme up \
	--port "$PORT" \
	--metrics-interval-sec 5 \
	2>&1 | tee "$TMP/srv.log" &
SRV=$!

ready=0
for _ in $(seq 1 120); do
	if grep -qF "ENet server listening on ${PORT}" "$TMP/srv.log" 2>/dev/null; then
		ready=1
		break
	fi
	if grep -qE "minimal server: create_server failed|Couldn't create an ENet host" "$TMP/srv.log" 2>/dev/null; then
		wait "$SRV" || true
		echo "ERROR: dedicated server could not bind port ${PORT}" >&2
		exit 1
	fi
	if ! kill -0 "$SRV" 2>/dev/null; then
		wait "$SRV" || true
		echo "ERROR: dedicated server exited before listen" >&2
		head -40 "$TMP/srv.log" >&2 || true
		exit 1
	fi
	sleep 0.05
done

if [[ "$ready" -ne 1 ]]; then
	echo "ERROR: timeout waiting for dedicated listen on ${PORT}" >&2
	kill "$SRV" 2>/dev/null || true
	exit 1
fi

godot4 --headless --path . --client --ip 127.0.0.1 --headless --client-label dedicated_c1 --port "$PORT" --role rogue Main.tscn 2>&1 | tee "$TMP/c1.log" &
C1=$!
wait "$C1" || true
wait "$SRV" || true

if ! grep -qF "listen_port=${PORT}" "$TMP/c1.log" 2>/dev/null; then
	echo "ERROR: client log missing listen_port=${PORT} (welcome schema 9)" >&2
	exit 1
fi

if ! grep -qF "party_peer_count=1" "$TMP/c1.log" 2>/dev/null; then
	echo "ERROR: client log missing party_peer_count=1" >&2
	exit 1
fi

if ! grep -qF "dungeoneers_host peers=" "$TMP/srv.log" 2>/dev/null; then
	echo "ERROR: dedicated server log missing metrics line (dungeoneers_host)" >&2
	exit 1
fi

echo "smoke_dedicated_server: OK (port=$PORT)"
rm -rf "$TMP"
exit 0
