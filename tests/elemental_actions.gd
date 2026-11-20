extends SceneTree

## Магический щит (+2 к броне для следующей защиты) и телепортация Лавы.
## Запуск: godot --headless --path . --script res://tests/elemental_actions.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_shield()
	_test_teleport()
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


func _test_shield() -> void:
	print("Магический щит")
	var game := _make_game()
	game.factions[1] = "elemental"
	game.start_shield(1)
	_check("щитов 3 на старте", game.shield_of(1) == 3)

	var unit := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 3)
	var attacker := game.add_unit(2, Vector2i(0, 1)).configure("pawn", 2, 0, 0)
	_check("щит поднят", game.use_shield(1, unit)["ok"])
	_check("щитов осталось 2", game.shield_of(1) == 2)
	_check("повторно на ту же фигуру нельзя", game.use_shield(1, unit)["ok"] == false)

	game.current_player = 2
	game.activate(attacker)
	game.dice.force([4, 1])
	var blow := game.attack(attacker, unit)
	_check("защита со щитом 6 (1+3+2)", blow["defense"] == 6, "def=%d" % blow["defense"])
	_check("атака отбита", blow["hit"] == false)
	_check("щит сброшен после защиты", unit.shield == false)


func _test_teleport() -> void:
	print("Телепортация Лавы")
	var game := _make_game()
	game.factions[1] = "elemental"
	var lava := game.add_unit(1, Vector2i(0, 0)).configure("cmd", 3, 2, 2)
	lava.with_ability("lava_teleport")
	_check("без активации нельзя", game.can_teleport(lava, Vector2i(2, 0))["ok"] == false)
	game.activate(lava)
	_check("телепортация выполнена", game.teleport(lava, Vector2i(2, 0))["ok"])
	_check("фигура переместилась", lava.coord == Vector2i(2, 0))
	_check("фигура помечена двинутой", lava.moved)
	_check("повторно нельзя", game.can_teleport(lava, Vector2i(3, 0))["ok"] == false)
