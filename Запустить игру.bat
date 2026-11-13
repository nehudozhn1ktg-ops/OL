@echo off
rem Запуск игры в один клик. Godot должен лежать в C:\Godot\
"C:\Godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0"
if errorlevel 1 pause
