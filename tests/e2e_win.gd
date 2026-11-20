extends SceneTree

## NET-001→PLAYTEST, победа по сети: 4 независимых клиента, игрок 1 ведёт отряд
## к ключевой точке и доводит партию до победы (8 очков). Это «полноценная
## партия» до результата на авторитетном сервере.
## Запуск: godot --headless --path . --script res://tests/e2e_win.gd

const PORT := 8133
const MAX_ROUNDS := 30

var failures: int = 0
var checks: int = 0
var _board: Board = null


func _init() -> void:
	_test_win()
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


func _get_board() -> Board:
	if _board == null:
		_board = Board.new()
		_board.load_map(MatchSetup.MAP_PATH)
	return _board


func _occupied(state: Dictionary) -> Dictionary:
	var occ := {}
	for u in state.get("units", []):
		occ[Vector2i(int(u["q"]), int(u["r"]))] = true
	return occ


## Кратчайший путь между клетками (BFS по проходимости, фигуры не учитываются).
func _bfs_path(board: Board, from: Vector2i, to: Vector2i) -> Array:
	var prev := {from: Vector2i(-999999, -999999)}
	var q: Array = [from]
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		if cur == to:
			var path: Array = [cur]
			while prev[cur] != Vector2i(-999999, -999999):
				cur = prev[cur]
				path.push_front(cur)
			return path
		for nb in board.neighbors(cur):
			if prev.has(nb) or not board.is_passable(nb):
				continue
			prev[nb] = cur
			q.append(nb)
	return []


## Шаг неходившей фигуры владельца к ближайшей свободной ключевой точке.
func _bot_move(state: Dictionary, owner: int) -> Array:
	var board := _get_board()
	var occ := _occupied(state)
	var keys: Array = []
	for c in board.cells.keys():
		if board.terrain_at(c) == Board.TERRAIN_KEY:
			keys.append(c)
	for u in state.get("units", []):
		if int(u.get("owner", 0)) != owner or bool(u.get("moved", false)):
			continue
		var from := Vector2i(int(u["q"]), int(u["r"]))
		if keys.has(from):
			continue  # фигура уже на точке — оставляем
		for k in keys:
			var path := _bfs_path(board, from, k)
			if path.size() >= 2 and not occ.has(path[1]):
				return [[from.x, from.y], [path[1].x, path[1].y]]
	return []


func _test_win() -> void:
	print("Партия до победы по сети")
	var server := GameServer.new()
	_check("сервер слушает", server.listen(PORT) == OK)

	var clients: Array[GameClient] = []
	for i in 4:
		var c := GameClient.new()
		c.connect_to_server("ws://127.0.0.1:%d/" % PORT)
		clients.append(c)
	_pump(server, clients, 1500)

	clients[0].create_room()
	_pump(server, clients, 300)
	var token := clients[0].room_token
	for i in range(1, 4):
		clients[i].join_room(token)
	_pump(server, clients, 800)
	_check("матч стартовал", not clients[0].state.is_empty())

	var winner := 0
	var rounds := 0
	while rounds < MAX_ROUNDS and winner == 0:
		for i in 4:
			if i == 0:
				var mv := _bot_move(clients[0].state, 1)
				if not mv.is_empty():
					clients[0].intent("move", {"from": mv[0], "to": mv[1]})
					_pump(server, clients, 40)
			clients[i].intent("end_turn")
			_pump(server, clients, 40)
			winner = int(clients[0].state.get("winner", 0))
			if winner != 0:
				break
		rounds += 1

	_check("партия дошла до победы", winner != 0, "winner=%d rounds=%d" % [winner, rounds])
	_check("победил игрок 1 (держал ключевую точку)", winner == 1)

	server.stop()
	for c in clients:
		c.ws.close()
