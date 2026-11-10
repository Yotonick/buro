@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set "GODOT="
for %%f in (Godot_v4*_win64.exe) do set "GODOT=%%f"
if "%GODOT%"=="" goto nogodot
start "" "%GODOT%" --editor --path game
goto :eof
:nogodot
echo ОШИБКА: рядом с этим файлом нет Godot_v4..._win64.exe
pause
