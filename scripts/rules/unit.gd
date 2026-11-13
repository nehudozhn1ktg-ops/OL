extends RefCounted
class_name Unit

## Фигура. Числа из карты персонажа: урон, передвижение, броня.
## Одна жизнь: второе ранение — гибель.

var owner: int
var coord: Vector2i
var name_ru: String = ""
var kind: String = "pawn"      # king / commander / pawn
var move: int = 2
var damage: int = 0            # бонус к урону (прибавляется к D4)
var armor: int = 0             # бонус к защите (прибавляется к D4)
var range: int = 1             # дальность атаки в клетках; 1 — только соседняя
var can_attack: bool = true
var water_walk: bool = false
var abilities: Array[String] = []
## Текст способности с карты персонажа — для подсказки в интерфейсе.
var ability_text: String = ""

var wounded: bool = false

# Состояние в рамках текущего хода игрока
var activated: bool = false
var moved: bool = false
var attacked: bool = false


func _init(owner_id: int, at: Vector2i, can_walk_water: bool = false) -> void:
	owner = owner_id
	coord = at
	water_walk = can_walk_water


## Собрать фигуру из записи фракционного листа.
static func from_data(owner_id: int, at: Vector2i, data: Dictionary) -> Unit:
	var unit := Unit.new(owner_id, at, bool(data.get("water_walk", false)))
	unit.name_ru = str(data.get("name", ""))
	unit.kind = str(data.get("kind", "pawn"))
	unit.move = int(data.get("move", 2))
	unit.damage = int(data.get("damage", 0))
	unit.armor = int(data.get("armor", 0))
	unit.range = int(data.get("range", 1))
	unit.can_attack = bool(data.get("can_attack", true))
	unit.ability_text = str(data.get("text", ""))
	for ability in data.get("abilities", []):
		unit.abilities.append(str(ability))
	return unit


func traits() -> Dictionary:
	return {"water_walk": water_walk}


func is_king() -> bool:
	return kind == "king"


func configure(kind_name: String, move_value: int, damage_bonus: int, armor_bonus: int) -> Unit:
	kind = kind_name
	move = move_value
	damage = damage_bonus
	armor = armor_bonus
	return self


func with_ability(ability: String) -> Unit:
	abilities.append(ability)
	return self


func reset_turn_state() -> void:
	activated = false
	moved = false
	attacked = false
