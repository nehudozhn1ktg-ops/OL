extends Node2D

@onready var grid: HexGrid = $HexGrid
@onready var hint: Label = $UI/Hint


func _ready() -> void:
	grid.status.connect(_on_status)
	hint.text = "Фигура — активировать и выбрать. Клетка — идти. Враг рядом — атаковать. Пробел — передать ход."
	if "--shot" in OS.get_cmdline_user_args():
		_take_screenshot()


func _on_status(text: String) -> void:
	hint.text = text


## Отладочный снимок окна: godot --path . -- --shot [--map=4ffa]
func _take_screenshot() -> void:
	for unit in grid.game.units:
		if unit.owner == grid.game.current_player:
			grid.select_unit(unit)
			break
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshot.png")
	var error := image.save_png(path)
	print("SCREENSHOT: ", path, " err=", error)
	get_tree().quit()
