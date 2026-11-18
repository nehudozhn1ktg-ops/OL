extends RefCounted
class_name Board

## Поле и правила проходимости — чистая логика, без сцен и отрисовки.
## Всё, что здесь есть, проверяется headless-тестами в tests/.
##
## Источник истины — docs/canon и docs/memory/decisions.md (ADR-001: вода
## непроходима, встать на неё и толкнуть в неё нельзя без water-walk).

const TERRAIN_GRASS := 0
const TERRAIN_WATER := 1
const TERRAIN_FOREST := 2
const TERRAIN_FORT := 3
const TERRAIN_KEY := 4
const TERRAIN_FLAG := 5
const TERRAIN_CAMP := 6

const TERRAIN_LAND := TERRAIN_GRASS

const TERRAIN_NAMES := {
	"grass": TERRAIN_GRASS, "water": TERRAIN_WATER, "forest": TERRAIN_FOREST,
	"fort": TERRAIN_FORT, "key": TERRAIN_KEY, "flag": TERRAIN_FLAG, "camp": TERRAIN_CAMP,
}

## Шесть направлений для flat-top гексов (аксиальные координаты).
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## coord (Vector2i) -> террейн (int)
var cells: Dictionary = {}


## Круглое поле радиуса radius. water — список водных клеток.
func build_disk(radius: int, water: Array[Vector2i] = []) -> void:
	cells.clear()
	for coord in within_radius(Vector2i.ZERO, radius):
		cells[coord] = TERRAIN_WATER if water.has(coord) else TERRAIN_LAND


func set_terrain(coord: Vector2i, terrain: int) -> void:
	cells[coord] = terrain


## Загружает раскладку, снятую с картинки (assets/maps/data/*.json).
func load_map(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("не открыть карту: %s" % path)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed.has("cells"):
		push_error("плохой json карты: %s" % path)
		return false
	cells.clear()
	for item in parsed["cells"]:
		var name := String(item["t"])
		if not TERRAIN_NAMES.has(name):
			continue
		cells[Vector2i(int(item["q"]), int(item["r"]))] = TERRAIN_NAMES[name]
	return true


func has_cell(coord: Vector2i) -> bool:
	return cells.has(coord)


## -1, если клетки нет.
func terrain_at(coord: Vector2i) -> int:
	return cells.get(coord, -1)


func is_water(coord: Vector2i) -> bool:
	return terrain_at(coord) == TERRAIN_WATER


## ADR-001: на воду нельзя встать без способности ходить по воде.
## Клетки вне поля тоже непроходимы.
func is_passable(coord: Vector2i, traits: Dictionary = {}) -> bool:
	if not cells.has(coord):
		return false
	if cells[coord] == TERRAIN_FLAG:
		return false  # канон: флаг — физическое препятствие, сквозь него нельзя
	if cells[coord] == TERRAIN_WATER:
		return bool(traits.get("water_walk", false))
	return true


## ADR-001: толкнуть фигуру в воду нельзя даже фигурой с water_walk.
func can_push_into(coord: Vector2i) -> bool:
	if not cells.has(coord):
		return false
	return cells[coord] != TERRAIN_WATER


func neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in DIRECTIONS:
		result.append(coord + direction)
	return result


## Расстояние в гексах (кубическая метрика) — как Hex.Distance.
func distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	var ds: int = (-a.x - a.y) - (-b.x - b.y)
	return (absi(dq) + absi(dr) + absi(ds)) / 2


## Все клетки в радиусе N, включая центр (3r^2 + 3r + 1 штук).
func within_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		var r_min: int = maxi(-radius, -q - radius)
		var r_max: int = mini(radius, -q + radius)
		for r in range(r_min, r_max + 1):
			result.append(center + Vector2i(q, r))
	return result


## Клетки, достижимые из from за steps шагов (BFS по проходимости).
## Фигуры и их блокировки здесь не учитываются — это следующий слой.
func reachable(from: Vector2i, steps: int, traits: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not cells.has(from):
		return result
	var seen: Dictionary = {from: 0}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var dist: int = seen[current]
		if dist >= steps:
			continue
		for next in neighbors(current):
			if seen.has(next) or not is_passable(next, traits):
				continue
			seen[next] = dist + 1
			queue.append(next)
			result.append(next)
	return result


## Клетки для расстановки отряда («лагерь»): сначала соседи якоря (флага),
## затем ближайшие свободные проходимые клетки — если сосед непроходим или вне
## поля. Порядок детерминированный (BFS по расстоянию); случайность задаёт
## вызывающий (перемешиванием отряда). Флаг и вода исключаются.
func deployment_cells(anchor: Vector2i, count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not cells.has(anchor):
		return result
	var seen: Dictionary = {anchor: true}
	var queue: Array = [anchor]
	while not queue.is_empty() and result.size() < count:
		var current: Vector2i = queue.pop_front()
		for next in neighbors(current):
			if result.size() >= count:
				return result
			if seen.has(next) or not cells.has(next):
				continue
			seen[next] = true
			queue.append(next)
			if cells[next] == TERRAIN_FLAG or not is_passable(next):
				continue
			result.append(next)
	return result
