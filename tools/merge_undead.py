"""Сводит нежить в один файл: исправляет классы по значкам карт, чинит
текст Жнеца (там ранение, а не «3 урона») и добавляет недостающих фигур.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "data" / "factions" / "undead.json"

# класс по значку внизу карты (корона / шлем / шеврон)
KINDS = {
    "necromancer": "king",        # корона
    "skeleton_king": "commander",  # шлем
    "reaper": "commander",         # шлем
    "blood_golem": "commander",    # шлем
    "baron": "pawn",               # шеврон
    "bodyguard": "pawn",           # шеврон
    "kettle": "pawn",              # шеврон
    "dream_thief": "pawn",
    "succubus": "commander",
    "miner": "pawn",
}

EXTRA = [
    {
        "id": "kettle", "name": "Котелок", "damage": 1, "move": 3, "armor": 1,
        "can_attack": True, "abilities": ["unknown"],
        "text": "Нанесите этой фигуре [ранение], получив 1 [эссенция]. "
                "Если она [выжила], то применение этого [действие] уничтожает её, "
                "а вы получаете 2 [эссенция]. (формулировка требует уточнения)",
    },
]


def main() -> None:
    faction = json.loads(TARGET.read_text(encoding="utf-8"))
    units = faction["units"]

    old_extra = ROOT / "data" / "factions" / "undead_extra.json"
    if old_extra.exists():
        units.extend(json.loads(old_extra.read_text(encoding="utf-8"))["units"])
    units.extend(EXTRA)

    for unit in units:
        if unit["id"] in KINDS:
            unit["kind"] = KINDS[unit["id"]]
        if unit["id"] == "reaper":
            unit["abilities"] = ["aura_wound"]
            unit["text"] = ("[аура]: [фигура]/[враг] получают [ранение]. "
                            "Требует уточнения: радиус и задевает ли союзников.")

    faction["units"] = units
    faction["notes"].append("Классы проставлены по значку внизу карты: корона — king, "
                            "шлем — commander, шеврон — pawn. Название фигуры класс не задаёт.")
    TARGET.write_text(json.dumps(faction, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"фигур: {len(units)} -> {[u['id'] + ':' + u['kind'] for u in units]}")


if __name__ == "__main__":
    main()
