extends SceneTree

## Пассивки элементалей Эфиральда: Огонь +1 урон, Земля +1 броня, Вода +1
## передвижение, Молния +1 дальность, Воздух — сквозь фигуры и воду.
## Запуск: godot --headless --path . --script res://tests/elemental_passives.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_stat_passives()
	_test_air_phase()
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


func _test_stat_passives() -> void:
	print("Пассивки элементалей (статы)")
	var game := _make_game()
	game.factions[1] = "elemental"

	var fire := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 1, 1, 3)
	fire.with_ability("fire_damage_bonus")
	_check("Огонь: +1 урон", game.attack_bonus(fire) == 2, "=%d" % game.attack_bonus(fire))

	var earth := game.add_unit(1, Vector2i(1, 0)).configure("pawn", 1, 1, 3)
	earth.with_ability("earth_armor_bonus")
	_check("Земля: +1 броня", game.defense_bonus(earth) == 4, "=%d" % game.defense_bonus(earth))

	var water := game.add_unit(1, Vector2i(2, 0)).configure("pawn", 1, 1, 3)
	water.with_ability("water_move_bonus")
	_check("Вода: +1 передвижение", game.move_value(water) == 2, "=%d" % game.move_value(water))

	var bolt := game.add_unit(1, Vector2i(3, 0)).configure("pawn", 1, 1, 3)
	bolt.range = 2
	bolt.with_ability("bolt_range_bonus")
	_check("Молния: +1 дальность", game.attack_range(bolt) == 3, "=%d" % game.attack_range(bolt))


func _test_air_phase() -> void:
	print("Воздух: сквозь фигуры и воду")
	var game := _make_game()
	game.factions[1] = "elemental"
	var air := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 1, 1, 3)
	air.with_ability("air_phase")
	air.mp_left = 2
	game.add_unit(1, Vector2i(0, -1)).configure("pawn", 1, 0, 0)  # занятая клетка
	game.board.set_terrain(Vector2i(1, 0), Board.TERRAIN_WATER)

	_check("сквозь фигуру", game.reachable(air).has(Vector2i(0, -1)))
	_check("сквозь воду", game.reachable(air).has(Vector2i(1, 0)))
