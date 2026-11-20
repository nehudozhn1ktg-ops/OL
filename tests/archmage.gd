extends SceneTree

## Архимаг Эфиральда: наследует пассивки живых элементалей, атака И действие,
## возрождает погибшего элементаля на соседней клетке.
## Запуск: godot --headless --path . --script res://tests/archmage.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_heart_of_elements()
	_test_attack_and_act()
	_test_resurrect()
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


func _test_heart_of_elements() -> void:
	print("Сердце стихий: пассивки элементалей")
	var game := _make_game()
	var am := game.add_unit(1, Vector2i(0, 0)).configure("king", 2, 2, 3)
	am.with_ability("heart_of_elements")

	_check("без элементалей: урон 2", game.attack_bonus(am) == 2)
	_check("без элементалей: броня 3", game.defense_bonus(am) == 3)

	var earth := game.add_unit(1, Vector2i(1, 0)).configure("pawn", 1, 1, 3)
	earth.with_ability("earth_armor_bonus")
	earth.elemental = true
	_check("с Землёй: броня +1 = 4", game.defense_bonus(am) == 4)

	var fire := game.add_unit(1, Vector2i(2, 0)).configure("pawn", 1, 1, 3)
	fire.with_ability("fire_damage_bonus")
	fire.elemental = true
	_check("с Огнём: урон +1 = 3", game.attack_bonus(am) == 3)

	var water := game.add_unit(1, Vector2i(3, 0)).configure("pawn", 1, 1, 3)
	water.with_ability("water_move_bonus")
	water.elemental = true
	water.mp_left = 2
	_check("с Водой: движение +1 = 3", game.move_value(am) == 3, "mp=%d" % water.mp_left)

	# после гибели элементаля бонус пропадает
	game._remove(earth)
	_check("после гибели Земли: броня 3", game.defense_bonus(am) == 3)


func _test_attack_and_act() -> void:
	print("Атака И действие")
	var game := _make_game()
	var am := game.add_unit(1, Vector2i(0, 0)).configure("king", 2, 2, 3)
	am.with_ability("heart_of_elements")
	game.activate(am)

	var enemy := game.add_unit(2, Vector2i(0, 1)).configure("pawn", 2, 0, 0)
	game.dice.force([1, 4])  # урон 1, защита 4 — промах, но атака засчитана
	game.attack(am, enemy)
	_check("после атаки может действовать", game.can_act(am)["ok"])


func _test_resurrect() -> void:
	print("Возрождение элементаля")
	var game := _make_game()
	var am := game.add_unit(1, Vector2i(0, 0)).configure("king", 2, 2, 3)
	am.with_ability("heart_of_elements")
	game.activate(am)

	var fire := game.add_unit(1, Vector2i(1, 0)).configure("pawn", 1, 1, 3)
	fire.with_ability("fire_damage_bonus")
	fire.elemental = true
	game._remove(fire)
	_check("Огонь в могиле", game.graveyard.has(fire))

	var cell := Vector2i(0, 1)
	var v := game.resurrect_elemental(am, cell)
	_check("элементаль возрождён", v["ok"])
	_check("Огонь на поле", game.units.has(fire))
	_check("клетка (0,1)", fire.coord == cell)
	_check("живой (не ранен)", fire.wounded == false and fire.no_wound == true)