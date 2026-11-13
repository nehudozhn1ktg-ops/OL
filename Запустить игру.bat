@echo off
rem Launch OneLife. Keep this file in the project folder next to project.godot.
setlocal
set "GODOT=C:\Godot\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT%" goto no_godot
if not exist "%~dp0project.godot" goto no_project

start "" "%GODOT%" --path "%~dp0"
exit /b 0

:no_godot
echo Godot not found: "%GODOT%"
echo Install Godot 4.7.2 into C:\Godot, or edit this file.
pause
exit /b 1

:no_project
echo project.godot not found next to this file.
echo Move this launcher into the game folder.
pause
exit /b 1
