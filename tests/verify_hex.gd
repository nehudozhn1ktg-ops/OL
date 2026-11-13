extends SceneTree

## Headless-проверка геометрии поля. Запуск:
##   godot --headless --path . --script res://tests/verify_hex.gd
## Не требует окна и сцены: проверяет только математику.

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_roundtrip()
	_test_distance()
	_test_within_radius()

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
	print("Пиксель -> клетка -> пиксель")
	var grid := HexGrid.new()
	var coords: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
		Vector2i(1, -1), Vector2i(-2, 3), Vector2i(3, -2), Vector2i(-3, 1),
	]
	for coord in coords:
		var back := grid.pixel_to_hex(grid.hex_to_pixel(coord))
		_check("клетка %s" % coord, back == coord, "получили %s" % back)
	grid.free()


func _test_distance() -> void:
	print("Расстояние в гексах")
	var board := Board.new()
	_check("центр-центр = 0", board.distance(Vector2i(0, 0), Vector2i(0, 0)) == 0)
	_check("сосед = 1", board.distance(Vector2i(0, 0), Vector2i(1, 0)) == 1)
	_check("(0,0)-(2,-1) = 2", board.distance(Vector2i(0, 0), Vector2i(2, -1)) == 2)
	_check("(0,0)-(0,3) = 3", board.distance(Vector2i(0, 0), Vector2i(0, 3)) == 3)
	_check("симметрия", board.distance(Vector2i(-1, 2), Vector2i(3, -1)) == board.distance(Vector2i(3, -1), Vector2i(-1, 2)))


func _test_within_radius() -> void:
	print("Клетки в радиусе (3r^2 + 3r + 1)")
	var board := Board.new()
	_check("радиус 0 = 1", board.within_radius(Vector2i(0, 0), 0).size() == 1)
	_check("радиус 1 = 7", board.within_radius(Vector2i(0, 0), 1).size() == 7)
	_check("радиус 2 = 19", board.within_radius(Vector2i(0, 0), 2).size() == 19)
	_check("радиус 3 = 37", board.within_radius(Vector2i(0, 0), 3).size() == 37)
	var far := board.within_radius(Vector2i(5, -2), 2)
	var all_near := true
	for coord in far:
		if board.distance(Vector2i(5, -2), coord) > 2:
			all_near = false
	_check("смещённый центр не выходит за радиус", all_near)
