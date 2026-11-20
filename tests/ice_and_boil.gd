extends SceneTree

## Ледяное копьё Льда (фикс. 4 урона) и аура Кипения (2 кубика, мин).
## Запуск: godot --headless --path . --script res://tests/ice_and_boil.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_ice_lance()
	_test_boiling_aura()
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


func _test_ice_lance() -> void:
	print("Ледяное копьё")
	var game := _make_game()
	var lyod := game.add_unit(1, Vector2i(0, 0)).configure("cmd", 3, 2, 2)
	lyod.with_ability("bolt_range_bonus").with_ability("ice_lance")
	game.activate(lyod)

	var target := game.add_unit(2, Vector2i(0, 2)).configure("pawn", 2, 0, 0)
	_check("копьё на дальности 2", game.can_ice_lance(lyod, target)["ok"],
		game.can_ice_lance(lyod, target)["reason"])
	game.dice.force([4, 1])  # защита 1
	var blow := game.ice_lance(lyod, target)
	_check("урон 4+2=6", blow["damage"] == 6, "dmg=%d def=%d" % [blow["damage"], blow["defense"]])


func _test_boiling_aura() -> void:
	print("Аура Кипения (2 кубика, мин)")
	var game := _make_game()
	game.factions[1] = "elemental"
	var kip := game.add_unit(2, Vector2i(0, 0)).configure("cmd", 3, 2, 2)
	kip.with_ability("boiling_aura")

	var attacker := game.add_unit(1, Vector2i(0, 1)).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	game.dice.force([4, 1, 1])  # d1=4, d2=1 → мин=1; защита 1
	var blow := game.attack(attacker, kip)
	_check("урон с ауры = 1 (мин из 4 и 1)", blow["damage"] == 1,
		"dmg=%d (ждали 1)" % blow["damage"])