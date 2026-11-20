extends SceneTree

## Запуск авторитетного сервера OneLife (NET-001):
##   godot --headless --path . --script res://scripts/server.gd [-- --port=8125]
## Логика — в scripts/net/server.gd (GameServer); здесь только цикл обработки.

var server: GameServer


func _init() -> void:
	var port := 8125
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.substr(7))
	server = GameServer.new()
	if server.listen(port) != OK:
		push_error("не удалось открыть порт %d" % port)
		quit(1)
		return
	print("OneLife server: listening on 127.0.0.1:%d" % port)
	# Headless: крутим обработку до остановки процесса.
	while true:
		server.poll()
		OS.delay_msec(5)
