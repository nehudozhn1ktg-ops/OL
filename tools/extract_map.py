"""Распознавание раскладки карт OneLife по картинке.

Ключевая идея: у настоящего гекса по периметру есть тёмная обводка. Поэтому
клетка считается настоящей, только если в 6 точках на грани (радиус 0.87*s)
пиксели заметно темнее её основания. Это отсекает фон, рамку и «коврик»
вокруг поля, не полагаясь на цвет фона.

Дальше тип террейна определяется по основанию (медиана) и доле тёмных
пикселей — иконке (деревья, башни, гора). Трава — единственный террейн
без иконки.

Запуск: python extract_map.py 1x1x1 [--stats]
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
MAPS_DIR = ROOT / "assets" / "maps"
OUT_DIR = MAPS_DIR / "data"

TERRAIN_COLORS = {
    "grass": (140, 170, 80),
    "water": (70, 150, 210),
    "forest": (25, 70, 25),
    "fort": (230, 140, 40),
    "key": (150, 60, 200),
    "flag": (240, 225, 40),
    "camp": (200, 40, 30),
}

NEIGHBORS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]


def rgb_to_hsv(arr: np.ndarray) -> np.ndarray:
    a = arr.astype(np.float32) / 255.0
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = a.max(axis=-1)
    mn = a.min(axis=-1)
    diff = mx - mn
    h = np.zeros_like(mx)
    mask = diff > 1e-6
    idx = (mx == r) & mask
    h[idx] = ((g[idx] - b[idx]) / diff[idx]) % 6
    idx = (mx == g) & mask
    h[idx] = (b[idx] - r[idx]) / diff[idx] + 2
    idx = (mx == b) & mask
    h[idx] = (r[idx] - g[idx]) / diff[idx] + 4
    h = h * 60.0
    s = np.where(mx > 1e-6, diff / np.maximum(mx, 1e-6), 0.0)
    return np.stack([h, s, mx], axis=-1)


def find_top_hex(hsv: np.ndarray):
    """Верхняя кромка верхнего гекса: длина кромки flat-top гекса равна радиусу.

    Верхний гекс бывает любого террейна (трава, лес, лагерь, флаг), поэтому
    маска берёт все «игровые» цвета и отбрасывает бежевый фон и тёмную рамку.
    """
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    terrain = (
        ((h >= 45) & (h <= 165)) |
        ((h >= 172) & (h <= 248)) |
        ((h >= 250) & (h <= 332)) |
        ((h >= 8) & (h <= 45) & (v > 0.42))
    ) & (s > 0.32) & (v > 0.34)
    height, width = terrain.shape
    x = width // 2
    for y in range(int(height * 0.04), int(height * 0.30)):
        row = terrain[y]
        xs = np.flatnonzero(row)
        if xs.size < 20:
            continue
        splits = np.split(xs, np.flatnonzero(np.diff(xs) > 3) + 1)
        containing = [r for r in splits if len(r) and r[0] <= x <= r[-1]]
        if not containing:
            continue
        run = containing[0]
        if 30 <= len(run) <= 220:
            return y, int(run[0]), int(run[-1])
    raise RuntimeError("не нашёл верхний гекс")


def fit_lattice(rgb: np.ndarray, size0: float, cx0: float, cy0: float):
    """Подгоняет размер и начало решётки так, чтобы клетки попадали на гексы.

    Меряем «качество посадки»: у настоящего гекса по 6 граням идёт тёмная
    обводка. Перебираем размер и смещения вокруг оценки сверху, максимизируем
    долю клеток, у которых обводка видна хотя бы с 4 сторон.
    """
    v = rgb.max(axis=2).astype(np.float32) / 255.0
    height, width = v.shape
    qs = np.arange(-10, 11)
    Q, R = np.meshgrid(qs, qs, indexing="ij")
    base_x = 1.5 * Q
    base_y = np.sqrt(3) * (R + Q / 2.0)
    dirs = [(np.cos(np.deg2rad(30 + 60 * i)), np.sin(np.deg2rad(30 + 60 * i))) for i in range(6)]
    radii = np.linspace(0.78, 1.02, 9)

    best_score = -1.0
    best = (size0, cx0, cy0)
    for size in np.arange(size0 - 6, size0 + 7, 1.0):
        for cx in np.arange(cx0 - 6, cx0 + 7, 2.0):
            for cy in np.arange(cy0 - 6, cy0 + 7, 1.5):
                X = cx + size * base_x
                Y = cy + size * base_y
                keep = (X > size) & (X < width - size) & (Y > size) & (Y < height - size)
                Xk, Yk = X[keep], Y[keep]
                if Xk.size < 50:
                    continue
                dark = np.zeros((Xk.size, 6), bool)
                for j, (dx, dy) in enumerate(dirs):
                    bestv = np.ones(Xk.size, np.float32)
                    for rr in radii:
                        xi = np.clip((Xk + dx * size * rr).astype(np.int32), 0, width - 1)
                        yi = np.clip((Yk + dy * size * rr).astype(np.int32), 0, height - 1)
                        bestv = np.minimum(bestv, v[yi, xi])
                    dark[:, j] = bestv < 0.28
                score = float(np.mean(dark.sum(axis=1) >= 4))
                if score > best_score:
                    best_score = score
                    best = (float(size), float(cx), float(cy))
    print(f"  подгонка решётки: размер={best[0]:.1f} центр=({best[1]:.1f},{best[2]:.1f}) посадка={best_score:.2f}")
    return best, best_score


def border_score(rgb: np.ndarray, cx: float, cy: float, size: float, base_v: float) -> int:
    """Сколько из 6 граней имеют тёмную обводку.

    Обводка тонкая, поэтому идём по радиусу и берём минимум яркости:
    так промах на пару пикселей не ломает проверку.
    """
    h, w = rgb.shape[:2]
    dark = 0
    for i in range(6):
        ang = np.deg2rad(30 + 60 * i)
        best = 1.0
        for k in range(9):
            radius = size * (0.78 + 0.03 * k)
            x = int(round(cx + np.cos(ang) * radius))
            y = int(round(cy + np.sin(ang) * radius))
            if not (0 <= x < w and 0 <= y < h):
                continue
            patch = rgb[max(0, y - 1):y + 2, max(0, x - 1):x + 2].astype(np.float32)
            best = min(best, float(patch.mean(axis=(0, 1)).max() / 255.0))
        if best < base_v * 0.78:
            dark += 1
    return dark


def hex_features(rgb: np.ndarray, cx: float, cy: float, size: float):
    h, w = rgb.shape[:2]
    r_in = size * 0.62
    xs = np.arange(int(cx - r_in), int(cx + r_in) + 1)
    ys = np.arange(int(cy - r_in), int(cy + r_in) + 1)
    xs = xs[(xs >= 0) & (xs < w)]
    ys = ys[(ys >= 0) & (ys < h)]
    if xs.size < 4 or ys.size < 4:
        return None
    patch = rgb[np.ix_(ys, xs)].astype(np.float32)
    yy, xx = np.mgrid[ys[0]:ys[-1] + 1, xs[0]:xs[-1] + 1]
    inside = ((xx - cx) ** 2 + (yy - cy) ** 2) <= r_in ** 2
    if inside.sum() < 40:
        return None
    pixels = patch[inside]
    # Иконка (деревья, башни, гора) тёмная и занимает центр. Основание террейна —
    # это самые светлые пиксели гекса, поэтому берём медиану верхних 45%.
    values = pixels.max(axis=1)
    threshold = np.percentile(values, 55)
    bright = pixels[values >= threshold]
    base = np.median(bright, axis=0)
    base_v = float(base.max() / 255.0)
    icon_frac = float(np.mean(values < np.percentile(values, 55) * 0.85))
    return base, icon_frac, base_v


def classify(h: float, s: float, v: float, icon_frac: float) -> str:
    if 175 <= h <= 245:
        return "water"
    if 250 <= h <= 330:
        return "key"
    if 40 <= h <= 72 and s > 0.55 and v > 0.55:
        return "flag"
    if icon_frac >= 0.10:
        if h < 20 or h >= 335:
            return "camp"
        if 20 <= h < 48:
            return "fort"
        if 48 <= h < 170:
            return "forest"
    return "grass"


def _cleanup(cells, rgb, size, cx0, cy0):
    """Убирает одиночек вне поля и закрывает дырки внутри поля.

    Клетка внутри поля почти всегда окружена соседями, а мусор снаружи —
    нет. Поэтому: у кого меньше двух соседей — выкидываем; пустое место,
    у которого четыре и более соседей, — добавляем.
    """
    coords = {(c["q"], c["r"]): c for c in cells}

    def neighbours(q, r):
        return sum(1 for dq, dr in NEIGHBORS if (q + dq, r + dr) in coords)

    dropped = [k for k in coords if neighbours(*k) <= 1]
    for k in dropped:
        del coords[k]

    # дырки: обходим решётку и смотрим на окружение
    added = 0
    height, width = rgb.shape[:2]
    for q in range(-18, 19):
        for r in range(-18, 19):
            if (q, r) in coords:
                continue
            if sum(1 for dq, dr in NEIGHBORS if (q + dq, r + dr) in coords) < 4:
                continue
            cx = cx0 + 1.5 * size * q
            cy = cy0 + np.sqrt(3) * size * (r + q / 2.0)
            if not (0 <= cx < width and 0 <= cy < height):
                continue
            got = hex_features(rgb, cx, cy, size)
            if got is None:
                continue
            base, icon_frac, base_v = got
            hh, ss, vv = rgb_to_hsv(base.reshape(1, 1, 3))[0, 0]
            terrain = classify(float(hh), float(ss), float(vv), icon_frac)
            coords[(q, r)] = {"q": q, "r": r, "t": terrain,
                              "_h": round(float(hh), 1), "_s": round(float(ss), 2),
                              "_v": round(float(vv), 2), "_icon": round(icon_frac, 3)}
            added += 1
    if dropped or added:
        print(f"  чистка: убрано {len(dropped)}, добавлено {added}")
    return list(coords.values())


def extract(name: str, stats: bool = False, min_border: int = 3):
    img = Image.open(MAPS_DIR / f"{name}.webp").convert("RGB")
    rgb = np.asarray(img)
    hsv = rgb_to_hsv(rgb)

    y_top, x0, x1 = find_top_hex(hsv)
    run_len = float(x1 - x0 + 1)
    cx0 = (x0 + x1) / 2.0
    cy0 = y_top + run_len * np.sqrt(3) / 2.0
    print(f"{name}: {rgb.shape[1]}x{rgb.shape[0]} кромка≈{run_len:.0f} центр верхнего≈({cx0:.0f},{cy0:.0f})")
    # соседние гексы одного цвета сливаются в одну кромку, поэтому верхняя
    # кромка может быть в 2-3 раза длиннее радиуса гекса
    best = None
    for divisor in (1, 2, 3):
        size_try = run_len / divisor
        if not (30 <= size_try <= 220):
            continue
        got, score = fit_lattice(rgb, size_try, cx0, cy0)
        if best is None or score > best[1]:
            best = (got, score, divisor)
    (size, cx0, cy0), score, divisor = best
    print(f"  выбрано: гекс={size:.1f} (кромка 1/{divisor}), посадка={score:.2f}")

    height, width = rgb.shape[:2]
    cells = []
    rejected = 0
    score_hist = {}
    for q in range(-18, 19):
        for r in range(-18, 19):
            cx = cx0 + 1.5 * size * q
            cy = cy0 + np.sqrt(3) * size * (r + q / 2.0)
            if not (size * 0.5 < cx < width - size * 0.5 and size * 0.5 < cy < height - size * 0.5):
                continue
            got = hex_features(rgb, cx, cy, size)
            if got is None:
                continue
            base, icon_frac, base_v = got
            score = border_score(rgb, cx, cy, size, base_v)
            score_hist[score] = score_hist.get(score, 0) + 1
            if score < min_border:
                rejected += 1
                continue
            hh, ss, vv = rgb_to_hsv(base.reshape(1, 1, 3))[0, 0]
            terrain = classify(float(hh), float(ss), float(vv), icon_frac)
            # отсечь рамку (тёмная) и светлый «коврик» (блеклый, низкая насыщенность)
            if terrain in ("grass", "forest", "fort", "camp"):
                if vv < 0.30 or ss < 0.45:
                    rejected += 1
                    continue
            cells.append({"q": q, "r": r, "t": terrain,
                          "_h": round(float(hh), 1), "_s": round(float(ss), 2),
                          "_v": round(float(vv), 2), "_icon": round(icon_frac, 3)})

    cells = _cleanup(cells, rgb, size, cx0, cy0)
    counts = {}
    for c in cells:
        counts[c["t"]] = counts.get(c["t"], 0) + 1
    print(f"  клеток: {len(cells)} (отброшено по обводке: {rejected})  {counts}")
    print(f"  распределение border_score: {score_hist}")
    if stats:
        for terrain in sorted(counts):
            rows = [c for c in cells if c["t"] == terrain]
            print(f"    {terrain:7s} n={len(rows):3d}  h={np.mean([c['_h'] for c in rows]):5.1f}"
                  f" s={np.mean([c['_s'] for c in rows]):.2f}"
                  f" v={np.mean([c['_v'] for c in rows]):.2f}"
                  f" icon={np.mean([c['_icon'] for c in rows]):.2f}")
    return cells, size, (cx0, cy0)


def draw_debug(name: str, cells, size, origin):
    img = Image.open(MAPS_DIR / f"{name}.webp").convert("RGB")
    scale = 0.5
    img = img.resize((int(img.width * scale), int(img.height * scale)))
    img = Image.blend(img, Image.new("RGB", img.size, (40, 40, 40)), 0.45)
    draw = ImageDraw.Draw(img)
    cx0, cy0 = origin
    s = size * scale
    for c in cells:
        cx = (cx0 + 1.5 * size * c["q"]) * scale
        cy = (cy0 + np.sqrt(3) * size * (c["r"] + c["q"] / 2.0)) * scale
        pts = [(cx + s * np.cos(np.deg2rad(60 * i)),
                cy + s * np.sin(np.deg2rad(60 * i))) for i in range(6)]
        draw.polygon(pts, fill=TERRAIN_COLORS[c["t"]], outline=(0, 0, 0))
    out = OUT_DIR / f"debug_{name}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"  отладка: {out}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    name = args[0] if args else "1x1x1"
    cells, size, origin = extract(name, stats="--stats" in sys.argv)
    draw_debug(name, cells, size, origin)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for c in cells:
        for key in [k for k in c if k.startswith("_")]:
            del c[key]
    payload = {"name": name, "hex_size": round(size, 2), "cells": cells}
    (OUT_DIR / f"{name}.json").write_text(json.dumps(payload, ensure_ascii=False, indent=1))
    print(f"  json: {OUT_DIR / (name + '.json')}")


if __name__ == "__main__":
    main()
