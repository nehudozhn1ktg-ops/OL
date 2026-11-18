extends Control
class_name Hud

## Интерфейс партии.
##
## - Сверху — строка характеристик: актуальные значения (с учётом местности и
##   ауры) с разложением источника бонуса прямо в строке.
## - У выбранной фигуры (справа от неё) — плашка кнопок передвижение/атака/действие.
## - Подсказка при наведении: фигура + эффект террейна.

const ICON_DAMAGE := preload("res://assets/ui/damage.png")
const ICON_MOVE := preload("res://assets/ui/move.png")
const ICON_ARMOR := preload("res://assets/ui/armor.png")
const ICON_ACTION := preload("res://assets/ui/action.png")

const COLOR_TEXT := Color(0.94, 0.94, 0.92)
const COLOR_DIM := Color(0.72, 0.74, 0.78)
const COLOR_ACCENT := Color("#ffd447")

const ICON_SIZE := Vector2(56.0, 56.0)
const STAT_ICON_SIZE := Vector2(30.0, 30.0)

var grid: HexGrid = null
var selected: Unit = null
var hovered: Unit = null
var hovered_coord: Vector2i = Vector2i.ZERO
var has_tile_hover: bool = false

var _actions: PanelContainer
var _btn_move: TextureButton
var _btn_attack: TextureButton
var _btn_action: TextureButton
var _btn_armor: TextureButton
var _stats: PanelContainer
var _lbl_damage: Label
var _lbl_damage_src: Label
var _lbl_move: Label
var _lbl_armor: Label
var _lbl_armor_src: Label
var _lbl_resource: Label
var _tooltip: PanelContainer
var _lbl_tooltip: Label
var _boost_panel: PanelContainer
var _move_panel: PanelContainer
## Подсказка ходит за курсором; на снимке её ставят в заданную точку.
var _follow_mouse: bool = true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_actions()
	_build_stats()
	_build_boost()
	_build_move_boost()
	_build_tooltip()
	_refresh_resource()


func bind(grid_: HexGrid) -> void:
	grid = grid_
	grid.unit_selected_changed.connect(_on_selected_changed)
	grid.unit_hovered_changed.connect(_on_hovered_changed)
	grid.action_changed.connect(_on_action_changed)
	grid.tile_hovered_changed.connect(_on_tile_hovered_changed)


# --- Построение --------------------------------------------------------------

## Плашка кнопок — позиционируется справа от выбранной фигуры.
func _build_actions() -> void:
	_actions = PanelContainer.new()
	_actions.mouse_filter = Control.MOUSE_FILTER_STOP
	_actions.add_theme_stylebox_override("panel", _panel_style())
	add_child(_actions)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_actions.add_child(row)

	_btn_move = _make_button(ICON_MOVE, "Передвижение")
	_btn_move.pressed.connect(func(): _choose("move"))
	_btn_attack = _make_button(ICON_DAMAGE, "Атака")
	_btn_attack.pressed.connect(func(): _choose("attack"))
	_btn_action = _make_button(ICON_ACTION, "Действие")
	_btn_action.pressed.connect(func(): _choose("action"))
	_btn_armor = _make_button(ICON_ARMOR, "Броня +1 (биомасса)")
	_btn_armor.pressed.connect(func(): grid.boost_selected_armor())
	row.add_child(_btn_move)
	row.add_child(_btn_attack)
	row.add_child(_btn_action)
	row.add_child(_btn_armor)
	_actions.visible = false


## Строка характеристик сверху: актуальные значения + источник бонуса.
func _build_stats() -> void:
	_stats = PanelContainer.new()
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.anchor_left = 0.5
	_stats.anchor_right = 0.5
	_stats.anchor_top = 0.0
	_stats.anchor_bottom = 0.0
	_stats.offset_left = -330.0
	_stats.offset_right = 330.0
	_stats.offset_top = 12.0
	_stats.offset_bottom = 78.0
	_stats.add_theme_stylebox_override("panel", _panel_style())
	add_child(_stats)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	_stats.add_child(row)

	var damage := _stat_box(ICON_DAMAGE)
	_lbl_damage = damage[1]
	_lbl_damage_src = damage[2]
	row.add_child(damage[0])

	var move := _stat_box(ICON_MOVE)
	_lbl_move = move[1]
	row.add_child(move[0])

	var armor := _stat_box(ICON_ARMOR)
	_lbl_armor = armor[1]
	_lbl_armor_src = armor[2]
	row.add_child(armor[0])

	var sep := VSeparator.new()
	row.add_child(sep)

	_lbl_resource = Label.new()
	_lbl_resource.add_theme_font_size_override("font_size", 18)
	_lbl_resource.add_theme_color_override("font_color", COLOR_ACCENT)
	_lbl_resource.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_lbl_resource)
	_stats.visible = false


## Панель усиления атаки биомассой — всплывает под плашкой после «Атака».
func _build_boost() -> void:
	_boost_panel = PanelContainer.new()
	_boost_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_boost_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.10, 0.07, 0.09, 0.94)))
	add_child(_boost_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_boost_panel.add_child(column)

	var title := Label.new()
	title.text = "Биомасса в атаку"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	column.add_child(title)

	var boost_damage := _boost_button(column, "−1 биомасса: атака +1")
	boost_damage.pressed.connect(func(): grid.set_attack_boost(true, false))
	var boost_range := _boost_button(column, "−2 биомассы: +1 дальность")
	boost_range.pressed.connect(func(): grid.set_attack_boost(false, true))
	var plain := _boost_button(column, "обычная атака")
	plain.pressed.connect(func(): grid.set_attack_boost(false, false))
	_boost_panel.visible = false


func _boost_button(parent: VBoxContainer, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 15)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(button)
	return button


## Панель усиления передвижения биомассой — всплывает под плашкой после «Передвижение».
func _build_move_boost() -> void:
	_move_panel = PanelContainer.new()
	_move_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_move_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.10, 0.09, 0.94)))
	add_child(_move_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_move_panel.add_child(column)

	var title := Label.new()
	title.text = "Биомасса в движение"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	column.add_child(title)

	var plus_one := _boost_button(column, "−1 биомасса: +1 клетка")
	plus_one.pressed.connect(func(): grid.set_move_boost(1))
	var plus_two := _boost_button(column, "−2 биомассы: +2 клетки")
	plus_two.pressed.connect(func(): grid.set_move_boost(2))
	var plain := _boost_button(column, "обычное движение")
	plain.pressed.connect(func(): grid.set_move_boost(0))
	_move_panel.visible = false


func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_stylebox_override("panel", _panel_style(Color(0.09, 0.10, 0.13, 0.96)))
	_tooltip.custom_minimum_size = Vector2(260.0, 0.0)
	add_child(_tooltip)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_tooltip.add_child(margin)

	_lbl_tooltip = Label.new()
	_lbl_tooltip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_tooltip.custom_minimum_size = Vector2(240.0, 0.0)
	_lbl_tooltip.add_theme_font_size_override("font_size", 16)
	_lbl_tooltip.add_theme_color_override("font_color", COLOR_TEXT)
	margin.add_child(_lbl_tooltip)
	_tooltip.visible = false


func _panel_style(color: Color = Color(0.06, 0.07, 0.09, 0.88)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _make_button(texture: Texture2D, hint: String) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = texture
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.custom_minimum_size = ICON_SIZE
	button.tooltip_text = hint
	return button


## Пара «иконка + значение (и строка источника)» для строки характеристик.
func _stat_box(texture: Texture2D) -> Array:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = STAT_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -2)
	box.add_child(column)

	var main := Label.new()
	main.add_theme_font_size_override("font_size", 24)
	main.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(main)

	var source := Label.new()
	source.add_theme_font_size_override("font_size", 13)
	source.add_theme_color_override("font_color", COLOR_DIM)
	column.add_child(source)

	return [box, main, source]


# --- Реакция на события поля ------------------------------------------------

func _on_selected_changed(unit: Unit) -> void:
	selected = unit
	_boost_panel.visible = false
	_move_panel.visible = false
	_refresh_plaque(unit)
	_refresh_stats_display()


func _on_hovered_changed(unit: Unit) -> void:
	hovered = unit
	_follow_mouse = true
	_refresh_tooltip()
	_refresh_stats_display()


func _on_tile_hovered_changed(coord: Vector2i, has_hover: bool) -> void:
	hovered_coord = coord
	has_tile_hover = has_hover
	_refresh_tooltip()


func _on_action_changed(mode: String) -> void:
	if selected != null:
		_update_buttons(selected)
	_update_boost_visibility(mode)


func _is_infected() -> bool:
	if grid == null:
		return false
	return str(grid.faction_ids.get(grid.game.current_player, "")) == "infected"


func _update_boost_visibility(mode: String) -> void:
	var enough := grid != null and grid.game.biomass_of(grid.game.current_player) > 0
	_boost_panel.visible = mode == "attack" and _is_infected() and enough
	_move_panel.visible = mode == "move" and _is_infected() and enough
	if _boost_panel.visible or _move_panel.visible:
		_position_boost_panels()


# --- Плашка действий ---------------------------------------------------------

func _refresh_plaque(unit: Unit) -> void:
	if unit == null:
		_actions.visible = false
		return
	_update_buttons(unit)
	_actions.visible = true
	_actions.reset_size()
	_position_plaque(unit)


func _position_plaque(unit: Unit) -> void:
	var pos := grid.figure_screen_pos(unit)
	var view := get_viewport_rect().size
	var size := _actions.size
	var target := pos + Vector2(grid.hex_size + 12.0, -size.y * 0.5)
	target.x = clampf(target.x, 8.0, maxf(8.0, view.x - size.x - 8.0))
	target.y = clampf(target.y, 8.0, maxf(8.0, view.y - size.y - 8.0))
	_actions.position = target


## Панели биомассы всплывают под плашкой кнопок.
func _position_boost_panels() -> void:
	var base := _actions.position + Vector2(0.0, _actions.size.y + 8.0)
	var view := get_viewport_rect().size
	for panel: PanelContainer in [_boost_panel, _move_panel]:
		if not panel.visible:
			continue
		panel.reset_size()
		var size: Vector2 = panel.size
		panel.position = Vector2(
			clampf(base.x, 8.0, maxf(8.0, view.x - size.x - 8.0)),
			clampf(base.y, 8.0, maxf(8.0, view.y - size.y - 8.0)))


func _update_buttons(unit: Unit) -> void:
	_btn_move.disabled = unit.moved
	_btn_attack.disabled = unit.attacked or unit.acted or not unit.can_attack
	# «Действие» показываем только когда оно реализовано у фигуры (cast_spell).
	var has_action := grid.game.has_action(unit)
	_btn_action.visible = has_action
	_btn_action.disabled = unit.attacked or unit.acted
	# Усиление брони — только заражённым.
	_btn_armor.visible = _is_infected()


# --- Строка характеристик ----------------------------------------------------

func _refresh_stats_display() -> void:
	_refresh_stats(hovered if hovered != null else selected)


func _refresh_stats(unit: Unit) -> void:
	if unit == null:
		_stats.visible = false
		return
	_stats.visible = true
	var game: Game = grid.game
	var terrain := game.terrain_defense_bonus(unit, 1)
	var aura := game.aura_defense_bonus(unit)
	var armor_total := unit.armor + terrain + aura + unit.armor_boost

	_lbl_damage.text = "%d-%d" % [unit.damage + 1, unit.damage + 4]
	_lbl_damage_src.text = "(бонус %d)" % unit.damage
	_lbl_move.text = "%d" % unit.move

	_lbl_armor.text = "%d-%d" % [armor_total + 1, armor_total + 4]
	var parts: Array[String] = [str(unit.armor)]
	if terrain > 0:
		parts.append("%s %d" % [grid.terrain_name(game.board.terrain_at(unit.coord)), terrain])
	if aura > 0:
		parts.append("аура %d" % aura)
	if unit.armor_boost > 0:
		parts.append("усиление %d" % unit.armor_boost)
	_lbl_armor_src.text = "(%s)" % " + ".join(parts)


# --- Подсказка (тайл + фигура) -----------------------------------------------

func _refresh_tooltip() -> void:
	var lines: Array[String] = []
	if hovered != null:
		lines.append_array(_figure_lines(hovered))
		lines.append("")
	if has_tile_hover and grid.board.has_cell(hovered_coord):
		lines.append_array(_tile_lines(hovered_coord))
	if lines.is_empty():
		_tooltip.visible = false
		return
	_lbl_tooltip.text = "\n".join(lines)
	_tooltip.visible = true
	_tooltip.reset_size()


func _figure_lines(unit: Unit) -> Array[String]:
	var kind_name := {"king": "Король", "commander": "Командир", "pawn": "Пешка"}
	var title := unit.name_ru if unit.name_ru != "" else "Фигура"
	var lines: Array[String] = ["%s · %s игрока %d" % [title, kind_name.get(unit.kind, ""), unit.owner]]
	if unit.wounded:
		lines.append("Ранена.")
	if unit.range > 1:
		lines.append("Дальность атаки: %d кл." % unit.range)
	if unit.ability_text != "":
		lines.append(unit.ability_text)
	else:
		lines.append("Особой способности нет.")
	return lines


func _tile_lines(coord: Vector2i) -> Array[String]:
	var terrain := grid.board.terrain_at(coord)
	var lines: Array[String] = ["Клетка: %s" % grid.terrain_name(terrain)]
	var effect := grid.terrain_effect(terrain)
	if effect != "":
		lines.append(effect)
	return lines


func _choose(mode: String) -> void:
	if grid == null:
		return
	if mode == "action" and selected != null:
		grid.status.emit(selected.ability_text)
		return
	grid.choose_action(mode)


func _refresh_resource() -> void:
	if grid == null or grid.game == null:
		_lbl_resource.visible = false
		return
	var player := grid.game.current_player
	var faction := str(grid.faction_ids.get(player, ""))
	if faction == "infected":
		_lbl_resource.text = "Биомасса %d" % grid.game.biomass_of(player)
		_lbl_resource.visible = true
	elif faction == "undead":
		_lbl_resource.text = "Эссенция %d" % grid.game.essence_of(player)
		_lbl_resource.visible = true
	else:
		_lbl_resource.visible = false


## Только для отладочного снимка: подсказка в заданной точке, без курсора.
func show_tooltip_at(unit: Unit, at: Vector2) -> void:
	_follow_mouse = false
	_lbl_tooltip.text = "\n".join(_figure_lines(unit))
	_tooltip.reset_size()
	_tooltip.position = at
	_tooltip.visible = true


func _process(_delta: float) -> void:
	_refresh_resource()
	if _tooltip.visible and _follow_mouse:
		var mouse := get_global_mouse_position()
		var view := get_viewport_rect().size
		var size := _tooltip.size
		var pos := mouse + Vector2(18.0, 18.0)
		pos.x = minf(pos.x, view.x - size.x - 12.0)
		pos.y = minf(pos.y, view.y - size.y - 12.0)
		_tooltip.position = pos.max(Vector2(12.0, 12.0))
