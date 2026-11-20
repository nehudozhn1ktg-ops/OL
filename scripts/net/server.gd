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
## Фракции в порядке мест 1–4 (FFA: одна фракция на игрока).
const FACTIONS := ["infected", "undead", "people", "elves"]
const MAP_PATH := "res://assets/maps/data/4ffa.json"

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
		"intent":
			_intent(p, payload)
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
	if seats.size() >= MAX_SEATS:
		_start_match(token)


## Матч: когда комната заполнилась, сервер сам строит партию и становится
## единственным авторитетом правил. Клиент дальше шлёт только намерения.
func _start_match(token: String) -> void:
	var room: Dictionary = rooms[token]
	var board := Board.new()
	if not board.load_map(MAP_PATH):
		_broadcast(token, {"type": "rejected", "reason": "не загрузилась карта"})
		return
	var game := Game.new()
	game.setup(board, null, MAX_SEATS)

	var faction_ids := {}
	var flags := _flags(board)
	for seat in range(1, MAX_SEATS + 1):
		var fid: String = FACTIONS[seat - 1]
		faction_ids[seat] = fid
		var faction := FactionData.load_file("res://data/factions/%s.json" % fid)
		var roster := FactionData.roster(faction, 6)
		game.add_flag(seat, flags[seat - 1])
		game.place_roster(seat, flags[seat - 1], roster)
	game.factions = faction_ids
	for seat in faction_ids.keys():
		if faction_ids[seat] == "infected":
			game.start_biomass(seat)
		elif faction_ids[seat] == "undead":
			game.start_essence(seat)
			game.register_summonables(seat,
				FactionData.summonables(FactionData.load_file("res://data/factions/undead.json")))
	room["game"] = game
	room["board"] = board
	room["factions"] = faction_ids
	_broadcast(token, {"type": "match_started", "payload": {"players": faction_ids}})
	_broadcast(token, {"type": "state", "payload": _state(token)})


## Намерение хода. Сервер проверяет, что ходит именно этот игрок, и применяет
## действие через правила. Сейчас — end_turn; движение/бой добавятся следом.
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
		_:
			_send(p, {"type": "rejected", "reason": "действие не поддерживается"})


## Клетки-флаги карты в детерминированном порядке.
func _flags(board: Board) -> Array[Vector2i]:
	var flags: Array[Vector2i] = []
	for coord in board.cells.keys():
		if board.terrain_at(coord) == Board.TERRAIN_FLAG:
			flags.append(coord)
	flags.sort_custom(func(a, b): return a.x < b.x)
	return flags


## Компактное состояние матча для рассылки клиентам.
func _state(token: String) -> Dictionary:
	var game: Game = rooms[token]["game"]
	var units: Array = []
	for u in game.units:
		units.append({"owner": u.owner, "q": u.coord.x, "r": u.coord.y,
			"name": u.name_ru, "wounded": u.wounded})
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
