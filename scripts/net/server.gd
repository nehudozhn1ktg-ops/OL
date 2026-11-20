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
## Время жизни незапущенной комнаты (мс) и лимит неудачных входов на peer.
var room_timeout_ms: int = 300000
var max_bad_joins: int = 10


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
		_peers.append({"ws": ws, "id": _next_peer_id, "nick": "гость", "room": "", "player": 0,
			"seq": -1, "bad_joins": 0})
		_next_peer_id += 1

	for peer in _peers:
		var ws: WebSocketPeer = peer["ws"]
		ws.poll()
		while ws.get_available_packet_count() > 0:
			_handle(peer, ws.get_packet().get_string_from_utf8())

	_peers = _peers.filter(func(peer): return peer["ws"].get_ready_state() != WebSocketPeer.STATE_CLOSED)
	if room_timeout_ms > 0:
		_expire_rooms()


func _handle(p: Dictionary, raw: String) -> void:
	var msg = JSON.parse_string(raw)
	if not msg is Dictionary or not msg.has("type"):
		_send(p, {"type": "rejected", "reason": "плохой json"})
		return
	var seq := int(msg.get("seq", -1))
	if seq >= 0:
		if seq <= int(p.get("seq", -1)):
			_send(p, {"type": "rejected", "reason": "повтор сообщения"})
			return
		p["seq"] = seq
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
		"intent":
			_intent(p, payload)
		_:
			_send(p, {"type": "rejected", "reason": "неизвестный тип сообщения"})


func _create_room(p: Dictionary) -> void:
	if p["room"] != "":
		_send(p, {"type": "rejected", "reason": "уже в комнате"})
		return
	var token := _new_token()
	rooms[token] = {"seats": {1: p["id"]}, "created": Time.get_ticks_msec()}
	p["room"] = token
	p["player"] = 1
	_send(p, {"type": "room_created", "payload": {"invite_token": token, "player": 1}})


func _join_room(p: Dictionary, token: String) -> void:
	if p["room"] != "":
		_send(p, {"type": "rejected", "reason": "уже в комнате"})
		return
	if not rooms.has(token):
		p["bad_joins"] = int(p.get("bad_joins", 0)) + 1
		if int(p["bad_joins"]) > max_bad_joins:
			_send(p, {"type": "rejected", "reason": "слишком много попыток"})
			return
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
	if seats.size() >= MAX_SEATS:
		_start_match(token)


## Истечение незапущенных комнат (таймаут из аудита P3).
func _expire_rooms() -> void:
	var now := Time.get_ticks_msec()
	for token in rooms.keys():
		var room: Dictionary = rooms[token]
		var seats: Dictionary = room.get("seats", {})
		if seats.size() >= MAX_SEATS:
			continue
		if now - int(room.get("created", 0)) > room_timeout_ms:
			_broadcast(token, {"type": "room_closed", "payload": {"reason": "комната истекла"}})
			rooms.erase(token)


## Матч: когда комната заполнилась, сервер сам строит партию и становится
## единственным авторитетом правил. Клиент дальше шлёт только намерения.
func _start_match(token: String) -> void:
	var room: Dictionary = rooms[token]
	var board := Board.new()
	if not board.load_map(MatchSetup.MAP_PATH):
		_broadcast(token, {"type": "rejected", "reason": "не загрузилась карта"})
		return
	var game := Game.new()
	game.setup(board, null, MAX_SEATS)

	var faction_ids := {}
	for seat in range(1, MAX_SEATS + 1):
		faction_ids[seat] = MatchSetup.FACTIONS[seat - 1]
	MatchSetup.place(game, board, faction_ids)
	room["game"] = game
	room["board"] = board
	room["factions"] = faction_ids
	_broadcast(token, {"type": "match_started", "payload": {"players": faction_ids}})
	_broadcast(token, {"type": "state", "payload": _state(token)})


## Намерение хода. Сервер проверяет, что ходит именно этот игрок, и применяет
## действие через правила (Game.can_*), затем рассылает state/event.
func _intent(p: Dictionary, payload: Dictionary) -> void:
	var token: String = p["room"]
	if token == "" or not rooms.has(token):
		_send(p, {"type": "rejected", "reason": "не в комнате"})
		return
	var game: Game = rooms[token].get("game")
	if game == null:
		_send(p, {"type": "rejected", "reason": "матч не начат"})
		return
	if game.current_player != int(p["player"]):
		_send(p, {"type": "rejected", "reason": "сейчас ход другого игрока"})
		return
	match str(payload.get("action", "")):
		"end_turn":
			game.end_turn()
			_broadcast(token, {"type": "state", "payload": _state(token)})
		"activate":
			_activate(p, token, game, payload)
		"move":
			_move(p, token, game, payload)
		"attack":
			_attack(p, token, game, payload)
		_:
			_send(p, {"type": "rejected", "reason": "действие не поддерживается"})


func _activate(p: Dictionary, token: String, game: Game, payload: Dictionary) -> void:
	var unit := game.unit_at(_coord(payload.get("from")))
	if unit == null or unit.owner != game.current_player:
		_send(p, {"type": "rejected", "reason": "нет вашей фигуры на этой клетке"})
		return
	if not game.activate(unit):
		_send(p, {"type": "rejected", "reason": game.can_activate(unit)["reason"]})
		return
	_broadcast(token, {"type": "state", "payload": _state(token)})


func _move(p: Dictionary, token: String, game: Game, payload: Dictionary) -> void:
	var unit := game.unit_at(_coord(payload.get("from")))
	if unit == null:
		_send(p, {"type": "rejected", "reason": "нет фигуры на этой клетке"})
		return
	var to := _coord(payload.get("to"))
	var verdict := game.can_move(unit, to)
	if not verdict["ok"]:
		_send(p, {"type": "rejected", "reason": verdict["reason"]})
		return
	game.move_unit(unit, to)
	_broadcast(token, {"type": "state", "payload": _state(token)})


func _attack(p: Dictionary, token: String, game: Game, payload: Dictionary) -> void:
	var attacker := game.unit_at(_coord(payload.get("from")))
	var defender := game.unit_at(_coord(payload.get("target")))
	if attacker == null:
		_send(p, {"type": "rejected", "reason": "нет фигуры на этой клетке"})
		return
	if defender == null:
		_send(p, {"type": "rejected", "reason": "нет цели на этой клетке"})
		return
	var verdict := game.can_attack(attacker, defender)
	if not verdict["ok"]:
		_send(p, {"type": "rejected", "reason": verdict["reason"]})
		return
	var blow := game.attack(attacker, defender)
	_broadcast(token, {"type": "event", "payload": blow})
	_broadcast(token, {"type": "state", "payload": _state(token)})


func _coord(v) -> Vector2i:
	if v is Array and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-999999, -999999)


## Компактное состояние матча для рассылки клиентам.
func _state(token: String) -> Dictionary:
	var game: Game = rooms[token]["game"]
	var units: Array = []
	for u in game.units:
		units.append({"owner": u.owner, "q": u.coord.x, "r": u.coord.y,
			"name": u.name_ru, "wounded": u.wounded, "activated": u.activated, "moved": u.moved})
	return {
		"current_player": game.current_player,
		"turn_number": game.turn_number,
		"round_number": game.round_number,
		"is_day": game.is_day,
		"winner": game.winner,
		"scores": game.scores.duplicate(),
		"units": units,
	}


func _broadcast(token: String, msg: Dictionary) -> void:
	for p in _peers:
		if p["room"] == token:
			_send(p, msg)


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
