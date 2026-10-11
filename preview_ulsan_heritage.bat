@echo off
setlocal
cd /d "%~dp0"
tools\godot\Godot_v4.3-stable_win64.exe --path godot_project --rendering-method gl_compatibility res://scenes/ulsan_heritage_preview.tscn
