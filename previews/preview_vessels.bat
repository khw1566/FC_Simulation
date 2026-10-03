@echo off
setlocal
cd /d "%~dp0.."
set "APPDATA=%CD%\results\runtime_appdata"
start "" "tools\godot\Godot_v4.3-stable_win64.exe" --path "%CD%\godot_project" --rendering-method gl_compatibility res://scenes/vessel_asset_preview.tscn
