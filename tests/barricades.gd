extends SceneTree

## Баррикады людей (патч 7): ставятся рядом со своей фигурой, непроходимы,
## уничтожаются атакой любой силы. На воду и занятые клетки — нельзя.
## Запуск: godot --headless --path . --script res://tests/barricades.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_barricades()
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


func _test_barricades() -> void:
	print("Баррикады")
	var game := _make_game()
	game.factions[1] = "people"
	game.start_barricades(1)
	_check("стартовые 4 баррикады", game.barricades_of(1) == 4)

	var unit := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	var cell := Vector2i(0, 1)
	var v := game.place_barricade(1, cell)
	_check("баррикада поставлена", v["ok"])
	_check("осталось 3", game.barricades_of(1) == 3)
	_check("террейн = баррикада", game.board.terrain_at(cell) == Board.TERRAIN_BARRICADE)
	_check("баррикада непроходима", game.board.is_passable(cell) == false)

	game.board.set_terrain(Vector2i(1, 0), Board.TERRAIN_WATER)
	_check("на воду нельзя", game.place_barricade(1, Vector2i(1, 0))["ok"] == false)
	_check("на занятую фигурой нельзя", game.place_barricade(1, unit.coord)["ok"] == false)
	_check("вдали от своих фигур нельзя", game.place_barricade(1, Vector2i(3, 0))["ok"] == false)

	var attacker := game.add_unit(1, Vector2i(1, 1)).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	var av := game.attack_barricade(attacker, cell)
	_check("баррикада разрушена атакой", av["destroyed"])
	_check("террейн снова трава", game.board.terrain_at(cell) == Board.TERRAIN_GRASS)
