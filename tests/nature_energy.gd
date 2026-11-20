extends SceneTree

## Энергия природы эльфов (патч 7): +1 активация раз в ход за 1 энергию.
## Запуск: godot --headless --path . --script res://tests/nature_energy.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_energy()
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


func _test_energy() -> void:
	print("Энергия природы: +1 активация")
	var game := _make_game()
	game.factions[1] = "elves"
	game.start_energy(1)
	_check("стартовая энергия 2", game.energy_of(1) == 2, "=%d" % game.energy_of(1))

	var a := game.add_unit(1, Vector2i(0, 0))
	var b := game.add_unit(1, Vector2i(1, 0))
	var c := game.add_unit(1, Vector2i(2, 0))
	game.activate(a)
	game.activate(b)
	_check("две активации использованы", game.activated_count(1) == 2)
	_check("третью нельзя (лимит 2)", game.can_activate(c)["ok"] == false)

	var verdict := game.use_nature_energy(1)
	_check("энергия применена", verdict["ok"])
	_check("энергия потрачена (осталась 1)", game.energy_of(1) == 1)
	_check("третья активация теперь доступна", game.can_activate(c)["ok"])
	game.activate(c)
	_check("активаций теперь 3", game.activated_count(1) == 3)

	var again := game.use_nature_energy(1)
	_check("повторно в тот же ход нельзя", again["ok"] == false)

	game.end_turn()
	game.end_turn()  # снова ход игрока 1
	_check("энергия не восстановилась (1)", game.energy_of(1) == 1)
	_check("активации сброшены", game.activated_count(1) == 0)

	var d := game.add_unit(1, Vector2i(3, 0))
	game.activate(d)
	game.activate(a)
	_check("лимит снова 2 (без энергии)", game.can_activate(b)["ok"] == false)
