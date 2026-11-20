class_name MatchSetup
extends RefCounted

## Общая расстановка матча — используется и клиентом, и сервером (NET-001).
## Ставит флаги и отряды из карты и фракций. Чистая логика, без сцен.

const MAP_PATH := "res://assets/maps/data/4ffa.json"
const FACTIONS := ["infected", "undead", "people", "elves"]


## Клетки-флаги карты в детерминированном порядке.
static func flags(board: Board) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord in board.cells.keys():
		if board.terrain_at(coord) == Board.TERRAIN_FLAG:
			result.append(coord)
	result.sort_custom(func(a, b): return a.x < b.x)
	return result


## Поставить флаги и отряды для игроков (factions: player -> id фракции).
## Возвращает faction_ids. Стартовые ресурсы по фракциям начисляются здесь же.
static func place(game: Game, board: Board, factions: Dictionary) -> Dictionary:
	var faction_ids: Dictionary = {}
	var flag_cells := flags(board)
	for player in factions.keys():
		var fid: String = str(factions[player])
		faction_ids[player] = fid
		var faction := FactionData.load_file("res://data/factions/%s.json" % fid)
		var roster := FactionData.roster(faction, 6)
		game.add_flag(player, flag_cells[int(player) - 1])
		game.place_roster(player, flag_cells[int(player) - 1], roster)
	game.factions = faction_ids.duplicate()
	for player in faction_ids.keys():
		if faction_ids[player] == "infected":
			game.start_biomass(player)
		elif faction_ids[player] == "undead":
			game.start_essence(player)
			game.register_summonables(player,
				FactionData.summonables(FactionData.load_file("res://data/factions/undead.json")))
		elif faction_ids[player] == "elves":
			game.start_energy(player)
	return faction_ids
