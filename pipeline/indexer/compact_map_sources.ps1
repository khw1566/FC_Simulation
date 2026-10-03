param([switch]$Restore, [string[]]$SourceName = @())
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$archiveRoot = Join-Path $projectRoot 'data/archives'
New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sources = @(
    @{name='ulsan_metro_60km_source';path='godot_project/assets/maps/ulsan_metro_60km'},
    @{name='ulsan_80km_collection_cache';path='godot_project/assets/maps/ulsan_metro_80km/buildings_cache'},
    @{name='ulsan_80km_merged_source';path='data/raw/ulsan_metro_80km/buildings'},
    @{name='shimonoseki_port_3km_source';path='godot_project/assets/maps/shimonoseki_port_3km'}
)
$records = @()
foreach ($source in $sources) {
	if ($SourceName.Count -gt 0 -and $source.name -notin $SourceName) { continue }
    $target = [IO.Path]::GetFullPath((Join-Path $projectRoot $source.path))
    if (-not $target.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "프로젝트 밖 경로는 처리할 수 없습니다: $target"
    }
    $zipPath = Join-Path $archiveRoot ($source.name + '.zip')
    if ($Restore) {
        if (Test-Path -LiteralPath $target) { throw "복원 대상이 이미 있습니다: $target" }
        $catalog = Get-Content (Join-Path $archiveRoot 'manifest.json') -Raw | ConvertFrom-Json
        $record = $catalog.archives | Where-Object archive -EQ ('data/archives/' + $source.name + '.zip')
        if ($null -eq $record -or (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower() -ne $record.sha256) {
            throw "보관 파일 해시 검증 실패: $zipPath"
        }
        [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $target)
        Write-Output "복원: $($source.path)"
        continue
    }
    if (-not (Test-Path -LiteralPath $target)) { continue }
    if (Test-Path -LiteralPath $zipPath) { throw "기존 보관 파일을 덮어쓰지 않습니다: $zipPath" }
    $files = @(Get-ChildItem -LiteralPath $target -Recurse -File)
    $originalBytes = ($files | Measure-Object Length -Sum).Sum
    [IO.Compression.ZipFile]::CreateFromDirectory($target, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entries = @($archive.Entries | Where-Object { $_.Name -ne '' })
        if ($entries.Count -ne $files.Count) { throw '압축 파일 수 검증 실패' }
        foreach ($file in $files) {
            $relative = $file.FullName.Substring($target.Length + 1).Replace('\', '/')
            $entry = $archive.GetEntry($relative)
            if ($null -eq $entry -or $entry.Length -ne $file.Length) { throw "압축 항목 검증 실패: $relative" }
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '')
                if ($hash -ne (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) {
                    throw "압축 해시 검증 실패: $relative"
                }
            } finally { $stream.Dispose(); $sha.Dispose() }
        }
    } finally { $archive.Dispose() }
    $records += @{archive=('data/archives/' + $source.name + '.zip');original_path=$source.path;original_bytes=$originalBytes;archive_bytes=(Get-Item -LiteralPath $zipPath).Length;file_count=$files.Count;sha256=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()}
    # 전체 원본의 파일 수·길이·SHA-256을 확인한 뒤 명시적으로 검증된 경로만 제거한다.
    Remove-Item -LiteralPath $target -Recurse -Force
    Write-Output "압축 보관 완료: $($source.path)"
}
if (-not $Restore -and $records.Count -gt 0) {
    @{created_date='2026-10-03';archives=$records;restore_command='powershell -File pipeline/indexer/compact_map_sources.ps1 -Restore'} |
        ConvertTo-Json -Depth 10 | Set-Content (Join-Path $archiveRoot 'manifest.json') -Encoding utf8
}
