extends SceneTree

## Тесты правил поля (ADR-001: вода). Запуск:
##   godot --headless --path . --script res://tests/rules_board.gd
## Здесь нет ни сцены, ни отрисовки — только правила.

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_terrain()
	_test_water_passability()
	_test_push_rule()
	_test_neighbors()
	_test_reachable()

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


func _make_board() -> Board:
	var board := Board.new()
	var water: Array[Vector2i] = [Vector2i(1, 0)]
	board.build_disk(2, water)
	return board


func _test_terrain() -> void:
	print("Террейн")
	var board := _make_board()
	_check("размер поля радиус 2 = 19", board.cells.size() == 19, "получили %d" % board.cells.size())
	_check("суша опознаётся", board.terrain_at(Vector2i(0, 0)) == Board.TERRAIN_LAND)
	_check("вода опознаётся", board.is_water(Vector2i(1, 0)))
	_check("клетка вне поля = -1", board.terrain_at(Vector2i(9, 9)) == -1)


func _test_water_passability() -> void:
	print("Вода: встать нельзя (ADR-001)")
	var board := _make_board()
	var water := Vector2i(1, 0)
	_check("пешком на воду нельзя", board.is_passable(water) == false)
	_check("с water_walk на воду можно", board.is_passable(water, {"water_walk": true}) == true)
	_check("на сушу можно", board.is_passable(Vector2i(0, 0)) == true)
	_check("вне поля нельзя", board.is_passable(Vector2i(9, 9)) == false)
	_check("вне поля нельзя даже с water_walk",
		board.is_passable(Vector2i(9, 9), {"water_walk": true}) == false)


func _test_push_rule() -> void:
	print("Вода: толкнуть нельзя (ADR-001)")
	var board := _make_board()
	_check("толкнуть в воду нельзя", board.can_push_into(Vector2i(1, 0)) == false)
	_check("толкнуть на сушу можно", board.can_push_into(Vector2i(0, 0)) == true)
	_check("толкнуть за поле нельзя", board.can_push_into(Vector2i(9, 9)) == false)


func _test_neighbors() -> void:
	print("Соседи")
	var board := _make_board()
	_check("у центра 6 соседей", board.neighbors(Vector2i(0, 0)).size() == 6)
	var inside := 0
	for coord in board.neighbors(Vector2i(2, 0)):
		if board.has_cell(coord):
			inside += 1
	_check("у края часть соседей за полем", inside < 6, "внутри %d" % inside)


func _test_reachable() -> void:
	print("Достижимые клетки")
	var board := _make_board()
	var one := board.reachable(Vector2i(0, 0), 1)
	_check("за 1 шаг — 5 клеток (6 соседей минус вода)", one.size() == 5, "получили %d" % one.size())
	_check("воды среди достижимых нет", one.has(Vector2i(1, 0)) == false)

	var two := board.reachable(Vector2i(0, 0), 2)
	_check("за 2 шага больше, чем за 1", two.size() > one.size())
	var water_inside := false
	for coord in two:
		if board.is_water(coord):
			water_inside = true
	_check("вода не входит в маршрут и на 2 шага", water_inside == false)

	var with_trait := board.reachable(Vector2i(0, 0), 1, {"water_walk": true})
	_check("с water_walk достижима вода", with_trait.has(Vector2i(1, 0)))
	_check("с water_walk — все 6 соседей", with_trait.size() == 6, "получили %d" % with_trait.size())
