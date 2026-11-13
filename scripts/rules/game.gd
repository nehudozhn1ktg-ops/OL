extends RefCounted
class_name Game

## Партия по правилам 0.7.1.
##
## Ход: активируются две фигуры (движение + атака), остальные только двигаются.
## Бой: D4 + бонус урона против D4 + броня + террейн + ауры.
## Проигрыш в защите: монета — белая сторона ранит, чёрная убивает.
## Раненая фигура при следующем проигрыше погибает без монеты.

const MAX_ACTIVATIONS := 2

## Бонусы защиты от террейна (легенда карт).
const TERRAIN_DEFENSE := {
	Board.TERRAIN_FOREST: 1,
	Board.TERRAIN_FORT: 1,
}

var board: Board
var dice: Dice
var units: Array[Unit] = []
var current_player: int = 1
var turn_number: int = 1
var round_number: int = 1
var is_day: bool = true
var scores: Dictionary = {1: 0, 2: 0, 3: 0, 4: 0}

var points_collected_last: int = 0


func setup(board_: Board, dice_: Dice = null) -> void:
	board = board_
	dice = dice_ if dice_ != null else Dice.new()
	units.clear()
	current_player = 1
	turn_number = 1
	round_number = 1
	is_day = true
	scores = {1: 0, 2: 0, 3: 0, 4: 0}
	begin_turn()


func add_unit(owner: int, at: Vector2i, water_walk: bool = false) -> Unit:
	var unit := Unit.new(owner, at, water_walk)
	units.append(unit)
	return unit


func add_unit_from_data(owner: int, at: Vector2i, data: Dictionary) -> Unit:
	var unit := Unit.from_data(owner, at, data)
	units.append(unit)
	return unit


func unit_at(coord: Vector2i) -> Unit:
	for unit in units:
		if unit.coord == coord:
			return unit
	return null


# --- Взаимодействия: свойства объектов дают числа ---------------------------

func terrain_defense_bonus(unit: Unit) -> int:
	return int(TERRAIN_DEFENSE.get(board.terrain_at(unit.coord), 0))


## Аура «командир»: союзники в радиусе 1 получают +1 к защите.
func aura_defense_bonus(unit: Unit) -> int:
	var bonus := 0
	for other in units:
		if other == unit or other.owner != unit.owner:
			continue
		if other.abilities.has("commander") and board.distance(other.coord, unit.coord) <= 1:
			bonus += 1
	return bonus


func defense_bonus(unit: Unit) -> int:
	return unit.armor + terrain_defense_bonus(unit) + aura_defense_bonus(unit)


func attack_bonus(unit: Unit) -> int:
	return unit.damage


# --- Активация фигур --------------------------------------------------------

func activated_count(player: int) -> int:
	var count := 0
	for unit in units:
		if unit.owner == player and unit.activated:
			count += 1
	return count


func can_activate(unit: Unit) -> Dictionary:
	if unit.owner != current_player:
		return {"ok": false, "reason": "сейчас ход другого игрока"}
	if unit.activated:
		return {"ok": false, "reason": "фигура уже активирована"}
	if activated_count(current_player) >= MAX_ACTIVATIONS:
		return {"ok": false, "reason": "на этот ход уже активированы %d фигуры" % MAX_ACTIVATIONS}
	return {"ok": true, "reason": ""}


func activate(unit: Unit) -> bool:
	if not can_activate(unit)["ok"]:
		return false
	unit.activated = true
	return true


# --- Передвижение -----------------------------------------------------------

func can_move(unit: Unit, to: Vector2i) -> Dictionary:
	if unit.owner != current_player:
		return {"ok": false, "reason": "сейчас ход другого игрока"}
	if unit.moved:
		return {"ok": false, "reason": "эта фигура уже двигалась"}
	if not board.has_cell(to):
		return {"ok": false, "reason": "за пределами поля"}
	if board.distance(unit.coord, to) > unit.move:
		return {"ok": false, "reason": "дальше, чем позволяет передвижение (%d)" % unit.move}
	if not reachable(unit).has(to):
		return {"ok": false, "reason": "нет пути: мешают фигуры, вода или край поля"}
	return {"ok": true, "reason": ""}


## Клетки, куда фигура может дойти за свой ход (BFS по проходимости и занятости).
func reachable(unit: Unit) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if unit.owner != current_player or unit.moved:
		return result
	var seen := {unit.coord: 0}
	var queue: Array = [[unit.coord, 0]]
	while not queue.is_empty():
		var entry: Array = queue.pop_front()
		var current: Vector2i = entry[0]
		var dist: int = entry[1]
		if dist >= unit.move:
			continue
		for next in board.neighbors(current):
			if seen.has(next):
				continue
			if not board.is_passable(next, unit.traits()):
				continue
			if unit_at(next) != null:
				continue
			seen[next] = dist + 1
			result.append(next)
			queue.append([next, dist + 1])
	return result


func move_unit(unit: Unit, to: Vector2i) -> bool:
	if not can_move(unit, to)["ok"]:
		return false
	unit.coord = to
	unit.moved = true
	return true


# --- Бой --------------------------------------------------------------------

func can_attack(attacker: Unit, defender: Unit) -> Dictionary:
	if attacker.owner != current_player:
		return {"ok": false, "reason": "сейчас ход другого игрока"}
	if not attacker.activated:
		return {"ok": false, "reason": "фигура не активирована: она может только двигаться"}
	if not attacker.can_attack:
		return {"ok": false, "reason": "эта фигура не может атаковать"}
	if attacker.attacked:
		return {"ok": false, "reason": "эта фигура уже атаковала"}
	if attacker.owner == defender.owner:
		return {"ok": false, "reason": "своих не атакуют"}
	if board.distance(attacker.coord, defender.coord) != 1:
		return {"ok": false, "reason": "атака только по соседней клетке"}
	return {"ok": true, "reason": ""}


## Один бросок атаки: {damage, defense, hit, killed, wounded, coin}
func attack(attacker: Unit, defender: Unit) -> Dictionary:
	var verdict := can_attack(attacker, defender)
	if not verdict["ok"]:
		return {"hit": false, "damage": 0, "defense": 0, "killed": false,
			"wounded": false, "coin": "", "reason": verdict["reason"]}

	attacker.attacked = true
	var damage: int = dice.d4() + attack_bonus(attacker)
	var defense: int = dice.d4() + defense_bonus(defender)
	var result := {"hit": damage > defense, "damage": damage, "defense": defense,
		"killed": false, "wounded": false, "coin": "", "reason": ""}
	if not result["hit"]:
		return result

	var owner_id := attacker.owner
	if defender.wounded:
		result["killed"] = true
		result["reason"] = "рана повторно — фигура покидает поле"
		_remove(defender)
		scores[owner_id] = int(scores.get(owner_id, 0)) + 1
		return result

	var coin: String = dice.coin()
	result["coin"] = coin
	if coin == "black":
		result["killed"] = true
		result["reason"] = "чёрная сторона монеты — фигура погибает"
		_remove(defender)
		scores[owner_id] = int(scores.get(owner_id, 0)) + 1
	else:
		defender.wounded = true
		result["wounded"] = true
		result["reason"] = "белая сторона монеты — фигура ранена"
	return result


func _remove(unit: Unit) -> void:
	units.erase(unit)


func attackable_targets(unit: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	if unit.owner != current_player or unit.attacked or not unit.activated:
		return result
	for other in units:
		if can_attack(unit, other)["ok"]:
			result.append(other)
	return result


# --- Очки и ход -------------------------------------------------------------

## +1 за каждую свою фигуру на ключевой точке.
func collect_points(player: int) -> int:
	var gained := 0
	for unit in units:
		if unit.owner == player and board.terrain_at(unit.coord) == Board.TERRAIN_KEY:
			gained += 1
	scores[player] = int(scores.get(player, 0)) + gained
	return gained


func begin_turn() -> void:
	for unit in units:
		unit.reset_turn_state()
	points_collected_last = collect_points(current_player)


func end_turn() -> void:
	current_player = 3 - current_player
	if current_player == 1:
		turn_number += 1
		round_number += 1
		is_day = not is_day
	begin_turn()


func units_of(player: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if unit.owner == player:
			result.append(unit)
	return result
