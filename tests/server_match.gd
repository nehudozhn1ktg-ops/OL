extends SceneTree

## NET-001, авторитетный матч: сервер сам строит партию на 4, применяет
## end_turn только от текущего игрока и рассылает state всем.
## Запуск: godot --headless --path . --script res://tests/server_match.gd

const PORT := 8128

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

	func received(type: String) -> Dictionary:
		for m in inbox:
			if m.get("type", "") == type:
				return m
		return {}

	func last(type: String) -> Dictionary:
		var result := {}
		for m in inbox:
			if m.get("type", "") == type:
				result = m
		return result


func _init() -> void:
	_test_match()
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


func _test_match() -> void:
	print("Авторитетный матч: старт на 4 и очередь ходов")
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
	var created := clients[0].received("room_created")
	var token: String = str(created.get("payload", {}).get("invite_token", ""))

	for i in range(1, 4):
		clients[i].send({"type": "join_room", "payload": {"invite_token": token}})
	_pump(server, clients, 600)

	for i in 4:
		_check("игрок %d: матч стартовал" % (i + 1), clients[i].received("match_started").has("payload"))
	var state0 := clients[0].received("state")
	_check("state: 24 фигуры", int(state0.get("payload", {}).get("units", []).size()) == 24)
	_check("state: первым ходит игрок 1", int(state0.get("payload", {}).get("current_player", -1)) == 1)

	# Чужой ход до очереди отклоняется сервером.
	clients[1].send({"type": "intent", "payload": {"action": "end_turn"}})
	_pump(server, clients, 300)
	_check("ход игрока 2 до очереди отклонён",
		str(clients[1].received("rejected").get("reason", "")).contains("другого"))

	# Очередь 1→2→3→4→1 через сервер.
	for i in 4:
		clients[i].send({"type": "intent", "payload": {"action": "end_turn"}})
		_pump(server, clients, 300)
	var state_last := clients[0].last("state")
	_check("после 4 ходов снова игрок 1", int(state_last.get("payload", {}).get("current_player", -1)) == 1)
	_check("раунд 2", int(state_last.get("payload", {}).get("turn_number", -1)) == 2)

	server.stop()
	for c in clients:
		c.ws.close()
