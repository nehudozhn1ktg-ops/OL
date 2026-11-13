extends SceneTree

## Дальний бой и лес по патчу 7 (решение владельца 2026-11-14):
## у фигуры есть дальность атаки (по умолчанию 1 — только соседняя клетка),
## эльфы получают +1 (в данных range 2, у Данте 3); лес даёт +1 защиту только
## при атаке с соседней клетки, из леса бить вдаль можно.
## Запуск: godot --headless --path . --script res://tests/ranged.gd

const FOREST := Vector2i(0, 0)
const NEAR := Vector2i(1, 0)
const TWO_AWAY := Vector2i(2, 0)
const THREE_AWAY := Vector2i(3, 0)

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_default_range()
	_test_elf_range()
	_test_dante_range()
	_test_forest_only_melee()
	_test_attack_from_forest()
	_test_fort_always()
	_test_data_loads_range()

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


## Атакующий игрока 1 слева, цель игрока 2 справа.
func _duel(attacker_range: int, target_coord: Vector2i) -> Game:
	var game := _make_game()
	var attacker := game.add_unit(1, Vector2i.ZERO)
	attacker.configure("pawn", 3, 0, 0)
	attacker.range = attacker_range
	game.activate(attacker)
	game.add_unit(2, target_coord).configure("pawn", 2, 0, 0)
	return game


func _test_default_range() -> void:
	print("Пешка бьёт только соседнюю клетку")
	var game := _duel(1, NEAR)
	var attacker := game.units[0]
	var target := game.units[1]
	_check("range по умолчанию 1", attacker.range == 1)
	_check("на соседнюю клетку можно", game.can_attack(attacker, target)["ok"])

	var far := _duel(1, TWO_AWAY)
	_check("на две клетки нельзя", far.can_attack(far.units[0], far.units[1])["ok"] == false)
	_check("причина названа",
		far.can_attack(far.units[0], far.units[1])["reason"].contains("дальности атаки"))


func _test_elf_range() -> void:
	print("Эльф (range 2) бьёт на две клетки")
	var game := _duel(2, TWO_AWAY)
	_check("на две клетки можно", game.can_attack(game.units[0], game.units[1])["ok"])

	var too_far := _duel(2, THREE_AWAY)
	_check("на три клетки нельзя", too_far.can_attack(too_far.units[0], too_far.units[1])["ok"] == false)


func _test_dante_range() -> void:
	print("Данте (range 3) бьёт на три клетки")
	var game := _duel(3, THREE_AWAY)
	_check("на три клетки можно", game.can_attack(game.units[0], game.units[1])["ok"])


func _test_forest_only_melee() -> void:
	print("Лес защищает только от атаки в упор")
	var game := _make_game()
	var defender := game.add_unit(2, FOREST)
	defender.configure("pawn", 2, 0, 2)
	game.board.set_terrain(FOREST, Board.TERRAIN_FOREST)
	_check("в упор броня 2 + 1 = 3", game.defense_bonus(defender, 1) == 3,
		"= %d" % game.defense_bonus(defender, 1))
	_check("с дистанции 2 броня 2", game.defense_bonus(defender, 2) == 2,
		"= %d" % game.defense_bonus(defender, 2))


func _test_attack_from_forest() -> void:
	print("Из леса можно бить вдаль")
	var game := _make_game()
	var attacker := game.add_unit(1, FOREST)
	attacker.configure("pawn", 3, 0, 0)
	attacker.range = 2
	game.board.set_terrain(FOREST, Board.TERRAIN_FOREST)
	game.activate(attacker)
	game.add_unit(2, TWO_AWAY).configure("pawn", 2, 0, 0)
	_check("выстрел из леса по траве разрешён", game.can_attack(attacker, game.units[1])["ok"])

	# Проверка боя: защита цели в лесу без террейн-бонуса на дистанции 2.
	var forest_defender := game.add_unit(2, Vector2i(2, -1)).configure("pawn", 2, 0, 3)
	game.board.set_terrain(Vector2i(2, -1), Board.TERRAIN_FOREST)
	game.dice.force([2, 1])
	var blow := game.attack(attacker, forest_defender)
	_check("цель в лесу, дистанция 2 — бонуса нет (защита 1 + броня 3)", blow["defense"] == 4,
		"= %d" % blow["defense"])


func _test_fort_always() -> void:
	print("Укрепление даёт +1 и на дистанции")
	var game := _make_game()
	var defender := game.add_unit(2, FOREST).configure("pawn", 2, 0, 1)
	game.board.set_terrain(FOREST, Board.TERRAIN_FORT)
	_check("в упор 1 + 1 = 2", game.defense_bonus(defender, 1) == 2)
	_check("на дистанции 2 тоже 2", game.defense_bonus(defender, 2) == 2)


func _test_data_loads_range() -> void:
	print("Данные фракций: дальность из листа")
	var unit := Unit.from_data(1, Vector2i.ZERO, {"range": 2})
	_check("Unit читает range", unit.range == 2)

	var faction := FactionData.load_file("res://data/factions/elves.json")
	var dante_range := 0
	for entry in FactionData.roster(faction, 6):
		if str(entry.get("id", "")) == "dante":
			dante_range = int(entry.get("range", 1))
	_check("у Данте range 3", dante_range == 3, "= %d" % dante_range)
