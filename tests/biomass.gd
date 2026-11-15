extends SceneTree

## Биомасса заражённых (фракционный лист 0–6, патч 7):
## старт — максимум, +1 за уничтоженного противника, +2 за свою потерю;
## трата: 1 = +1 урон, 2 = +1 дальность атаки (выбор игрока после «Атаки»).
## Запуск: godot --headless --path . --script res://tests/biomass.gd

const START := Vector2i.ZERO

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_start_and_cap()
	_test_spend()
	_test_gain_on_kill()
	_test_gain_on_loss()
	_test_damage_boost()
	_test_range_boost()
	_test_not_enough()
	_test_move_boost()
	_test_armor_boost()

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


func _test_start_and_cap() -> void:
	print("Старт и предел биомассы")
	var game := _make_game()
	game.start_biomass(1)
	_check("в начале матча 6", game.biomass_of(1) == 6, "= %d" % game.biomass_of(1))
	game.add_biomass(1, 5)
	_check("выше 6 не поднимается", game.biomass_of(1) == 6, "= %d" % game.biomass_of(1))


func _test_spend() -> void:
	print("Трата")
	var game := _make_game()
	game.start_biomass(1)
	_check("списать 2 можно", game.spend_biomass(1, 2))
	_check("осталось 4", game.biomass_of(1) == 4)
	_check("списать больше, чем есть, нельзя", game.spend_biomass(1, 9) == false)
	_check("биомасса не ушла", game.biomass_of(1) == 4)


func _test_gain_on_kill() -> void:
	print("+1 за уничтоженного противника")
	var game := _make_game()
	game.factions[1] = "infected"
	var attacker := game.add_unit(1, START).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	var victim := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	victim.wounded = true
	game.dice.force([4, 1])
	var blow := game.attack(attacker, victim)
	_check("фигура погибла", blow["killed"])
	_check("атакующий получил 1", game.biomass_of(1) == 1, "= %d" % game.biomass_of(1))


func _test_gain_on_loss() -> void:
	print("+2 за свою уничтоженную фигуру")
	var game := _make_game()
	game.factions[2] = "infected"
	var attacker := game.add_unit(1, START).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	var victim := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	victim.wounded = true
	game.dice.force([4, 1])
	game.attack(attacker, victim)
	_check("потерявший получил 2", game.biomass_of(2) == 2, "= %d" % game.biomass_of(2))


func _test_damage_boost() -> void:
	print("1 биомасса = +1 к урону")
	var game := _make_game()
	game.start_biomass(1)
	var attacker := game.add_unit(1, START).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	var defender := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	game.dice.force([2, 2])
	var plain := game.attack(attacker, defender)
	_check("обычная атака: урон 2 защита 2 — мимо", plain["hit"] == false, "урон %d" % plain["damage"])

	var boosted := _make_game()
	boosted.start_biomass(1)
	var hero := boosted.add_unit(1, START).configure("pawn", 2, 0, 0)
	boosted.activate(hero)
	var target := boosted.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	boosted.dice.force([2, 2])
	var blow := boosted.attack_with_biomass(hero, target, true, false)
	_check("усиленная: урон 3 против 2 — попадание", blow["hit"], "урон %d" % blow["damage"])
	_check("списана 1 биомасса", boosted.biomass_of(1) == 5, "= %d" % boosted.biomass_of(1))


func _test_range_boost() -> void:
	print("2 биомассы = +1 к дальности")
	var game := _make_game()
	game.start_biomass(1)
	var attacker := game.add_unit(1, START).configure("pawn", 3, 0, 0)
	game.activate(attacker)
	var target := game.add_unit(2, Vector2i(2, 0)).configure("pawn", 2, 0, 0)
	_check("без усиления цель недосягаема", game.can_attack(attacker, target)["ok"] == false)

	game.dice.force([4, 1])
	var blow := game.attack_with_biomass(attacker, target, false, true)
	_check("с усилением атака прошла", blow["damage"] > 0, str(blow))
	_check("списано 2 биомассы", game.biomass_of(1) == 4, "= %d" % game.biomass_of(1))


func _test_not_enough() -> void:
	print("Не хватает биомассы")
	var game := _make_game()
	game.biomass[1] = 1
	var attacker := game.add_unit(1, START).configure("pawn", 3, 0, 0)
	game.activate(attacker)
	var target := game.add_unit(2, Vector2i(2, 0)).configure("pawn", 2, 0, 0)
	var blow := game.attack_with_biomass(attacker, target, false, true)
	_check("атака отклонена", blow["damage"] == 0)
	_check("причина названа", blow["reason"].contains("биомассы"))
	_check("атака не израсходована", attacker.attacked == false)
	_check("биомасса не списана", game.biomass_of(1) == 1)

	var far := _make_game()
	far.start_biomass(1)
	var shooter := far.add_unit(1, START).configure("pawn", 3, 0, 0)
	far.activate(shooter)
	var distant := far.add_unit(2, Vector2i(3, 0)).configure("pawn", 2, 0, 0)
	var miss := far.attack_with_biomass(shooter, distant, true, true)
	_check("слишком далеко — отказ", miss["damage"] == 0)
	_check("биомасса не списана", far.biomass_of(1) == 6, "= %d" % far.biomass_of(1))


func _test_move_boost() -> void:
	print("1 биомасса = +1 клетка передвижения")
	var game := _make_game()
	game.start_biomass(1)
	var unit := game.add_unit(1, START).configure("pawn", 2, 0, 0)
	var target := Vector2i(3, 0)
	_check("без усиления далеко", game.can_move(unit, target)["ok"] == false)
	_check("с усилением можно", game.can_move(unit, target, 1)["ok"])
	var verdict := game.move_with_biomass(unit, target, 1)
	_check("переход выполнен", verdict["ok"], str(verdict))
	_check("фигура на месте", unit.coord == target)
	_check("списана 1 биомасса", game.biomass_of(1) == 5, "= %d" % game.biomass_of(1))

	var poor := _make_game()
	var walker := poor.add_unit(1, START).configure("pawn", 2, 0, 0)
	var denied := poor.move_with_biomass(walker, Vector2i(3, 0), 1)
	_check("без биомассы отказ", denied["ok"] == false)
	_check("причина названа", str(denied["reason"]).contains("биомассы"))
	_check("фигура не двинулась", walker.coord == START)


func _test_armor_boost() -> void:
	print("1 биомасса = +1 броня к следующей защите")
	var game := _make_game()
	game.start_biomass(2)  # биомасса у защищающегося (владельца фигуры)
	var attacker := game.add_unit(1, START).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	var defender := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 2)
	var boost := game.boost_armor(defender)
	_check("усиление выдано", boost["ok"], str(boost))
	_check("броня +1 на фигуре", defender.armor_boost == 1)
	_check("списана 1 биомасса", game.biomass_of(2) == 5, "= %d" % game.biomass_of(2))

	game.dice.force([2, 2])
	var blow := game.attack(attacker, defender)
	_check("в защите 2 + броня 2 + усиление 1 = 5", blow["defense"] == 5, "= %d" % blow["defense"])
	_check("усиление израсходовано", defender.armor_boost == 0)

	var empty := _make_game()
	var bare := empty.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 2)
	_check("без биомассы отказ", empty.boost_armor(bare)["ok"] == false)
	_check("броня не выросла", bare.armor_boost == 0)
