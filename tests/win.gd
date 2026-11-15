extends SceneTree

## Условие победы (канон): 8 очков каждый за себя — победа объявляется сразу.
## Запуск: godot --headless --path . --script res://tests/win.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_no_winner_before_points()
	_test_win_at_eight()
	_test_win_on_flag()
	_test_winner_locked()

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


func _test_no_winner_before_points() -> void:
	print("До 8 очков победителя нет")
	var game := _make_game()
	_check("в начале winner = 0", game.winner == 0)
	game._add_score(1, 7)
	_check("7 очков — ещё нет", game.check_winner() == 0)
	_check("победитель не зафиксирован", game.winner == 0)


func _test_win_at_eight() -> void:
	print("8 очков — победа сразу")
	var game := _make_game()
	game._add_score(1, 8)
	_check("победитель = игрок 1", game.check_winner() == 1)
	_check("winner зафиксирован", game.winner == 1)


func _test_win_on_flag() -> void:
	print("Флаг добивает до 8 — победа")
	var game := _make_game()
	game._add_score(1, 5)
	game.board.set_terrain(Vector2i(1, 0), Board.TERRAIN_FLAG)
	game.add_flag(2, Vector2i(1, 0))
	var unit := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	game.activate(unit)
	game.dice.force([4])
	game.attack_flag(unit, Vector2i(1, 0))
	_check("счёт 8", game.scores[1] == 8, "= %d" % game.scores[1])
	_check("победа объявлена", game.winner == 1)


func _test_winner_locked() -> void:
	print("Победитель не меняется после игры")
	var game := _make_game()
	game._add_score(1, 8)
	game._add_score(2, 20)
	_check("победитель всё ещё игрок 1", game.check_winner() == 1)
