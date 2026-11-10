@echo off
chcp 65001 >nul
rem Запуск игры. Вызывается из play.bat (папка уже корень проекта, GODOT найден).
git log -1 --format=VERSION=%%h_%%s >> logs\update_log.txt 2>&1
"%GODOT%" --headless --path game --import > logs\import_log.txt 2>&1
echo Запускаю...
start "" "%GODOT%" --path game --log-file "%~dp0..\..\logs\game_log.txt" -- %*
