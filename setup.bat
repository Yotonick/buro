@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
if not exist logs mkdir logs
set "LOG=logs\setup_log.txt"
echo === setup %date% %time% === > "%LOG%"

echo [1/4] Проверяю Git...
where git >> "%LOG%" 2>&1
if errorlevel 1 goto nogit
git --version >> "%LOG%" 2>&1

echo [2/4] Ищу Godot...
set "GODOT="
for %%f in (Godot_v4*_win64.exe) do set "GODOT=%%f"
if "%GODOT%"=="" goto nogodot
echo GODOT=%GODOT% >> "%LOG%"
"%GODOT%" --version >> "%LOG%" 2>&1

echo [3/4] Скачиваю проект с GitHub...
if exist ".git" goto pull
git init -b main >> "%LOG%" 2>&1
git remote add origin https://github.com/Yotonick/buro.git >> "%LOG%" 2>&1
git fetch origin main >> "%LOG%" 2>&1
if errorlevel 1 goto nofetch
git reset --hard origin/main >> "%LOG%" 2>&1
git branch --set-upstream-to=origin/main main >> "%LOG%" 2>&1
goto imported
:pull
git pull --ff-only origin main >> "%LOG%" 2>&1
if errorlevel 1 goto nofetch
:imported
git log -1 --oneline >> "%LOG%" 2>&1

echo [4/4] Godot готовит проект, подожди минутку...
"%GODOT%" --headless --path game --import >> "%LOG%" 2>&1
echo IMPORT_EXIT=%errorlevel% >> "%LOG%"
echo SETUP=OK >> "%LOG%"
echo.
echo Готово! Теперь запусти play.bat - откроется игра.
goto end

:nogit
echo SETUP=NO_GIT >> "%LOG%"
echo ОШИБКА: Git не найден. Установи Git for Windows и запусти setup.bat ещё раз.
goto end
:nogodot
echo SETUP=NO_GODOT >> "%LOG%"
echo ОШИБКА: рядом с этим файлом нет Godot_v4..._win64.exe
goto end
:nofetch
echo SETUP=NO_FETCH >> "%LOG%"
echo ОШИБКА: не получилось скачать проект с GitHub. Проверь интернет и запусти ещё раз.
goto end

:end
echo.
pause
