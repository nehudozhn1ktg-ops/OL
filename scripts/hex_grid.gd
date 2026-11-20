extends Node2D
class_name HexGrid

## Поле, фигуры и ввод. Правила не здесь: что можно — решают Board и Game.

signal status(text: String)
signal unit_selected_changed(unit: Unit)
signal unit_hovered_changed(unit: Unit)
signal action_changed(mode: String)
signal tile_hovered_changed(coord: Vector2i, has_hover: bool)
## Объявлена атака, и защитник может ответить биомассой (+1 броня) — пауза.
signal defense_requested(unit: Unit)

const SQRT3 := 1.7320508075688772
const MAP_PATH := "res://assets/maps/data/1x1x1.json"

const TERRAIN_FILL := {
	0: Color("#7d8f4a"),  # трава
	1: Color("#4f8fb5"),  # вода
	2: Color("#2f4a2a"),  # лес
	3: Color("#c9822f"),  # укрепление
	4: Color("#9b6fc4"),  # ключевая точка
	5: Color("#d8c34a"),  # флаг
	6: Color("#b3543a"),  # лагерь
}
## Тайлы из набора артов (assets/tiles). Пропорция flat-top: 2 : sqrt(3).
const TERRAIN_TEXTURE := {
	0: preload("res://assets/tiles/grass.png"),
	1: preload("res://assets/tiles/water.png"),
	2: preload("res://assets/tiles/forest.png"),
	3: preload("res://assets/tiles/fort.png"),
	4: preload("res://assets/tiles/key.png"),
	5: preload("res://assets/tiles/flag.png"),
	6: preload("res://assets/tiles/camp.png"),
}
const OWNER_COLOR := {1: Color("#4a7fd4"), 2: Color("#d4574a"), 3: Color("#4a9e57"), 4: Color("#b26fd4")}
const COLOR_BORDER := Color(0.0, 0.0, 0.0, 0.45)
const COLOR_HOVER := Color("#f0f0f0")
const COLOR_SELECTED := Color("#ffd447")
const COLOR_MOVE_HINT := Color("#ffffff")
const COLOR_ATTACK := Color("#ff6b5a")

@export var hex_size: float = 42.0
@export var map_radius: int = 3

var board: Board
var game: Game
var hovered: Vector2i = Vector2i.ZERO
var has_hover: bool = false
var selected_unit: Unit = null
var hovered_unit: Unit = null
var legal_cells: Array[Vector2i] = []
var attack_targets: Array[Unit] = []
## Что выбрано в панели действий: "", "move", "attack", "action".
var action_mode: String = ""
## Усиление атаки биомассой: {"damage": bool, "range": bool}.
var attack_boost: Dictionary = {"damage": false, "range": false}
## Усиление передвижения биомассой: 0..2 клетки.
var move_boost: int = 0
## Кто за какую фракцию играет: player -> id фракции.
var faction_ids: Dictionary = {}
## Открыта пауза «защитник может ответить биомассой» после объявления атаки.
var pending_defense: bool = false
## Сетевой режим (NET-001): клиент и выбранная клетка (без локального Unit).
var client: GameClient = null
var _net_selected: Vector2i = Vector2i(-999999, -999999)


func _ready() -> void:
	board = Board.new()
	if GameConfig.online and GameConfig.client != null:
		_setup_network()
	else:
		_setup_local()
	_fit_to_view()
	queue_redraw()


## Локальная партия: карта + локальный Game + отряды из меню.
func _setup_local() -> void:
	var map_path := MAP_PATH
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			map_path = "res://assets/maps/data/%s.json" % arg.substr(6)
	if not board.load_map(map_path):
		push_warning("карта не загрузилась, показываю тестовый круг")
		board.build_disk(map_radius)

	game = Game.new()
	game.setup(board, null, GameConfig.player_count())
	_place_demo_units()


## Онлайн-партия (NET-001): карту рисуем локально, фигуры и ход — с сервера.
func _setup_network() -> void:
	board.load_map(MatchSetup.MAP_PATH)
	client = GameConfig.client
	set_process(true)


func _process(_delta: float) -> void:
	if client != null:
		client.poll()
		queue_redraw()


## Отряды всех игроков из фракционных листов: по шесть фигур к своим флагам.
## Флаги берутся из карты (клетки TERRAIN_FLAG) и раздаются игрокам 1..N по
## детерминированному порядку (сортировка по q). Заражённые начинают с
## максимумом биомассы, нежить — со стартовой эссенцией и списком призываемых.
func _place_demo_units() -> void:
	var players := range(1, GameConfig.player_count() + 1)
	var rosters := {}
	var factions_data := {}
	for player in players:
		var faction := FactionData.load_file(GameConfig.path_for(player))
		faction_ids[player] = str(faction.get("id", ""))
		factions_data[player] = faction
		rosters[player] = FactionData.roster(faction, 6)

	var flags: Array[Vector2i] = []
	for coord in board.cells.keys():
		if board.terrain_at(coord) == Board.TERRAIN_FLAG:
			flags.append(coord)
	flags.sort_custom(func(a, b): return a.x < b.x)

	if flags.size() < players.size():
		push_warning("на карте флагов %d меньше, чем игроков %d — ставлю заглушки" % [flags.size(), players.size()])
		for player in players:
			game.add_unit(player, Vector2i((player - 1) * 2 - 2, 0), false)
		game.factions = faction_ids.duplicate()
		return

	for player in players:
		if rosters.get(player, []).is_empty():
			push_warning("фракция игрока %d не загрузилась — заглушка" % player)
			game.add_unit(player, flags[player - 1], false)
			continue
		game.add_flag(player, flags[player - 1])
		_place_team(player, flags[player - 1], rosters[player])

	game.factions = faction_ids.duplicate()
	for player in faction_ids.keys():
		if faction_ids[player] == "infected":
			game.start_biomass(player)
		elif faction_ids[player] == "undead":
			game.start_essence(player)
			game.register_summonables(player, FactionData.summonables(factions_data[player]))


func _place_team(player: int, anchor: Vector2i, roster: Array) -> void:
	game.place_roster(player, anchor, roster)


func _fit_to_view() -> void:
	if board.cells.is_empty():
		return
	var view := get_viewport_rect().size
	for _i in 4:
		var b := _pixel_bounds()
		var span: Vector2 = b[1] - b[0]
		if span.x <= 0.0 or span.y <= 0.0:
			break
		var k: float = minf(view.x * 0.88 / span.x, view.y * 0.86 / span.y)
		if absf(k - 1.0) < 0.005:
			break
		hex_size *= k
	var b := _pixel_bounds()
	var center: Vector2 = (b[0] + b[1]) * 0.5
	position = Vector2(view.x * 0.5, view.y * 0.54) - center


func _pixel_bounds() -> Array:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for coord in board.cells.keys():
		var p := hex_to_pixel(coord)
		mn = mn.min(p)
		mx = mx.max(p)
	return [mn - Vector2(hex_size, hex_size), mx + Vector2(hex_size, hex_size)]


func hex_to_pixel(coord: Vector2i) -> Vector2:
	return Vector2(
		hex_size * 1.5 * coord.x,
		hex_size * SQRT3 * (coord.y + coord.x * 0.5)
	)


func pixel_to_hex(point: Vector2) -> Vector2i:
	var fq: float = (2.0 / 3.0 * point.x) / hex_size
	var fr: float = (-1.0 / 3.0 * point.x + SQRT3 / 3.0 * point.y) / hex_size
	return _cube_round(fq, fr)


func _cube_round(fq: float, fr: float) -> Vector2i:
	var fs: float = -fq - fr
	var q: int = roundi(fq)
	var r: int = roundi(fr)
	var s: int = roundi(fs)
	var dq: float = absf(q - fq)
	var dr: float = absf(r - fr)
	var ds: float = absf(s - fs)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(q, r)


func _hex_corners(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle: float = deg_to_rad(60.0 * i)
		points.append(center + Vector2(cos(angle), sin(angle)) * hex_size)
	return points


func _fill_color(coord: Vector2i) -> Color:
	var terrain: int = board.terrain_at(coord)
	var base: Color = TERRAIN_FILL.get(terrain, Color("#666666"))
	if legal_cells.has(coord):
		return base.lerp(COLOR_MOVE_HINT, 0.4)
	return base


func _draw() -> void:
	for coord in board.cells.keys():
		var center := hex_to_pixel(coord)
		var texture: Texture2D = TERRAIN_TEXTURE.get(board.terrain_at(coord))
		if texture != null:
			draw_texture_rect(texture, _hex_rect(center), false)
		else:
			draw_colored_polygon(_hex_corners(center), _fill_color(coord))
		if legal_cells.has(coord):
			draw_colored_polygon(_hex_corners(center), Color(1.0, 1.0, 1.0, 0.28))

	if selected_unit != null and board.has_cell(selected_unit.coord):
		_draw_outline(selected_unit.coord, COLOR_SELECTED, 3.0)
	if client != null and board.has_cell(_net_selected):
		_draw_outline(_net_selected, COLOR_SELECTED, 3.0)
	if has_hover and board.has_cell(hovered):
		_draw_outline(hovered, COLOR_HOVER, 2.0)
	for target in attack_targets:
		if board.has_cell(target.coord):
			_draw_outline(target.coord, COLOR_ATTACK, 3.0)

	if client != null:
		for u in client.state.get("units", []):
			_draw_network_unit(u)
	else:
		for unit in game.units:
			_draw_unit(unit)


func _hex_rect(center: Vector2) -> Rect2:
	var half_width: float = hex_size
	var half_height: float = hex_size * SQRT3 * 0.5
	return Rect2(center - Vector2(half_width, half_height),
		Vector2(half_width * 2.0, half_height * 2.0))


func _draw_unit(unit: Unit) -> void:
	var center := hex_to_pixel(unit.coord)
	var color: Color = OWNER_COLOR.get(unit.owner, Color.WHITE)
	if unit.wounded:
		color = color.darkened(0.35)
	draw_circle(center, hex_size * 0.52, Color(0, 0, 0, 0.55))
	draw_circle(center, hex_size * 0.46, color)
	var ring := Color(1, 1, 1, 0.85)
	if unit.wounded:
		ring = Color("#ff8a4a")
	draw_arc(center, hex_size * 0.46, 0.0, TAU, 24, ring, 2.0, true)
	if unit.wounded:
		# отметка раны — косой крест
		var d: float = hex_size * 0.2
		draw_line(center - Vector2(d, d), center + Vector2(d, d), Color(1, 1, 1, 0.9), 2.0)
		draw_line(center + Vector2(d, -d), center - Vector2(d, -d), Color(1, 1, 1, 0.9), 2.0)


## Рисует фигуру из серверного state (словарь), а не из локального Unit.
func _draw_network_unit(u: Dictionary) -> void:
	var center := hex_to_pixel(Vector2i(int(u["q"]), int(u["r"])))
	var color: Color = OWNER_COLOR.get(int(u["owner"]), Color.WHITE)
	if bool(u.get("wounded", false)):
		color = color.darkened(0.35)
	draw_circle(center, hex_size * 0.52, Color(0, 0, 0, 0.55))
	draw_circle(center, hex_size * 0.46, color)
	var ring := Color("#ff8a4a") if bool(u.get("wounded", false)) else Color(1, 1, 1, 0.85)
	draw_arc(center, hex_size * 0.46, 0.0, TAU, 24, ring, 2.0, true)
	if bool(u.get("wounded", false)):
		var d: float = hex_size * 0.2
		draw_line(center - Vector2(d, d), center + Vector2(d, d), Color(1, 1, 1, 0.9), 2.0)
		draw_line(center + Vector2(d, -d), center - Vector2(d, -d), Color(1, 1, 1, 0.9), 2.0)


func _draw_outline(coord: Vector2i, color: Color, width: float) -> void:
	var points := _hex_corners(hex_to_pixel(coord))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, color, width, true)


## Выбрать фигуру: подсветки нет, пока игрок не выберет действие справа.
func select_unit(unit: Unit) -> void:
	selected_unit = unit
	action_mode = ""
	attack_boost = {"damage": false, "range": false}
	move_boost = 0
	legal_cells = []
	attack_targets = []
	queue_redraw()
	unit_selected_changed.emit(unit)
	unit_hovered_changed.emit(unit)
	status.emit("«%s» игрока %d — выберите действие справа" % [_unit_name(unit), unit.owner])


## Действие из панели: передвижение / атака / особое действие.
func choose_action(mode: String) -> void:
	if selected_unit == null:
		return
	match mode:
		"move":
			action_mode = "move"
			move_boost = 0
			legal_cells = game.reachable(selected_unit)
			attack_targets = []
			status.emit("Передвижение: клеток %d. Клик по клетке" % legal_cells.size())
		"attack":
			if not selected_unit.activated and not game.activate(selected_unit):
				status.emit(game.can_activate(selected_unit)["reason"])
				return
			action_mode = "attack"
			attack_targets = game.attackable_targets(selected_unit, _extra_range())
			legal_cells = []
			status.emit("Атака: целей %d. Клик по противнику" % attack_targets.size())
		_:
			action_mode = ""
			legal_cells = []
			attack_targets = []
	action_changed.emit(action_mode)
	queue_redraw()


func _unit_name(unit: Unit) -> String:
	return unit.name_ru if unit.name_ru != "" else "фигура"


## Дополнительная дальность от усиления биомассой.
func _extra_range() -> int:
	return 1 if bool(attack_boost.get("range", false)) else 0


## Усиление атаки биомассой — выбор игрока после нажатия «Атака»:
## 1 биомасса = +1 урон, 2 биомассы = +1 дальность.
func set_attack_boost(damage_up: bool, range_up: bool) -> void:
	attack_boost = {"damage": damage_up, "range": range_up}
	if action_mode != "attack" or selected_unit == null:
		return
	attack_targets = game.attackable_targets(selected_unit, _extra_range())
	var parts: Array[String] = []
	if damage_up:
		parts.append("+1 урон")
	if range_up:
		parts.append("+1 дальность")
	var label := "без усиления" if parts.is_empty() else ", ".join(parts)
	status.emit("Атака %s. Целей %d, биомассы %d" % [
		label, attack_targets.size(), game.biomass_of(game.current_player)])
	queue_redraw()


## Усиление передвижения биомассой: 1 биомасса = +1 клетка (на 1 или 2).
func set_move_boost(extra: int) -> void:
	move_boost = clampi(extra, 0, 2)
	if action_mode != "move" or selected_unit == null:
		return
	legal_cells = game.reachable(selected_unit, move_boost)
	var label := "без усиления" if move_boost == 0 else "+%d клетка" % move_boost
	status.emit("Передвижение %s: клеток %d, биомассы %d" % [
		label, legal_cells.size(), game.biomass_of(game.current_player)])
	queue_redraw()


## Ответ защитника на отложенную атаку: усилить броню биомассой или пропустить,
## затем выполнить бросок.
func choose_defense(boost: bool) -> void:
	if not pending_defense:
		return
	var defender := game.pending_defender()
	if boost and defender != null:
		var verdict := game.defend_with_biomass(defender)
		if not verdict["ok"]:
			status.emit(verdict["reason"])
			return
	pending_defense = false
	_finish_attack()


## Выполнить отложенный бросок и показать итог.
func _finish_attack() -> void:
	var blow := game.resolve_attack()
	var text := "Атака: урон %d против защиты %d. %s" % [
		blow["damage"], blow["defense"], blow["reason"]]
	_clear_selection()
	status.emit(text)


## Сетевой клик: выбрать свою фигуру, затем клик по клетке — сходить.
func _network_click(coord: Vector2i) -> void:
	for u in client.state.get("units", []):
		if int(u.get("owner", 0)) == client.seat and int(u["q"]) == coord.x and int(u["r"]) == coord.y:
			_net_selected = coord
			status.emit("Фигура выбрана — кликните по клетке, чтобы пойти.")
			queue_redraw()
			return
	if board.has_cell(_net_selected):
		client.intent("move", {"from": [_net_selected.x, _net_selected.y], "to": [coord.x, coord.y]})
		_net_selected = Vector2i(-999999, -999999)
		status.emit("Ход отправлен серверу.")
		queue_redraw()
		return
	status.emit("Клетка (%d, %d) · %s" % [coord.x, coord.y, terrain_name(board.terrain_at(coord))])


func _click(coord: Vector2i) -> void:
	if not board.has_cell(coord):
		return
	if client != null:
		_network_click(coord)
		return

	var clicked := game.unit_at(coord)
	if clicked != null and clicked.owner == game.current_player:
		select_unit(clicked)
		return

	if selected_unit != null and clicked != null and action_mode == "attack" and attack_targets.has(clicked):
		var decl := game.declare_attack(selected_unit, clicked,
			bool(attack_boost.get("damage", false)), bool(attack_boost.get("range", false)))
		if not decl["ok"]:
			status.emit(decl["reason"])
			return
		if decl["needs_defense"]:
			pending_defense = true
			action_mode = ""
			attack_targets.clear()
			legal_cells.clear()
			action_changed.emit("")
			status.emit("Атака объявлена. Защитник: «Броня +1» за биомассу или пропустить.")
			defense_requested.emit(clicked)
			queue_redraw()
			return
		_finish_attack()
		return

	if selected_unit != null and game.has_flag(coord) and game.flag_owner(coord) != game.current_player:
		var flag_verdict := game.can_attack_flag(selected_unit, coord)
		if not flag_verdict["ok"]:
			status.emit(flag_verdict["reason"])
			return
		var blow_flag := game.attack_flag(selected_unit, coord)
		_clear_selection()
		status.emit(blow_flag["reason"])
		return

	if selected_unit != null and action_mode == "move":
		var mover := selected_unit
		var verdict := game.move_with_biomass(mover, coord, move_boost)
		if not verdict["ok"]:
			status.emit(verdict["reason"])
			return
		action_mode = ""
		move_boost = 0
		legal_cells.clear()
		attack_targets.clear()
		queue_redraw()
		var note := _reaction_note()
		if not game.units.has(mover):
			_clear_selection()
			status.emit("Фигура погибла от реакции укрепления.%s" % note)
			return
		if mover.activated and not mover.attacked:
			status.emit("Фигура перешла. Можно атаковать соседнюю цель или нажать пробел%s" % note)
		else:
			_clear_selection()
			status.emit("Фигура перешла. Нажмите пробел, чтобы передать ход%s" % note)
		return

	if selected_unit != null and clicked != null:
		status.emit("Выберите действие справа: «атака», чтобы ударить по цели")
		return

	status.emit("Клетка (%d, %d) · %s" % [coord.x, coord.y, terrain_name(board.terrain_at(coord))])


func _clear_selection() -> void:
	selected_unit = null
	action_mode = ""
	attack_boost = {"damage": false, "range": false}
	move_boost = 0
	pending_defense = false
	legal_cells.clear()
	attack_targets.clear()
	queue_redraw()
	unit_selected_changed.emit(null)


## Подпись о реакции укрепления после перехода (ADR-002).
func _reaction_note() -> String:
	if game.last_fort_reactions.is_empty():
		return ""
	var parts: Array[String] = []
	for blow in game.last_fort_reactions:
		parts.append("урон %d против защиты %d (%s)" % [
			blow["damage"], blow["defense"], blow["reason"]])
	return " Реакция укрепления: " + "; ".join(parts) + "."


func terrain_name(terrain: int) -> String:
	match terrain:
		Board.TERRAIN_GRASS:
			return "трава"
		Board.TERRAIN_WATER:
			return "вода"
		Board.TERRAIN_FOREST:
			return "лес"
		Board.TERRAIN_FORT:
			return "укрепление"
		Board.TERRAIN_KEY:
			return "ключевая точка"
		Board.TERRAIN_FLAG:
			return "флаг"
		Board.TERRAIN_CAMP:
			return "лагерь"
		_:
			return "?"


## Человекочитаемый эффект террейна — для подсказки при наведении на клетку.
func terrain_effect(terrain: int) -> String:
	match terrain:
		Board.TERRAIN_FOREST:
			return "+1 к защите при атаке в упор."
		Board.TERRAIN_FORT:
			return "+1 к защите; стоящая здесь фигура бьёт каждого врага, остановившегося рядом."
		Board.TERRAIN_KEY:
			return "Ключевая точка: +1 очко за свою фигуру в начале хода."
		Board.TERRAIN_WATER:
			return "Непроходима (ADR-001)."
		Board.TERRAIN_FLAG:
			return "Препятствие; уничтожается броском 4 (король 3-4), +3 очка."
		Board.TERRAIN_CAMP:
			return "Лагерь: зона развёртывания."
		_:
			return ""


## Позиция гекса фигуры в экранных координатах — для плашки действий в HUD.
func figure_screen_pos(unit: Unit) -> Vector2:
	return to_global(hex_to_pixel(unit.coord))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var coord := pixel_to_hex(get_local_mouse_position())
		if board.has_cell(coord):
			if not has_hover or hovered != coord:
				hovered = coord
				has_hover = true
				queue_redraw()
				tile_hovered_changed.emit(hovered, true)
		elif has_hover:
			has_hover = false
			queue_redraw()
			tile_hovered_changed.emit(hovered, false)
		var under_cursor: Unit = null
		if board.has_cell(coord) and game != null:
			under_cursor = game.unit_at(coord)
		if under_cursor != hovered_unit:
			hovered_unit = under_cursor
			unit_hovered_changed.emit(under_cursor)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click(pixel_to_hex(get_local_mouse_position()))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_clear_selection()
			status.emit("Выбор снят")
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		end_turn()


## Передать ход: пробел или кнопка «Конец хода» в HUD (на мобильных пробела нет).
func end_turn() -> void:
	if client != null:
		client.intent("end_turn")
		_net_selected = Vector2i(-999999, -999999)
		status.emit("Ход передан (ждём сервер).")
		queue_redraw()
		return
	game.end_turn()
	_clear_selection()
	status.emit("Ход передан игроку %d (раунд %d)" % [game.current_player, game.round_number])
