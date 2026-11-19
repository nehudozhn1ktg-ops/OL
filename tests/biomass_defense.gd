extends SceneTree

## Биомасса/защита (правильный тайминг, ADR-015):
## «−1 биомасса: +1 броня» — только в ответ на атаку врага, максимум +1 за защиту.
## Двухфазная атака: объявление → (ответ защитника) → бросок.
## Запуск: godot --headless --path . --script res://tests/biomass_defense.gd

const START := Vector2i.ZERO

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_declare_marks_attacker()
	_test_defend_in_response()
	_test_max_one_per_defense()
	_test_no_pause_without_biomass()
	_test_no_pause_without_infected()
	_test_attacker_pays_on_declare()
	_test_declare_fails_no_spend()
	_test_resolve_without_pending()

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


func _test_declare_marks_attacker() -> void:
	print("Объявление помечает атакующего и держит бросок")
	var game := _make_game()
	game.start_biomass(1)
	var attacker := game.add_unit(1, START).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	var defender := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	var decl := game.declare_attack(attacker, defender, true, false, false)
	_check("объявление прошло", bool(decl["ok"]), str(decl))
	_check("атакующий помечен атаковавшим", attacker.attacked)
	_check("бросок ещё не выполнен", game.pending_attack.get("attacker", null) == attacker)
	_check("защитник — цель отложенной атаки", game.pending_defender() == defender)


func _test_defend_in_response() -> void:
	print("+1 броня только в ответ на атаку")
	var game := _make_game()
	game.factions[2] = "infected"
	game.start_biomass(2)
	var attacker := game.add_unit(1, START).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	var defender := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 2)

	# Вне атаки усилить броню нельзя.
	_check("вне атаки усилить нельзя", game.can_defend_with_biomass(defender) == false)
	var denied := game.defend_with_biomass(defender)
	_check("усиление вне атаки отклонено", denied["ok"] == false)
	_check("биомасса цела", game.biomass_of(2) == 6, "= %d" % game.biomass_of(2))

	var decl := game.declare_attack(attacker, defender, false, false, false)
	_check("атака объявлена, защитнику нужна пауза",
		bool(decl["ok"]) and bool(decl["needs_defense"]), str(decl))

	var boost := game.defend_with_biomass(defender)
	_check("защита усилена", boost["ok"], str(boost))
	_check("броня +1 на фигуре", defender.armor_boost == 1)
	_check("списана 1 биомасса", game.biomass_of(2) == 5, "= %d" % game.biomass_of(2))

	game.dice.force([2, 2])
	var blow := game.resolve_attack()
	_check("защита 2 + броня 2 + усиление 1 = 5", blow["defense"] == 5, "= %d" % blow["defense"])
	_check("усиление израсходовано", defender.armor_boost == 0)
	_check("отложенная атака очищена", game.pending_attack.is_empty())


func _test_max_one_per_defense() -> void:
	print("Максимум +1 брони за одну защиту")
	var game := _make_game()
	game.factions[2] = "infected"
	game.start_biomass(2)
	var attacker := game.add_unit(1, START).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	var defender := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 2)
	game.declare_attack(attacker, defender)
	game.defend_with_biomass(defender)
	_check("повторно усилить нельзя", game.can_defend_with_biomass(defender) == false)
	var again := game.defend_with_biomass(defender)
	_check("повторное усиление отклонено", again["ok"] == false)
	_check("броня осталась 1", defender.armor_boost == 1)
	_check("списана только 1 биомасса", game.biomass_of(2) == 5, "= %d" % game.biomass_of(2))


func _test_no_pause_without_biomass() -> void:
	print("Без биомассы паузы нет")
	var game := _make_game()
	game.factions[2] = "infected"
	var attacker := game.add_unit(1, START).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	var defender := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 2)
	var decl := game.declare_attack(attacker, defender)
	_check("атака объявлена", bool(decl["ok"]), str(decl))
	_check("паузы нет", decl["needs_defense"] == false)
	_check("усиление недоступно", game.defend_with_biomass(defender)["ok"] == false)
	game.dice.force([1, 1])
	var blow := game.resolve_attack()
	_check("бросок выполнен сразу", blow["damage"] >= 1, "урон %d" % blow["damage"])


func _test_no_pause_without_infected() -> void:
	print("Не заражённый не может усилить броню")
	var game := _make_game()
	game.start_biomass(2)  # биомасса есть, но фракция игрока 2 не infected
	var attacker := game.add_unit(1, START).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	var defender := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 2)
	var decl := game.declare_attack(attacker, defender)
	_check("паузы нет для не-заражённого", decl["needs_defense"] == false)


func _test_attacker_pays_on_declare() -> void:
	print("Атакующий платит биомассу при объявлении")
	var game := _make_game()
	game.start_biomass(1)
	var attacker := game.add_unit(1, START).configure("pawn", 3, 0, 0)
	game.activate(attacker)
	var target := game.add_unit(2, Vector2i(2, 0)).configure("pawn", 2, 0, 0)
	var decl := game.declare_attack(attacker, target, false, true, false)
	_check("атака с дальностью объявлена", bool(decl["ok"]), str(decl))
	_check("списано 2 биомассы", game.biomass_of(1) == 4, "= %d" % game.biomass_of(1))


func _test_declare_fails_no_spend() -> void:
	print("Отказ объявления не тратит ресурсы")
	var game := _make_game()
	game.biomass[1] = 1
	var attacker := game.add_unit(1, START).configure("pawn", 3, 0, 0)
	game.activate(attacker)
	var target := game.add_unit(2, Vector2i(2, 0)).configure("pawn", 2, 0, 0)
	var decl := game.declare_attack(attacker, target, false, true, false)
	_check("отказ — не хватает биомассы", decl["ok"] == false)
	_check("биомасса цела", game.biomass_of(1) == 1)
	_check("атакующий не помечен", attacker.attacked == false)
	_check("отложенной атаки нет", game.pending_attack.is_empty())


func _test_resolve_without_pending() -> void:
	print("Бросок без объявленной атаки")
	var game := _make_game()
	var blow := game.resolve_attack()
	_check("бросок не выполнен", blow["damage"] == 0)
	_check("причина названа", str(blow["reason"]) != "")
