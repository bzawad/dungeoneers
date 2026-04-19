#!/usr/bin/env bash
# Regenerate dungeoneers/dungeon/data/monsters.csv from Explorer `Dungeon.Monster.all_monsters/0`
# (source of truth: dungeon_explorer/lib/dungeon/monster.ex). Requires `mix` on PATH.
# Post-step: inserts **Kobold Slinger** if absent (referenced in themes.json but not in Elixir list).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DNG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPLORER="$(cd "$DNG_ROOT/../dungeon_explorer" && pwd)"
OUT="$DNG_ROOT/dungeon/data/monsters.csv"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if ! command -v mix &>/dev/null; then
	echo "ERROR: mix not found (install Elixir / run from dev env)." >&2
	exit 1
fi

(
	cd "$EXPLORER"
	mix run --no-start -e '
hdr = "name,image,armor_class,hit_points,attack_bonus,damage_dice,weapon,treasure,rarity,size,role,hunts_player,challenge_rating,alignment"
IO.puts(hdr)
for m <- Dungeon.Monster.all_monsters() do
  treas = m.treasure |> case do; nil -> ""; x -> to_string(x); end
  role = m.role |> case do; nil -> ""; x -> to_string(x); end
  hunts = if m.hunts_player?, do: "1", else: "0"
  rarity = m.rarity |> to_string() |> String.trim_leading(":")
  align = m.alignment |> to_string() |> String.trim_leading(":")
  line = Enum.join([m.name, m.image, m.armor_class, m.hit_points, m.attack_bonus, m.damage_dice, m.weapon, treas, rarity, m.size, role, hunts, m.challenge_rating, align], ",")
  IO.puts(line)
end
'
) >"$TMP"

/usr/bin/python3 - "$TMP" "$OUT" <<'PY'
import sys
from pathlib import Path

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
lines = src.read_text().splitlines()
slinger = "Kobold Slinger,kobold_spearman.png,11,4,2,1d4,Sling,1d4,common,0.75,,1,1,chaotic"
if any(l.startswith("Kobold Slinger,") for l in lines):
    dst.write_text("\n".join(lines) + "\n")
    sys.exit(0)
out: list[str] = []
inserted = False
for line in lines:
    out.append(line)
    if line.startswith("Kobold Spearman,") and not inserted:
        out.append(slinger)
        inserted = True
if not inserted:
    raise SystemExit("Kobold Spearman row not found; cannot insert Kobold Slinger")
dst.write_text("\n".join(out) + "\n")
PY

echo "Wrote $OUT"
