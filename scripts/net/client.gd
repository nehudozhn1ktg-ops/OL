class_name GameClient
extends RefCounted

## Сетевой клиент OneLife (NET-001): подключение к серверу, комнаты, намерения.
## GUI-клиент рисует серверный state и шлёт intent через этот класс. Чистая логика,
## без сцен — проверяется тестом tests/e2e_game.gd.

var ws: WebSocketPeer = null
var inbox: Array = []
var connected: bool = false

var guest_id: int = 0
var nick: String = ""
var room_token: String = ""
var seat: int = 0
## Последний `state` от сервера (Dictionary): current_player, units, scores...
var state: Dictionary = {}
## События боя (удары, ранения, гибель) — для анимаций.
var events: Array = []
var _seq: int = 0


func connect_to_server(url: String) -> void:
	ws = WebSocketPeer.new()
	ws.connect_to_url(url)


func poll() -> void:
	if ws == null:
		return
	ws.poll()
	if not connected and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		connected = true
	while ws.get_available_packet_count() > 0:
		_on_message(JSON.parse_string(ws.get_packet().get_string_from_utf8()))


func send(obj: Dictionary) -> void:
	if ws != null:
		obj["seq"] = _seq
		_seq += 1
		ws.send_text(JSON.stringify(obj))


func hello(nick_: String) -> void:
	nick = nick_
	send({"type": "hello", "payload": {"nick": nick}})


func create_room() -> void:
	send({"type": "create_room"})


func join_room(token: String) -> void:
	send({"type": "join_room", "payload": {"invite_token": token}})


## Намерение хода: intent("move", {"from": [q,r], "to": [q,r]}).
func intent(action: String, fields: Dictionary = {}) -> void:
	var payload := fields.duplicate()
	payload["action"] = action
	send({"type": "intent", "payload": payload})


func last(type: String) -> Dictionary:
	var result := {}
	for m in inbox:
		if m.get("type", "") == type:
			result = m
	return result


func _on_message(m) -> void:
	if not m is Dictionary:
		return
	inbox.append(m)
	match str(m.get("type", "")):
		"welcome":
			guest_id = int(m.get("payload", {}).get("guest_id", 0))
		"room_created":
			room_token = str(m.get("payload", {}).get("invite_token", ""))
			seat = int(m.get("payload", {}).get("player", 0))
		"seat_assigned":
			room_token = str(m.get("payload", {}).get("invite_token", ""))
			seat = int(m.get("payload", {}).get("player", 0))
		"state":
			state = m.get("payload", {})
		"event":
			events.append(m.get("payload", {}))
