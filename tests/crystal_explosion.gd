extends SceneTree

## Кристалл (чёт кубика → +2) и Взрыв (AOE при убийстве).
## Запуск: godot --headless --path . --script res://tests/crystal_explosion.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_crystal()
	_test_explosion()
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


func _test_crystal() -> void:
	print("Кристалл: чёт кубика → +2")
	var game := _make_game()
	var crystal := game.add_unit(1, Vector2i(0, 0)).configure("cmd", 3, 2, 2)
	crystal.with_ability("crystal_gamble")
	game.activate(crystal)
	var target := game.add_unit(2, Vector2i(0, 1)).configure("pawn", 2, 0, 0)

	game.dice.force([4, 1])  # атака 4 (чёт → +2), защита 1
	var blow := game.attack(crystal, target)
	_check("атака 4+2+2=8 (чёт + кристалл + бонус)", blow["damage"] == 8, "dmg=%d" % blow["damage"])


func _test_explosion() -> void:
	print("Взрыв: AOE при убийстве")
	var game := _make_game()
	var vzryv := game.add_unit(1, Vector2i(0, 0)).configure("cmd", 3, 2, 2)
	vzryv.with_ability("explosion")
	game.activate(vzryv)

	var victim := game.add_unit(2, Vector2i(0, 1)).configure("pawn", 2, 0, 0)
	var neighbor := game.add_unit(2, Vector2i(1, 1)).configure("pawn", 2, 0, 0)
	victim.wounded = true  # вторая рана — смерть
	game.dice.force([4, 1])
	game.attack(vzryv, victim)
	_check("сосед ранен взрывом", neighbor.wounded)