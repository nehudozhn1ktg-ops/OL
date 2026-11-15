extends SceneTree

## Призыв Некроманта и каркас «Атака ИЛИ Действие» (ADR-012, патч 7):
## 2 эссенции — призыв пешки (Шахтёр/Телохранитель) или воскрешение пешки,
## 3 — призыв командира (Кровавый голем/Суккуб) или воскрешение командира,
## 4 — уничтожение чужой пешки/командира. Призываемые не имеют механики ранения.
## Запуск: godot --headless --path . --script res://tests/necromancy.gd

const START := Vector2i.ZERO

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_framework()
	_test_summon()
	_test_resurrect()
	_test_slay()
	_test_no_wound()

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
	game.factions[1] = "undead"
	return game


## Некромант игрока 1: активирован, способность cast_spell.
func _necro(game: Game) -> Unit:
	var unit := game.add_unit(1, START).configure("king", 2, 3, 3)
	unit.with_ability("cast_spell")
	game.activate(unit)
	return unit


func _summon_def(id: String, name: String, kind: String, damage: int, move: int,
		armor: int, can_attack: bool) -> Dictionary:
	return {"id": id, "name": name, "kind": kind, "damage": damage,
		"move": move, "armor": armor, "can_attack": can_attack,
		"abilities": [], "text": ""}


func _register_summonables(game: Game, player: int = 1) -> void:
	game.register_summonables(player, {
		"miner": _summon_def("miner", "Шахтёр", "pawn", 0, 3, 0, false),
		"bodyguard": _summon_def("bodyguard", "Телохранитель", "pawn", 0, 2, 3, false),
		"blood_golem": _summon_def("blood_golem", "Кровавый голем", "commander", 2, 3, 2, true),
		"succubus": _summon_def("succubus", "Суккуб", "commander", 0, 3, 2, false),
	})


## Убить victim боевой атакой attacker-а: переключаем ход на его владельца.
func _combat_kill(game: Game, attacker: Unit, victim: Unit) -> void:
	victim.wounded = true
	game.current_player = attacker.owner
	game.activate(attacker)
	game.dice.force([4, 1])
	game.attack(attacker, victim)


func _test_framework() -> void:
	print("Каркас: атака ИЛИ действие (ADR-012)")
	var game := _make_game()
	_register_summonables(game)
	game.essence[1] = 4
	var necro := _necro(game)
	var enemy := game.add_unit(2, Vector2i(0, 1)).configure("pawn", 2, 0, 0)
	var verdict := game.summon(necro, "miner", Vector2i(1, 0))
	_check("действие выполнено", verdict["ok"], str(verdict))
	_check("после действия атака закрыта", game.can_attack(necro, enemy)["ok"] == false)
	_check("причина названа", str(game.can_attack(necro, enemy)["reason"]).contains("действие"))

	var game2 := _make_game()
	_register_summonables(game2)
	game2.essence[1] = 4
	var necro2 := _necro(game2)
	var enemy2 := game2.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	game2.dice.force([4, 1])
	var blow := game2.attack(necro2, enemy2)
	_check("атака выполнена", blow["damage"] > 0, str(blow))
	_check("после атаки действие закрыто",
		game2.can_summon(necro2, "miner", Vector2i(-1, 0))["ok"] == false)

	var game3 := _make_game()
	var plain := game3.add_unit(1, START).configure("pawn", 2, 0, 0)
	game3.activate(plain)
	_check("без способности действия нет", game3.can_act(plain)["ok"] == false)

	var game4 := _make_game()
	_register_summonables(game4)
	var necro4 := _necro(game4)
	necro4.activated = false
	_check("неактивированная не действует", game4.can_act(necro4)["ok"] == false)


func _test_summon() -> void:
	print("Призыв (2/3 эссенции)")
	var game := _make_game()
	_register_summonables(game)
	game.essence[1] = 3
	var necro := _necro(game)
	var verdict := game.summon(necro, "miner", Vector2i(1, 0))
	_check("шахтёр призван", verdict["ok"], str(verdict))
	_check("эссенция 3->1", game.essence_of(1) == 1, "= %d" % game.essence_of(1))
	var summoned := game.unit_at(Vector2i(1, 0))
	_check("фигура на клетке", summoned != null)
	_check("призванный без механики ранения", summoned != null and summoned.no_wound)

	var game2 := _make_game()
	_register_summonables(game2)
	game2.essence[1] = 3
	var necro2 := _necro(game2)
	var verdict2 := game2.summon(necro2, "blood_golem", Vector2i(-1, 0))
	_check("кровавый голем призван", verdict2["ok"], str(verdict2))
	_check("эссенция списана до 0", game2.essence_of(1) == 0, "= %d" % game2.essence_of(1))

	var game3 := _make_game()
	_register_summonables(game3)
	game3.essence[1] = 1
	var necro3 := _necro(game3)
	var verdict3 := game3.summon(necro3, "miner", Vector2i(1, 0))
	_check("без эссенции отказ", verdict3["ok"] == false)
	_check("причина названа", str(verdict3["reason"]).contains("эссенции"))
	_check("фигура не появилась", game3.unit_at(Vector2i(1, 0)) == null)

	var game4 := _make_game()
	_register_summonables(game4)
	game4.essence[1] = 4
	var necro4 := _necro(game4)
	_check("не соседняя клетка — отказ",
		game4.summon(necro4, "miner", Vector2i(2, 0))["ok"] == false)

	var game5 := _make_game()
	_register_summonables(game5)
	game5.essence[1] = 4
	var necro5 := _necro(game5)
	game5.add_unit(1, Vector2i(1, 0))
	_check("занятая клетка — отказ",
		game5.summon(necro5, "miner", Vector2i(1, 0))["ok"] == false)

	var game6 := _make_game()
	_register_summonables(game6)
	game6.essence[1] = 4
	var necro6 := _necro(game6)
	_check("неизвестная фигура — отказ",
		game6.summon(necro6, "no_such", Vector2i(1, 0))["ok"] == false)


func _test_resurrect() -> void:
	print("Воскрешение (2/3 эссенции)")
	var game := _make_game()
	_register_summonables(game)
	game.essence[1] = 2
	var necro := _necro(game)
	var pawn := game.add_unit(1, Vector2i(2, 0)).configure("pawn", 2, 1, 1)
	var enemy := game.add_unit(2, Vector2i(3, 0)).configure("pawn", 2, 0, 0)
	_combat_kill(game, enemy, pawn)
	game.current_player = 1
	_check("пешка погибла", not game.units.has(pawn))
	_check("пешка в кладбище", game.graveyard.has(pawn))
	var verdict := game.resurrect(necro, pawn, Vector2i(1, 0))
	_check("пешка воскрешена", verdict["ok"], str(verdict))
	_check("вернулась на поле", game.units.has(pawn))
	_check("ранена", pawn.wounded)
	_check("эссенция 2->0", game.essence_of(1) == 0, "= %d" % game.essence_of(1))
	_check("нет в кладбище", not game.graveyard.has(pawn))

	var game2 := _make_game()
	_register_summonables(game2)
	game2.essence[1] = 3
	var necro2 := _necro(game2)
	var commander := game2.add_unit(1, Vector2i(2, 0)).configure("commander", 3, 2, 2)
	var enemy2 := game2.add_unit(2, Vector2i(3, 0)).configure("pawn", 2, 0, 0)
	_combat_kill(game2, enemy2, commander)
	game2.current_player = 1
	var verdict2 := game2.resurrect(necro2, commander, Vector2i(-1, 0))
	_check("командир воскрешён", verdict2["ok"], str(verdict2))
	_check("эссенция 3->0", game2.essence_of(1) == 0, "= %d" % game2.essence_of(1))

	var game3 := _make_game()
	_register_summonables(game3)
	game3.essence[1] = 3
	var necro3 := _necro(game3)
	var king := game3.add_unit(1, Vector2i(2, 0)).configure("king", 2, 3, 0)
	var enemy3 := game3.add_unit(2, Vector2i(3, 0)).configure("pawn", 2, 0, 0)
	_combat_kill(game3, enemy3, king)
	game3.current_player = 1
	var verdict3 := game3.resurrect(necro3, king, Vector2i(1, 0))
	_check("короля нельзя", verdict3["ok"] == false)
	_check("причина названа", str(verdict3["reason"]).contains("короля"))

	var game4 := _make_game()
	_register_summonables(game4)
	game4.essence[1] = 4
	var necro4 := _necro(game4)
	var enemy4 := game4.add_unit(2, Vector2i(2, 0)).configure("pawn", 2, 0, 0)
	var killer := game4.add_unit(1, Vector2i(3, 0)).configure("pawn", 2, 0, 0)
	_combat_kill(game4, killer, enemy4)
	game4.current_player = 1
	var verdict4 := game4.resurrect(necro4, enemy4, Vector2i(1, 0))
	_check("чужую нельзя", verdict4["ok"] == false)
	_check("причина названа", str(verdict4["reason"]).contains("свою"))


func _test_slay() -> void:
	print("Убийство заклинанием (4 эссенции)")
	var game := _make_game()
	game.essence[1] = 4
	var necro := _necro(game)
	var pawn := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	var verdict := game.slay(necro, pawn)
	_check("пешка уничтожена", verdict["ok"], str(verdict))
	_check("ушла с поля", not game.units.has(pawn))
	_check("в кладбище", game.graveyard.has(pawn))
	_check("очко начислено", game.scores[1] == 1, "= %d" % game.scores[1])
	_check("эссенция 4->0, без начисления", game.essence_of(1) == 0, "= %d" % game.essence_of(1))

	var game2 := _make_game()
	game2.essence[1] = 4
	var necro2 := _necro(game2)
	var commander := game2.add_unit(2, Vector2i(1, 0)).configure("commander", 3, 2, 2)
	_check("командир уничтожен", game2.slay(necro2, commander)["ok"])

	var game3 := _make_game()
	game3.essence[1] = 4
	var necro3 := _necro(game3)
	var king := game3.add_unit(2, Vector2i(1, 0)).configure("king", 2, 3, 3)
	var verdict3 := game3.slay(necro3, king)
	_check("король защищён", verdict3["ok"] == false)
	_check("причина названа", str(verdict3["reason"]).contains("короля"))

	var game4 := _make_game()
	game4.essence[1] = 4
	var necro4 := _necro(game4)
	var own := game4.add_unit(1, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	_check("свою нельзя", game4.slay(necro4, own)["ok"] == false)

	var game5 := _make_game()
	game5.essence[1] = 3
	var necro5 := _necro(game5)
	var target := game5.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	var verdict5 := game5.slay(necro5, target)
	_check("без эссенции отказ", verdict5["ok"] == false)
	_check("цель на месте", game5.units.has(target))


func _test_no_wound() -> void:
	print("Призванные не имеют механики ранения")
	var game := _make_game()
	var attacker := game.add_unit(1, START).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	var summoned := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	summoned.no_wound = true
	game.dice.force([4, 1])
	var blow := game.attack(attacker, summoned)
	_check("погиб сразу", blow["killed"])
	_check("не ранен", blow["wounded"] == false)
	_check("монеты не было", blow["coin"] == "")
	_check("ушла с поля", not game.units.has(summoned))

	var game2 := _make_game()
	var attacker2 := game2.add_unit(1, START).configure("pawn", 2, 0, 0)
	game2.activate(attacker2)
	var normal := game2.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	game2.dice.force([4, 1], ["white"])
	var blow2 := game2.attack(attacker2, normal)
	_check("обычная фигура ранена монетой", blow2["wounded"])
	_check("монета была", blow2["coin"] == "white")
