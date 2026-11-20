extends RefCounted
class_name GameConfig

## Выбор фракций из стартового меню. Значения по умолчанию — демо-партия,
## которую видно и в отладочном снимке (`-- --shot`).

static var factions: Dictionary = {1: "infected", 2: "undead", 3: "people", 4: "elves"}


static func player_count() -> int:
	return factions.size()


static func path_for(player: int) -> String:
	return "res://data/factions/%s.json" % str(factions.get(player, "undead"))


static func id_for(player: int) -> String:
	return str(factions.get(player, "undead"))
