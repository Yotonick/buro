@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
if not exist logs mkdir logs
set "GODOT="
for %%f in (Godot_v4*_win64.exe) do set "GODOT=%%f"
if "%GODOT%"=="" goto nogodot
if not exist "game\project.godot" goto nosetup

echo Обновляю игру...
git pull --ff-only origin main > logs\update_log.txt 2>&1
if errorlevel 1 echo Обновить не получилось, запускаю то, что есть. Подробности: logs\update_log.txt
"%GODOT%" --headless --path game --import > logs\import_log.txt 2>&1

echo Запускаю...
start "" "%GODOT%" --path game --log-file "%~dp0logs\game_log.txt" -- %*
goto :eof

:nogodot
echo ОШИБКА: рядом с этим файлом нет Godot_v4..._win64.exe
pause
goto :eof
:nosetup
echo Сначала запусти setup.bat
pause
