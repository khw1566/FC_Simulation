$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$source = Join-Path $root 'data/raw/ulsan_metro_80km/railway'
$stations = @{}
$wanted = @('기장','일광','좌천','월내','서생','남창','망양','덕하','개운포','태화강','울산','경주')
Get-ChildItem -LiteralPath $source -Filter '*_station.osm' | ForEach-Object {
    [xml]$xml = Get-Content -LiteralPath $_.FullName -Raw
    foreach ($node in $xml.osm.node) {
        $tags = @{}
        foreach ($tag in $node.tag) { $tags[$tag.k] = $tag.v }
        if ($tags.name -notin $wanted -or $tags.railway -notin @('station','halt','stop')) { continue }
        if ($stations.ContainsKey($tags.name) -and $stations[$tags.name].tags.railway -eq 'station') { continue }
        $stations[$tags.name] = @{type='node';id=[long]$node.id;lat=[double]$node.lat;lon=[double]$node.lon;tags=$tags}
    }
}
foreach ($name in $wanted) {
    if (-not $stations.ContainsKey($name)) { throw "실제 역 좌표를 찾지 못했습니다: $name" }
}
@{source='OpenStreetMap API 0.6 / map';elements=@($stations.Values)} |
    ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $source 'osm_stations.json')
Write-Output "철도 정차역 $($stations.Count)개 좌표 인덱싱 완료"
