extends SceneTree

## NET-001, сквозной тест: 4 независимых клиента подключаются, входят в комнату,
## сервер строит матч, каждый игрок ходит (move + end_turn) два раунда.
## Запуск: godot --headless --path . --script res://tests/e2e_game.gd

const PORT := 8130

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_e2e()
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


## Свободная проходимая соседняя клетка для неходившей фигуры владельца.
func _find_move(state: Dictionary, owner: int) -> Array:
	var board := Board.new()
	board.load_map(MatchSetup.MAP_PATH)
	var occupied := {}
	for u in state.get("units", []):
		occupied[Vector2i(int(u["q"]), int(u["r"]))] = true
	for u in state.get("units", []):
		if int(u.get("owner", 0)) != owner:
			continue
		if bool(u.get("moved", false)):
			continue
		var from := Vector2i(int(u["q"]), int(u["r"]))
		for nb in board.neighbors(from):
			if board.is_passable(nb) and not occupied.has(nb):
				return [[from.x, from.y], [nb.x, nb.y]]
	return []


func _unit_at(state: Dictionary, q: int, r: int, owner: int) -> bool:
	for u in state.get("units", []):
		if int(u.get("owner", 0)) == owner and int(u["q"]) == q and int(u["r"]) == r:
			return true
	return false


func _test_e2e() -> void:
	print("Сквозной: 4 клиента, 2 раунда ходов")
	var server := GameServer.new()
	_check("сервер слушает", server.listen(PORT) == OK)

	var clients: Array[GameClient] = []
	for i in 4:
		var c := GameClient.new()
		c.connect_to_server("ws://127.0.0.1:%d/" % PORT)
		clients.append(c)
	_pump(server, clients, 1500)
	_check("4 клиента подключены", server.peer_count() == 4)

	clients[0].create_room()
	_pump(server, clients, 300)
	var token := clients[0].room_token
	_check("комната создана (токен 32)", token.length() == 32)
	for i in range(1, 4):
		clients[i].join_room(token)
	_pump(server, clients, 600)
	for i in 4:
		_check("клиент %d получил место %d" % [i + 1, i + 1],
			clients[i].seat == i + 1 and not clients[i].state.is_empty())

	var moved_total := 0
	for round_i in 2:
		for i in 4:
			var mv := _find_move(clients[i].state, i + 1)
			if not mv.is_empty():
				clients[i].intent("move", {"from": mv[0], "to": mv[1]})
				_pump(server, clients, 300)
				var st := clients[i].state
				var gone := not _unit_at(st, mv[0][0], mv[0][1], i + 1)
				var arrived := _unit_at(st, mv[1][0], mv[1][1], i + 1)
				_check("р%d игрок %d: фигура перешла" % [round_i + 1, i + 1], gone and arrived)
				moved_total += 1
			clients[i].intent("end_turn")
			_pump(server, clients, 300)

	_check("за 2 раунда сделано 8 ходов", moved_total == 8, "=%d" % moved_total)
	var st := clients[0].state
	_check("раунд 3 (2 полных цикла)", int(st.get("turn_number", 0)) == 3)
	_check("снова ходит игрок 1", int(st.get("current_player", 0)) == 1)
	_check("фигур по-прежнему 24", int(st.get("units", []).size()) == 24)

	server.stop()
	for c in clients:
		c.ws.close()
