extends SceneTree

## Реакция укрепления — ADR-002 и уточнения владельца от 2026-11-14:
## фигура на клетке «укрепление» получает +1 к защите постоянно, пока стоит
## на ней, и автоматически атакует каждого противника, который **завершил
## движение** на соседней клетке. Атака разовая, бесплатная (не тратит
## активацию и не запрещает фигуре действовать в свой ход), срабатывает на
## каждого противника отдельно.
##
## Запуск: godot --headless --path . --script res://tests/fort_reaction.gd

const FORT := Vector2i(1, 0)

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_defense_bonus()
	_test_no_reaction_at_distance()
	_test_reaction_on_stop_adjacent()
	_test_reaction_is_free()
	_test_each_stop_is_a_new_reaction()
	_test_every_fort_reacts()
	_test_no_reaction_off_fort()
	_test_no_reaction_for_allies()
	_test_reaction_kills_and_scores()
	_test_reaction_uses_normal_bonuses()
	_test_unit_without_attack_does_not_react()
	_test_reacts_on_enemy_turn()

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
	board.set_terrain(FORT, Board.TERRAIN_FORT)
	var game := Game.new()
	game.setup(board, dice if dice != null else Dice.new(999))
	return game


## Сторожевая фигура игрока 2 на укреплении + свой ход игрока 1.
func _setup(dice: Dice = null, guard_damage: int = 0) -> Game:
	var game := _make_game(dice)
	game.add_unit(2, FORT).configure("pawn", 2, guard_damage, 0)
	return game


## --- Бонус защиты ------------------------------------------------------------

func _test_defense_bonus() -> void:
	print("Укрепление: +1 к защите, пока фигура на клетке")
	var game := _make_game()
	var unit := game.add_unit(1, FORT).configure("pawn", 2, 0, 1)
	_check("на укреплении броня 1 + 1 = 2", game.defense_bonus(unit) == 2,
		"= %d" % game.defense_bonus(unit))
	unit.coord = Vector2i(3, 0)
	_check("ушла с укрепления — бонус снят", game.defense_bonus(unit) == 1,
		"= %d" % game.defense_bonus(unit))


## --- Когда реакции нет -------------------------------------------------------

func _test_no_reaction_at_distance() -> void:
	print("Остановка не рядом — реакции нет")
	var game := _setup()
	var mover := game.add_unit(1, Vector2i(0, 1)).configure("pawn", 3, 0, 0)
	game.activate(mover)
	_check("переход разрешён", game.move_unit(mover, Vector2i(3, 0)))
	_check("расстояние 2 — реакции нет", game.last_fort_reactions.is_empty(),
		"реакций %d" % game.last_fort_reactions.size())


func _test_no_reaction_off_fort() -> void:
	print("Стоящий не на укреплении не реагирует")
	var game := _make_game()
	game.board.set_terrain(FORT, Board.TERRAIN_GRASS)
	game.add_unit(2, FORT).configure("pawn", 2, 0, 0)
	var mover := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	game.activate(mover)
	game.move_unit(mover, Vector2i(1, 1))
	_check("на траве реакции нет", game.last_fort_reactions.is_empty())


func _test_no_reaction_for_allies() -> void:
	print("Своя фигура рядом не вызывает реакции")
	var game := _make_game()
	game.add_unit(2, FORT).configure("pawn", 2, 0, 0)
	var ally := game.add_unit(2, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	game.end_turn()
	game.end_turn()  # снова ход игрока 2
	game.activate(ally)
	game.move_unit(ally, Vector2i(1, 1))
	_check("союзник не атакован", game.last_fort_reactions.is_empty())


## --- Реакция есть ------------------------------------------------------------

func _test_reaction_on_stop_adjacent() -> void:
	print("Остановка рядом — реакция")
	var game := _setup()
	var mover := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	game.activate(mover)
	game.dice.force([3, 1], ["white"])
	game.move_unit(mover, Vector2i(1, 1))
	_check("одна реакция", game.last_fort_reactions.size() == 1,
		"реакций %d" % game.last_fort_reactions.size())
	if game.last_fort_reactions.is_empty():
		return
	var blow: Dictionary = game.last_fort_reactions[0]
	_check("атаковала фигура с укрепления", blow["attacker"].coord == FORT)
	_check("цель — пришедшая фигура", blow["defender"] == mover)
	_check("попадание 3 против 1", blow["hit"])
	_check("фигура ранена", mover.wounded)


func _test_reaction_is_free() -> void:
	print("Реакция бесплатна: не тратит активацию и атаку")
	var game := _setup()
	var guard := game.units_of(2)[0]
	guard.activated = true
	guard.attacked = true
	var mover := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	game.activate(mover)
	game.dice.force([2, 1], ["white"])
	game.move_unit(mover, Vector2i(1, 1))
	_check("реакция сработала в чужой ход", game.last_fort_reactions.size() == 1)
	_check("атака не израсходована", guard.attacked == true)
	_check("активация не тронута", guard.activated == true)


func _test_each_stop_is_a_new_reaction() -> void:
	print("Каждый остановившийся рядом — отдельная реакция")
	var game := _setup()
	var first := game.add_unit(1, Vector2i(0, 1)).configure("pawn", 2, 0, 0)
	var second := game.add_unit(1, Vector2i(0, -1)).configure("pawn", 2, 0, 0)
	game.activate(first)
	game.activate(second)
	game.dice.force([1, 4, 1, 4])
	game.move_unit(first, Vector2i(0, 0))
	_check("первая реакция", game.last_fort_reactions.size() == 1)
	game.move_unit(second, Vector2i(1, 1))
	_check("вторая реакция", game.last_fort_reactions.size() == 1,
		"реакций %d" % game.last_fort_reactions.size())


func _test_every_fort_reacts() -> void:
	print("Реагирует каждое укрепление по соседству")
	var game := _make_game()
	game.board.set_terrain(Vector2i(1, -1), Board.TERRAIN_FORT)
	game.add_unit(2, FORT).configure("pawn", 2, 0, 0)
	game.add_unit(2, Vector2i(1, -1)).configure("pawn", 2, 0, 0)
	var mover := game.add_unit(1, Vector2i(0, 1)).configure("pawn", 2, 0, 0)
	game.activate(mover)
	game.dice.force([1, 4, 1, 4])
	game.move_unit(mover, Vector2i(0, 0))
	_check("две реакции от двух укреплений", game.last_fort_reactions.size() == 2,
		"реакций %d" % game.last_fort_reactions.size())


func _test_reaction_kills_and_scores() -> void:
	print("Реакция может убить и приносит очко")
	var game := _setup()
	var mover := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	game.activate(mover)
	game.dice.force([4, 1], ["black"])
	game.move_unit(mover, Vector2i(1, 1))
	_check("фигура погибла", game.units_of(1).is_empty())
	_check("очко владельцу укрепления", game.scores[2] == 1,
		"счёт %d" % game.scores[2])


func _test_reaction_uses_normal_bonuses() -> void:
	print("Реакция — обычный бой с бонусами")
	var game := _setup(null, 2)
	var mover := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	game.activate(mover)
	game.dice.force([1, 1])
	game.move_unit(mover, Vector2i(1, 1))
	if game.last_fort_reactions.is_empty():
		_check("реакция есть", false)
		return
	var blow: Dictionary = game.last_fort_reactions[0]
	_check("урон = D4 + бонус 2", blow["damage"] == 3, "= %d" % blow["damage"])
	_check("попадание при 3 против 1", blow["hit"])


func _test_unit_without_attack_does_not_react() -> void:
	print("Фигура, не умеющая атаковать, не реагирует (ASSUMPTION-002)")
	var game := _setup()
	game.units_of(2)[0].can_attack = false
	var mover := game.add_unit(1, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	game.activate(mover)
	game.move_unit(mover, Vector2i(1, 1))
	_check("реакции нет", game.last_fort_reactions.is_empty())
	_check("фигура цела", mover.wounded == false)


func _test_reacts_on_enemy_turn() -> void:
	print("Реакция работает и на своём ходу владельца укрепления")
	var game := _make_game()
	game.add_unit(1, FORT).configure("pawn", 2, 0, 0)
	var enemy := game.add_unit(2, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	game.end_turn()
	game.activate(enemy)
	game.dice.force([3, 1], ["white"])
	game.move_unit(enemy, Vector2i(1, 1))
	_check("реакция игрока 1 на ходу игрока 2",
		game.last_fort_reactions.size() == 1)
