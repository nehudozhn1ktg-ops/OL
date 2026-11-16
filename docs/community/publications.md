# Публикации (VK / Telegram) — памятка для агента

## VK

- Группа: https://vk.com/club230399307 «OneLife - настольная игра/Творчество».
- Токен: `.secrets/vk-api.token` (gitignored).
- Стиль постов: [vk-voice.md](vk-voice.md) — автор Слава; примеры — реальные посты
  (`C:\Users\Admin\Desktop\посты вк.txt`). Без длинных тире, без утрированных шуток.
- **Статус токена (2026-11-16):** в `.secrets` лежит **групповой** токен —
  `users.get` отдаёт пустой ответ, `wall.get` — `error 27`. Для публикации нужен
  **пользовательский** токен администратора группы (scope `wall`, `groups`,
  `offline`; для картинок — `photos`). Групповой токен для надёжной публикации
  не подходит.
- Публикация: `python tools/vk_publish.py --file <путь> --defer-hours N`
  (0 часов = сразу). Отложенный пост — через `publish_date` (VK «отложенные»).

## Отложенные посты

Черновики в [drafts/](drafts/), в сеть не уходят, пока владелец не подтвердит текст
и не будет рабочего токена.

- [2026-11-16 · нежить/Некромант](drafts/2026-11-16-nekromant.md) — статус: ОТЛОЖЕНО.

## Telegram

- Токен бота: `.secrets/telegram.token` (gitignored).
- Группа: https://t.me/+WGsCo2O1uzBjZDcy (приватная, invite-ссылка).
- **Статус:** `api.telegram.org` заблокирован из РФ. Прокси TgWsProxy
  (127.0.0.1:1080) — только MTProto для приложения, для Bot API не подходит.
  zapret запущен, но Bot API не открывает (нужен AmneziaVPN). **Решение отложено
  (вариант Б)** — публикацию в TG пока не настраиваем.

## GitHub

- Репозиторий: https://github.com/nehudozhn1ktg-ops/OL (private, ветка `main`).
- Каждый шаг коммитится и пушится. «Публикации» на GitHub = release notes/changelog.
