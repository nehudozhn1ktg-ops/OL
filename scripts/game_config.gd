extends RefCounted
class_name GameConfig

## Выбор фракций из стартового меню. Значения по умолчанию — демо-партия,
## которую видно и в отладочном снимке (`-- --shot`).

static var factions: Dictionary = {1: "infected", 2: "undead", 3: "people", 4: "elves"}

## Онлайн-режим (NET-001): true — клиент играет по сети, false — локально.
static var online: bool = false
static var server_url: String = "ws://127.0.0.1:8125/"
## Сетевой клиент, созданный в меню и переданный игровой сцене.
static var client: GameClient = null


static func player_count() -> int:
	return factions.size()


static func path_for(player: int) -> String:
	return "res://data/factions/%s.json" % str(factions.get(player, "undead"))


static func id_for(player: int) -> String:
	return str(factions.get(player, "undead"))
