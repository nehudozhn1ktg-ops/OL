extends SceneTree

## NET-001, комнаты: создание комнаты, четыре места, отказ пятому, неверный токен.
## Запуск: godot --headless --path . --script res://tests/server.gd

const PORT := 8126

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


func _init() -> void:
	_test_rooms()
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


func _test_rooms() -> void:
	print("Комнаты: создание, 4 места, отказ пятому")
	var server := GameServer.new()
	_check("сервер слушает", server.listen(PORT) == OK)

	var clients: Array = []
	for i in 5:
		var c := Client.new()
		c.ws.connect_to_url("ws://127.0.0.1:%d/" % PORT)
		clients.append(c)
	_pump(server, clients, 1500)

	var c1: Client = clients[0]
	c1.send({"type": "hello", "payload": {"nick": "Аня"}})
	_pump(server, clients, 300)
	var welcome := c1.received("welcome")
	_check("welcome получен", welcome.has("payload"))
	_check("гостю выдан id 1", int(welcome.get("payload", {}).get("guest_id", -1)) == 1)
	_check("ник сохранён", str(welcome.get("payload", {}).get("nick", "")) == "Аня")

	c1.send({"type": "create_room"})
	_pump(server, clients, 300)
	var created := c1.received("room_created")
	_check("комната создана", created.has("payload"))
	var token: String = str(created.get("payload", {}).get("invite_token", ""))
	_check("токен 32 hex-символа", token.length() == 32)

	for i in range(1, 4):
		var c: Client = clients[i]
		c.send({"type": "join_room", "payload": {"invite_token": token}})
		_pump(server, clients, 300)
		var m := c.received("seat_assigned")
		_check("место %d выдано" % (i + 1),
			int(m.get("payload", {}).get("player", -1)) == i + 1)

	var c5: Client = clients[4]
	c5.send({"type": "join_room", "payload": {"invite_token": token}})
	_pump(server, clients, 300)
	_check("пятому отказано (полна)", str(c5.received("rejected").get("reason", "")).contains("полна"))

	var c6 := Client.new()
	c6.ws.connect_to_url("ws://127.0.0.1:%d/" % PORT)
	clients.append(c6)
	_pump(server, clients, 300)
	c6.send({"type": "join_room", "payload": {"invite_token": "нет-такого"}})
	_pump(server, clients, 300)
	_check("неверный токен отклонён", str(c6.received("rejected").get("reason", "")).contains("не найдена"))

	server.stop()
	for c in clients:
		c.ws.close()
