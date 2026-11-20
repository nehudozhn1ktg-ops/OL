extends SceneTree

## Четыре игрока (GAME-4P-001): очередь 1→2→3→4→1, четыре флага, четыре отряда,
## победа в FFA на 8 очках у любого из четверых.
## Запуск: godot --headless --path . --script res://tests/four_players.gd

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_turn_order()
	_test_four_flags()
	_test_four_rosters()
	_test_win_by_fourth()
	_test_kill_resource_for_four()
	_test_points_for_four()

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


func _make_game(player_count: int = 4) -> Game:
	var board := Board.new()
	board.build_disk(3)
	var game := Game.new()
	game.setup(board, Dice.new(7), player_count)
	return game


func _test_turn_order() -> void:
	print("Очередь ходов 1→2→3→4→1")
	var game := _make_game(4)
	_check("число игроков 4", game.player_count == 4)
	_check("первым ходит игрок 1", game.current_player == 1)
	game.end_turn()
	_check("вторым — игрок 2", game.current_player == 2)
	game.end_turn()
	_check("третьим — игрок 3", game.current_player == 3)
	game.end_turn()
	_check("четвёртым — игрок 4", game.current_player == 4)
	_check("раунд ещё первый", game.round_number == 1)
	game.end_turn()
	_check("снова игрок 1", game.current_player == 1)
	_check("раунд стал вторым", game.round_number == 2)
	_check("сутки сменились", game.is_day == false)

	var duel := _make_game(2)
	duel.end_turn()
	_check("дуэль: после 1 ходит 2", duel.current_player == 2)
	duel.end_turn()
	_check("дуэль: снова 1", duel.current_player == 1)


func _test_four_flags() -> void:
	print("Четыре флага по игрокам")
	var game := _make_game(4)
	game.add_flag(1, Vector2i(-2, 0))
	game.add_flag(2, Vector2i(2, 0))
	game.add_flag(3, Vector2i(0, -2))
	game.add_flag(4, Vector2i(0, 2))
	_check("флаг игрока 1", game.flag_of(1) == Vector2i(-2, 0))
	_check("флаг игрока 3", game.flag_of(3) == Vector2i(0, -2))
	_check("флаг игрока 4", game.flag_of(4) == Vector2i(0, 2))
	_check("флагов всего 4", game.flags.size() == 4)


func _test_four_rosters() -> void:
	print("Четыре отряда — по шесть фигур")
	var game := _make_game(4)
	var data := FactionData.load_file("res://data/factions/undead.json")
	var roster := FactionData.roster(data, 6)
	game.place_roster(1, Vector2i(-2, 0), roster)
	game.place_roster(2, Vector2i(2, 0), roster)
	game.place_roster(3, Vector2i(0, -2), roster)
	game.place_roster(4, Vector2i(0, 2), roster)
	_check("всего фигур 24", game.units.size() == 24, "= %d" % game.units.size())
	_check("у игрока 1 шесть", game.units_of(1).size() == 6)
	_check("у игрока 3 шесть", game.units_of(3).size() == 6)
	_check("у игрока 4 шесть", game.units_of(4).size() == 6)


func _test_win_by_fourth() -> void:
	print("Победа любого из четверых на 8 очках")
	var game := _make_game(4)
	game._add_score(3, 8)
	_check("победитель — игрок 3", game.check_winner() == 3)
	_check("winner зафиксирован", game.winner == 3)

	var game2 := _make_game(4)
	game2._add_score(4, 8)
	_check("победитель — игрок 4", game2.check_winner() == 4)


func _test_kill_resource_for_four() -> void:
	print("Ресурсы за убийство у игроков 3–4")
	var game := _make_game(4)
	game.factions = {1: "people", 2: "elves", 3: "infected", 4: "undead"}
	game.start_biomass(3)
	game.start_essence(4)
	game.spend_biomass(3, 2)  # 6 → 4, чтобы +1 не упёрся в потолок
	game._gain_kill_resource(3)
	_check("биомасса +1 игроку 3", game.biomass_of(3) == 5, "= %d" % game.biomass_of(3))
	game._gain_kill_resource(4)
	_check("эссенция +1 игроку 4", game.essence_of(4) == 2, "= %d" % game.essence_of(4))
	game._gain_kill_resource(1)
	_check("у людей ресурса нет", game.biomass_of(1) == 0 and game.essence_of(1) == 0)


func _test_points_for_four() -> void:
	print("Очки игроков 3–4: ключевая точка и флаг")
	var game := _make_game(4)
	var unit3 := game.add_unit(3, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	game.board.set_terrain(Vector2i(0, 0), Board.TERRAIN_KEY)
	game.current_player = 3
	game.begin_turn()
	_check("очко игроку 3 за точку", game.scores[3] == 1, "= %d" % game.scores[3])

	var game2 := _make_game(4)
	game2.board.set_terrain(Vector2i(1, 0), Board.TERRAIN_FLAG)
	game2.add_flag(1, Vector2i(1, 0))
	var unit4 := game2.add_unit(4, Vector2i(0, 0)).configure("pawn", 2, 0, 0)
	game2.current_player = 4
	game2.activate(unit4)
	game2.dice.force([4])
	game2.attack_flag(unit4, Vector2i(1, 0))
	_check("флаг снесён игроком 4 (+3)", game2.scores[4] == 3, "= %d" % game2.scores[4])
