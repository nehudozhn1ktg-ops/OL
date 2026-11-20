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

## Энергия природы эльфов: 2 фишки на фракционном листе, без пополнения.
const ENERGY_START := 2

## Баррикады людей: 4 фишки, без пополнения.
const BARRICADE_START := 4

## Цены заклинаний Некроманта (ADR-012, патч 7): пешка — 2, командир — 3,
## уничтожение чужой пешки/командира — 4.
const ESSENCE_SUMMON_PAWN := 2
const ESSENCE_SUMMON_COMMANDER := 3
const ESSENCE_RESURRECT_PAWN := 2
const ESSENCE_RESURRECT_COMMANDER := 3
const ESSENCE_SLAY := 4

## Бонусы защиты от террейна (легенда карт).
const TERRAIN_DEFENSE := {
	Board.TERRAIN_FOREST: 1,
	Board.TERRAIN_FORT: 1,
}

var board: Board
var dice: Dice
var units: Array[Unit] = []
var current_player: int = 1
## Число игроков в партии (2 — дуэль, 4 — FFA). Задаётся в setup().
var player_count: int = 2
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
## Энергия природы эльфов (0–2) и +1 активация в текущий ход (сбрасывается в начале хода).
var energy: Dictionary = {}
var extra_activations: Dictionary = {}
## Урна душ нежити: одноразовая фишка — до конца хода эссенция на максимуме.
var urn_used: Dictionary = {}
var urn_active: Dictionary = {}
var essence_before_urn: Dictionary = {}
## Баррикады людей: player -> остаток фишек (0–4).
var barricades: Dictionary = {}
## Кокон заражённых: player -> клетка кокона (возрождение первой погибшей).
var cocoon: Dictionary = {}
## Магический щит Эфиральда: player -> остаток щитов (0–3).
var shield: Dictionary = {}
## Погибшие фигуры — для воскрешения Некромантом (ADR-012).
var graveyard: Array[Unit] = []
## Призываемые фигуры: player -> {unit_id: Dictionary (данные фракционного листа)}.
var summon_defs: Dictionary = {}
## Слияния Эфиральда: player -> {fusion_id: Dictionary}.
var fusion_defs: Dictionary = {}
## Отложенная атака (двухфазный бой, ADR-015): объявление → (ответ защитника) → бросок.
## Ключи: attacker, defender, extra_damage, min_attack. Пусто — атаки не объявлено.
var pending_attack: Dictionary = {}


func setup(board_: Board, dice_: Dice = null, player_count_: int = 2) -> void:
	board = board_
	dice = dice_ if dice_ != null else Dice.new()
	player_count = maxi(1, player_count_)
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
	energy.clear()
	extra_activations.clear()
	urn_used.clear()
	urn_active.clear()
	essence_before_urn.clear()
	barricades.clear()
	cocoon.clear()
	shield.clear()
	graveyard.clear()
	summon_defs.clear()
	fusion_defs.clear()
	pending_attack.clear()
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


## Расставить отряд на клетках лагеря (соседях флага) в случайном порядке.
## Канон: фигуры — на клетках «лагерь» рядом с флагом, какая фигура на какой
## клетке — случайно. Число клеток берётся по размеру отряда (не всегда 6).
func place_roster(player: int, anchor: Vector2i, roster: Array) -> Array[Unit]:
	var spots := board.deployment_cells(anchor, roster.size())
	var order := roster.duplicate()
	order.shuffle()
	var placed: Array[Unit] = []
	for i in mini(spots.size(), order.size()):
		placed.append(add_unit_from_data(player, spots[i], order[i]))
	return placed


func unit_at(coord: Vector2i) -> Unit:
	for unit in units:
		if unit.coord == coord:
			return unit
	return null


# --- Взаимодействия: свойства объектов дают числа ---------------------------

## Бонус защиты от террейна. Патч 7: лес защищает только от атаки с соседней
## клетки — дальний выстрел в лес бонуса не получает. Дерево (tree_bark):
## трава для этой фигуры считается лесом.
func terrain_defense_bonus(unit: Unit, distance: int = 1) -> int:
	var terrain: int = board.terrain_at(unit.coord)
	if unit.abilities.has("tree_bark") and terrain == Board.TERRAIN_GRASS:
		terrain = Board.TERRAIN_FOREST
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
	var bonus: int = unit.armor + terrain_defense_bonus(unit, distance) + aura_defense_bonus(unit)
	if unit.abilities.has("earth_armor_bonus") or _has_elemental_ability(unit, "earth_armor_bonus"):
		bonus += 1
	return bonus


## Дальность атаки фигуры в клетках (1 — только соседняя).
func attack_range(unit: Unit) -> int:
	var r: int = maxi(1, unit.range)
	if unit.abilities.has("bolt_range_bonus") or _has_elemental_ability(unit, "bolt_range_bonus"):
		r += 1
	return r


func attack_bonus(unit: Unit) -> int:
	var bonus: int = unit.damage
	if unit.abilities.has("fire_damage_bonus") or _has_elemental_ability(unit, "fire_damage_bonus"):
		bonus += 1
	return bonus


## Пула передвижения фигуры с учётом пассивок (Вода +1).
func move_value(unit: Unit) -> int:
	var v: int = unit.mp_left
	if unit.abilities.has("water_move_bonus") or _has_elemental_ability(unit, "water_move_bonus"):
		v += 1
	return v


## Есть ли среди живых элементалей владельца такой с пассивкой (для Архимага).
func _has_elemental_ability(unit: Unit, ability: String) -> bool:
	if not unit.abilities.has("heart_of_elements"):
		return false
	for u in units:
		if u.owner == unit.owner and u.elemental and u.abilities.has(ability):
			return true
	return false


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
	var limit: int = MAX_ACTIVATIONS + int(extra_activations.get(current_player, 0))
	if activated_count(current_player) >= limit:
		return {"ok": false, "reason": "на этот ход уже активированы %d фигуры" % limit}
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
	var step: int = move_value(unit) + extra_move
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
	var step: int = move_value(unit) + extra_move
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
			if unit_at(next) != null and not unit.abilities.has("air_phase"):
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


# --- Рокировка (люди, патч 7) ------------------------------------------------

## Активная рокировка: активированная фигура меняется местами с соседней своей.
## Раз за ход фигуры, не заменяет атаку/передвижение, доступна только людям.
func can_castle(unit: Unit, target: Unit) -> Dictionary:
	if unit.owner != current_player:
		return {"ok": false, "reason": "сейчас ход другого игрока"}
	if str(factions.get(unit.owner, "")) != "people":
		return {"ok": false, "reason": "рокировка доступна только Ордену креста"}
	if not unit.activated:
		return {"ok": false, "reason": "фигура не активирована"}
	if unit.castled:
		return {"ok": false, "reason": "эта фигура уже рокировалась в этот ход"}
	if target == null or not units.has(target):
		return {"ok": false, "reason": "нет такой фигуры"}
	if target == unit:
		return {"ok": false, "reason": "нельзя меняться с собой"}
	if target.owner != unit.owner:
		return {"ok": false, "reason": "рокировка только со своей фигурой"}
	if board.distance(unit.coord, target.coord) != 1:
		return {"ok": false, "reason": "рокировка только с соседней фигурой"}
	return {"ok": true, "reason": ""}


func castle(unit: Unit, target: Unit) -> Dictionary:
	var verdict := can_castle(unit, target)
	if not verdict["ok"]:
		return verdict
	var a := unit.coord
	unit.coord = target.coord
	target.coord = a
	unit.castled = true
	return {"ok": true, "reason": "рокировка выполнена"}


## Защитная рокировка: можно ли атакуемую фигуру поменять местами с соседней своей
## до броска (атака перенаправится).
func can_castle_defense(defender: Unit) -> bool:
	if pending_attack.is_empty() or pending_attack["defender"] != defender:
		return false
	if str(factions.get(defender.owner, "")) != "people":
		return false
	for unit in units:
		if unit.owner != defender.owner or unit == defender:
			continue
		if board.distance(unit.coord, defender.coord) == 1:
			return true
	return false


func castle_defense(defender: Unit, target: Unit) -> Dictionary:
	if not can_castle_defense(defender):
		return {"ok": false, "reason": "защитная рокировка недоступна"}
	if target == null or target == defender or target.owner != defender.owner:
		return {"ok": false, "reason": "неверная цель рокировки"}
	if board.distance(target.coord, defender.coord) != 1:
		return {"ok": false, "reason": "рокировка только с соседней фигурой"}
	var a := defender.coord
	defender.coord = target.coord
	target.coord = a
	pending_attack["defender"] = target
	return {"ok": true, "reason": "защитная рокировка: атака перенаправлена"}


# --- Слияние Эфиральда --------------------------------------------------------

## Элементаль, ещё не слитый (участвует в слиянии).
func _is_elemental(unit: Unit) -> bool:
	return unit != null and unit.elemental and not unit.fusion


## По паре элементалей — id их слияния (или пусто).
func _fusion_for(a: Unit, b: Unit) -> String:
	var defs: Dictionary = fusion_defs.get(a.owner, {})
	for fusion_id in defs.keys():
		var elements: Array = defs[fusion_id].get("elements", [])
		if elements.size() != 2:
			continue
		var e0: String = str(elements[0])
		var e1: String = str(elements[1])
		if (e0 == a.unit_id and e1 == b.unit_id) or (e0 == b.unit_id and e1 == a.unit_id):
			return str(fusion_id)
	return ""


func can_fuse(unit: Unit, target: Unit) -> Dictionary:
	if unit.owner != current_player:
		return {"ok": false, "reason": "сейчас ход другого игрока"}
	if str(factions.get(unit.owner, "")) != "elemental":
		return {"ok": false, "reason": "слияние доступно только Эфиральду"}
	if not unit.activated:
		return {"ok": false, "reason": "фигура не активирована"}
	if target == null or target == unit or target.owner != unit.owner:
		return {"ok": false, "reason": "цель — другой ваш элементаль"}
	if not _is_elemental(unit) or not _is_elemental(target):
		return {"ok": false, "reason": "сливать можно только элементалей"}
	if board.distance(unit.coord, target.coord) != 1:
		return {"ok": false, "reason": "элементали должны быть соседними"}
	if _fusion_for(unit, target) == "":
		return {"ok": false, "reason": "нет слияния для этой пары"}
	return {"ok": true, "reason": ""}


## Слить двух соседних элементалей в слияние на месте цели.
func fuse(unit: Unit, target: Unit) -> Dictionary:
	var verdict := can_fuse(unit, target)
	if not verdict["ok"]:
		return verdict
	var fusion_id := _fusion_for(unit, target)
	var def: Dictionary = fusion_defs[unit.owner].get(fusion_id, {})
	var cell := target.coord
	var owner := unit.owner
	unit.acted = true
	_remove(unit)
	_remove(target)
	var fusion_unit := add_unit_from_data(owner, cell, def)
	fusion_unit.no_wound = true
	fusion_unit.fusion = true
	return {"ok": true, "reason": "%s создано" % str(def.get("name", fusion_id))}


## Телепортация Лавы на расстояние своего передвижения (патч 7).
func can_teleport(unit: Unit, to: Vector2i) -> Dictionary:
	if unit.owner != current_player:
		return {"ok": false, "reason": "сейчас ход другого игрока"}
	if not unit.abilities.has("lava_teleport"):
		return {"ok": false, "reason": "телепортация доступна только Лаве"}
	if not unit.activated:
		return {"ok": false, "reason": "фигура не активирована"}
	if unit.moved:
		return {"ok": false, "reason": "фигура уже двигалась"}
	if not board.has_cell(to):
		return {"ok": false, "reason": "за пределами поля"}
	if unit_at(to) != null:
		return {"ok": false, "reason": "клетка занята"}
	if not board.is_passable(to):
		return {"ok": false, "reason": "клетка непроходима"}
	var dist: int = board.distance(unit.coord, to)
	if dist > move_value(unit):
		return {"ok": false, "reason": "дальше, чем позволяет передвижение"}
	return {"ok": true, "reason": ""}


func teleport(unit: Unit, to: Vector2i) -> Dictionary:
	var verdict := can_teleport(unit, to)
	if not verdict["ok"]:
		return verdict
	unit.coord = to
	unit.moved = true
	return {"ok": true, "reason": "телепортация выполнена"}


## Магнетизм: после движения притянуть свою пешку/командира на соседнюю клетку.
func can_pull_ally(unit: Unit, target: Unit, to: Vector2i) -> Dictionary:
	if not unit.abilities.has("magnet_pull"):
		return {"ok": false, "reason": "магнетизм доступен только слиянию Магнетизм"}
	if unit.owner != current_player:
		return {"ok": false, "reason": "сейчас ход другого игрока"}
	if not unit.moved:
		return {"ok": false, "reason": "сначала передвиньте Магнетизм"}
	if target == null or not units.has(target) or target == unit:
		return {"ok": false, "reason": "нет такой фигуры"}
	if target.owner != unit.owner:
		return {"ok": false, "reason": "только свою фигуру"}
	if target.kind != "pawn" and target.kind != "commander":
		return {"ok": false, "reason": "только пешку или командира"}
	if board.distance(unit.coord, to) != 1:
		return {"ok": false, "reason": "только на соседнюю от Магнетизма клетку"}
	if not board.has_cell(to) or not board.is_passable(to) or unit_at(to) != null:
		return {"ok": false, "reason": "клетка занята или непроходима"}
	return {"ok": true, "reason": ""}


func pull_ally(unit: Unit, target: Unit, to: Vector2i) -> Dictionary:
	var verdict := can_pull_ally(unit, target, to)
	if not verdict["ok"]:
		return verdict
	target.coord = to
	return {"ok": true, "reason": "фигура притянута"}


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
	if attacker.acted and not attacker.abilities.has("heart_of_elements"):
		return {"ok": false, "reason": "фигура уже потратила действие (атака или действие)"}
	if attacker.owner == defender.owner:
		return {"ok": false, "reason": "своих не атакуют"}
	var reach: int = attack_range(attacker) + extra_range
	var dist: int = board.distance(attacker.coord, defender.coord)
	if dist > 1 and defender.abilities.has("heat_shield"):
		return {"ok": false, "reason": "цель невосприимчива к дальним атакам"}
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


# --- Двухфазная атака (ADR-015): броня биомассой в ответ -----------------------

## Первая фаза — объявление атаки. Проверяет ход/дальность, списывает ресурсы
## атакующего (биомасса за урон/дальность, эссенция за всплеск) и помечает
## «атаковал». Сам бросок откладывается до resolve_attack, чтобы защитник успел
## ответить биомассой (+1 броня). needs_defense=true — защитнику нужна пауза.
func declare_attack(attacker: Unit, defender: Unit,
		damage_up: bool = false, range_up: bool = false, surge: bool = false) -> Dictionary:
	if not pending_attack.is_empty():
		return {"ok": false, "reason": "уже объявлена атака — сперва бросок", "needs_defense": false}
	var extra_range := 1 if range_up else 0
	var verdict := can_attack(attacker, defender, extra_range)
	if not verdict["ok"]:
		return {"ok": false, "reason": verdict["reason"], "needs_defense": false}
	var cost := (BIOMASS_DAMAGE_COST if damage_up else 0) + (BIOMASS_RANGE_COST if range_up else 0)
	if surge and essence_of(attacker.owner) < 1:
		return {"ok": false, "reason": "не хватает эссенции для всплеска", "needs_defense": false}
	if cost > 0 and biomass_of(attacker.owner) < cost:
		return {"ok": false,
			"reason": "не хватает биомассы: нужно %d, есть %d" % [cost, biomass_of(attacker.owner)],
			"needs_defense": false}
	if cost > 0:
		spend_biomass(attacker.owner, cost)
	if surge:
		spend_essence(attacker.owner, 1)
	attacker.attacked = true
	pending_attack = {
		"attacker": attacker,
		"defender": defender,
		"extra_damage": 1 if damage_up else 0,
		"min_attack": 3 if surge else 1,
	}
	return {"ok": true, "needs_defense": can_defend_with_biomass(defender) or can_castle_defense(defender), "reason": ""}


## Защитник отложенной атаки (или null, если атака не объявлена).
func pending_defender() -> Unit:
	if pending_attack.is_empty():
		return null
	return pending_attack["defender"] as Unit


## Может ли защитник отложенной атаки ответить биомассой: +1 броня к этой защите.
## Только заражённый (фракция infected) с биомассой, максимум +1 за защиту.
func can_defend_with_biomass(defender: Unit) -> bool:
	if pending_attack.is_empty() or pending_attack["defender"] != defender:
		return false
	if str(factions.get(defender.owner, "")) != "infected":
		return false
	if biomass_of(defender.owner) < BIOMASS_ARMOR_COST:
		return false
	if defender.armor_boost > 0:
		return false
	return true


## Защитник тратит 1 биомассу на +1 броню к этой защите (только в ответ на атаку).
func defend_with_biomass(defender: Unit) -> Dictionary:
	if not can_defend_with_biomass(defender):
		return {"ok": false, "reason": "усиление брони недоступно"}
	spend_biomass(defender.owner, BIOMASS_ARMOR_COST)
	defender.armor_boost += 1
	return {"ok": true, "reason": "броня +1 к этой защите (биомассы %d)" % biomass_of(defender.owner)}


## Вторая фаза: выполнить отложенный бросок. Если защитник ответил биомассой,
## его +1 броня уже в defender.armor_boost и войдёт в защиту.
func resolve_attack() -> Dictionary:
	if pending_attack.is_empty():
		return {"hit": false, "damage": 0, "defense": 0, "killed": false,
			"wounded": false, "coin": "", "reason": "нет объявленной атаки"}
	var attacker: Unit = pending_attack["attacker"]
	var defender: Unit = pending_attack["defender"]
	var extra_damage: int = pending_attack["extra_damage"]
	var min_attack: int = pending_attack["min_attack"]
	pending_attack.clear()
	return _strike(attacker, defender, extra_damage, min_attack)


## Ледяное копьё Льда (патч 7): действие, наносит 4 урона (плюс бонусы).
func can_ice_lance(unit: Unit, defender: Unit) -> Dictionary:
	if not unit.abilities.has("ice_lance"):
		return {"ok": false, "reason": "ледяное копьё доступно только Льду"}
	var verdict := can_act(unit)
	if not verdict["ok"]:
		return verdict
	if defender == null or not units.has(defender):
		return {"ok": false, "reason": "нет цели"}
	if defender.owner == unit.owner:
		return {"ok": false, "reason": "своих не атакуют"}
	var dist: int = board.distance(unit.coord, defender.coord)
	if dist < 1 or dist > attack_range(unit):
		return {"ok": false, "reason": "цель дальше дальности атаки (%d)" % attack_range(unit)}
	return {"ok": true, "reason": ""}


func ice_lance(unit: Unit, defender: Unit) -> Dictionary:
	var verdict := can_ice_lance(unit, defender)
	if not verdict["ok"]:
		return {"hit": false, "damage": 0, "defense": 0, "killed": false,
			"wounded": false, "coin": "", "reason": verdict["reason"]}
	unit.acted = true
	return _strike(unit, defender, 0, 1, 4)


## Сам бросок боя, без проверки хода и без расхода атаки: общий путь для
## обычной атаки и для реакции укрепления (ADR-002).
func _strike(attacker: Unit, defender: Unit, extra_damage: int = 0, min_attack: int = 1, fixed_damage: int = 0) -> Dictionary:
	var shot_distance: int = board.distance(attacker.coord, defender.coord)
	var damage: int
	if fixed_damage > 0:
		damage = fixed_damage + attack_bonus(attacker) + extra_damage
	else:
		var raw: int
		if defender.abilities.has("boiling_aura"):
			var d1: int = dice.d4(min_attack)
			var d2: int = dice.d4(min_attack)
			raw = mini(d1, d2)
		else:
			raw = dice.d4(min_attack)
		if attacker.abilities.has("crystal_gamble") and raw % 2 == 0:
			raw += 2
		if attacker.abilities.has("black_flame") and board.terrain_at(defender.coord) == Board.TERRAIN_FOREST:
			raw += 1
		damage = raw + attack_bonus(attacker) + extra_damage
	var shield_bonus: int = 2 if defender.shield else 0
	var raw_def: int = dice.d4()
	if defender.abilities.has("crystal_gamble") and raw_def % 2 == 0:
		raw_def += 2
	var defense: int = raw_def + defense_bonus(defender, shot_distance) + defender.armor_boost + shield_bonus
	defender.armor_boost = 0  # усиление брони — на одну защиту
	defender.shield = false  # магический щит — на одну защиту
	var result := {"hit": damage > defense, "damage": damage, "defense": defense,
		"killed": false, "wounded": false, "coin": "", "reason": ""}
	if not result["hit"]:
		return result

	var owner_id := attacker.owner
	if defender.no_wound:
		var expl_cell := defender.coord
		result["reason"] = "призванная фигура не имеет механики ранения — погибает"
		_kill_or_reborn(defender, owner_id, result)
		if result["killed"] and attacker.abilities.has("explosion"):
			_explode_at(expl_cell, attacker)
		return result

	if defender.wounded:
		var expl_cell := defender.coord
		result["reason"] = "рана повторно — фигура покидает поле"
		_kill_or_reborn(defender, owner_id, result)
		if result["killed"] and attacker.abilities.has("explosion"):
			_explode_at(expl_cell, attacker)
		return result

	var coin: String = dice.coin()
	result["coin"] = coin
	if coin == "black":
		var expl_cell := defender.coord
		result["reason"] = "чёрная сторона монеты — фигура погибает"
		_kill_or_reborn(defender, owner_id, result)
		if result["killed"] and attacker.abilities.has("explosion"):
			_explode_at(expl_cell, attacker)
	else:
		defender.wounded = true
		result["wounded"] = true
		result["reason"] = "белая сторона монеты — фигура ранена"
	return result


## Возрождение из кокона: если стоит — фигура переносится на его место живой.
func _reborn_from_cocoon(unit: Unit) -> bool:
	if not cocoon.has(unit.owner):
		return false
	var cell: Vector2i = cocoon[unit.owner]
	cocoon.erase(unit.owner)
	unit.coord = cell
	unit.wounded = false
	unit.no_wound = false
	unit.armor_boost = 0
	return true


## Взрыв (слияние Взрыв): при убийстве — ранит соседей цели.
func _explode_at(coord: Vector2i, attacker: Unit) -> void:
	var victims: Array = []
	for u in units:
		if u.owner != attacker.owner and board.distance(coord, u.coord) == 1:
			victims.append(u)
	for u in victims:
		if u.wounded:
			_remove(u)
			_add_score(attacker.owner, 1)
			_gain_kill_resource(attacker.owner)
		else:
			u.wounded = true


## Гибель с проверкой кокона: возрождение (без очков) или удаление (очки + ресурс).
func _kill_or_reborn(defender: Unit, owner_id: int, result: Dictionary) -> void:
	if _reborn_from_cocoon(defender):
		result["killed"] = false
		result["reborn"] = true
		result["reason"] = "фигура возродилась из кокона"
		return
	result["killed"] = true
	_remove(defender)
	_add_score(owner_id, 1)
	_gain_kill_resource(owner_id)


func _remove(unit: Unit) -> void:
	var owner_id := unit.owner
	units.erase(unit)
	graveyard.append(unit)
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


# --- Энергия природы эльфов ---------------------------------------------------

func start_energy(player: int) -> void:
	energy[player] = ENERGY_START


func energy_of(player: int) -> int:
	return int(energy.get(player, 0))


func spend_energy(player: int, amount: int) -> bool:
	if amount <= 0:
		return true
	if energy_of(player) < amount:
		return false
	energy[player] = energy_of(player) - amount
	return true


## +1 активация в этот ход (патч 7). Раз в ход, тратит 1 энергию.
func use_nature_energy(player: int) -> Dictionary:
	if energy_of(player) < 1:
		return {"ok": false, "reason": "нет энергии природы"}
	if int(extra_activations.get(player, 0)) >= 1:
		return {"ok": false, "reason": "энергия уже использована в этот ход"}
	spend_energy(player, 1)
	extra_activations[player] = 1
	return {"ok": true, "reason": "+1 активация в этот ход"}


# --- Урна душ нежити ----------------------------------------------------------

## Одноразовая фишка: до конца хода эссенция — максимум, в конце хода
## возвращается к значению начала хода (патч 7).
func use_urn_of_souls(player: int) -> Dictionary:
	if bool(urn_used.get(player, false)):
		return {"ok": false, "reason": "урна душ уже использована"}
	if bool(urn_active.get(player, false)):
		return {"ok": false, "reason": "урна уже активна в этот ход"}
	urn_used[player] = true
	essence_before_urn[player] = essence_of(player)
	essence[player] = ESSENCE_MAX
	urn_active[player] = true
	return {"ok": true, "reason": "до конца хода эссенция — максимум"}


# --- Баррикады людей ----------------------------------------------------------

func start_barricades(player: int) -> void:
	barricades[player] = BARRICADE_START


func barricades_of(player: int) -> int:
	return int(barricades.get(player, 0))


func spend_barricade(player: int) -> bool:
	if barricades_of(player) < 1:
		return false
	barricades[player] = barricades_of(player) - 1
	return true


## Поставить баррикаду на клетку, соседнюю со своей фигурой (патч 7).
func can_place_barricade(player: int, coord: Vector2i) -> Dictionary:
	if barricades_of(player) < 1:
		return {"ok": false, "reason": "нет фишек «баррикада»"}
	if not board.has_cell(coord):
		return {"ok": false, "reason": "клетка за пределами поля"}
	if board.is_water(coord):
		return {"ok": false, "reason": "на воду баррикаду ставить нельзя"}
	var terrain: int = board.terrain_at(coord)
	if terrain == Board.TERRAIN_FLAG or terrain == Board.TERRAIN_BARRICADE:
		return {"ok": false, "reason": "клетка занята препятствием"}
	if unit_at(coord) != null:
		return {"ok": false, "reason": "клетка занята фигурой"}
	var adjacent := false
	for unit in units_of(player):
		if board.distance(unit.coord, coord) == 1:
			adjacent = true
			break
	if not adjacent:
		return {"ok": false, "reason": "баррикада ставится только рядом со своей фигурой"}
	return {"ok": true, "reason": ""}


func place_barricade(player: int, coord: Vector2i) -> Dictionary:
	var verdict := can_place_barricade(player, coord)
	if not verdict["ok"]:
		return verdict
	spend_barricade(player)
	board.set_terrain(coord, Board.TERRAIN_BARRICADE)
	return {"ok": true, "reason": "баррикада поставлена"}


## Баррикада уничтожается атакой любой силы (без броска и очков).
func can_attack_barricade(attacker: Unit, coord: Vector2i) -> Dictionary:
	if board.terrain_at(coord) != Board.TERRAIN_BARRICADE:
		return {"ok": false, "reason": "здесь нет баррикады"}
	if attacker.owner != current_player:
		return {"ok": false, "reason": "сейчас ход другого игрока"}
	if not attacker.activated:
		return {"ok": false, "reason": "фигура не активирована"}
	if not attacker.can_attack:
		return {"ok": false, "reason": "эта фигура не может атаковать"}
	if attacker.attacked:
		return {"ok": false, "reason": "эта фигура уже атаковала"}
	if board.distance(attacker.coord, coord) != 1:
		return {"ok": false, "reason": "атака только по соседней клетке"}
	return {"ok": true, "reason": ""}


func attack_barricade(attacker: Unit, coord: Vector2i) -> Dictionary:
	var verdict := can_attack_barricade(attacker, coord)
	if not verdict["ok"]:
		return {"destroyed": false, "reason": verdict["reason"]}
	attacker.attacked = true
	board.set_terrain(coord, Board.TERRAIN_GRASS)
	return {"destroyed": true, "reason": "баррикада разрушена"}


# --- Кокон возрождения заражённых --------------------------------------------

## Поставить кокон на соседнюю незанятую клетку от своей фигуры (патч 7).
func can_place_cocoon(player: int, coord: Vector2i) -> Dictionary:
	if cocoon.has(player):
		return {"ok": false, "reason": "кокон уже стоит"}
	if not board.has_cell(coord):
		return {"ok": false, "reason": "клетка за пределами поля"}
	if board.is_water(coord):
		return {"ok": false, "reason": "на воду кокон ставить нельзя"}
	if unit_at(coord) != null:
		return {"ok": false, "reason": "клетка занята фигурой"}
	if cocoon.values().has(coord):
		return {"ok": false, "reason": "клетка занята коконом"}
	var adjacent := false
	for unit in units_of(player):
		if board.distance(unit.coord, coord) == 1:
			adjacent = true
			break
	if not adjacent:
		return {"ok": false, "reason": "кокон ставится только рядом со своей фигурой"}
	return {"ok": true, "reason": ""}


func place_cocoon(player: int, coord: Vector2i) -> Dictionary:
	var verdict := can_place_cocoon(player, coord)
	if not verdict["ok"]:
		return verdict
	cocoon[player] = coord
	return {"ok": true, "reason": "кокон поставлен"}


func cocoon_of(player: int) -> Vector2i:
	return cocoon.get(player, Vector2i(-999999, -999999))


## Кокон уничтожается атакой любой силы (без броска и очков).
func can_attack_cocoon(attacker: Unit, coord: Vector2i) -> Dictionary:
	if not cocoon.values().has(coord):
		return {"ok": false, "reason": "здесь нет кокона"}
	if attacker.owner != current_player:
		return {"ok": false, "reason": "сейчас ход другого игрока"}
	if not attacker.activated:
		return {"ok": false, "reason": "фигура не активирована"}
	if not attacker.can_attack:
		return {"ok": false, "reason": "эта фигура не может атаковать"}
	if attacker.attacked:
		return {"ok": false, "reason": "эта фигура уже атаковала"}
	if board.distance(attacker.coord, coord) != 1:
		return {"ok": false, "reason": "атака только по соседней клетке"}
	return {"ok": true, "reason": ""}


func attack_cocoon(attacker: Unit, coord: Vector2i) -> Dictionary:
	var verdict := can_attack_cocoon(attacker, coord)
	if not verdict["ok"]:
		return {"destroyed": false, "reason": verdict["reason"]}
	attacker.attacked = true
	for player in cocoon.keys():
		if cocoon[player] == coord:
			cocoon.erase(player)
			break
	return {"destroyed": true, "reason": "кокон разрушен"}


# --- Магический щит Эфиральда ------------------------------------------------

func start_shield(player: int) -> void:
	shield[player] = 3


func shield_of(player: int) -> int:
	return int(shield.get(player, 0))


func spend_shield(player: int) -> bool:
	if shield_of(player) < 1:
		return false
	shield[player] = shield_of(player) - 1
	return true


func use_shield(player: int, unit: Unit) -> Dictionary:
	if shield_of(player) < 1:
		return {"ok": false, "reason": "нет магических щитов"}
	if unit.shield:
		return {"ok": false, "reason": "щит уже поднят на этой фигуре"}
	spend_shield(player)
	unit.shield = true
	return {"ok": true, "reason": "щит поднят (+2 к броне для следующей защиты)"}


## +ресурс за уничтоженного противника — по фракции убийцы.
func _gain_kill_resource(player: int) -> void:
	match str(factions.get(player, "")):
		"undead":
			add_essence(player, ESSENCE_PER_KILL)
		"infected":
			add_biomass(player, BIOMASS_PER_KILL)


# --- Каркас «Атака ИЛИ Действие» и заклинания Некроманта (ADR-012) ------------

## Есть ли у фигуры особое действие. Пока — заклинание Некроманта (cast_spell),
## дальше сюда добавятся действия других фигур.
func has_action(unit: Unit) -> bool:
	return unit.abilities.has("cast_spell") or unit.abilities.has("heart_of_elements") or unit.abilities.has("ice_lance")


## Общая проверка «фигура может действовать»: активирована, ход её игрока,
## ещё не атаковала и не действовала. Атака и действие исключают друг друга.
func can_act(unit: Unit) -> Dictionary:
	if unit.owner != current_player:
		return {"ok": false, "reason": "сейчас ход другого игрока"}
	if not unit.activated:
		return {"ok": false, "reason": "фигура не активирована: она может только двигаться"}
	if not has_action(unit):
		return {"ok": false, "reason": "у фигуры нет действия"}
	if unit.attacked and not unit.abilities.has("heart_of_elements"):
		return {"ok": false, "reason": "фигура уже атаковала"}
	if unit.acted:
		return {"ok": false, "reason": "фигура уже действовала"}
	return {"ok": true, "reason": ""}


## Архимаг: возродить погибшего элементаля на соседней клетке (патч 7).
func can_resurrect_elemental(unit: Unit, at: Vector2i) -> Dictionary:
	if not unit.abilities.has("heart_of_elements"):
		return {"ok": false, "reason": "действие только для Архимага"}
	var verdict := can_act(unit)
	if not verdict["ok"]:
		return verdict
	var target: Unit = null
	for g in graveyard:
		if g.owner == unit.owner and g.elemental:
			target = g
			break
	if target == null:
		return {"ok": false, "reason": "нет погибших элементалей"}
	if not board.has_cell(at):
		return {"ok": false, "reason": "клетка за пределами поля"}
	if board.distance(unit.coord, at) != 1:
		return {"ok": false, "reason": "возрождение только на соседнюю клетку"}
	if not board.is_passable(at):
		return {"ok": false, "reason": "клетка непроходима"}
	if unit_at(at) != null:
		return {"ok": false, "reason": "клетка занята"}
	return {"ok": true, "reason": ""}


func resurrect_elemental(unit: Unit, at: Vector2i) -> Dictionary:
	var verdict := can_resurrect_elemental(unit, at)
	if not verdict["ok"]:
		return verdict
	var target: Unit = null
	for g in graveyard:
		if g.owner == unit.owner and g.elemental:
			target = g
			break
	graveyard.erase(target)
	target.coord = at
	target.reset_turn_state()
	target.wounded = false
	target.no_wound = true
	units.append(target)
	unit.acted = true
	return {"ok": true, "reason": "%s возрождён" % target.name_ru}


## Погибшие фигуры игрока — кандидаты на воскрешение.
func graveyard_of(player: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in graveyard:
		if unit.owner == player:
			result.append(unit)
	return result


## Зарегистрировать призываемых фигур (id -> данные). Зовётся при расстановке.
func register_summonables(player: int, defs: Dictionary) -> void:
	summon_defs[player] = defs


## Зарегистрировать слияния Эфиральда (id -> данные).
func register_fusions(player: int, defs: Dictionary) -> void:
	fusion_defs[player] = defs


## Цена призыва/воскрешения по классу: пешка 2, командир 3. Король — нельзя
## (проверяется раньше).
func _spell_cost(kind: String) -> int:
	return ESSENCE_SUMMON_PAWN if kind == "pawn" else ESSENCE_SUMMON_COMMANDER


## Допустима ли клетка для призыва/воскрешения: соседняя с заклинателем, в поле,
## проходима и свободна.
func _valid_spawn_cell(caster: Unit, at: Vector2i) -> Dictionary:
	if not board.has_cell(at):
		return {"ok": false, "reason": "клетка за пределами поля"}
	if board.distance(caster.coord, at) != 1:
		return {"ok": false, "reason": "призыв только на соседнюю клетку"}
	if not board.is_passable(at):
		return {"ok": false, "reason": "клетка непроходима"}
	if unit_at(at) != null:
		return {"ok": false, "reason": "клетка занята"}
	return {"ok": true, "reason": ""}


## Призыв существа (патч 7): 2 эссенции — пешка, 3 — командир, на соседнюю клетку.
func can_summon(caster: Unit, unit_id: String, at: Vector2i) -> Dictionary:
	var verdict := can_act(caster)
	if not verdict["ok"]:
		return verdict
	var defs: Dictionary = summon_defs.get(caster.owner, {})
	if not defs.has(unit_id):
		return {"ok": false, "reason": "нет такой призываемой фигуры: %s" % unit_id}
	var kind := str(defs[unit_id].get("kind", "pawn"))
	if kind == "king":
		return {"ok": false, "reason": "короля призвать нельзя"}
	var cost := _spell_cost(kind)
	if essence_of(caster.owner) < cost:
		return {"ok": false, "reason": "не хватает эссенции: нужно %d, есть %d" % [cost, essence_of(caster.owner)]}
	return _valid_spawn_cell(caster, at)


func summon(caster: Unit, unit_id: String, at: Vector2i) -> Dictionary:
	var verdict := can_summon(caster, unit_id, at)
	if not verdict["ok"]:
		return verdict
	var def: Dictionary = summon_defs[caster.owner][unit_id]
	var cost := _spell_cost(str(def.get("kind", "pawn")))
	spend_essence(caster.owner, cost)
	var unit := add_unit_from_data(caster.owner, at, def)
	unit.no_wound = true
	caster.acted = true
	return {"ok": true, "reason": "%s призван на поле (эссенции: %d)" % [str(def.get("name", unit_id)), cost]}


## Воскрешение уничтоженной пешки/командира (патч 7): 2/3 эссенции, на соседнюю
## клетку, раненым. Короля воскресить нельзя.
func can_resurrect(caster: Unit, target: Unit, at: Vector2i) -> Dictionary:
	var verdict := can_act(caster)
	if not verdict["ok"]:
		return verdict
	if target == null or not graveyard.has(target):
		return {"ok": false, "reason": "нет такой погибшей фигуры"}
	if target.owner != caster.owner:
		return {"ok": false, "reason": "воскрешать можно только свою фигуру"}
	if target.kind == "king":
		return {"ok": false, "reason": "короля воскресить нельзя"}
	var cost := _spell_cost(target.kind)
	if essence_of(caster.owner) < cost:
		return {"ok": false, "reason": "не хватает эссенции: нужно %d, есть %d" % [cost, essence_of(caster.owner)]}
	return _valid_spawn_cell(caster, at)


func resurrect(caster: Unit, target: Unit, at: Vector2i) -> Dictionary:
	var verdict := can_resurrect(caster, target, at)
	if not verdict["ok"]:
		return verdict
	var cost := _spell_cost(target.kind)
	spend_essence(caster.owner, cost)
	graveyard.erase(target)
	target.coord = at
	target.reset_turn_state()
	target.wounded = true
	target.no_wound = false
	units.append(target)
	caster.acted = true
	return {"ok": true, "reason": "%s воскрешён раненым (эссенции: %d)" % [target.name_ru, cost]}


## Уничтожение заклинанием (патч 7): 4 эссенции — любая чужая пешка/командир.
## Эссенция за это убийство не начисляется; победное очко — начисляется.
func can_slay(caster: Unit, target: Unit) -> Dictionary:
	var verdict := can_act(caster)
	if not verdict["ok"]:
		return verdict
	if target == null or not units.has(target):
		return {"ok": false, "reason": "нет такой фигуры на поле"}
	if target.owner == caster.owner:
		return {"ok": false, "reason": "своих заклинанием не уничтожают"}
	if target.kind == "king":
		return {"ok": false, "reason": "короля уничтожить заклинанием нельзя"}
	if essence_of(caster.owner) < ESSENCE_SLAY:
		return {"ok": false, "reason": "не хватает эссенции: нужно %d, есть %d" % [ESSENCE_SLAY, essence_of(caster.owner)]}
	return {"ok": true, "reason": ""}


func slay(caster: Unit, target: Unit) -> Dictionary:
	var verdict := can_slay(caster, target)
	if not verdict["ok"]:
		return verdict
	spend_essence(caster.owner, ESSENCE_SLAY)
	var owner_id := caster.owner
	var name_ru := target.name_ru
	_remove(target)
	_add_score(owner_id, 1)
	caster.acted = true
	return {"ok": true, "reason": "заклинание уничтожило %s" % name_ru}


func attackable_targets(unit: Unit, extra_range: int = 0) -> Array[Unit]:
	var result: Array[Unit] = []
	if unit.owner != current_player or unit.attacked or unit.acted or not unit.activated:
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
	extra_activations[current_player] = 0
	points_collected_last = collect_points(current_player)


func end_turn() -> void:
	if bool(urn_active.get(current_player, false)):
		essence[current_player] = int(essence_before_urn.get(current_player, 0))
		urn_active[current_player] = false
	pending_attack.clear()
	current_player = (current_player % player_count) + 1
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


## Итог партии для экрана победы: строки статистики (очки, живые, могила).
func victory_summary() -> Array[String]:
	var lines: Array[String] = []
	if winner != 0:
		lines.append("Победил игрок %d!" % winner)
	for player in scores.keys():
		var alive := units_of(player).size()
		var dead := 0
		for g in graveyard:
			if g.owner == player:
				dead += 1
		lines.append("Игрок %d: %d очков, %d живых, %d в могиле" % [player, int(scores[player]), alive, dead])
	return lines


## Автосохранение (каркас): сбрасывает ключевое состояние партии в файл.
## Полный сброс (террейн, ресурсы, коконы) — отдельным шагом.
func save_state(path: String) -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "current_player", current_player)
	cf.set_value("game", "turn_number", turn_number)
	cf.set_value("game", "round_number", round_number)
	cf.set_value("game", "is_day", is_day)
	cf.set_value("game", "winner", winner)
	cf.set_value("game", "scores", scores)
	var unit_list: Array = []
	for u in units:
		unit_list.append({"owner": u.owner, "q": u.coord.x, "r": u.coord.y,
			"id": u.unit_id, "kind": u.kind, "wounded": u.wounded})
	cf.set_value("game", "units", unit_list)
	cf.save(path)
