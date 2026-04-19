#!/usr/bin/env bash
# Automated smoke: one headless server + two headless clients, same checksum, distinct player_id.
# Uses a free TCP port (not 12345) so this script does not collide with ./start_server.sh or editors.
# Usage: ./smoke_two_clients.sh
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

TMP="${TMPDIR:-/tmp}/dng_smoke_$$"
mkdir -p "$TMP"
SEED=90909
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
		grep -qF "stub server: create_server failed" "$TMP/srv.log" 2>/dev/null; then
		wait "$SRV" || true
		echo "ERROR: server could not bind ENet (see $TMP/srv.log). Port was ${PORT}." >&2
		exit 1
	fi
	if ! kill -0 "$SRV" 2>/dev/null; then
		wait "$SRV" || true
		echo "ERROR: server exited before listen. Log: $TMP/srv.log" >&2
		head -40 "$TMP/srv.log" >&2 || true
		exit 1
	fi
	sleep 0.05
done

if [[ "$ready" -ne 1 ]]; then
	echo "ERROR: timeout waiting for ENet listen on port ${PORT} ($TMP/srv.log)" >&2
	kill "$SRV" 2>/dev/null || true
	exit 1
fi

godot4 --headless --path . --client --ip 127.0.0.1 --headless --client-label c1 --port "$PORT" --role rogue Main.tscn 2>&1 | tee "$TMP/c1.log" &
C1=$!
sleep 0.35
godot4 --headless --path . --client --ip 127.0.0.1 --headless --client-label c2 --port "$PORT" --role fighter Main.tscn 2>&1 | tee "$TMP/c2.log" &
C2=$!

ec1=0
ec2=0
wait "$C1" || ec1=$?
wait "$C2" || ec2=$?
wait "$SRV" || true

if [[ "$ec1" -ne 0 ]] || [[ "$ec2" -ne 0 ]]; then
	echo "ERROR: client exit c1=$ec1 c2=$ec2 (server log: $TMP/srv.log)" >&2
	exit 1
fi

chk_srv=$(grep "Server authority dungeon" "$TMP/srv.log" | head -1 | sed -e 's/.*checksum=//' -e 's/ .*//' || true)
chk_c1=$(grep "replicated dungeon" "$TMP/c1.log" | head -1 | sed -e 's/.*checksum=//' -e 's/ .*//' || true)
chk_c2=$(grep "replicated dungeon" "$TMP/c2.log" | head -1 | sed -e 's/.*checksum=//' -e 's/ .*//' || true)

id_c1=$(grep "player_id=" "$TMP/c1.log" | head -1 | sed -e 's/.*player_id=//' -e 's/ .*//' || true)
id_c2=$(grep "player_id=" "$TMP/c2.log" | head -1 | sed -e 's/.*player_id=//' -e 's/ .*//' || true)

if [[ -z "$chk_srv" ]] || [[ -z "$chk_c1" ]] || [[ -z "$chk_c2" ]]; then
	echo "ERROR: could not parse checksums (srv=$chk_srv c1=$chk_c1 c2=$chk_c2)" >&2
	exit 1
fi

if [[ "$chk_srv" != "$chk_c1" ]] || [[ "$chk_srv" != "$chk_c2" ]]; then
	echo "ERROR: checksum mismatch srv=$chk_srv c1=$chk_c1 c2=$chk_c2" >&2
	exit 1
fi

if [[ -z "$id_c1" ]] || [[ -z "$id_c2" ]] || [[ "$id_c1" == "$id_c2" ]]; then
	echo "ERROR: expected distinct player_id (c1=$id_c1 c2=$id_c2)" >&2
	exit 1
fi

if ! grep -q "role=rogue" "$TMP/c1.log" 2>/dev/null; then
	echo "ERROR: client c1 expected welcome role rogue in log" >&2
	exit 1
fi
if ! grep -q "role=fighter" "$TMP/c2.log" 2>/dev/null; then
	echo "ERROR: client c2 expected welcome role fighter in log" >&2
	exit 1
fi

slot_c1=$(grep "assigned_slot=" "$TMP/c1.log" | head -1 | sed -e 's/.*assigned_slot=//' -e 's/ .*//' || true)
slot_c2=$(grep "assigned_slot=" "$TMP/c2.log" | head -1 | sed -e 's/.*assigned_slot=//' -e 's/ .*//' || true)
if [[ "$slot_c1" != "0" ]] || [[ "$slot_c2" != "1" ]]; then
	echo "ERROR: expected assigned_slot c1=0 c2=1 (got c1=$slot_c1 c2=$slot_c2)" >&2
	exit 1
fi

echo "smoke_two_clients: OK (port=$PORT checksum=$chk_srv player_id c1=$id_c1 c2=$id_c2 slots c1=$slot_c1 c2=$slot_c2)"
rm -rf "$TMP"
exit 0
