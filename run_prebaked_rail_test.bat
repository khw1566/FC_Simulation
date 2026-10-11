@echo off
cd /d "%~dp0"
start "" "tools\godot\Godot_v4.3-stable_win64.exe" --path "results\prebaked_rail_test\runtime" %*
