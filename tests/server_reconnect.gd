extends SceneTree

## NET-001, переподключение (аудит P3): гость обрывает связь и возвращается
## в ту же партию по guest_id.
## Запуск: godot --headless --path . --script res://tests/server_reconnect.gd

const PORT := 8132

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_reconnect()
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


func _test_reconnect() -> void:
	print("Переподключение: обрыв → возврат в ту же партию")
	var server := GameServer.new()
	server.listen(PORT)

	var clients: Array[GameClient] = []
	for i in 4:
		var c := GameClient.new()
		c.connect_to_server("ws://127.0.0.1:%d/" % PORT)
		clients.append(c)
	_pump(server, clients, 1500)

	clients[0].hello("Аня")
	clients[0].create_room()
	_pump(server, clients, 400)
	var token := clients[0].room_token
	for i in range(1, 4):
		clients[i].hello("Игрок%d" % (i + 1))
		clients[i].join_room(token)
	_pump(server, clients, 800)
	_check("матч стартовал", not clients[0].state.is_empty())

	var guest2 := clients[1].guest_id
	_check("у игрока 2 есть guest_id", guest2 != 0)

	# Игрок 2 обрывает связь.
	clients[1].ws.close()
	_pump(server, clients, 400)
	_check("соединение игрока 2 закрыто", clients[1].connected == false or clients[1].ws.get_ready_state() != WebSocketPeer.STATE_OPEN)

	# Переподключение по guest_id.
	var c2b := GameClient.new()
	c2b.connect_to_server("ws://127.0.0.1:%d/" % PORT)
	clients[1] = c2b
	_pump(server, clients, 400)
	c2b.resume("Игрок2", guest2)
	_pump(server, clients, 600)

	_check("вернулся прежний guest_id", c2b.guest_id == guest2)
	_check("вернулось место 2", c2b.seat == 2)
	_check("вернулся state (та же партия)", not c2b.state.is_empty())
	_check("state содержит 24 фигуры", int(c2b.state.get("units", []).size()) == 24)

	server.stop()
	for c in clients:
		c.ws.close()
