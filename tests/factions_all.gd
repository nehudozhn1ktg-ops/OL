extends SceneTree

## Общая проверка всех фракционных листов: структура, диапазоны, единственный
## король в отряде. Ловит порчу данных, когда фракций станет много.
## Запуск: godot --headless --path . --script res://tests/factions_all.gd

var failures: int = 0
var checks: int = 0
const DIR := "res://data/factions"
const KINDS := ["king", "commander", "pawn"]


func _init() -> void:
	var files := _json_files()
	print("Листов найдено: %d -> %s" % [files.size(), ", ".join(files)])
	for file in files:
		_check_faction(file)
	print("")
	print("РЕЗУЛЬТАТ: %d проверок, провалов %d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _json_files() -> Array:
	var result: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".json"):
			result.append(DIR + "/" + name)
		name = dir.get_next()
	result.sort()
	return result


func _check(name: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		print("  OK   %s" % name)
	else:
		failures += 1
		print("  FAIL %s %s" % [name, detail])


func _check_faction(path: String) -> void:
	print("--- %s" % path.get_file())
	var faction := FactionData.load_file(path)
	_check("читается", not faction.is_empty())
	if faction.is_empty():
		return
	_check("есть id", String(faction.get("id", "")) != "")
	_check("есть название", String(faction.get("name", "")) != "")
	_check("описан ресурс", faction.has("resource"))
	_check("описано особое действие", faction.has("special_action"))

	var units: Array = faction.get("units", [])
	_check("фигуры есть", units.size() > 0, "%d" % units.size())
	_check("отряд собирается из 6", FactionData.roster(faction, 6).size() == 6)

	var ids := {}
	var kings := 0
	for data in units:
		var unit_id := String(data.get("id", ""))
		_check("у фигуры есть id", unit_id != "")
		_check("id не повторяется у %s" % unit_id, not ids.has(unit_id))
		ids[unit_id] = true
		_check("у %s есть название" % unit_id, String(data.get("name", "")) != "")
		var kind := String(data.get("kind", ""))
		_check("класс %s из списка" % unit_id, KINDS.has(kind), "= %s" % kind)
		if kind == "king":
			kings += 1
		_check("урон %s — число" % unit_id, int(data.get("damage", -99)) >= 0)
		_check("движение %s > 0" % unit_id, int(data.get("move", 0)) > 0)
		_check("броня %s — число" % unit_id, int(data.get("armor", -99)) >= 0)
		_check("у %s есть текст" % unit_id, String(data.get("text", "")) != "")
		_check("способности %s — массив" % unit_id, data.get("abilities", null) is Array)
	_check("ровно один король в отряде", kings == 1, "королей: %d" % kings)
