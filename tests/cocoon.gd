extends SceneTree

## Кокон возрождения заражённых (патч 7): ставится рядом со своей фигурой, при
## первой гибели фигура возрождается на его месте живой (без очка противнику).
## Уничтожается атакой любой силы.
## Запуск: godot --headless --path . --script res://tests/cocoon.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_cocoon()
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


func _test_cocoon() -> void:
	print("Кокон возрождения")
	var game := _make_game()
	game.factions[1] = "infected"
	game.factions[2] = "undead"
	var unit := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	var attacker := game.add_unit(2, Vector2i(0, 1)).configure("pawn", 2, 0, 0)

	var cocoon_cell := Vector2i(1, 0)
	_check("кокон поставлен", game.place_cocoon(1, cocoon_cell)["ok"])
	_check("кокон на клетке", game.cocoon_of(1) == cocoon_cell)
	_check("второй кокон нельзя", game.place_cocoon(1, Vector2i(1, 1))["ok"] == false)

	game.board.set_terrain(Vector2i(0, -1), Board.TERRAIN_WATER)
	_check("на воду нельзя", game.place_cocoon(1, Vector2i(0, -1))["ok"] == false)
	_check("вдали нельзя", game.place_cocoon(1, Vector2i(3, 0))["ok"] == false)

	unit.wounded = true
	game.current_player = 2
	game.activate(attacker)
	game.dice.force([4, 1])
	var blow := game.attack(attacker, unit)
	_check("фигура возродилась (не убита)",
		blow.get("reborn", false) == true and blow.get("killed", false) == false)
	_check("фигура на месте кокона", unit.coord == cocoon_cell)
	_check("фигура не ранена после возрождения", unit.wounded == false)
	_check("кокон израсходован", game.cocoon_of(1) == Vector2i(-999999, -999999))
	_check("очков противнику за возрождение нет", game.scores[2] == 0)
