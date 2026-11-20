class_name GameAI
extends RefCounted

## Простейший ИИ (Solo, v1.1): активирует фигуру, идёт к ближайшему
## врагу, атакует если сосед. Вызывает end_turn.
## Игровой цикл зовёт GameAI.make_turn(game, player) вмест о кликов.

static func make_turn(game: Game, player: int) -> void:
	var my_units := game.units_of(player)
	if my_units.is_empty():
		game.end_turn()
		return

	var enemies: Array = []
	for u in game.units:
		if u.owner != player:
			enemies.append(u)

	if enemies.is_empty():
		game.end_turn()
		return

	for unit in my_units:
		if unit.activated or game.activated_count(player) >= 2:
			continue
		game.activate(unit)
		var best_enemy: Unit = null
		var best_dist: int = 999999
		for e in enemies:
			var d: int = game.board.distance(unit.coord, e.coord)
			if d < best_dist:
				best_dist = d
				best_enemy = e
		if best_enemy != null and best_dist == 1 and unit.can_attack and not unit.attacked:
			game.attack(unit, best_enemy)
		elif best_enemy != null:
			var step := _step_toward(game, unit, best_enemy.coord)
			if step != Vector2i.ZERO:
				if game.can_move(unit, step)["ok"]:
					game.move_unit(unit, step)
		break

	game.end_turn()


static func _step_toward(game: Game, unit: Unit, target: Vector2i) -> Vector2i:
	var best_dist: int = 999999
	var best_cell := Vector2i.ZERO
	for nb in game.board.neighbors(unit.coord):
		if not game.board.has_cell(nb) or not game.board.is_passable(nb):
			continue
		if game.unit_at(nb) != null:
			continue
		var d: int = game.board.distance(nb, target)
		if d < best_dist:
			best_dist = d
			best_cell = nb
	return best_cell