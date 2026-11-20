extends SceneTree

## Урна душ нежити (патч 7): до конца хода эссенция — максимум, в конце хода
## возвращается к значению начала хода. Одноразовая.
## Запуск: godot --headless --path . --script res://tests/urn_of_souls.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_urn()
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


func _test_urn() -> void:
	print("Урна душ: эссенция на максимум до конца хода")
	var game := _make_game()
	game.factions[1] = "undead"
	game.start_essence(1)
	game.add_essence(1, 1)
	_check("эссенция 2 на старте", game.essence_of(1) == 2, "=%d" % game.essence_of(1))

	var v := game.use_urn_of_souls(1)
	_check("урна применена", v["ok"])
	_check("эссенция стала максимумом (4)", game.essence_of(1) == 4)

	game.spend_essence(1, 3)
	_check("эссенция потрачена до 1", game.essence_of(1) == 1)

	game.end_turn()
	game.end_turn()  # снова ход игрока 1
	_check("эссенция вернулась к значению начала хода (2)", game.essence_of(1) == 2, "=%d" % game.essence_of(1))

	var again := game.use_urn_of_souls(1)
	_check("повторно нельзя (одноразовая)", again["ok"] == false)
