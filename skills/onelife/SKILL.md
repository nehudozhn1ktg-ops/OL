---
name: onelife
description: Правила и команды проекта OneLife — настольная игра на Godot. Загружай перед правкой кода, тестов, данных фракций, карт или артов.
---

# OneLife: как работать в этом проекте

## Проект

Godot 4.7.2, GDScript. Движок в `C:\Godot`, проект — в этой папке (`project.godot`).
Правила игры: `docs/canon/01-core.md`. Решения владельца: `docs/memory/decisions.md`.
Текущее состояние: `docs/memory/context.md`. Открытые вопросы: `docs/memory/errors.md`.

## Команды

```powershell
# запустить игру
C:\Godot\Godot_v4.7.2-stable_win64.exe --path .

# проверить, что проект цел
C:\Godot\Godot_v4.7.2-stable_win64.exe --path . --headless --quit

# тесты (каждый файл отдельно)
C:\Godot\Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/combat.gd
C:\Godot\Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/game_rules.gd
C:\Godot\Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/rules_board.gd
C:\Godot\Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/faction_data.gd
C:\Godot\Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/factions_all.gd
C:\Godot\Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/verify_hex.gd

# снимок окна для отчёта
C:\Godot\Godot_v4.7.2-stable_win64.exe --path . -- --shot
```

Git: `C:\Git\cmd\git.exe` (в PATH). Логичные сообщения коммитов — по-русски.

## Границы

- Правила живут в `scripts/rules/` и не знают о сценах. Отрисовка — `scripts/hex_grid.gd`.
- Меняешь механику — сначала тест, потом код.
- Канон старше кода: если расходятся, прав код, а не `docs/canon/`.
- Числа фигур — из `data/factions/*.json`, снятые с карт. Не выдумывать.
- Класс фигуры задаёт значок внизу карты (корона/шлем/шеврон), а не название.
