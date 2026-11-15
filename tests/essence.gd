extends SceneTree

## Эссенция нежити: старт 1, максимум 4, +1 за убитого противника.
## Начисление идёт только фракции нежити (по game.factions).
## Запуск: godot --headless --path . --script res://tests/essence.gd

const START := Vector2i.ZERO

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_start_and_cap()
	_test_spend()
	_test_gain_on_kill()
	_test_only_undead_gain()

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
	print("Старт и предел эссенции")
	var game := _make_game()
	game.start_essence(1)
	_check("старт = 1", game.essence_of(1) == 1, "= %d" % game.essence_of(1))
	game.add_essence(1, 10)
	_check("максимум 4", game.essence_of(1) == 4, "= %d" % game.essence_of(1))


func _test_spend() -> void:
	print("Трата эссенции")
	var game := _make_game()
	game.essence[1] = 3
	_check("списать 2 можно", game.spend_essence(1, 2))
	_check("осталось 1", game.essence_of(1) == 1)
	_check("списать больше нельзя", game.spend_essence(1, 5) == false)
	_check("эссенция не ушла", game.essence_of(1) == 1)


func _test_gain_on_kill() -> void:
	print("+1 эссенция за убитого противника")
	var game := _make_game()
	game.factions[1] = "undead"
	var attacker := game.add_unit(1, START).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	var victim := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	victim.wounded = true
	game.dice.force([4, 1])
	var blow := game.attack(attacker, victim)
	_check("фигура погибла", blow["killed"])
	_check("убийца получил 1 эссенцию", game.essence_of(1) == 1, "= %d" % game.essence_of(1))
	_check("биомассы нет", game.biomass_of(1) == 0)


func _test_only_undead_gain() -> void:
	print("Только нежить получает эссенцию")
	var game := _make_game()
	game.factions[1] = "infected"
	var attacker := game.add_unit(1, START).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	var victim := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	victim.wounded = true
	game.dice.force([4, 1])
	game.attack(attacker, victim)
	_check("заражённый получает биомассу", game.biomass_of(1) == 1)
	_check("но не эссенцию", game.essence_of(1) == 0)
