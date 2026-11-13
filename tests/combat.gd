extends SceneTree

## Бой по правилам 0.7.1: D4 + бонусы, монета при проигрыше в защите.
## Кубик подменяется заранее заданными значениями, поэтому тест детерминирован.
## Запуск: godot --headless --path . --script res://tests/combat.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_bonuses()
	_test_hit_and_defense()
	_test_wound_and_coin()
	_test_second_wound_kills()
	_test_attack_rules()
	_test_points()

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


func _make_game(dice: Dice = null) -> Game:
	var board := Board.new()
	board.build_disk(3)
	var game := Game.new()
	game.setup(board, dice if dice != null else Dice.new(12345))
	return game


func _test_bonuses() -> void:
	print("Бонусы защиты")
	var game := _make_game()
	var unit := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 1, 0)
	_check("на траве без бонусов", game.defense_bonus(unit) == 0, "= %d" % game.defense_bonus(unit))

	game.board.set_terrain(Vector2i(0, 0), Board.TERRAIN_FOREST)
	_check("лес даёт +1", game.defense_bonus(unit) == 1, "= %d" % game.defense_bonus(unit))

	game.board.set_terrain(Vector2i(0, 0), Board.TERRAIN_FORT)
	_check("укрепление даёт +1", game.defense_bonus(unit) == 1, "= %d" % game.defense_bonus(unit))

	game.board.set_terrain(Vector2i(0, 0), Board.TERRAIN_GRASS)
	var commander := game.add_unit(1, Vector2i(1, 0)).with_ability("commander")
	_check("аура командира +1 союзнику", game.defense_bonus(unit) == 1, "= %d" % game.defense_bonus(unit))
	_check("командир не усиливает себя", game.defense_bonus(commander) == 0, "= %d" % game.defense_bonus(commander))

	var armored := game.add_unit(2, Vector2i(-2, 0)).configure("pawn", 1, 0, 2)
	_check("броня складывается", game.defense_bonus(armored) == 2, "= %d" % game.defense_bonus(armored))


func _test_hit_and_defense() -> void:
	print("Попадание и защита")
	var dice := Dice.new()
	var game := _make_game(dice)
	var attacker := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 1, 0)
	var defender := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	game.activate(attacker)

	dice.force([3, 1], ["white"])
	var hit := game.attack(attacker, defender)
	_check("урон больше защиты — попадание", hit["hit"], "урон %d защита %d" % [hit["damage"], hit["defense"]])
	_check("урон = D4 + бонус", hit["damage"] == 4, "= %d" % hit["damage"])

	var game2 := _make_game(dice)
	var atk2 := game2.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	var def2 := game2.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	game2.board.set_terrain(Vector2i(1, 0), Board.TERRAIN_FORT)
	game2.activate(atk2)
	dice.force([2, 2])
	var miss := game2.attack(atk2, def2)
	_check("защита 2+1 перекрывает урон 2", miss["hit"] == false, "урон %d защита %d" % [miss["damage"], miss["defense"]])
	_check("при защите монета не бросается", miss["coin"] == "")

	var game3 := _make_game(dice)
	var atk3 := game3.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	var def3 := game3.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	game3.activate(atk3)
	dice.force([2, 2])
	var equal := game3.attack(atk3, def3)
	_check("равенство — защита (по правилам «защита урона»)", equal["hit"] == false)


func _test_wound_and_coin() -> void:
	print("Ранение и монета")
	var dice := Dice.new()
	var game := _make_game(dice)
	var attacker := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 1, 0)
	var defender := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	game.activate(attacker)

	dice.force([4, 1], ["white"])
	var white := game.attack(attacker, defender)
	_check("белая монета — ранен", white["wounded"])
	_check("фигура осталась на поле", game.unit_at(Vector2i(1, 0)) != null)
	_check("рана отмечена", defender.wounded)

	var game2 := _make_game(dice)
	var a2 := game2.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 1, 0)
	var d2 := game2.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	game2.activate(a2)
	dice.force([4, 1], ["black"])
	var black := game2.attack(a2, d2)
	_check("чёрная монета — гибель", black["killed"])
	_check("погибшая убрана", game2.unit_at(Vector2i(1, 0)) == null)
	_check("очко за уничтожение", game2.scores[1] == 1, "счёт %d" % game2.scores[1])


func _test_second_wound_kills() -> void:
	print("Второй проигрыш в защите")
	var dice := Dice.new()
	var game := _make_game(dice)
	var first := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 1, 0)
	var second := game.add_unit(1, Vector2i(2, 0)).configure("pawn", 2, 1, 0)
	var victim := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	game.activate(first)
	game.activate(second)

	dice.force([4, 1], ["white"])
	game.attack(first, victim)
	_check("после первой раны жива", victim.wounded and game.unit_at(Vector2i(1, 0)) != null)

	dice.force([4, 1])
	var final := game.attack(second, victim)
	_check("второй проигрыш убивает без монеты", final["killed"])
	_check("монета не бросалась", final["coin"] == "")
	_check("фигура убрана", game.unit_at(Vector2i(1, 0)) == null)


func _test_attack_rules() -> void:
	print("Правила атаки")
	var game := _make_game()
	var fighter := game.add_unit(1, Vector2i(0, 0))
	var enemy := game.add_unit(2, Vector2i(1, 0))
	var far := game.add_unit(2, Vector2i(3, 0))
	var ally := game.add_unit(1, Vector2i(-1, 0))

	_check("неактивированная атаковать не может", game.can_attack(fighter, enemy)["ok"] == false)
	_check("причина названа", game.can_attack(fighter, enemy)["reason"].contains("не активирована"))

	game.activate(fighter)
	_check("после активации можно", game.can_attack(fighter, enemy)["ok"])
	_check("через клетку нельзя", game.can_attack(fighter, far)["ok"] == false)
	_check("по своим нельзя", game.can_attack(fighter, ally)["ok"] == false)

	game.dice.force([4, 1], ["black"])
	game.attack(fighter, enemy)
	_check("дважды за ход нельзя", game.can_attack(fighter, enemy)["ok"] == false)


func _test_points() -> void:
	print("Ключевые точки")
	var game := _make_game()
	var scorer := game.add_unit(1, Vector2i(0, 0))
	game.board.set_terrain(Vector2i(0, 0), Board.TERRAIN_KEY)
	var gained := game.collect_points(1)
	_check("очко начисляется", gained == 1, "очков %d" % gained)
	_check("счёт записан", game.scores[1] == 1)

	game.move_unit(scorer, Vector2i(0, 1))
	_check("с точки ушёл — очков нет", game.collect_points(1) == 0)
