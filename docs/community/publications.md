# Публикации (VK / Telegram) — памятка для агента

## VK

- Группа: https://vk.com/club230399307 «OneLife - настольная игра/Творчество».
- Токен: `.secrets/vk-api.token` (gitignored).
- Стиль постов: [vk-voice.md](vk-voice.md) — автор Слава, живой разговорный,
  самоирония, хэштеги в конце.
- **Статус:** токен групповой; `wall.get` (чтение) даёт `error 27` — для чтения
  нужен **пользовательский** токен со scope `wall`. Для чтения стены: попросить
  пользовательский токен ИЛИ попросить владельца вставить 3–5 постов текстом.
  Публикация `wall.post` групповым токеном — не проверена.

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
