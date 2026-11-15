extends SceneTree

## Проверка фракционного листа: файл читается, числа совпадают с картами.
## Запуск: godot --headless --path . --script res://tests/faction_data.gd

var failures: int = 0
var checks: int = 0
const PATH := "res://data/factions/undead.json"


func _init() -> void:
	_test_load()
	_test_units()
	_test_errors()
	_test_summonables()

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


func _test_load() -> void:
	print("Загрузка листа")
	var faction := FactionData.load_file(PATH)
	_check("файл читается", not faction.is_empty())
	_check("id фракции", faction.get("id", "") == "undead")
	_check("название", faction.get("name", "") == "Нежить")
	_check("шесть фигур в отряде", FactionData.roster(faction, 6).size() == 6,
		"получили %d" % FactionData.roster(faction, 6).size())
	_check("roster(3) возвращает 3", FactionData.roster(faction, 3).size() == 3)
	_check("ресурс описан", faction["resource"]["name"] == "Эссенция")
	_check("особое действие описано", faction["special_action"]["name"] == "Урна душ")


func _test_units() -> void:
	print("Фигуры")
	var faction := FactionData.load_file(PATH)
	var by_id := {}
	for data in FactionData.unit_defs(faction):
		by_id[data["id"]] = data

	var king: Dictionary = by_id.get("skeleton_king", {})
	_check("король есть", not king.is_empty())
	_check("король: урон 3", int(king.get("damage", -1)) == 3)
	_check("король: движение 3", int(king.get("move", -1)) == 3)
	_check("король: броня 3", int(king.get("armor", -1)) == 3)
	_check("по значку карты — командир (шлем)", king.get("kind", "") == "commander")

	var necro: Dictionary = by_id.get("necromancer", {})
	_check("некромант по значку — король (корона)", necro.get("kind", "") == "king")
	_check("в листе десять фигур", FactionData.unit_defs(faction).size() == 10,
		"получили %d" % FactionData.unit_defs(faction).size())

	var bodyguard: Dictionary = by_id.get("bodyguard", {})
	_check("телохранитель не атакует", bodyguard.get("can_attack", true) == false)
	_check("телохранитель: броня 3", int(bodyguard.get("armor", -1)) == 3)

	var reaper: Dictionary = by_id.get("reaper", {})
	_check("жнец: урон 2", int(reaper.get("damage", -1)) == 2)
	_check("жнец: движение 3", int(reaper.get("move", -1)) == 3)
	_check("жнец наносит ранение, а не 3 урона", reaper.get("text", "").contains("ранение"))
	_check("у жнеца нет выдуманного «3 урона»", not reaper.get("text", "").contains("3 урона"))

	var succubus: Dictionary = by_id.get("succubus", {})
	_check("суккуб не атакует", succubus.get("can_attack", true) == false)
	var miner: Dictionary = by_id.get("miner", {})
	_check("шахтёр не атакует", miner.get("can_attack", true) == false)
	_check("котелок перенесён", by_id.has("kettle"))

	var baron: Dictionary = by_id.get("baron", {})
	_check("барон: движение 4", int(baron.get("move", -1)) == 4)

	var unit := Unit.from_data(1, Vector2i(0, 0), king)
	_check("из данных собирается фигура", unit.name_ru == "Король скелетов")
	_check("у фигуры урон из данных", unit.damage == 3)
	_check("способность перенесена", unit.abilities.has("essence_on_kill"))

	var guard := Unit.from_data(2, Vector2i(1, 0), bodyguard)
	_check("запрет атаки перенесён", guard.can_attack == false)


func _test_errors() -> void:
	print("Ошибки загрузки")
	var missing := FactionData.load_file("res://data/factions/нет-такого.json")
	_check("нет файла — пустой словарь", missing.is_empty())


func _test_summonables() -> void:
	print("Стартовый отряд и призываемые (ADR-009)")
	var faction := FactionData.load_file(PATH)
	var roster := FactionData.roster(faction, 6)
	var summonable := FactionData.summonables(faction)
	_check("призываемых четыре", summonable.size() == 4, "= %d" % summonable.size())
	var roster_ids := {}
	for data in roster:
		roster_ids[data["id"]] = true
	for unit_id in summonable.keys():
		_check("%s не в стартовом отряде" % unit_id, not roster_ids.has(unit_id))
	_check("стартовый отряд без Кровавого голема", not roster_ids.has("blood_golem"))
	_check("стартовый отряд без Телохранителя", not roster_ids.has("bodyguard"))
	_check("стартовый отряд с Котелком", roster_ids.has("kettle"))
	_check("стартовый отряд с Похитительницей снов", roster_ids.has("dream_thief"))
