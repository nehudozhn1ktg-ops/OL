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
const WIN_POINTS_FFA := 8
const WIN_POINTS_TEAM := 16

## Биомасса заражённых: шкала на фракционном листе 0–6, в начале матча — максимум.
const BIOMASS_MAX := 6
const BIOMASS_DAMAGE_COST := 1
const BIOMASS_RANGE_COST := 2
const BIOMASS_MOVE_COST := 1
const BIOMASS_ARMOR_COST := 1
## +2 биомассы за каждую свою уничтоженную фигуру, +1 за уничтоженного противника.
const BIOMASS_PER_LOSS := 2
const BIOMASS_PER_KILL := 1

## Эссенция нежити: старт 1, максимум 4, +1 за убитого противника.
const ESSENCE_MAX := 4
const ESSENCE_START := 1
const ESSENCE_PER_KILL := 1

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
## Победитель партии: 0 — игра идёт, иначе id победившего игрока.
var winner: int = 0
## Фракции по игрокам: player -> id фракции ("undead", "infected", ...).
var factions: Dictionary = {}
## Эссенция нежити по игрокам (0–4).
var essence: Dictionary = {}


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
	essence.clear()
	winner = 0
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

func can_move(unit: Unit, to: Vector2i, extra_move: int = 0) -> Dictionary:
	if unit.owner != current_player:
		return {"ok": false, "reason": "сейчас ход другого игрока"}
	if unit.moved:
		return {"ok": false, "reason": "эта фигура уже двигалась"}
	if not board.has_cell(to):
		return {"ok": false, "reason": "за пределами поля"}
	var step: int = unit.mp_left + extra_move
	if board.distance(unit.coord, to) > step:
		return {"ok": false, "reason": "дальше, чем позволяет передвижение (%d)" % step}
	if not reachable(unit, extra_move).has(to):
		return {"ok": false, "reason": "нет пути: мешают фигуры, вода или край поля"}
	return {"ok": true, "reason": ""}


## Клетки, куда фигура может дойти за свой ход (BFS по проходимости и занятости).
func reachable(unit: Unit, extra_move: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if unit.owner != current_player or unit.moved:
		return result
	var step: int = unit.mp_left + extra_move
	var seen := {unit.coord: 0}
	var queue: Array = [[unit.coord, 0]]
	while not queue.is_empty():
		var entry: Array = queue.pop_front()
		var current: Vector2i = entry[0]
		var dist: int = entry[1]
		if dist >= step:
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


func move_unit(unit: Unit, to: Vector2i, extra_move: int = 0) -> bool:
	if not can_move(unit, to, extra_move)["ok"]:
		return false
	unit.coord = to
	unit.moved = true
	unit.mp_left = 0
	_resolve_fort_reactions(unit)
	return true


## Движение с усилением биомассой: 1 биомасса = +1 клетка (на 1 или 2).
func move_with_biomass(unit: Unit, to: Vector2i, extra_move: int) -> Dictionary:
	var extra: int = clampi(extra_move, 0, 2)
	var verdict := can_move(unit, to, extra)
	if not verdict["ok"]:
		return verdict
	var cost := BIOMASS_MOVE_COST * extra
	if biomass_of(unit.owner) < cost:
		return {"ok": false,
			"reason": "не хватает биомассы: нужно %d, есть %d" % [cost, biomass_of(unit.owner)]}
	spend_biomass(unit.owner, cost)
	move_unit(unit, to, extra)
	return {"ok": true, "reason": "передвижение +%d за %d биомассы" % [extra, cost]}


# --- Обмен (Линдвурм, ADR-010) ----------------------------------------------

## Обмен местами с другой своей фигурой: стоит 2 передвижения, повторяется,
## пока хватает пула. Цель — любая своя фигура, любое расстояние.
func can_swap(unit: Unit, target: Unit) -> Dictionary:
	if unit.owner != current_player:
		return {"ok": false, "reason": "сейчас ход другого игрока"}
	if target == null or not units.has(target):
		return {"ok": false, "reason": "нет такой фигуры"}
	if target == unit:
		return {"ok": false, "reason": "нельзя меняться с собой"}
	if target.owner != unit.owner:
		return {"ok": false, "reason": "меняться можно только со своей фигурой"}
	if unit.moved:
		return {"ok": false, "reason": "фигура уже потратила движение"}
	if unit.mp_left < 2:
		return {"ok": false, "reason": "не хватает передвижения: нужно 2, есть %d" % unit.mp_left}
	if not unit.abilities.has("swap_places_with_any_figure"):
		return {"ok": false, "reason": "эта фигура не умеет обмениваться"}
	return {"ok": true, "reason": ""}


## Обмен координатами, тратит 2 MP. Не помечает фигуру «сдвинутой» — она может
## обменяться ещё раз или дойти остатком пула.
func swap(unit: Unit, target: Unit) -> Dictionary:
	var verdict := can_swap(unit, target)
	if not verdict["ok"]:
		return verdict
	var a := unit.coord
	unit.coord = target.coord
	target.coord = a
	unit.mp_left -= 2
	return {"ok": true, "reason": "обмен выполнен (осталось %d передвижения)" % unit.mp_left}


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


## Всплеск эссенции (ADR-011): 1 эссенция — кубик атаки минимум 3. Только атака,
## только активированные фигуры.
func attack_with_surge(attacker: Unit, defender: Unit) -> Dictionary:
	var verdict := can_attack(attacker, defender)
	if not verdict["ok"]:
		return {"hit": false, "damage": 0, "defense": 0, "killed": false,
			"wounded": false, "coin": "", "reason": verdict["reason"]}
	if essence_of(attacker.owner) < 1:
		return {"hit": false, "damage": 0, "defense": 0, "killed": false,
			"wounded": false, "coin": "", "reason": "не хватает эссенции для всплеска"}
	spend_essence(attacker.owner, 1)
	attacker.attacked = true
	return _strike(attacker, defender, 0, 3)


## Сам бросок боя, без проверки хода и без расхода атаки: общий путь для
## обычной атаки и для реакции укрепления (ADR-002).
func _strike(attacker: Unit, defender: Unit, extra_damage: int = 0, min_attack: int = 1) -> Dictionary:
	var shot_distance: int = board.distance(attacker.coord, defender.coord)
	var damage: int = dice.d4(min_attack) + attack_bonus(attacker) + extra_damage
	var defense: int = dice.d4() + defense_bonus(defender, shot_distance) + defender.armor_boost
	defender.armor_boost = 0  # усиление брони — на одну защиту
	var result := {"hit": damage > defense, "damage": damage, "defense": defense,
		"killed": false, "wounded": false, "coin": "", "reason": ""}
	if not result["hit"]:
		return result

	var owner_id := attacker.owner
	if defender.wounded:
		result["killed"] = true
		result["reason"] = "рана повторно — фигура покидает поле"
		_remove(defender)
		_add_score(owner_id, 1)
		_gain_kill_resource(owner_id)
		return result

	var coin: String = dice.coin()
	result["coin"] = coin
	if coin == "black":
		result["killed"] = true
		result["reason"] = "чёрная сторона монеты — фигура погибает"
		_remove(defender)
		_add_score(owner_id, 1)
		_gain_kill_resource(owner_id)
	else:
		defender.wounded = true
		result["wounded"] = true
		result["reason"] = "белая сторона монеты — фигура ранена"
	return result


func _remove(unit: Unit) -> void:
	var owner_id := unit.owner
	units.erase(unit)
	if str(factions.get(owner_id, "")) == "infected":
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


## Усиление брони биомассой: 1 биомасса = +1 к следующей защите этой фигуры.
func boost_armor(unit: Unit) -> Dictionary:
	if biomass_of(unit.owner) < BIOMASS_ARMOR_COST:
		return {"ok": false,
			"reason": "не хватает биомассы: нужно %d, есть %d" % [BIOMASS_ARMOR_COST, biomass_of(unit.owner)]}
	spend_biomass(unit.owner, BIOMASS_ARMOR_COST)
	unit.armor_boost += 1
	return {"ok": true, "reason": "броня +1 к следующей защите (биомассы %d)" % biomass_of(unit.owner)}


# --- Эссенция нежити ----------------------------------------------------------

## Стартовая эссенция нежити: 1 шт. (фракционный лист).
func start_essence(player: int) -> void:
	essence[player] = ESSENCE_START


func essence_of(player: int) -> int:
	return int(essence.get(player, 0))


func add_essence(player: int, amount: int) -> void:
	essence[player] = mini(ESSENCE_MAX, essence_of(player) + amount)


func spend_essence(player: int, amount: int) -> bool:
	if amount <= 0:
		return true
	if essence_of(player) < amount:
		return false
	essence[player] = essence_of(player) - amount
	return true


## +ресурс за уничтоженного противника — по фракции убийцы.
func _gain_kill_resource(player: int) -> void:
	match str(factions.get(player, "")):
		"undead":
			add_essence(player, ESSENCE_PER_KILL)
		"infected":
			add_biomass(player, BIOMASS_PER_KILL)


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
	_add_score(owner_id, FLAG_POINTS)
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
	_add_score(player, gained)
	return gained


## Условие победы (канон): 8 очков каждый за себя, 16 — команда. Победа сразу.
func win_points() -> int:
	return WIN_POINTS_FFA


func check_winner() -> int:
	if winner != 0:
		return winner
	for player in scores.keys():
		if int(scores[player]) >= win_points():
			winner = player
			return winner
	return 0


## Начисление очков с проверкой победы.
func _add_score(player: int, amount: int) -> void:
	scores[player] = int(scores.get(player, 0)) + amount
	check_winner()


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
