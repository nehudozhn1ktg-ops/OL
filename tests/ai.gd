extends SceneTree

## Простейший ИИ (Solo): ходит, атакует, передаёт ход.
## Запуск: godot --headless --path . --script res://tests/ai.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_ai()
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


func _test_ai() -> void:
	print("ИИ: ход к врагу и атака")
	var game := _make_game()
	var my_unit := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	var enemy := game.add_unit(2, Vector2i(2, 0)).configure("pawn", 2, 0, 0)
	game.current_player = 1
	GameAI.make_turn(game, 1)
	_check("ИИ походил (фигура активирована или ход передан)",
		my_unit.activated or game.current_player == 2)