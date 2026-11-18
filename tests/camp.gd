extends SceneTree

## Размещение отряда: фигуры ставятся на клетки «лагерь» — 6 соседей флага,
## какая фигура на какой клетке — случайно. Проверяем инвариант (биекция на
## соседние клетки, без наложений) и откат на ближайшие свободные, если сосед
## непроходим.
## Запуск: godot --headless --path . --script res://tests/camp.gd

const START := Vector2i.ZERO

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_deployment_cells()
	_test_place_roster()
	_test_water_fallback()

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


func _make_game() -> Game:
	var board := Board.new()
	board.build_disk(4)
	var game := Game.new()
	game.setup(board, Dice.new(7))
	return game


func _roster(count: int = 6) -> Array:
	var result := []
	for i in count:
		result.append({
			"id": "u%d" % i, "name": "Фигура %d" % i, "kind": "pawn",
			"damage": 0, "move": 2, "armor": 0, "can_attack": true,
			"abilities": [], "text": ""})
	return result


func _test_deployment_cells() -> void:
	print("Клетки лагеря = 6 соседей флага")
	var game := _make_game()
	game.add_flag(1, START)
	var spots := game.board.deployment_cells(START, 6)
	_check("ровно 6 клеток", spots.size() == 6, "= %d" % spots.size())
	var distinct := {}
	for spot in spots:
		distinct[spot] = true
		_check("(%d,%d) — сосед флага" % [spot.x, spot.y],
			game.board.distance(START, spot) == 1)
	_check("клетки не повторяются", distinct.size() == spots.size())


func _test_place_roster() -> void:
	print("Расстановка отряда на лагерь")
	var game := _make_game()
	game.add_flag(1, START)
	var placed := game.place_roster(1, START, _roster(6))
	_check("поставлены все 6", placed.size() == 6, "= %d" % placed.size())
	var occupied := {}
	for unit in placed:
		occupied[unit.coord] = true
		_check("фигура (%d,%d) на соседней клетке" % [unit.coord.x, unit.coord.y],
			game.board.distance(START, unit.coord) == 1)
	_check("нет наложений", occupied.size() == 6, "клеток %d" % occupied.size())

	# Меньший отряд (как у магов после слияния) — тоже корректно.
	var small := _make_game()
	small.add_flag(1, START)
	var placed_small := small.place_roster(1, START, _roster(5))
	_check("отряд из 5 ставится без ошибок", placed_small.size() == 5, "= %d" % placed_small.size())


func _test_water_fallback() -> void:
	print("Непроходимый сосед — ближайшая свободная клетка")
	var board := Board.new()
	board.build_disk(4, [Vector2i(1, 0)])
	var game := Game.new()
	game.setup(board, Dice.new(7))
	game.add_flag(1, START)
	var spots := board.deployment_cells(START, 6)
	_check("всё равно 6 клеток", spots.size() == 6, "= %d" % spots.size())
	var max_dist := 0
	for spot in spots:
		_check("клетка (%d,%d) проходима" % [spot.x, spot.y], board.is_passable(spot))
		max_dist = maxi(max_dist, board.distance(START, spot))
	_check("не дальше 2 от флага", max_dist <= 2, "максимум %d" % max_dist)
