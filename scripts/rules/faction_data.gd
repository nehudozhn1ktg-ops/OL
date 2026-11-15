extends RefCounted
class_name FactionData

## Загрузка фракционного листа из data/factions/*.json.
## Один файл — одна фракция: ресурс, особое действие, фигуры с числами.

static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("нет файла фракции: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("не открыть файл фракции: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed.has("units"):
		push_error("плохой json фракции: %s" % path)
		return {}
	return parsed


static func unit_defs(faction: Dictionary) -> Array:
	return faction.get("units", [])


## Готовый список для расстановки: первые count фигур отряда, без призываемых
## (ADR-009: призываемые не входят в стартовый отряд).
static func roster(faction: Dictionary, count: int = 6) -> Array:
	var result := []
	for data in unit_defs(faction):
		if bool(data.get("summonable", false)):
			continue
		if result.size() >= count:
			break
		result.append(data)
	return result


## Призываемые фигуры: id -> данные. Для заклинания Некроманта (ADR-012).
static func summonables(faction: Dictionary) -> Dictionary:
	var result := {}
	for data in unit_defs(faction):
		if bool(data.get("summonable", false)):
			result[str(data.get("id", ""))] = data
	return result
