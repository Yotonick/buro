#!/bin/bash
# Сборка Godot 4.7.2 из исходников (релизы GitHub недоступны из среды). Возобновляемая.
set -x
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq build-essential pkg-config libx11-dev libxcursor-dev libxinerama-dev libgl1-mesa-dev libglu1-mesa-dev libasound2-dev libpulse-dev libudev-dev libxi-dev libxrandr-dev xvfb mingw-w64 >/dev/null 2>&1
pip install --break-system-packages -q scons
cd /home/claude/godotengine
[ -d godot/.git ] || git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot godot
cd godot
scons -j2 platform=linuxbsd target=editor openxr=no wayland=no debug_symbols=no lto=none progress=no
