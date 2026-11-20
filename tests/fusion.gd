extends SceneTree

## Слияние Эфиральда (патч 7): два соседних элементаля → слияние на месте цели.
## Запуск: godot --headless --path . --script res://tests/fusion.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_fusion()
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


func _elem(game: Game, id: String, at: Vector2i) -> Unit:
	var u := game.add_unit(1, at).configure("pawn", 1, 1, 3)
	u.unit_id = id
	u.elemental = true
	u.no_wound = true
	return u


func _test_fusion() -> void:
	print("Слияние Эфиральда")
	var game := _make_game()
	game.factions[1] = "elemental"
	var data := FactionData.load_file("res://data/factions/elemental.json")
	game.register_fusions(1, FactionData.fusions(data))
	_check("слияний зарегистрировано 10", game.fusion_defs[1].size() == 10)

	var fire := _elem(game, "el_fire", Vector2i(0, 0))
	var earth := _elem(game, "el_earth", Vector2i(1, 0))
	_check("без активации нельзя", game.can_fuse(fire, earth)["ok"] == false)
	game.activate(fire)
	var v := game.fuse(fire, earth)
	_check("слияние создано", v["ok"])
	var fused := game.unit_at(Vector2i(1, 0))
	_check("«Лава» создана на месте цели", fused != null and fused.unit_id == "lava")
	_check("элементали убраны", not game.units.has(fire) and not game.units.has(earth))

	var a := _elem(game, "el_fire", Vector2i(0, 2))
	var b := _elem(game, "el_water", Vector2i(1, 2))
	var non := game.add_unit(1, Vector2i(0, 1)).configure("pawn", 2, 0, 0)
	game.activate(a)
	_check("не-элементаль в пару нельзя", game.can_fuse(a, non)["ok"] == false)

	var c := _elem(game, "el_air", Vector2i(3, 0))
	_check("не-соседнюю пару нельзя", game.can_fuse(a, c)["ok"] == false)

	var game2 := _make_game()
	game2.factions[1] = "undead"
	var d := game2.add_unit(1, Vector2i(0, 0)).configure("pawn", 1, 1, 3)
	var e := game2.add_unit(1, Vector2i(1, 0)).configure("pawn", 1, 1, 3)
	game2.activate(d)
	_check("не-Эфиральду слияние недоступно", game2.can_fuse(d, e)["ok"] == false)
