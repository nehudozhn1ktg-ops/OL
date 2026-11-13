extends SceneTree

## Флаг фракции по канону 0.7.1 (docs/canon/01-core.md, «Флаг и артефакт»):
## препятствие; уничтожается броском 4 (3–4, если бьёт Король); 3 очка;
## убирается, если отряд уничтожен. Способности фигур на условие не влияют.
## Запуск: godot --headless --path . --script res://tests/flag.gd

const FLAG := Vector2i(1, 0)

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_flag_blocks_movement()
	_test_needs_activation()
	_test_pawn_needs_four()
	_test_king_three_or_four()
	_test_abilities_do_not_count()
	_test_flag_removed_and_points()
	_test_friendly_flag()
	_test_flag_out_of_reach()
	_test_squad_loss_removes_flag()

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
	board.set_terrain(FLAG, Board.TERRAIN_FLAG)
	var game := Game.new()
	game.setup(board, Dice.new(7))
	game.add_flag(2, FLAG)
	return game


## Игрок 1, пешка на (0,0), рядом с чужим флагом.
func _setup_attacker(kind: String = "pawn", damage: int = 0) -> Game:
	var game := _make_game()
	var unit := game.add_unit(1, Vector2i(0, 0))
	unit.configure(kind, 2, damage, 0)
	game.activate(unit)
	return game


func _test_flag_blocks_movement() -> void:
	print("Флаг — препятствие")
	var game := _make_game()
	var unit := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	_check("на клетку флага встать нельзя", game.can_move(unit, FLAG)["ok"] == false)
	_check("поле считает флаг непроходимым", game.board.is_passable(FLAG) == false)
	_check("флаг не входит в достижимые клетки", game.reachable(unit).has(FLAG) == false)


func _test_needs_activation() -> void:
	print("Атаковать флаг можно только активированной фигурой")
	var game := _make_game()
	var unit := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	_check("без активации нельзя", game.can_attack_flag(unit, FLAG)["ok"] == false)
	_check("причина названа", game.can_attack_flag(unit, FLAG)["reason"].contains("не активирована"))


func _test_pawn_needs_four() -> void:
	print("Пешка уничтожает флаг только на 4")
	var game := _setup_attacker()
	game.dice.force([3])
	var blow := game.attack_flag(game.units[0], FLAG)
	_check("бросок 3 — флаг цел", blow["destroyed"] == false)
	_check("очков нет", game.scores[1] == 0)
	_check("флаг на поле", game.has_flag(FLAG))
	_check("атака израсходована", game.units[0].attacked)

	var success := _setup_attacker()
	success.dice.force([4])
	var hit := success.attack_flag(success.units[0], FLAG)
	_check("бросок 4 — флаг уничтожен", hit["destroyed"])
	_check("начислено 3 очка", success.scores[1] == 3, "счёт %d" % success.scores[1])


func _test_king_three_or_four() -> void:
	print("Король уничтожает флаг на 3–4")
	for roll in [3, 4]:
		var game := _setup_attacker("king")
		game.dice.force([roll])
		_check("король на %d уничтожает" % roll, game.attack_flag(game.units[0], FLAG)["destroyed"])

	var weak := _setup_attacker("king")
	weak.dice.force([2])
	_check("король на 2 — нет", weak.attack_flag(weak.units[0], FLAG)["destroyed"] == false)


func _test_abilities_do_not_count() -> void:
	print("Способности и урон не влияют на условие")
	var game := _setup_attacker("pawn", 3)
	game.dice.force([3])
	_check("урон +3 не помогает пешке", game.attack_flag(game.units[0], FLAG)["destroyed"] == false)

	var aura := _setup_attacker("pawn", 0)
	aura.units[0].with_ability("banner")
	aura.dice.force([3])
	_check("способность не помогает", aura.attack_flag(aura.units[0], FLAG)["destroyed"] == false)


func _test_flag_removed_and_points() -> void:
	print("Уничтоженный флаг убирается с поля")
	var game := _setup_attacker()
	game.dice.force([4])
	game.attack_flag(game.units[0], FLAG)
	_check("флага больше нет", game.has_flag(FLAG) == false)
	_check("клетка стала свободной (ASSUMPTION)", game.board.terrain_at(FLAG) == Board.TERRAIN_GRASS)


func _test_friendly_flag() -> void:
	print("Свой флаг не атакуют")
	var board := Board.new()
	board.build_disk(3)
	board.set_terrain(FLAG, Board.TERRAIN_FLAG)
	var game := Game.new()
	game.setup(board, Dice.new(7))
	game.add_flag(1, FLAG)
	var unit := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	game.activate(unit)
	_check("свой флаг нельзя атаковать", game.can_attack_flag(unit, FLAG)["ok"] == false)


func _test_flag_out_of_reach() -> void:
	print("Атака только с соседней клетки")
	var game := _make_game()
	var unit := game.add_unit(1, Vector2i(-2, 0)).configure("pawn", 3, 0, 0)
	game.activate(unit)
	_check("издалека нельзя", game.can_attack_flag(unit, FLAG)["ok"] == false)


func _test_squad_loss_removes_flag() -> void:
	print("Потеря отряда убирает флаг")
	var game := _make_game()
	var victim := game.add_unit(2, Vector2i(2, -1)).configure("pawn", 2, 0, 0)
	var attacker := game.add_unit(1, Vector2i(1, -1)).configure("pawn", 2, 0, 0)
	game.activate(attacker)
	game.dice.force([4, 1], ["black"])
	var blow := game.attack(attacker, victim)
	_check("фигура погибла", blow["killed"])
	_check("отряд пуст", game.units_of(2).is_empty())
	_check("флаг убран без очков", game.has_flag(FLAG) == false)
	_check("за флаг очков не дали", game.scores[1] == 1, "счёт %d" % game.scores[1])
