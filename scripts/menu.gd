extends Control

## Стартовое меню: выбор фракции игрока перед партией.
## Вторая сторона получает следующую фракцию из списка (пока — демо-соперник).

const FACTIONS := [
	{"id": "infected", "name": "Заражённые", "note": "биомасса: усиления и возрождение"},
	{"id": "undead", "name": "Нежить", "note": "эссенция: всплеск, призыв, заклинания"},
	{"id": "people", "name": "Орден креста", "note": "рокировка, защита, баррикады"},
	{"id": "elves", "name": "Хранители рощи", "note": "дальний бой, мобильность"},
]

const COLOR_TEXT := Color(0.94, 0.94, 0.92)
const COLOR_DIM := Color(0.72, 0.74, 0.78)


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
	subtitle.text = "Партия 1 на 1: выбери сторону, соперник получит другую фракцию"
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
	GameConfig.factions[1] = faction_id
	GameConfig.factions[2] = _opponent_for(faction_id)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


## Соперник — следующая фракция по кругу (демо-режим до выбора за обе стороны).
func _opponent_for(faction_id: String) -> String:
	for i in FACTIONS.size():
		if FACTIONS[i]["id"] == faction_id:
			return FACTIONS[(i + 1) % FACTIONS.size()]["id"]
	return "undead"
