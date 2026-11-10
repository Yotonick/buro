@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
if not exist logs mkdir logs
if not exist build mkdir build
set "LOG=logs\build_log.txt"
echo === build %date% %time% === > "%LOG%"
set "GODOT="
for %%f in (Godot_v4*_win64.exe) do set "GODOT=%%f"
if "%GODOT%"=="" goto nogodot

rem --- версия Godot, например 4.7.2.stable ---
set "VER=4.7.2.stable"
set "TAG=4.7.2-stable"
"%GODOT%" --version > logs\godot_version.txt 2>nul
for /f "tokens=1-4 delims=." %%a in (logs\godot_version.txt) do (
  set "VER=%%a.%%b.%%c.%%d"
  set "TAG=%%a.%%b.%%c-%%d"
)
echo VER=%VER% >> "%LOG%"
set "TPL=%APPDATA%\Godot\export_templates\%VER%"
if exist "%TPL%\windows_release_x86_64.exe" goto export

echo [1/2] Скачиваю шаблоны сборки Godot (около 1 ГБ, один раз)...
set "TPZ=%TEMP%\godot_templates_%VER%.tpz"
set "TMPDIR=%TEMP%\godot_templates_%VER%"
curl -L --fail -o "%TPZ%" "https://github.com/godotengine/godot/releases/download/%TAG%/Godot_v%TAG%_export_templates.tpz"
if errorlevel 1 goto nodownload
if not exist "%TMPDIR%" mkdir "%TMPDIR%"
tar -xf "%TPZ%" -C "%TMPDIR%" "templates/windows_*x86_64*" "templates/version.txt" >> "%LOG%" 2>&1
if not exist "%TPL%" mkdir "%TPL%"
copy /y "%TMPDIR%\templates\*" "%TPL%\" >> "%LOG%" 2>&1
if not exist "%TPL%\windows_release_x86_64.exe" goto nodownload
del "%TPZ%" >nul 2>&1
rmdir /s /q "%TMPDIR%" >nul 2>&1

:export
echo [2/2] Собираю игру...
if exist "build\buro.exe" del "build\buro.exe"
"%GODOT%" --headless --path game --import >> "%LOG%" 2>&1
"%GODOT%" --headless --path game --export-release "Windows" "%~dp0build\buro.exe" >> "%LOG%" 2>&1
if not exist "build\buro.exe" goto nobuild
echo BUILD=OK >> "%LOG%"
dir build >> "%LOG%" 2>&1
echo.
echo Готово! Игра лежит тут: %~dp0build\buro.exe
echo Этот файл можно скинуть друзьям.
goto end

:nogodot
echo BUILD=NO_GODOT >> "%LOG%"
echo ОШИБКА: рядом с этим файлом нет Godot_v4..._win64.exe
goto end
:nodownload
echo BUILD=NO_TEMPLATES >> "%LOG%"
echo ОШИБКА: не получилось скачать шаблоны сборки. Проверь интернет и запусти ещё раз.
goto end
:nobuild
echo BUILD=FAIL >> "%LOG%"
echo ОШИБКА: сборка не получилась. Напиши Claude - он посмотрит logs\build_log.txt
goto end

:end
echo.
pause
