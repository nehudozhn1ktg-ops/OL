extends SceneTree

## Рокировка людей (патч 7): активная — активированная фигура меняется местами
## с соседней своей (раз за ход); защитная — до броска атака перенаправляется.
## Запуск: godot --headless --path . --script res://tests/castle.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_active_castle()
	_test_defensive_castle()
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


func _test_active_castle() -> void:
	print("Активная рокировка")
	var game := _make_game()
	game.factions[1] = "people"
	var u1 := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	var u2 := game.add_unit(1, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	var far := game.add_unit(1, Vector2i(3, 0)).configure("pawn", 2, 0, 0)

	_check("без активации нельзя", game.can_castle(u1, u2)["ok"] == false)
	game.activate(u1)
	_check("рокировка выполнена", game.castle(u1, u2)["ok"])
	_check("координаты поменялись", u1.coord == Vector2i(1, 0) and u2.coord == Vector2i(0, 0))
	_check("повторно в этот ход нельзя", game.can_castle(u1, u2)["ok"] == false)

	game.activate(far)
	_check("с дальней своей нельзя", game.can_castle(far, u1)["ok"] == false)

	var game2 := _make_game()
	game2.factions[1] = "undead"
	var a := game2.add_unit(1, Vector2i(0, 0))
	var b := game2.add_unit(1, Vector2i(1, 0))
	game2.activate(a)
	_check("не-людям рокировка недоступна", game2.can_castle(a, b)["ok"] == false)


func _test_defensive_castle() -> void:
	print("Защитная рокировка")
	var game := _make_game()
	game.factions[1] = "people"
	game.factions[2] = "undead"
	var defender := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	var ally := game.add_unit(1, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	var attacker := game.add_unit(2, Vector2i(0, 1)).configure("pawn", 2, 0, 0)

	game.current_player = 2
	game.activate(attacker)
	game.declare_attack(attacker, defender)
	_check("защитная рокировка доступна", game.can_castle_defense(defender))

	var v := game.castle_defense(defender, ally)
	_check("защитная рокировка выполнена", v["ok"])
	_check("атака перенаправлена на союзника", game.pending_defender() == ally)

	var blow := game.resolve_attack()
	_check("бросок прошёл по перенаправленной цели", blow.has("damage"))
