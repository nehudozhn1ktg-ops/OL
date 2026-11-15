extends SceneTree

## Всплеск эссенции (ADR-011): 1 эссенция — кубик атаки минимум 3. Только атака,
## только активированные фигуры.
## Запуск: godot --headless --path . --script res://tests/surge.gd

const START := Vector2i.ZERO

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_die_minimum()
	_test_surge_spends_essence()
	_test_surge_refuses_without_essence()
	_test_surge_is_attack_only()

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


func _test_die_minimum() -> void:
	print("Кубик D4 с минимумом 3")
	var dice := Dice.new(42)
	var ok := true
	for _i in 40:
		var r := dice.d4(3)
		if r < 3 or r > 4:
			ok = false
	_check("d4(3) даёт только 3 или 4", ok)


func _test_surge_spends_essence() -> void:
	print("Всплеск тратит эссенцию и бьёт")
	var game := _make_game()
	game.factions[1] = "undead"
	game.essence[1] = 1
	var attacker := game.add_unit(1, START).configure("pawn", 2, 1, 0)
	game.activate(attacker)
	var defender := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 1)
	game.dice.force([3, 1])
	var blow := game.attack_with_surge(attacker, defender)
	_check("удар выполнен", blow["damage"] > 0, str(blow))
	_check("эссенция списана", game.essence_of(1) == 0, "= %d" % game.essence_of(1))


func _test_surge_refuses_without_essence() -> void:
	print("Без эссенции всплеска нет")
	var game := _make_game()
	game.factions[1] = "undead"
	var attacker := game.add_unit(1, START).configure("pawn", 2, 1, 0)
	game.activate(attacker)
	var defender := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 1)
	var blow := game.attack_with_surge(attacker, defender)
	_check("отказ", blow["damage"] == 0)
	_check("причина названа", str(blow["reason"]).contains("эссенции"))


func _test_surge_is_attack_only() -> void:
	print("Всплеск — только на атаку (нужна активация)")
	var game := _make_game()
	game.factions[1] = "undead"
	game.essence[1] = 3
	var attacker := game.add_unit(1, START).configure("pawn", 2, 1, 0)
	var defender := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 1)
	var blow := game.attack_with_surge(attacker, defender)
	_check("без активации отказ", blow["damage"] == 0)
	_check("эссенция не списана", game.essence_of(1) == 3)
