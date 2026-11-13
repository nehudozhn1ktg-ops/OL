extends RefCounted
class_name Game

## Партия по правилам 0.7.1.
##
## Ход: активируются две фигуры (движение + атака), остальные только двигаются.
## Бой: D4 + бонус урона против D4 + броня + террейн + ауры.
## Проигрыш в защите: монета — белая сторона ранит, чёрная убивает.
## Раненая фигура при следующем проигрыше погибает без монеты.

const MAX_ACTIVATIONS := 2
const FLAG_POINTS := 3

## Биомасса заражённых: шкала на фракционном листе 0–6, в начале матча — максимум.
const BIOMASS_MAX := 6
const BIOMASS_DAMAGE_COST := 1
const BIOMASS_RANGE_COST := 2
## +2 биомассы за каждую свою уничтоженную фигуру, +1 за уничтоженного противника.
const BIOMASS_PER_LOSS := 2
const BIOMASS_PER_KILL := 1

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

## Реакции укрепления после последнего движения (ADR-002): список ударов.
var last_fort_reactions: Array[Dictionary] = []

## Флаги: coord -> владелец. Террейн «флаг» один для всех, поэтому владелец
## хранится отдельно от подложки карты.
var flags: Dictionary = {}
## Биомасса заражённых по игрокам (0–6). Начисляется за бои, тратится на усиления.
var biomass: Dictionary = {}


func setup(board_: Board, dice_: Dice = null) -> void:
	board = board_
	dice = dice_ if dice_ != null else Dice.new()
	units.clear()
	current_player = 1
	turn_number = 1
	round_number = 1
	is_day = true
	scores = {1: 0, 2: 0, 3: 0, 4: 0}
	flags.clear()
	last_fort_reactions.clear()
	biomass.clear()
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

## Бонус защиты от террейна. Патч 7: лес защищает только от атаки с соседней
## клетки — дальний выстрел в лес бонуса не получает.
func terrain_defense_bonus(unit: Unit, distance: int = 1) -> int:
	var terrain: int = board.terrain_at(unit.coord)
	if terrain == Board.TERRAIN_FOREST and distance > 1:
		return 0
	return int(TERRAIN_DEFENSE.get(terrain, 0))


## Аура «командир»: союзники в радиусе 1 получают +1 к защите.
func aura_defense_bonus(unit: Unit) -> int:
	var bonus := 0
	for other in units:
		if other == unit or other.owner != unit.owner:
			continue
		if other.abilities.has("commander") and board.distance(other.coord, unit.coord) <= 1:
			bonus += 1
	return bonus


func defense_bonus(unit: Unit, distance: int = 1) -> int:
	return unit.armor + terrain_defense_bonus(unit, distance) + aura_defense_bonus(unit)


## Дальность атаки фигуры в клетках (1 — только соседняя).
func attack_range(unit: Unit) -> int:
	return maxi(1, unit.range)


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
	_resolve_fort_reactions(unit)
	return true


# --- Бой --------------------------------------------------------------------

func can_attack(attacker: Unit, defender: Unit, extra_range: int = 0) -> Dictionary:
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
	var reach: int = attack_range(attacker) + extra_range
	var dist: int = board.distance(attacker.coord, defender.coord)
	if dist < 1 or dist > reach:
		return {"ok": false, "reason": "цель дальше дальности атаки (%d)" % reach}
	return {"ok": true, "reason": ""}


## Один бросок атаки: {damage, defense, hit, killed, wounded, coin}.
## bonus: {"damage": +N, "range": +N} — усиления (биомасса и т.п.).
func attack(attacker: Unit, defender: Unit, bonus: Dictionary = {}) -> Dictionary:
	var extra_range := int(bonus.get("range", 0))
	var verdict := can_attack(attacker, defender, extra_range)
	if not verdict["ok"]:
		return {"hit": false, "damage": 0, "defense": 0, "killed": false,
			"wounded": false, "coin": "", "reason": verdict["reason"]}

	attacker.attacked = true
	return _strike(attacker, defender, int(bonus.get("damage", 0)))


## Атака с усилением биомассой: 1 биомасса = +1 урон, 2 = +1 дальность.
func attack_with_biomass(attacker: Unit, defender: Unit,
		damage_up: bool = false, range_up: bool = false) -> Dictionary:
	var extra_range := 1 if range_up else 0
	var verdict := can_attack(attacker, defender, extra_range)
	if not verdict["ok"]:
		return {"hit": false, "damage": 0, "defense": 0, "killed": false,
			"wounded": false, "coin": "", "reason": verdict["reason"]}

	var cost := (BIOMASS_DAMAGE_COST if damage_up else 0) + (BIOMASS_RANGE_COST if range_up else 0)
	if biomass_of(attacker.owner) < cost:
		return {"hit": false, "damage": 0, "defense": 0, "killed": false,
			"wounded": false, "coin": "",
			"reason": "не хватает биомассы: нужно %d, есть %d" % [cost, biomass_of(attacker.owner)]}

	spend_biomass(attacker.owner, cost)
	attacker.attacked = true
	return _strike(attacker, defender, 1 if damage_up else 0)


## Сам бросок боя, без проверки хода и без расхода атаки: общий путь для
## обычной атаки и для реакции укрепления (ADR-002).
func _strike(attacker: Unit, defender: Unit, extra_damage: int = 0) -> Dictionary:
	var shot_distance: int = board.distance(attacker.coord, defender.coord)
	var damage: int = dice.d4() + attack_bonus(attacker) + extra_damage
	var defense: int = dice.d4() + defense_bonus(defender, shot_distance)
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
		add_biomass(owner_id, BIOMASS_PER_KILL)
		return result

	var coin: String = dice.coin()
	result["coin"] = coin
	if coin == "black":
		result["killed"] = true
		result["reason"] = "чёрная сторона монеты — фигура погибает"
		_remove(defender)
		scores[owner_id] = int(scores.get(owner_id, 0)) + 1
		add_biomass(owner_id, BIOMASS_PER_KILL)
	else:
		defender.wounded = true
		result["wounded"] = true
		result["reason"] = "белая сторона монеты — фигура ранена"
	return result


func _remove(unit: Unit) -> void:
	var owner_id := unit.owner
	units.erase(unit)
	add_biomass(owner_id, BIOMASS_PER_LOSS)
	# Канон: потерявшая весь отряд фракция теряет и флаг. Очков за это не дают.
	if units_of(owner_id).is_empty():
		_remove_flag_of(owner_id)


# --- Биомасса заражённых ------------------------------------------------------

## В начале матча биомасса — максимум (фракционный лист, 0–6).
func start_biomass(player: int) -> void:
	biomass[player] = BIOMASS_MAX


func biomass_of(player: int) -> int:
	return int(biomass.get(player, 0))


func add_biomass(player: int, amount: int) -> void:
	biomass[player] = mini(BIOMASS_MAX, biomass_of(player) + amount)


func spend_biomass(player: int, amount: int) -> bool:
	if amount <= 0:
		return true
	if biomass_of(player) < amount:
		return false
	biomass[player] = biomass_of(player) - amount
	return true


## Хватает ли биомассы на усиление атаки (+1 урон / +1 дальность).
func can_empower_attack(player: int, damage_up: bool, range_up: bool) -> bool:
	var cost := (BIOMASS_DAMAGE_COST if damage_up else 0) + (BIOMASS_RANGE_COST if range_up else 0)
	return biomass_of(player) >= cost


func attackable_targets(unit: Unit, extra_range: int = 0) -> Array[Unit]:
	var result: Array[Unit] = []
	if unit.owner != current_player or unit.attacked or not unit.activated:
		return result
	for other in units:
		if can_attack(unit, other, extra_range)["ok"]:
			result.append(other)
	return result


# --- Реакция укрепления (ADR-002) -------------------------------------------

## Кто обязан ответить на остановку moved на соседней клетке: противники,
## стоящие на клетке укрепления и умеющие атаковать.
func fort_reactors_to(moved: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	if moved == null or not units.has(moved):
		return result
	for unit in units:
		if unit.owner == moved.owner or not unit.can_attack:
			continue
		if board.terrain_at(unit.coord) != Board.TERRAIN_FORT:
			continue
		if board.distance(unit.coord, moved.coord) != 1:
			continue
		result.append(unit)
	return result


## Отработать реакции после остановки: каждое укрепление бьёт один раз,
## бесплатно — без расхода активации и атаки, в чужой ход тоже. Цель могла
## погибнуть от предыдущей реакции: тогда следующие уже не бьют.
func _resolve_fort_reactions(moved: Unit) -> Array[Dictionary]:
	last_fort_reactions.clear()
	for reactor in fort_reactors_to(moved):
		if not units.has(moved):
			break
		var blow := _strike(reactor, moved)
		blow["attacker"] = reactor
		blow["defender"] = moved
		last_fort_reactions.append(blow)
	return last_fort_reactions


# --- Флаг фракции ------------------------------------------------------------

## Поставить флаг игрока на клетку (обычно — на клетку «флаг» из карты).
func add_flag(owner: int, coord: Vector2i) -> void:
	board.set_terrain(coord, Board.TERRAIN_FLAG)
	flags[coord] = owner


func has_flag(coord: Vector2i) -> bool:
	return flags.has(coord)


func flag_owner(coord: Vector2i) -> int:
	return int(flags.get(coord, 0))


func flag_of(owner: int) -> Vector2i:
	for coord in flags.keys():
		if int(flags[coord]) == owner:
			return coord
	return Vector2i.ZERO


## Канон: флаг — препятствие с особым условием уничтожения, атакуется как
## обычная цель с соседней клетки, но только активированной фигурой.
func can_attack_flag(attacker: Unit, coord: Vector2i) -> Dictionary:
	if not flags.has(coord):
		return {"ok": false, "reason": "здесь нет флага"}
	if attacker.owner != current_player:
		return {"ok": false, "reason": "сейчас ход другого игрока"}
	if not attacker.activated:
		return {"ok": false, "reason": "фигура не активирована: она может только двигаться"}
	if not attacker.can_attack:
		return {"ok": false, "reason": "эта фигура не может атаковать"}
	if attacker.attacked:
		return {"ok": false, "reason": "эта фигура уже атаковала"}
	if flag_owner(coord) == attacker.owner:
		return {"ok": false, "reason": "свой флаг не атакуют"}
	if board.distance(attacker.coord, coord) != 1:
		return {"ok": false, "reason": "атака только по соседней клетке"}
	return {"ok": true, "reason": ""}


## Бросок по флагу: нужна 4, Королю — 3–4. Бонусы урона и способности
## не участвуют: канон прямо говорит, что они не влияют на условие.
## Возвращает {destroyed, roll, reason}.
func attack_flag(attacker: Unit, coord: Vector2i) -> Dictionary:
	var verdict := can_attack_flag(attacker, coord)
	if not verdict["ok"]:
		return {"destroyed": false, "roll": 0, "reason": verdict["reason"]}

	attacker.attacked = true
	var roll: int = dice.d4()
	var need: int = 3 if attacker.is_king() else 4
	if roll < need:
		return {"destroyed": false, "roll": roll,
			"reason": "бросок %d — флаг устоял (нужно %d)" % [roll, need]}

	_remove_flag(coord)
	var owner_id := attacker.owner
	scores[owner_id] = int(scores.get(owner_id, 0)) + FLAG_POINTS
	return {"destroyed": true, "roll": roll,
		"reason": "бросок %d — флаг уничтожен (+%d очка)" % [roll, FLAG_POINTS]}


## Убранный флаг освобождает клетку: ASSUMPTION, канон об этом молчит,
## вопрос владельцу записан в docs/memory/errors.md.
func _remove_flag(coord: Vector2i) -> void:
	flags.erase(coord)
	board.set_terrain(coord, Board.TERRAIN_GRASS)


func _remove_flag_of(owner_id: int) -> void:
	for coord in flags.keys():
		if int(flags[coord]) == owner_id:
			_remove_flag(coord)
			return


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
