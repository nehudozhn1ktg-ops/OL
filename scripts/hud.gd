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
var _stats: PanelContainer
var _lbl_damage: Label
var _lbl_move: Label
var _lbl_armor: Label
var _tooltip: PanelContainer
var _lbl_tooltip: Label
## Подсказка ходит за курсором; на снимке её ставят в заданную точку.
var _follow_mouse: bool = true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_actions()
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
	column.add_child(_btn_move)
	column.add_child(_btn_attack)
	column.add_child(_btn_action)
	_actions.visible = false


func _build_stats() -> void:
	_stats = PanelContainer.new()
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.anchor_left = 0.5
	_stats.anchor_right = 0.5
	_stats.anchor_top = 0.0
	_stats.anchor_bottom = 0.0
	_stats.offset_left = -230.0
	_stats.offset_right = 230.0
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


func _on_action_changed(_mode: String) -> void:
	if selected != null:
		_update_buttons(selected)


func _update_buttons(unit: Unit) -> void:
	_btn_move.disabled = unit.moved
	_btn_attack.disabled = unit.attacked or not unit.can_attack
	# «Действие» показываем только когда оно есть у фигуры (текст карты).
	var has_action := unit.ability_text.contains("Действие")
	_btn_action.visible = has_action
	# Панель подстраивает высоту под число кнопок: отступы 10+10, шаг 10.
	var count := 3 if has_action else 2
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
	if _tooltip.visible and _follow_mouse:
		var mouse := get_global_mouse_position()
		var view := get_viewport_rect().size
		var size := _tooltip.size
		var pos := mouse + Vector2(18.0, 18.0)
		pos.x = minf(pos.x, view.x - size.x - 12.0)
		pos.y = minf(pos.y, view.y - size.y - 12.0)
		_tooltip.position = pos.max(Vector2(12.0, 12.0))
