$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$recordPath = Join-Path $PSScriptRoot '261012_FileSeparation.json'
$records = @()
if (Test-Path -LiteralPath $recordPath) {
    $saved = Get-Content -LiteralPath $recordPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    $records = @($saved.moves)
    foreach ($record in $records) {
        $from = Join-Path $projectRoot $record.source
        $to = Join-Path $projectRoot $record.destination
        if ($record.status -eq 'needs_attention' -and $record.metadata_mismatches -eq 0 -and
            $record.compatibility_junction -and (Test-Path -LiteralPath $to) -and
            (Test-Path -LiteralPath $from) -and
            (Get-Item -LiteralPath $from -Force).LinkType -eq 'Junction') {
            $record.status = 'verified'
            $record.junction_verified = $true
            $record.Remove('error')
        }
        if ($record.status -ne 'verified') { throw "기존 이동 복구 필요: $($record.source)" }
    }
}
$plans = @(
    @{ source = '.build'; destination = 'build_artifacts/work'; junction = $false },
    @{ source = 'dist'; destination = 'build_artifacts/releases'; junction = $false },
    @{ source = 'data/raw'; destination = 'source_assets/raw'; junction = $true },
    @{ source = 'data/archives'; destination = 'source_assets/archives'; junction = $true },
    @{ source = '기초 미가공데이터'; destination = 'source_assets/기초 미가공데이터'; junction = $true },
    @{ source = 'data/processed'; destination = 'build_artifacts/processed'; junction = $true }
)
foreach ($file in Get-ChildItem -LiteralPath $projectRoot -File -Force) {
    if ($file.Extension -eq '.log' -or $file.Name -eq '.godot_check.txt') {
        $plans += @{ source = $file.Name; destination = ('build_artifacts/logs/' + $file.Name); junction = $false }
    }
}
# 모든 이동은 확인된 프로젝트 내부 경로에서만 수행한다.
$completed = @($records | ForEach-Object { $_.source })
$plans = @($plans | Where-Object { $_.source -notin $completed })
foreach ($plan in $plans) {
    foreach ($key in @('source', 'destination')) {
        $resolved = [IO.Path]::GetFullPath((Join-Path $projectRoot $plan[$key]))
        if (-not $resolved.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "프로젝트 외부 경로: $resolved"
        }
    }
    $from = Join-Path $projectRoot $plan.source
    $to = Join-Path $projectRoot $plan.destination
    if (-not (Test-Path -LiteralPath $from)) { throw "원본 없음: $from" }
    if (Test-Path -LiteralPath $to) { throw "대상 존재: $to" }
    if ((Get-Item -LiteralPath $from -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "원본이 이미 연결 경로입니다: $from"
    }
}
foreach ($plan in $plans) {
    $from = Join-Path $projectRoot $plan.source
    $to = Join-Path $projectRoot $plan.destination
    $sourceItem = Get-Item -LiteralPath $from -Force
    $files = if ($sourceItem.PSIsContainer) {
        @(Get-ChildItem -LiteralPath $from -File -Recurse -Force)
    } else { @($sourceItem) }
    $before = @($files | ForEach-Object {
        @{ path = if ($sourceItem.PSIsContainer) { $_.FullName.Substring($from.Length + 1) } else { '' }
           bytes = $_.Length; modified = $_.LastWriteTimeUtc.Ticks }
    })
    New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force | Out-Null
    $record = @{ source = $plan.source; destination = $plan.destination; status = 'pending'; files = $before.Count
        bytes = ($files | Measure-Object Length -Sum).Sum; compatibility_junction = $plan.junction }
    try {
        Move-Item -LiteralPath $from -Destination $to
        $record.status = 'moved'
        $mismatch = 0
        foreach ($entry in $before) {
            $targetFile = if ($sourceItem.PSIsContainer) { Join-Path $to $entry.path } else { $to }
            $item = Get-Item -LiteralPath $targetFile -Force
            if ($item.Length -ne $entry.bytes -or $item.LastWriteTimeUtc.Ticks -ne $entry.modified) { $mismatch++ }
        }
        $record.metadata_mismatches = $mismatch
        if ($plan.junction) {
            New-Item -ItemType Junction -Path $from -Target $to | Out-Null
            $record.junction_verified = ((Get-Item -LiteralPath $from -Force).LinkType -eq 'Junction')
        }
        $record.status = if ($mismatch -eq 0) { 'verified' } else { 'changed_during_move' }
    } catch {
        $record.error = $_.Exception.Message
        $record.status = 'needs_attention'
    }
    $records += $record
    @{ date = '2026-10-12'; deleted_files = 0; verification = '파일별 크기와 수정시각 비교; 해시 검증 및 게임 실행 생략'; moves = $records } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
    if ($record.status -ne 'verified') { throw "이동 보류 또는 확인 필요: $($plan.source)" }
}
$records | Select-Object source,destination,status,files,bytes | Format-Table -AutoSize
