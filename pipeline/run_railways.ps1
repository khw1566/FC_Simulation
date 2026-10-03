param([switch]$Collect)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if ($Collect) { & (Join-Path $root 'pipeline/collectors/collect_ulsan_railways.ps1') }
$engine = Join-Path $root 'tools/godot/Godot_v4.3-stable_win64_console.exe'
$project = Join-Path $root 'godot_project'
$processor = Join-Path $root 'pipeline/processors/build_ulsan_railways.gd'
$log = Join-Path $root 'results/railway_build_latest.log'
& $engine --headless --path $project --script $processor --log-file $log
if ($LASTEXITCODE -ne 0) { throw "철도 자산 생성 실패: $log" }
