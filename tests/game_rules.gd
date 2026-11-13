extends SceneTree

## Правила хода по 0.7.1: активация двух фигур, движение до своего значения,
## смена игрока, смена суток, очки за ключевые точки.
## Запуск: godot --headless --path . --script res://tests/game_rules.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_start()
	_test_movement()
	_test_activation_limit()
	_test_move_only_without_activation()
	_test_turn_switch()
	_test_points_on_turn_start()

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
	board.build_disk(3)
	var game := Game.new()
	game.setup(board, Dice.new(7))
	return game


func _test_start() -> void:
	print("Начало партии")
	var game := _make_game()
	var unit := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	_check("первым ходит игрок 1", game.current_player == 1)
	_check("первый раунд днём", game.is_day)
	_check("фигура найдена по клетке", game.unit_at(Vector2i(0, 0)) == unit)
	_check("счёт с нуля", game.scores[1] == 0)


func _test_movement() -> void:
	print("Передвижение")
	var game := _make_game()
	var unit := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	_check("на соседнюю можно", game.can_move(unit, Vector2i(0, 1))["ok"])
	_check("на две клетки можно (move=2)", game.can_move(unit, Vector2i(0, 2))["ok"])
	_check("на три нельзя", game.can_move(unit, Vector2i(0, 3))["ok"] == false)
	_check("дальность названа", game.can_move(unit, Vector2i(0, 3))["reason"].contains("передвижение"))

	_check("ход выполняется", game.move_unit(unit, Vector2i(0, 2)))
	_check("координата обновилась", unit.coord == Vector2i(0, 2))
	_check("второй раз за ход нельзя", game.can_move(unit, Vector2i(0, 3))["ok"] == false)

	var swim := _make_game()
	swim.board.set_terrain(Vector2i(1, 0), Board.TERRAIN_WATER)
	var walker := swim.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	_check("через воду пути нет", swim.can_move(walker, Vector2i(1, 0))["ok"] == false)
	var swimmer := swim.add_unit(1, Vector2i(-1, 0), true).configure("pawn", 2, 0, 0)
	_check("с water_walk вода проходима", swimmer.traits()["water_walk"])


func _test_activation_limit() -> void:
	print("Активация: две фигуры за ход")
	var game := _make_game()
	var a := game.add_unit(1, Vector2i(0, 0))
	var b := game.add_unit(1, Vector2i(1, 0))
	var c := game.add_unit(1, Vector2i(2, 0))
	_check("первая активируется", game.activate(a))
	_check("вторая активируется", game.activate(b))
	_check("третья — уже нельзя", game.activate(c) == false)
	_check("причина названа", game.can_activate(c)["reason"].contains("2"))
	_check("счётчик активаций верный", game.activated_count(1) == 2)
	_check("чужая фигура не активируется", game.can_activate(game.add_unit(2, Vector2i(0, 2)))["ok"] == false)


func _test_move_only_without_activation() -> void:
	print("Без активации — только движение")
	var game := _make_game()
	var unit := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	_check("двигаться можно без активации", game.can_move(unit, Vector2i(0, 1))["ok"])
	_check("атаковать нельзя", game.can_attack(unit, game.add_unit(2, Vector2i(1, 0)))["ok"] == false)


func _test_turn_switch() -> void:
	print("Смена хода и суток")
	var game := _make_game()
	var first := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	var second := game.add_unit(2, Vector2i(2, 0)).configure("pawn", 2, 0, 0)
	game.activate(first)
	game.move_unit(first, Vector2i(0, 1))

	game.end_turn()
	_check("ходит игрок 2", game.current_player == 2)
	_check("активации сброшены", game.activated_count(1) == 0)
	_check("движение сброшено", second.moved == false)
	_check("свежая фигура может идти", game.can_move(second, Vector2i(1, 0))["ok"])

	game.end_turn()
	_check("снова игрок 1", game.current_player == 1)
	_check("номер раунда вырос", game.round_number == 2)
	_check("сутки сменились на ночь", game.is_day == false)


func _test_points_on_turn_start() -> void:
	print("Очки в начале хода")
	var game := _make_game()
	game.add_unit(1, Vector2i(0, 0))
	game.board.set_terrain(Vector2i(0, 0), Board.TERRAIN_KEY)
	game.begin_turn()
	_check("очко за фигуру на точке", game.scores[1] == 1, "счёт %d" % game.scores[1])
	_check("причина записана", game.points_collected_last == 1)

	var empty := _make_game()
	empty.add_unit(1, Vector2i(0, 0))
	empty.begin_turn()
	_check("без точки очков нет", empty.scores[1] == 0)
