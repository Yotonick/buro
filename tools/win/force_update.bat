@echo off
rem Обычное обновление не прошло (например, Godot тронул файл проекта) - берём версию с GitHub как есть.
rem Одна строка: файл может обновить сам себя.
git fetch origin main >> logs\update_log.txt 2>&1 && git reset --hard origin/main >> logs\update_log.txt 2>&1 || echo Обновить не получилось, запускаю то, что есть. Подробности: logs\update_log.txt
