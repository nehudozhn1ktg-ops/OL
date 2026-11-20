extends SceneTree

## NET-001, фундамент: headless Godot поднимает WebSocket-сервер, клиент
## подключается и обменивается JSON-сообщениями в обе стороны.
## Это базовый транспорт будущего авторитетного контура (сервер — правила,
## клиент — намерения). Запуск:
##   godot --headless --path . --script res://tests/websocket.gd

const PORT := 8124

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_roundtrip()
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


func _test_roundtrip() -> void:
	print("WebSocket: сервер ↔ клиент, JSON roundtrip")
	var tcp := TCPServer.new()
	var err := tcp.listen(PORT)
	_check("сервер слушает порт", err == OK, "err=%d" % err)

	var client := WebSocketPeer.new()
	client.connect_to_url("ws://127.0.0.1:%d/" % PORT)

	var server_ws: WebSocketPeer = null
	var sent_ping := false
	var got_ping := false
	var got_pong := false
	var t := 0

	while t < 3000:
		# Сервер: принять входящее подключение.
		if server_ws == null and tcp.is_connection_available():
			server_ws = WebSocketPeer.new()
			server_ws.accept_stream(tcp.take_connection())

		# Сервер: опросить и ответить на «ping».
		if server_ws != null:
			server_ws.poll()
			while server_ws.get_available_packet_count() > 0:
				var msg := server_ws.get_packet().get_string_from_utf8()
				if msg == "ping":
					got_ping = true
					server_ws.send_text("pong")

		# Клиент: опросить, отправить «ping» после открытия, принять «pong».
		client.poll()
		if client.get_ready_state() == WebSocketPeer.STATE_OPEN and not sent_ping:
			client.send_text("ping")
			sent_ping = true
		while client.get_available_packet_count() > 0:
			if client.get_packet().get_string_from_utf8() == "pong":
				got_pong = true

		if got_ping and got_pong:
			break
		OS.delay_msec(5)
		t += 5

	_check("клиент открыл соединение", client.get_ready_state() == WebSocketPeer.STATE_OPEN)
	_check("сервер принял «ping»", got_ping)
	_check("клиент получил «pong»", got_pong)

	client.close()
	if server_ws != null:
		server_ws.close()
	tcp.stop()
