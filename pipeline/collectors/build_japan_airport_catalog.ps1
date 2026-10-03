$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$ports = Get-Content (Join-Path $projectRoot 'results/261003_japan_airports_source.json') -Raw | ConvertFrom-Json
$runways = Get-Content (Join-Path $projectRoot 'results/261003_japan_runways_source.json') -Raw | ConvertFrom-Json
$names = @{RJDA='아마쿠사공항';RJDB='이키공항';RJDC='야마구치우베공항';RJFA='아시야 비행장';RJFF='후쿠오카공항';RJFK='가고시마공항';RJFM='미야자키공항';RJFN='뉴타바루 비행장';RJFO='오이타공항';RJFR='기타큐슈공항';RJFS='사가공항';RJFT='구마모토공항';RJFU='나가사키공항';RJFY='가노야 비행장';RJFZ='쓰이키 비행장';RJOF='호후 비행장';RJOZ='오즈키 비행장'}
$names['JP-0007']='오이타현 중앙공항'
$catalog = @()
foreach ($port in $ports) {
    $rows = @($runways | Where-Object airport_ident -EQ $port.ident)
    if ($rows.Count -eq 0 -and $port.ident -ne 'JP-0007') { continue }
    $lat = [double]$port.latitude_deg
    $lon = [double]$port.longitude_deg
    $metersLon = 111320 * [math]::Cos($lat * [math]::PI / 180)
    $strips = @()
    foreach ($row in $rows) {
        if (-not $row.le_latitude_deg -or -not $row.he_latitude_deg) { continue }
        $length = [math]::Round([double]$row.length_ft * 0.3048)
        $width = [math]::Round([double]$row.width_ft * 0.3048)
        if ($port.ident -eq 'RJFR') { $length = 2500; $width = 60 }
        if ($port.ident -eq 'RJFF') { $length = if ($row.le_ident -eq '16L') {2800} else {2500}; $width = 60 }
        $strips += @{designation=($row.le_ident+'/'+$row.he_ident);length_m=$length;width_m=$width;start=@([math]::Round(([double]$row.le_longitude_deg-$lon)*$metersLon,3),[math]::Round(($lat-[double]$row.le_latitude_deg)*111320,3));end=@([math]::Round(([double]$row.he_longitude_deg-$lon)*$metersLon,3),[math]::Round(($lat-[double]$row.he_latitude_deg)*111320,3))}
    }
    if ($port.ident -eq 'JP-0007') {
        $heading = 105.886111 * [math]::PI / 180
        $x = 400 * [math]::Sin($heading); $z = -400 * [math]::Cos($heading)
        $strips += @{designation='11/29';length_m=800;width_m=25;start=@((-$x),(-$z));end=@($x,$z)}
    }
    if ($strips.Count -eq 0) { continue }
    $kind = if ($port.name -match 'Base|Airfield') {'military'} else {'civil'}
    $primary = $strips | Sort-Object length_m -Descending | Select-Object -First 1
    $dx = $primary.end[0] - $primary.start[0]
    $dz = $primary.end[1] - $primary.start[1]
    $distance = [math]::Sqrt($dx*$dx+$dz*$dz)
    $dx /= $distance; $dz /= $distance
    $cx = ($primary.end[0] + $primary.start[0])/2
    $cz = ($primary.end[1] + $primary.start[1])/2
    $side = if ($port.ident -in @('RJFF','RJFM','RJFT','RJFO')) {-1} else {1}
    $sizes = @{RJDA=70;RJDB=65;RJDC=170;RJFF=550;RJFK=330;RJFM=230;RJFO=200;RJFR=180;RJFS=150;RJFT=260;RJFU=280}
    $terminalWidth = if ($sizes.ContainsKey($port.ident)) {$sizes[$port.ident]} else {100}
    $features = @()
    foreach($offset in @(250*$side)) {
        $points = @()
        foreach($p in @(@((-$terminalWidth/2),-30),@(($terminalWidth/2),-30),@(($terminalWidth/2),30),@((-$terminalWidth/2),30))) {
            $points += ,@([math]::Round($cx+$dx*$p[0]-$dz*($offset+$p[1]),3),[math]::Round($cz+$dz*$p[0]+$dx*($offset+$p[1]),3))
        }
        $features += @{kind='terminal';points=$points;height_m=if($kind -eq 'civil'){18}else{12}}
        $apron = @()
        foreach($p in @(@((-$terminalWidth/2-20),(80*$side)),@(($terminalWidth/2+20),(80*$side)),@(($terminalWidth/2+20),(210*$side)),@((-$terminalWidth/2-20),(210*$side)))) {
            $apron += ,@([math]::Round($cx+$dx*$p[0]-$dz*$p[1],3),[math]::Round($cz+$dz*$p[0]+$dx*$p[1],3))
        }
        $features += @{kind='apron';points=$apron}
        $parallel = @(@(($primary.start[0]-$dz*80*$side),($primary.start[1]+$dx*80*$side)),@(($primary.end[0]-$dz*80*$side),($primary.end[1]+$dx*80*$side)))
        $features += @{kind='taxiway';width_m=23;points=$parallel}
        foreach($fraction in @(0.1,0.35,0.65,0.9)) {
            $x=$primary.start[0]+$dx*$distance*$fraction;$z=$primary.start[1]+$dz*$distance*$fraction
            $features += @{kind='taxiway';width_m=23;points=@(@($x,$z),@(($x-$dz*80*$side),($z+$dx*80*$side)))}
        }
    }
    # 후쿠오카는 국내선과 국제선 터미널을 활주로 양쪽에 근사 배치한다.
    if($port.ident -eq 'RJFF') {
        $points=@();foreach($p in @(@(-180,-35),@(180,-35),@(180,35),@(-180,35))) { $points+=,@(($cx+$dx*$p[0]-$dz*(350+$p[1])),($cz+$dz*$p[0]+$dx*(350+$p[1]))) }
        $features += @{kind='terminal';points=$points;height_m=23}
    }
    $catalog += @{id=$port.ident;name_ko=$names[$port.ident];name_en=$port.name;kind=$kind;anchor=@{lat=$lat;lon=$lon};elevation_m=[math]::Round([double]$port.elevation_ft*0.3048,2);runways=$strips;features=$features;scene_path=('res://assets/generated/japan_airports/'+$port.ident+'.scn');accuracy='활주로 기준 좌표는 공개 자료. 터미널·관제탑·유도로·계류장 외관과 배치는 근사 모델.'}
}
$output = Join-Path $projectRoot 'config/japan_airports.json'
@{version=1;source_date='2026-10-03';sources=@('https://www.pref.oita.jp/site/kenou/shisetsu.html','https://ourairports.com/data/','https://www.fukuoka-airport.jp/ko/about/','https://english.kitakyu-air.jp/cargo/cargo-about.php');airports=$catalog} | ConvertTo-Json -Depth 20 | Set-Content $output -Encoding utf8
Write-Output "공항 설정 생성: $($catalog.Count)곳"


