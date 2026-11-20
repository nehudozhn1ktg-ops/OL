extends SceneTree

## NET-001, сетевой ход: сервер применяет activate и валидирует move/attack
## авторитетно (чужой игрок, чужая фигура, неверная геометрия).
## Запуск: godot --headless --path . --script res://tests/server_move.gd

const PORT := 8129

var failures: int = 0
var checks: int = 0


class Client:
	extends RefCounted

	var ws: WebSocketPeer
	var inbox: Array = []

	func _init():
		ws = WebSocketPeer.new()

	func send(obj: Dictionary) -> void:
		ws.send_text(JSON.stringify(obj))

	func poll() -> void:
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if m is Dictionary:
				inbox.append(m)

	func last(type: String) -> Dictionary:
		var result := {}
		for m in inbox:
			if m.get("type", "") == type:
				result = m
		return result


func _init() -> void:
	_test_network_move()
	print("")
	print("РЕЗУЛЬТАТ: %d проверок, провалов %d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(name: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		print("  OK   %s" % name)
	else:
		failures += 1
		print("  FAIL %s %s" % [name, detail])


func _pump(server: GameServer, clients: Array, ms: int) -> void:
	var t := 0
	while t < ms:
		server.poll()
		for c in clients:
			c.poll()
		OS.delay_msec(2)
		t += 2


func _find_unit(state: Dictionary, owner: int) -> Dictionary:
	for u in state.get("payload", {}).get("units", []):
		if int(u.get("owner", 0)) == owner:
			return u
	return {}


func _coord_of(u: Dictionary) -> Array:
	return [int(u.get("q", 0)), int(u.get("r", 0))]


func _test_network_move() -> void:
	print("Сетевой ход: activate, валидация move/attack")
	var server := GameServer.new()
	_check("сервер слушает", server.listen(PORT) == OK)

	var clients: Array[Client] = []
	for i in 4:
		var c := Client.new()
		c.ws.connect_to_url("ws://127.0.0.1:%d/" % PORT)
		clients.append(c)
	_pump(server, clients, 1500)

	clients[0].send({"type": "create_room"})
	_pump(server, clients, 300)
	var token: String = str(clients[0].last("room_created").get("payload", {}).get("invite_token", ""))
	for i in range(1, 4):
		clients[i].send({"type": "join_room", "payload": {"invite_token": token}})
	_pump(server, clients, 600)

	var state0 := clients[0].last("state")
	_check("матч: 24 фигуры", int(state0.get("payload", {}).get("units", []).size()) == 24)

	var u1 := _find_unit(state0, 1)
	var u2 := _find_unit(state0, 2)
	_check("есть фигура игрока 1", not u1.is_empty())
	_check("есть фигура игрока 2", not u2.is_empty())

	# 1) activate своей фигуры — применяется.
	clients[0].send({"type": "intent", "payload": {"action": "activate", "from": _coord_of(u1)}})
	_pump(server, clients, 300)
	var state1 := clients[0].last("state")
	var activated := false
	for u in state1.get("payload", {}).get("units", []):
		if int(u.get("owner", 0)) == 1 and [int(u["q"]), int(u["r"])] == _coord_of(u1):
			activated = bool(u.get("activated", false))
	_check("activate применился (флаг activated)", activated)

	# 2) move далеко — геометрия отклоняется.
	clients[0].send({"type": "intent", "payload": {"action": "move", "from": _coord_of(u1), "to": [999, 999]}})
	_pump(server, clients, 300)
	_check("move за пределы поля отклонён", clients[0].last("rejected").has("reason"))

	# 3) move чужой фигурой в свой ход — отклоняется.
	clients[0].send({"type": "intent", "payload": {"action": "move", "from": _coord_of(u2), "to": [0, 0]}})
	_pump(server, clients, 300)
	_check("move чужой фигурой отклонён", str(clients[0].last("rejected").get("reason", "")).contains("другого"))

	# 4) attack по дальней цели — дальность отклоняется.
	clients[0].send({"type": "intent", "payload": {"action": "attack", "from": _coord_of(u1), "target": _coord_of(u2)}})
	_pump(server, clients, 300)
	_check("attack по дальней цели отклонён", str(clients[0].last("rejected").get("reason", "")).contains("дальности"))

	# 5) чужой ход до очереди — отклоняется на входе в intent.
	clients[1].send({"type": "intent", "payload": {"action": "end_turn"}})
	_pump(server, clients, 300)
	_check("ход игрока 2 до очереди отклонён", str(clients[1].last("rejected").get("reason", "")).contains("другого"))

	server.stop()
	for c in clients:
		c.ws.close()
