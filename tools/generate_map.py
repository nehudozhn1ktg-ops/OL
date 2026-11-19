"""Генератор симметричных карт по правилам владельца (ADR-014).

Правила карты:
- у каждого игрока свой флаг, флаги симметричны;
- вокруг флага 6 клеток «лагерь» (соседи флага), заняты стартовыми фигурами;
- ключевых точек столько же, сколько игроков; каждая равноудалена от игроков;
- остальной террейн (трава/лес/укрепление/вода) симметричен, но случаен.

Использование:
  python tools/generate_map.py --players 2 --radius 7 --seed 42 --out sym-1x1.json
  python tools/generate_map.py --check <map.json>   # проверить симметрию

Выход — JSON в формате Board.load_map: {"name", "hex_size", "cells": [{"q","r","t"}]}.
"""

import argparse
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "maps" / "data"

DIRECTIONS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]

TERRAIN_GRASS = "grass"
TERRAIN_WATER = "water"
TERRAIN_FOREST = "forest"
TERRAIN_FORT = "fort"
TERRAIN_KEY = "key"
TERRAIN_FLAG = "flag"
TERRAIN_CAMP = "camp"

# Доли случайного террейна (кроме травы). Сумма < 1, остаток — трава.
TERRAIN_WEIGHTS = [
    (TERRAIN_FOREST, 0.20),
    (TERRAIN_FORT, 0.12),
    (TERRAIN_WATER, 0.08),
]


def hdist(a, b):
    dq = a[0] - b[0]
    dr = a[1] - b[1]
    ds = (-a[0] - a[1]) - (-b[0] - b[1])
    return (abs(dq) + abs(dr) + abs(ds)) // 2


def neighbors(q, r):
    return [(q + dq, r + dr) for dq, dr in DIRECTIONS]


def disk(radius):
    cells = []
    for q in range(-radius, radius + 1):
        r0 = max(-radius, -q - radius)
        r1 = min(radius, -q + radius)
        for r in range(r0, r1 + 1):
            cells.append((q, r))
    return cells


def reflection_2p(q, r):
    """Точечная симметрия (180°) вокруг начала координат — для 2 игроков."""
    return (-q, -r)


def place_flags_2p(f):
    """Флаги двух игроков на вертикальной оси, на расстоянии 2f друг от друга."""
    return [(0, -f), (0, f)]


def equidistant_cells(cells, flags):
    """Клетки, равноудалённые от всех флагов: (coord, distance)."""
    result = []
    for c in cells:
        ds = [hdist(c, flag) for flag in flags]
        if len(set(ds)) == 1:
            result.append((c, ds[0]))
    return result


def symmetric_pairs(cells, flags):
    """Разбивает равноудалённые клетки на зеркальные пары (для 2 игроков)."""
    mirror = {}
    for c, d in cells:
        m = reflection_2p(c[0], c[1])
        if c != m:
            mirror[c] = m
    # группируем по расстоянию
    by_dist = {}
    for c, d in cells:
        by_dist.setdefault(d, []).append(c)
    return by_dist, mirror


def generate(players, radius, f, key_distance, seed, rng):
    cells = disk(radius)
    board = {c: None for c in cells}

    flags = place_flags_2p(f)
    for flag in flags:
        board[flag] = TERRAIN_FLAG

    # лагеря — 6 соседей каждого флага
    camp_cells = []
    for flag in flags:
        for nb in neighbors(*flag):
            if nb in board and board[nb] is None:
                board[nb] = TERRAIN_CAMP
                camp_cells.append(nb)

    # ключевые точки — равноудалены от обоих флагов, зеркально
    eq = equidistant_cells([c for c in cells if board[c] is None], flags)
    by_dist, mirror = symmetric_pairs(eq, flags)
    key_cells = _pick_keys(by_dist, mirror, key_distance, players)
    for kc in key_cells:
        board[kc] = TERRAIN_KEY

    # остальной террейн — симметрично, случайно
    _fill_symmetric_terrain(board, rng)

    return board, flags, camp_cells, key_cells


def _pick_keys(by_dist, mirror, key_distance, players):
    """Берёт players/2 зеркальных пар равноудалённых клеток на целевом расстоянии."""
    if not by_dist:
        return []
    target = key_distance
    if target not in by_dist:
        # ближайшее доступное расстояние
        target = min(by_dist.keys(), key=lambda d: abs(d - key_distance))
    candidates = by_dist[target]
    pairs = []
    used = set()
    for c in candidates:
        if c in used:
            continue
        m = mirror.get(c)
        if m is None:
            continue
        if m in candidates:
            pairs.append((c, m))
            used.add(c)
            used.add(m)
    result = []
    for c, m in pairs[: players // 2]:
        result.extend([c, m])
    return result


def _fill_symmetric_terrain(board, rng):
    """Террейн ставится парами зеркальных клеток — карта остаётся симметричной."""
    remaining = [c for c, t in board.items() if t is None]
    handled = set()
    for c in remaining:
        if c in handled:
            continue
        m = reflection_2p(c[0], c[1])
        handled.add(c)
        terrain = _random_terrain(rng)
        board[c] = terrain
        if m in board and m != c:
            board[m] = terrain
            handled.add(m)


def _random_terrain(rng):
    roll = rng.random()
    acc = 0.0
    for terrain, weight in TERRAIN_WEIGHTS:
        acc += weight
        if roll < acc:
            return terrain
    return TERRAIN_GRASS


def to_json(name, board, hex_size=84.0):
    cells = []
    for (q, r), t in sorted(board.items()):
        cells.append({"q": q, "r": r, "t": t})
    return {"name": name, "hex_size": hex_size, "cells": cells}


def check_symmetry(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    cells = {(c["q"], c["r"]): c["t"] for c in data["cells"]}
    flags = [c for c, t in cells.items() if t == TERRAIN_FLAG]
    # симметрия по точке отражения между двумя первыми флагами (для 2 игроков)
    if len(flags) == 2:
        mid_q = (flags[0][0] + flags[1][0]) / 2.0
        mid_r = (flags[0][1] + flags[1][1]) / 2.0
        def mirror(q, r):
            return (round(2 * mid_q - q), round(2 * mid_r - r))
    else:
        # несколько флагов — точечная симметрия вокруг центра масс флагов
        mid_q = sum(f[0] for f in flags) / len(flags)
        mid_r = sum(f[1] for f in flags) / len(flags)
        def mirror(q, r):
            return (round(2 * mid_q - q), round(2 * mid_r - r))
    asym = []
    for (q, r), t in cells.items():
        m = mirror(q, r)
        mt = cells.get(m)
        if mt is None or mt != t:
            asym.append(((q, r), t, mt))
    return asym


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--players", type=int, default=2)
    ap.add_argument("--radius", type=int, default=7)
    ap.add_argument("--f", type=int, default=4, help="половина расстояния между флагами")
    ap.add_argument("--key-distance", type=int, default=5)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default="sym-1x1.json")
    ap.add_argument("--check", metavar="MAP.json", help="только проверить симметрию")
    args = ap.parse_args()

    if args.check:
        asym = check_symmetry(args.check)
        if asym:
            print("АСИММЕТРИЧНЫХ КЛЕТОК: %d" % len(asym))
            for item in asym[:20]:
                print("  ", item)
            sys.exit(1)
        print("Карта симметрична.")
        return

    if args.players != 2:
        print("пока поддерживается только 2 игрока")
        sys.exit(2)

    seed = args.seed if args.seed != 0 else random.randrange(2**31)
    rng = random.Random(seed)

    board, flags, camps, keys = generate(
        args.players, args.radius, args.f, args.key_distance, seed, rng)

    data = to_json(args.out.replace(".json", "").split("/")[-1] or "map", board)
    out_path = OUT_DIR / args.out if "/" not in args.out else Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")

    print("seed=%d флаги=%s лагеря=%d ключевые=%s" % (
        seed, flags, len(camps), keys))
    print("записано: %s (%d клеток)" % (out_path, len(board)))

    asym = check_symmetry(str(out_path))
    if asym:
        print("ВНИМАНИЕ: асимметричных клеток %d" % len(asym))
        sys.exit(1)
    print("симметрия подтверждена.")


if __name__ == "__main__":
    main()
