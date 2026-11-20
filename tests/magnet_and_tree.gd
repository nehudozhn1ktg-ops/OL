extends SceneTree

## Дерево (трава = лес) и Магнетизм (притянуть союзника после движения).
## Запуск: godot --headless --path . --script res://tests/magnet_and_tree.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_tree_bark()
	_test_magnet_pull()
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


func _test_tree_bark() -> void:
	print("Дерево: трава считается лесом")
	var game := _make_game()
	var derevo := game.add_unit(1, Vector2i(0, 0)).configure("cmd", 3, 2, 2)
	derevo.with_ability("tree_bark").with_ability("earth_armor_bonus")
	# на траве: дерево даёт лесной бонус (+1 защита)
	_check("на траве +1 (лес через tree_bark)", game.terrain_defense_bonus(derevo) == 1,
		"=%d" % game.terrain_defense_bonus(derevo))
	# поставим настоящий лес и проверим
	game.board.set_terrain(Vector2i(1, 0), Board.TERRAIN_FOREST)
	derevo.coord = Vector2i(1, 0)
	_check("в настоящем лесу тоже +1", game.terrain_defense_bonus(derevo) == 1)


func _test_magnet_pull() -> void:
	print("Магнетизм: притянуть союзника после движения")
	var game := _make_game()
	var magnet := game.add_unit(1, Vector2i(0, 0)).configure("cmd", 3, 2, 2)
	magnet.with_ability("magnet_pull")
	var ally := game.add_unit(1, Vector2i(2, 0)).configure("pawn", 2, 0, 0)

	game.activate(magnet)
	game.move_unit(magnet, Vector2i(1, 0))
	var pull_to := Vector2i(2, -1)
	_check("магнетизм доступен после движения", game.can_pull_ally(magnet, ally, pull_to)["ok"],
		game.can_pull_ally(magnet, ally, pull_to)["reason"])
	var v := game.pull_ally(magnet, ally, pull_to)
	_check("союзник притянут", v["ok"])
	_check("союзник переместился", ally.coord == pull_to)