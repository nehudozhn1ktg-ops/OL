extends Control
class_name Hud

## Интерфейс партии: панель действий справа, подсказка способности при наведении
## и постоянная строка характеристик выбранной/наведённой фигуры.
##
## Формат характеристик по канону боя: D4 + бонус, поэтому урон и броня
## показываются диапазоном «бонус+1 … бонус+4», передвижение — одним числом.

const ICON_DAMAGE := preload("res://assets/ui/damage.png")
const ICON_MOVE := preload("res://assets/ui/move.png")
const ICON_ARMOR := preload("res://assets/ui/armor.png")
const ICON_ACTION := preload("res://assets/ui/action.png")

const COLOR_TEXT := Color(0.94, 0.94, 0.92)
const COLOR_DIM := Color(0.72, 0.74, 0.78)
const COLOR_ACCENT := Color("#ffd447")

const ICON_SIZE := Vector2(56.0, 56.0)
const STAT_ICON_SIZE := Vector2(34.0, 34.0)

var grid: HexGrid = null
var selected: Unit = null
var hovered: Unit = null

var _actions: PanelContainer
var _btn_move: TextureButton
var _btn_attack: TextureButton
var _btn_action: TextureButton
var _btn_armor: TextureButton
var _move_panel: PanelContainer
var _stats: PanelContainer
var _lbl_damage: Label
var _lbl_move: Label
var _lbl_armor: Label
var _tooltip: PanelContainer
var _lbl_tooltip: Label
var _boost_panel: PanelContainer
var _lbl_biomass: Label
## Подсказка ходит за курсором; на снимке её ставят в заданную точку.
var _follow_mouse: bool = true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_actions()
	_build_boost()
	_build_move_boost()
	_build_stats()
	_build_tooltip()
	_refresh(null, null)


func bind(grid_: HexGrid) -> void:
	grid = grid_
	grid.unit_selected_changed.connect(_on_selected_changed)
	grid.unit_hovered_changed.connect(_on_hovered_changed)
	grid.action_changed.connect(_on_action_changed)


# --- Построение --------------------------------------------------------------

func _build_actions() -> void:
	_actions = PanelContainer.new()
	_actions.mouse_filter = Control.MOUSE_FILTER_STOP
	_actions.anchor_left = 1.0
	_actions.anchor_right = 1.0
	_actions.anchor_top = 0.5
	_actions.anchor_bottom = 0.5
	_actions.offset_left = -96.0
	_actions.offset_right = -16.0
	_actions.offset_top = -124.0
	_actions.offset_bottom = 124.0
	_actions.add_theme_stylebox_override("panel", _panel_style())
	add_child(_actions)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_actions.add_child(column)

	_btn_move = _make_button(ICON_MOVE, "Передвижение")
	_btn_move.pressed.connect(func(): _choose("move"))
	_btn_attack = _make_button(ICON_DAMAGE, "Атака")
	_btn_attack.pressed.connect(func(): _choose("attack"))
	_btn_action = _make_button(ICON_ACTION, "Действие")
	_btn_action.pressed.connect(func(): _choose("action"))
	_btn_armor = _make_button(ICON_ARMOR, "Броня +1 (биомасса)")
	_btn_armor.pressed.connect(func(): grid.boost_selected_armor())
	column.add_child(_btn_move)
	column.add_child(_btn_attack)
	column.add_child(_btn_action)
	column.add_child(_btn_armor)
	_actions.visible = false


## Панель усиления атаки биомассой — появляется после нажатия «Атака».
func _build_boost() -> void:
	_boost_panel = PanelContainer.new()
	_boost_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_boost_panel.anchor_left = 1.0
	_boost_panel.anchor_right = 1.0
	_boost_panel.anchor_top = 0.5
	_boost_panel.anchor_bottom = 0.5
	_boost_panel.offset_left = -404.0
	_boost_panel.offset_right = -110.0
	_boost_panel.offset_top = -80.0
	_boost_panel.offset_bottom = 80.0
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


## Панель усиления передвижения биомассой — в режиме «Передвижение».
func _build_move_boost() -> void:
	_move_panel = PanelContainer.new()
	_move_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_move_panel.anchor_left = 1.0
	_move_panel.anchor_right = 1.0
	_move_panel.anchor_top = 0.5
	_move_panel.anchor_bottom = 0.5
	_move_panel.offset_left = -404.0
	_move_panel.offset_right = -110.0
	_move_panel.offset_top = -80.0
	_move_panel.offset_bottom = 80.0
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


func _build_stats() -> void:
	_stats = PanelContainer.new()
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.anchor_left = 0.5
	_stats.anchor_right = 0.5
	_stats.anchor_top = 0.0
	_stats.anchor_bottom = 0.0
	_stats.offset_left = -280.0
	_stats.offset_right = 280.0
	_stats.offset_top = 64.0
	_stats.offset_bottom = 122.0
	_stats.add_theme_stylebox_override("panel", _panel_style())
	add_child(_stats)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	_stats.add_child(row)

	var damage_box := _stat_box(ICON_DAMAGE)
	_lbl_damage = damage_box[1]
	row.add_child(damage_box[0])

	var move_box := _stat_box(ICON_MOVE)
	_lbl_move = move_box[1]
	row.add_child(move_box[0])

	var armor_box := _stat_box(ICON_ARMOR)
	_lbl_armor = armor_box[1]
	row.add_child(armor_box[0])

	var sep := VSeparator.new()
	row.add_child(sep)
	_lbl_biomass = Label.new()
	_lbl_biomass.add_theme_font_size_override("font_size", 18)
	_lbl_biomass.add_theme_color_override("font_color", COLOR_ACCENT)
	_lbl_biomass.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_lbl_biomass)
	_stats.visible = false


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


## Пара «иконка + значение» для строки характеристик.
func _stat_box(texture: Texture2D) -> Array:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = STAT_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)

	var label := Label.new()
	label.text = "—"
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(label)
	return [box, label]


# --- Реакция на события поля ------------------------------------------------

func _on_selected_changed(unit: Unit) -> void:
	selected = unit
	_refresh(unit, hovered)
	_boost_panel.visible = false
	_move_panel.visible = false
	if unit == null:
		_actions.visible = false
		return
	if not _actions.visible:
		_actions.visible = true
	_update_buttons(unit)


func _on_hovered_changed(unit: Unit) -> void:
	hovered = unit
	_follow_mouse = true
	if unit != null:
		_show_tooltip(unit)
	else:
		_tooltip.visible = false
	_refresh(selected, unit)


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


func _update_buttons(unit: Unit) -> void:
	_btn_move.disabled = unit.moved
	_btn_attack.disabled = unit.attacked or not unit.can_attack
	# «Действие» показываем только когда оно есть у фигуры (текст карты).
	var has_action := unit.ability_text.contains("Действие")
	_btn_action.visible = has_action
	# Усиление брони — только заражённым, и не в момент, когда биомассы нет.
	_btn_armor.visible = _is_infected()
	# Панель подстраивает высоту под число кнопок: отступы 10+10, шаг 10.
	var count := 2
	if has_action:
		count += 1
	if _btn_armor.visible:
		count += 1
	var height := 20.0 + count * ICON_SIZE.y + (count - 1) * 10.0
	_actions.offset_top = -height * 0.5
	_actions.offset_bottom = height * 0.5


func _choose(mode: String) -> void:
	if grid == null:
		return
	if mode == "action" and selected != null:
		grid.status.emit(selected.ability_text)
		return
	grid.choose_action(mode)


# --- Содержимое ---------------------------------------------------------------

func _refresh(selected_unit: Unit, hovered_unit: Unit) -> void:
	var unit: Unit = hovered_unit if hovered_unit != null else selected_unit
	if unit == null:
		_stats.visible = false
		return
	_stats.visible = true
	# D4 + бонус: минимальное значение — бонус + 1, максимальное — бонус + 4.
	_lbl_damage.text = "%d-%d" % [unit.damage + 1, unit.damage + 4]
	_lbl_move.text = "%d" % unit.move
	_lbl_armor.text = "%d-%d" % [unit.armor + 1, unit.armor + 4]


func _show_tooltip(unit: Unit) -> void:
	var title := unit.name_ru if unit.name_ru != "" else "Фигура"
	var kind_name := {"king": "Король", "commander": "Командир", "pawn": "Пешка"}
	var lines: Array[String] = ["%s · %s игрока %d" % [title, kind_name.get(unit.kind, ""), unit.owner]]
	if unit.wounded:
		lines.append("Ранена.")
	if unit.range > 1:
		lines.append("Дальность атаки: %d кл." % unit.range)
	if unit.ability_text != "":
		lines.append(unit.ability_text)
	else:
		lines.append("Особой способности нет.")
	_lbl_tooltip.text = "\n".join(lines)
	_tooltip.visible = true
	_tooltip.reset_size()


## Только для отладочного снимка: подсказка в заданной точке, без курсора.
func show_tooltip_at(unit: Unit, at: Vector2) -> void:
	_show_tooltip(unit)
	_follow_mouse = false
	_tooltip.reset_size()
	_tooltip.position = at


func _process(_delta: float) -> void:
	if _lbl_biomass != null:
		var infected := _is_infected()
		_lbl_biomass.visible = infected
		if infected:
			_lbl_biomass.text = "Биомасса %d" % grid.game.biomass_of(grid.game.current_player)
	if _tooltip.visible and _follow_mouse:
		var mouse := get_global_mouse_position()
		var view := get_viewport_rect().size
		var size := _tooltip.size
		var pos := mouse + Vector2(18.0, 18.0)
		pos.x = minf(pos.x, view.x - size.x - 12.0)
		pos.y = minf(pos.y, view.y - size.y - 12.0)
		_tooltip.position = pos.max(Vector2(12.0, 12.0))
