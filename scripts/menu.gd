extends Control

## Стартовое меню: выбор фракции игрока перед партией.
## Вторая сторона получает следующую фракцию из списка (пока — демо-соперник).

const FACTIONS := [
	{"id": "infected", "name": "Заражённые", "note": "биомасса: усиления и возрождение"},
	{"id": "undead", "name": "Нежить", "note": "эссенция: всплеск, призыв, заклинания"},
	{"id": "people", "name": "Орден креста", "note": "рокировка, защита, баррикады"},
	{"id": "elves", "name": "Хранители рощи", "note": "дальний бой, мобильность"},
	{"id": "elemental", "name": "Маги Эфиральда", "note": "элементали и слияния"},
]

const COLOR_TEXT := Color(0.94, 0.94, 0.92)
const COLOR_DIM := Color(0.72, 0.74, 0.78)

var _status_label: Label
var _client: GameClient = null
var _mode: String = ""   # "host" | "guest"
var _join_token: String = ""
var _sent: bool = false


func _ready() -> void:
	# Отладочный снимок не должен упираться в меню.
	if "--shot" in OS.get_cmdline_user_args():
		_start(FACTIONS[0]["id"])
		return
	_build()
	if "--menu-shot" in OS.get_cmdline_user_args():
		_menu_screenshot()


## Снимок самого меню: godot --path . -- --menu-shot
func _menu_screenshot() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshot-menu.png")
	var error := image.save_png(path)
	print("SCREENSHOT: ", path, " err=", error)
	get_tree().quit()


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.10, 0.12)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)

	var title := Label.new()
	title.text = "OneLife — выбери фракцию"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "FFA на четверых: выбери свою фракцию, остальные игроки получат три остальные"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", COLOR_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	for faction in FACTIONS:
		var button := Button.new()
		button.text = "%s — %s" % [faction["name"], faction["note"]]
		button.custom_minimum_size = Vector2(560.0, 58.0)
		button.add_theme_font_size_override("font_size", 20)
		button.add_theme_stylebox_override("normal", _button_style(Color("#1b2230")))
		button.add_theme_stylebox_override("hover", _button_style(Color("#26344a")))
		button.add_theme_stylebox_override("pressed", _button_style(Color("#2f4258")))
		button.add_theme_stylebox_override("focus", _button_style(Color("#2f4258")))
		button.pressed.connect(_on_faction_pressed.bind(faction["id"]))
		column.add_child(button)

	_build_online(column)


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _on_faction_pressed(faction_id: String) -> void:
	_start(faction_id)


func _start(faction_id: String) -> void:
	# FFA на четверых: игрок 1 — выбранная фракция, игроки 2–4 — остальные по кругу.
	var start := 0
	for i in FACTIONS.size():
		if FACTIONS[i]["id"] == faction_id:
			start = i
			break
	GameConfig.factions.clear()
	for i in FACTIONS.size():
		GameConfig.factions[i + 1] = FACTIONS[(start + i) % FACTIONS.size()]["id"]
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


## Онлайн-секция: хост создаёт комнату, гость входит по коду. Пока не пришёл
## state от сервера (матч не начался), остаёмся в меню.
func _build_online(column: VBoxContainer) -> void:
	var sep := HSeparator.new()
	column.add_child(sep)

	var url_field := LineEdit.new()
	url_field.text = GameConfig.server_url
	url_field.placeholder_text = "адрес сервера (ws://...)"
	url_field.custom_minimum_size = Vector2(560.0, 40.0)
	column.add_child(url_field)

	var host_btn := Button.new()
	host_btn.text = "Онлайн: создать комнату"
	host_btn.custom_minimum_size = Vector2(560.0, 50.0)
	host_btn.add_theme_font_size_override("font_size", 18)
	host_btn.pressed.connect(func(): _connect_host(url_field.text))
	column.add_child(host_btn)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	var token_field := LineEdit.new()
	token_field.placeholder_text = "код комнаты"
	token_field.custom_minimum_size = Vector2(420.0, 40.0)
	join_row.add_child(token_field)
	var join_btn := Button.new()
	join_btn.text = "Войти по коду"
	join_btn.custom_minimum_size = Vector2(140.0, 40.0)
	join_btn.add_theme_font_size_override("font_size", 18)
	join_btn.pressed.connect(func(): _connect_guest(url_field.text, token_field.text))
	join_row.add_child(join_btn)
	column.add_child(join_row)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", COLOR_DIM)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status_label)


func _connect_host(url: String) -> void:
	_client = GameClient.new()
	GameConfig.client = _client
	GameConfig.online = true
	GameConfig.server_url = url
	_mode = "host"
	_sent = false
	_client.connect_to_server(url)
	set_process(true)


func _connect_guest(url: String, token: String) -> void:
	_client = GameClient.new()
	GameConfig.client = _client
	GameConfig.online = true
	GameConfig.server_url = url
	_mode = "guest"
	_join_token = token
	_sent = false
	_client.connect_to_server(url)
	set_process(true)


func _process(_delta: float) -> void:
	if _client == null:
		return
	_client.poll()
	if not _client.connected:
		_status_label.text = "Подключение к %s..." % GameConfig.server_url
		return
	if not _sent:
		if _mode == "host":
			_client.create_room()
			_sent = true
		elif _mode == "guest":
			_client.join_room(_join_token)
			_sent = true
	var rej := _client.last("rejected")
	if not rej.is_empty():
		_status_label.text = "Ошибка: %s" % str(rej.get("reason", ""))
	elif _client.room_token != "":
		_status_label.text = "Комната %s — ждём игроков..." % _client.room_token
	if not _client.state.is_empty():
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
