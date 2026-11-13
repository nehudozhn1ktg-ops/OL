extends RefCounted
class_name GameConfig

## Выбор фракций из стартового меню. Значения по умолчанию — демо-партия,
## которую видно и в отладочном снимке (`-- --shot`).

static var factions: Dictionary = {1: "infected", 2: "undead"}


static func path_for(player: int) -> String:
	return "res://data/factions/%s.json" % str(factions.get(player, "undead"))


static func id_for(player: int) -> String:
	return str(factions.get(player, "undead"))
