param([string]$Endpoint = 'https://overpass.kumi.systems/api/interpreter')
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$destination = Join-Path $root 'data/raw/ulsan_metro_80km/railway'
New-Item -ItemType Directory -Force $destination | Out-Null
$bbox = '35.1841,128.8125667,35.9049,129.6984333'
$queries = @{
    'osm_railways.json' = "[out:json][timeout:90];way[railway=rail]($bbox);out tags geom;"
}
# 정차역은 OSM 원본 API의 소규모 영역으로 수집하여 Overpass 부하를 피한다.
$locations = @(
    @('taehwa',129.354,35.539), @('ulsan',129.138,35.551),
    @('gaeunpo',129.322,35.508), @('deokha',129.303,35.486),
    @('mangyang',129.279,35.464), @('namchang',129.282,35.419),
    @('seosaeng',129.295,35.357), @('wolnae',129.277,35.329),
    @('jwachon',129.245,35.310), @('ilgwang',129.232,35.266),
    @('gijang',129.218,35.244), @('gyeongju',129.138,35.798)
)
foreach ($location in $locations) {
    $area = '{0},{1},{2},{3}' -f ($location[1]-0.018),($location[2]-0.018),($location[1]+0.018),($location[2]+0.018)
    Invoke-WebRequest -Uri ('https://api.openstreetmap.org/api/0.6/map?bbox='+$area) `
        -OutFile (Join-Path $destination ($location[0]+'_station.osm')) -TimeoutSec 60
}
& (Join-Path $root 'pipeline/indexer/merge_railway_stations.ps1')
foreach ($filename in $queries.Keys) {
    $uri = $Endpoint + '?data=' + [uri]::EscapeDataString($queries[$filename])
    $temporary = Join-Path $destination ($filename + '.download')
    Invoke-WebRequest -Uri $uri -OutFile $temporary -TimeoutSec 120
    $parsed = Get-Content -LiteralPath $temporary -Raw | ConvertFrom-Json
    if (-not $parsed.elements) { throw "철도 수집 결과가 없습니다: $filename" }
    Move-Item -LiteralPath $temporary -Destination (Join-Path $destination $filename) -Force
}
