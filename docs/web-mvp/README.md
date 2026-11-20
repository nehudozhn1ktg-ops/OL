# Ветка `web-mvp` — онлайн MVP OneLife

Отдельная ветка общения/работы. Базируется на `main` @ `5105a5a` («Броня
биомассой в ответ на атаку (ADR-015)»). `main` не трогаем; вся работа здесь,
мерж — только по решению владельца.

Рабочая папка: `C:\Projects\OneLife-web-mvp` (git worktree от `C:\Projects\OneLife`).

## План (приоритет из сообщения владельца)

1. **WEB-001** — воспроизводимый Web Export Godot 4.7.2 + проверка запуска.
2. **GAME-4P-001** — 4 игрока, очередь ходов, 4 отряда, расстановка на 4FFA.
3. **GAME-4P-002** — победа, очки, ресурсы, способности в партии на четверых.
4. **UI-001** — управление под мобильные экраны.
5. **NET-001** — серверный авторитетный контур, комнаты, инвайт-ссылки.
6. **PLAYTEST-001** — партия четырьмя независимыми клиентами.

## Техническая конфигурация (зафиксирована)

- Godot **4.7.2 Stable** (`4.7.2.stable.official.ed1daf0bf`, `C:\Godot`).
- Рендер **GL Compatibility** (`project.godot` → `gl_compatibility`) → WebGL 2.0.
- WebAssembly + WebGL 2.0.
- **Однопоточный экспорт** для первого браузерного билда: без SharedArrayBuffer,
  без обязательных COOP/COEP-заголовков.

## Статус

- [x] Отдельная ветка/папка (`web-mvp`).
- [x] Разобраны вложения: аудит, PDF-сопоставление, zip v1.1 (эталонный браузерный
  билд «OneLife Dark Fantasy Edition v1.0»), видео 5:51.
- [x] WEB-001: шаблоны экспорта установлены (`%APPDATA%\Godot\export_templates\4.7.2.stable\`,
  включая `web_nothreads_*`).
- [x] WEB-001: `export_presets.cfg` создан (Web, Compatibility, однопоточный).
- [x] WEB-001: экспорт выполнен (`build/web/`, exit 0).
- [x] WEB-001: запуск проверен (HTTP-сервер + headless Edge).

## Итог WEB-001

- Экспорт: `godot --headless --path . --export-release "Web" build/web/index.html`
  → exit 0. Артефакты: `index.wasm` (39.5 МБ), `index.pck` (15.1 МБ), `index.js`,
  `index.html`.
- Однопоточность подтверждена в `index.html`: `GODOT_THREADS_ENABLED = false`,
  `ensureCrossOriginIsolationHeaders: false` → SharedArrayBuffer/COOP/COEP не нужны.
- Тесты ветки до экспорта: **17 файлов, 0 провалов** (661 проверка).
- Проверка запуска: локальный сервер (`tools/web_serve.py`) отдаёт `.wasm` как
  `application/wasm`; headless Edge загрузил страницу, Godot стартовал (оверлей
  загрузки снят, ошибок нет), рендерится меню выбора фракции. Снимок —
  `docs/web-mvp/web-launch.png` (локально, в git не включён).

_Следующий шаг плана: GAME-4P-001 (4 игрока, очередь, 4 отряда, 4FFA)._

## Воспроизводимость (важно для агентов)

1. **Кэш классов Godot.** Свежий checkout/worktree НЕ имеет `.godot/`, и первый
   `--headless --quit` даёт ошибку `Identifier "GameConfig" not declared`
   (`scripts/menu.gd`), потому что глобальный кэш `class_name` ещё не собран.
   **Исправление:** один раз прогнать `godot --headless --editor --quit --path .`
   — он создаст `.godot/global_script_class_cache.cfg`. После этого `--quit` и
   экспорт чистые.
2. **Шаблоны экспорта** ставятся в `%APPDATA%\Godot\export_templates\4.7.2.stable\`
   (распакованный `templates/` из tpz). Скачивание: GitHub release
   `4.7.2-stable` → `Godot_v4.7.2-stable_export_templates.tpz`.
3. **`export_presets.cfg`** теперь коммитится (убран из `.gitignore`) — это и есть
   «воспроизводимый» пресет Web. Секретов в нём нет.
4. Экспорт: `godot --headless --path . --export-release "Web" build/web/index.html`.
   Артефакты `build/` игнорируются git.

## Вложения (входные материалы)

- `Z:\Загрузки\OneLife_Project_Audit.md` — сквозной аудит (прочитан).
- `Z:\Документы\OneLife_sopostavlenie_istochnikov_otchyot.pdf` — сверка источников
  (текст извлечён в `docs/attachments/sopostavlenie_otchyot.txt`).
- `Z:\Загрузки\OneLife_Game_v1_1.zip` — эталонный браузерный билд (референс
  локального FFA×4, не сетевой).
- `Z:\Загрузки\21232180136517.mp4` — видео 5:51 (референс, не разбиралось).
