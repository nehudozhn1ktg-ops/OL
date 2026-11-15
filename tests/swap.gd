extends SceneTree

## Обмен Линдвурма (ADR-010): передвижение за 2 MP, цель — своя фигура,
## любое расстояние, повторяется пока хватает пула (move 4 → до двух обменов).
## Запуск: godot --headless --path . --script res://tests/swap.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_mp_budget()
	_test_swap_basic()
	_test_swap_repeatable()
	_test_swap_then_move()
	_test_swap_not_own()
	_test_swap_requires_ability()
	_test_swap_any_distance()
	_test_swap_cannot_after_move()

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


## Линдвурм: move 4, способность обмена.
func _swap_unit(game: Game, owner: int, at: Vector2i) -> Unit:
	return game.add_unit(owner, at).configure("pawn", 4, 0, 0).with_ability("swap_places_with_any_figure")


func _test_mp_budget() -> void:
	print("Пул передвижения")
	var game := _make_game()
	var unit := game.add_unit(1, Vector2i.ZERO).configure("pawn", 4, 0, 0)
	_check("mp_left = move (4)", unit.mp_left == 4, "= %d" % unit.mp_left)
	game.move_unit(unit, Vector2i(2, 0))
	_check("после хода mp_left = 0", unit.mp_left == 0)


func _test_swap_basic() -> void:
	print("Обмен меняет координаты")
	var game := _make_game()
	var a := _swap_unit(game, 1, Vector2i.ZERO)
	var b := game.add_unit(1, Vector2i(3, 0)).configure("pawn", 2, 0, 0)
	var verdict := game.swap(a, b)
	_check("обмен выполнен", verdict["ok"], str(verdict))
	_check("a на месте b", a.coord == Vector2i(3, 0), str(a.coord))
	_check("b на месте a", b.coord == Vector2i.ZERO, str(b.coord))
	_check("стоило 2 MP", a.mp_left == 2, "= %d" % a.mp_left)


func _test_swap_repeatable() -> void:
	print("Обмен повторяется пока хватает MP")
	var game := _make_game()
	var a := _swap_unit(game, 1, Vector2i.ZERO)
	var b := game.add_unit(1, Vector2i(2, 0)).configure("pawn", 2, 0, 0)
	var c := game.add_unit(1, Vector2i(-2, 0)).configure("pawn", 2, 0, 0)
	game.swap(a, b)
	_check("после первого осталось 2", a.mp_left == 2)
	_check("второй обмен возможен", game.can_swap(a, c)["ok"])
	game.swap(a, c)
	_check("после второго осталось 0", a.mp_left == 0)
	_check("третий обмен нельзя", game.can_swap(a, b)["ok"] == false)


func _test_swap_then_move() -> void:
	print("После обмена можно дойти остатком")
	var game := _make_game()
	var a := _swap_unit(game, 1, Vector2i.ZERO)
	var b := game.add_unit(1, Vector2i(3, 0)).configure("pawn", 2, 0, 0)
	game.swap(a, b)  # a теперь на (3,0), mp_left=2
	_check("можно на 2 клетки", game.can_move(a, Vector2i(1, 0))["ok"])
	_check("на 3 нельзя", game.can_move(a, Vector2i(0, 0))["ok"] == false)


func _test_swap_not_own() -> void:
	print("Обмен только со своей фигурой")
	var game := _make_game()
	var a := _swap_unit(game, 1, Vector2i.ZERO)
	var enemy := game.add_unit(2, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	_check("с чужой нельзя", game.can_swap(a, enemy)["ok"] == false)
	_check("причина названа", str(game.can_swap(a, enemy)["reason"]).contains("своей"))


func _test_swap_requires_ability() -> void:
	print("Без способности обмена нет")
	var game := _make_game()
	var plain := game.add_unit(1, Vector2i.ZERO).configure("pawn", 4, 0, 0)
	var ally := game.add_unit(1, Vector2i(1, 0)).configure("pawn", 2, 0, 0)
	_check("обычная фигура не меняется", game.can_swap(plain, ally)["ok"] == false)


func _test_swap_any_distance() -> void:
	print("Обмен на любом расстоянии")
	var game := _make_game()
	var a := _swap_unit(game, 1, Vector2i.ZERO)
	var far := game.add_unit(1, Vector2i(0, 3)).configure("pawn", 2, 0, 0)
	_check("далеко — можно", game.can_swap(a, far)["ok"])


func _test_swap_cannot_after_move() -> void:
	print("После обычного хода обмен недоступен")
	var game := _make_game()
	var a := _swap_unit(game, 1, Vector2i.ZERO)
	var b := game.add_unit(1, Vector2i(2, 0)).configure("pawn", 2, 0, 0)
	game.move_unit(a, Vector2i(1, 0))
	_check("после хода обмен нельзя", game.can_swap(a, b)["ok"] == false)
