extends SceneTree

## NET-001, надёжность (аудит P3): защита от повтора (seq), таймаут комнаты,
## rate-limit входа по неверному коду.
## Запуск: godot --headless --path . --script res://tests/server_robust.gd

const PORT := 8131

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_seq()
	_test_room_timeout()
	_test_rate_limit()
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


func _test_seq() -> void:
	print("Защита от повтора (seq)")
	var server := GameServer.new()
	server.listen(PORT)
	var c := GameClient.new()
	c.connect_to_server("ws://127.0.0.1:%d/" % PORT)
	_pump(server, [c], 800)
	c.hello("Аня")
	_pump(server, [c], 300)
	_check("welcome получен", c.last("welcome").has("payload"))
	# Реплей того же seq=0 вручную, минуя авто-инкремент GameClient.
	c.ws.send_text(JSON.stringify({"type": "hello", "payload": {"nick": "Аня"}, "seq": 0}))
	_pump(server, [c], 300)
	_check("повтор seq=0 отклонён", str(c.last("rejected").get("reason", "")).contains("повтор"))
	server.stop()
	c.ws.close()


func _test_room_timeout() -> void:
	print("Таймаут незапущенной комнаты")
	var server := GameServer.new()
	server.room_timeout_ms = 400
	server.listen(PORT + 1)
	var c := GameClient.new()
	c.connect_to_server("ws://127.0.0.1:%d/" % (PORT + 1))
	_pump(server, [c], 800)
	c.create_room()
	_pump(server, [c], 100)
	_check("комната создана", server.room_count() == 1)
	_pump(server, [c], 700)
	_check("комната истекла", server.room_count() == 0)
	_check("клиенту отправлен room_closed", c.last("room_closed").has("payload"))
	server.stop()
	c.ws.close()


func _test_rate_limit() -> void:
	print("Rate-limit входа по неверному коду")
	var server := GameServer.new()
	server.listen(PORT + 2)
	var c := GameClient.new()
	c.connect_to_server("ws://127.0.0.1:%d/" % (PORT + 2))
	_pump(server, [c], 800)
	for i in 12:
		c.join_room("нет-такого")
		_pump(server, [c], 100)
	_check("12-я попытка ограничена", str(c.last("rejected").get("reason", "")).contains("слишком много"))
	server.stop()
	c.ws.close()
