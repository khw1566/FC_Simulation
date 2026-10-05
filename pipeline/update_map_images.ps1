param([string[]]$Maps = @(), [switch]$Force)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$mapPython = Join-Path $projectRoot '.venv_campus/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $mapPython)) { throw '프로젝트 Python 가상환경이 없습니다.' }
$mapArguments = @((Join-Path $projectRoot 'pipeline/processors/simple_maps/generate.py'))
if ($Maps.Count -gt 0) { $mapArguments += '--maps'; $mapArguments += $Maps }
if ($Force) { $mapArguments += '--force' }
$env:PYTHONIOENCODING = 'utf-8'
& $mapPython @mapArguments
if ($LASTEXITCODE -ne 0) { throw '수동 지도 갱신에 실패했습니다. 출력 오류를 확인하세요.' }
