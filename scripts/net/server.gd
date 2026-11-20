class_name GameServer
extends RefCounted

## Авторитетный сервер OneLife (NET-001): транспорт и комнаты.
## Чистая логика без сцен — проверяется headless-тестом tests/server.gd.
## Правила матча здесь не дублируются: их держит Game из scripts/rules/.
##
## Протокол (JSON): {type, payload, seq}. Типы: hello, welcome, create_room,
## room_created, join_room, seat_assigned, rejected. Дальше добавятся
## choose_faction / intent / state / event.

const MAX_SEATS := 4

var tcp: TCPServer = null
## invite_token -> {seats: {seat:int -> peer_id}}
var rooms: Dictionary = {}

var _peers: Array[Dictionary] = []
var _next_peer_id: int = 1
var _crypto := Crypto.new()


func listen(port: int) -> Error:
	tcp = TCPServer.new()
	return tcp.listen(port)


func stop() -> void:
	if tcp != null:
		tcp.stop()


func peer_count() -> int:
	return _peers.size()


func room_count() -> int:
	return rooms.size()


## Один шаг сервера: принять новые соединения, разобрать входящие, вычистить
## закрытые. Зовётся в цикле (headless server) или из теста.
func poll() -> void:
	while tcp != null and tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.accept_stream(tcp.take_connection())
		_peers.append({"ws": ws, "id": _next_peer_id, "nick": "гость", "room": "", "player": 0})
		_next_peer_id += 1

	for peer in _peers:
		var ws: WebSocketPeer = peer["ws"]
		ws.poll()
		while ws.get_available_packet_count() > 0:
			_handle(peer, ws.get_packet().get_string_from_utf8())

	_peers = _peers.filter(func(peer): return peer["ws"].get_ready_state() != WebSocketPeer.STATE_CLOSED)


func _handle(p: Dictionary, raw: String) -> void:
	var msg = JSON.parse_string(raw)
	if not msg is Dictionary or not msg.has("type"):
		_send(p, {"type": "rejected", "reason": "плохой json"})
		return
	var payload: Dictionary = msg.get("payload", {})
	match str(msg["type"]):
		"hello":
			if payload.has("nick") and str(payload["nick"]) != "":
				p["nick"] = str(payload["nick"])
			_send(p, {"type": "welcome", "payload": {"guest_id": p["id"], "nick": p["nick"]}})
		"create_room":
			_create_room(p)
		"join_room":
			_join_room(p, str(payload.get("invite_token", "")))
		_:
			_send(p, {"type": "rejected", "reason": "неизвестный тип сообщения"})


func _create_room(p: Dictionary) -> void:
	if p["room"] != "":
		_send(p, {"type": "rejected", "reason": "уже в комнате"})
		return
	var token := _new_token()
	rooms[token] = {"seats": {1: p["id"]}}
	p["room"] = token
	p["player"] = 1
	_send(p, {"type": "room_created", "payload": {"invite_token": token, "player": 1}})


func _join_room(p: Dictionary, token: String) -> void:
	if p["room"] != "":
		_send(p, {"type": "rejected", "reason": "уже в комнате"})
		return
	if not rooms.has(token):
		_send(p, {"type": "rejected", "reason": "комната не найдена"})
		return
	var room: Dictionary = rooms[token]
	var seats: Dictionary = room["seats"]
	if seats.size() >= MAX_SEATS:
		_send(p, {"type": "rejected", "reason": "комната полна"})
		return
	var seat := 1
	while seats.has(seat):
		seat += 1
	seats[seat] = p["id"]
	p["room"] = token
	p["player"] = seat
	_send(p, {"type": "seat_assigned", "payload": {"invite_token": token, "player": seat}})


func _send(p: Dictionary, msg: Dictionary) -> void:
	p["ws"].send_text(JSON.stringify(msg))


## Непредсказуемый invite token: 16 байт из CSPRNG → 32 hex-символа.
func _new_token() -> String:
	var bytes := _crypto.generate_random_bytes(16)
	var hex := ""
	for b in bytes:
		hex += "0123456789abcdef"[(b >> 4) & 0xF]
		hex += "0123456789abcdef"[b & 0xF]
	return hex
