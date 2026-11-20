extends SceneTree

## Бонусы слияний Эфиральда: Шторм (+1 движение, water_walk), Дерево (+1 броня),
## Лёд (+1 дальность), Жар (невосприимчивость к дальним атакам).
## Запуск: godot --headless --path . --script res://tests/fusion_abilities.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_fusion_bonuses()
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


func _test_fusion_bonuses() -> void:
	print("Бонусы слияний")
	var game := _make_game()
	game.factions[1] = "elemental"

	var shtorm := game.add_unit(1, Vector2i(0, 0)).configure("cmd", 3, 2, 2)
	shtorm.with_ability("storm").with_ability("water_move_bonus")
	_check("Шторм: +1 передвижение", game.move_value(shtorm) == 4)
	_check("Шторм: water_walk", shtorm.traits()["water_walk"])

	var derevo := game.add_unit(1, Vector2i(1, 0)).configure("cmd", 3, 2, 2)
	derevo.with_ability("earth_armor_bonus")
	_check("Дерево: +1 броня", game.defense_bonus(derevo) == 3)

	var lyod := game.add_unit(1, Vector2i(2, 0)).configure("cmd", 3, 2, 2)
	lyod.with_ability("bolt_range_bonus")
	_check("Лёд: +1 дальность (2)", game.attack_range(lyod) == 2)

	var zhar := game.add_unit(2, Vector2i(3, 0)).configure("cmd", 3, 0, 0)
	zhar.with_ability("heat_shield")
	var bolt := game.add_unit(1, Vector2i(3, 2)).configure("pawn", 2, 0, 0)
	bolt.range = 2
	game.current_player = 1
	game.activate(bolt)
	_check("Жар: дальняя атака по нему отклонена", game.can_attack(bolt, zhar)["ok"] == false)
	bolt.coord = Vector2i(3, 1)  # в упор
	_check("Жар: в упор — можно", game.can_attack(bolt, zhar)["ok"])