"""원본을 수정하지 않고 안정된 에셋 파일과 기존 매니페스트를 조사."""

import hashlib
import json
from pathlib import Path

CATEGORIES = {
    'taehwa_civil':'태화강 보·유수지·배수문 및 투명 수면·하상',
    'ulsan_dams':'울산 용수댐·조사 기반 제방 모델 및 지리 배치',
    'park_vegetation':'공원·정원 공용 군락·바닥·조립 예제',
    'industrial_lod':'공단 원경·초원경 LOD',
    'bamboo':'대나무 군집 및 숲 LOD',
    'trees':'수목 및 원경 LOD',
    'silvergrass':'억새·갈대 군락 LOD',
    'forest_trees':'공통 숲 수목 LOD',
    'taehwagang_ecozones':'태화강 둔치 생태 구역·식생 배치',
    'prebaked_rail_test':'철로 사전 보정 테스트 자산',
    'terrain_quality':'품질별 지형 파생 자산',
    'industrial_zones':'공단 구역 마스크',
    'road_assets':'모듈형 도로·보행로·교차로·데크',
    'harbor_assets':'모듈형 항구·방파제·등대·하역시설',
    'industrial':'산업·공단', 'industrial_plant':'플랜트 탑·배관·연기',
    'industrial_lighting':'공단 야간 조명', 'vessels':'선박', 'wolsong':'발전소',
    'taehwagang':'역사·역세권', 'railway':'철도', 'railway_bridges':'철도교',
    'railway_tunnels':'철도터널', 'pedestrian_bridges':'보행교',
    'bridges':'교량', 'airport':'공항', 'japan_airports':'일본 공항',
    'heritage':'문화유산', 'horizon':'원경', 'tiles':'지형 타일',
    'maps':'지도', 'ui':'UI', 'shaders':'셰이더', 'terrain':'지형·지도 기반',
    'asset_metadata':'공통 에셋 메타데이터',
}
ROLES = {'.glb':'모델', '.tscn':'씬', '.scn':'씬', '.png':'이미지',
         '.rf32z':'고도 래스터',
         '.f32':'고도 래스터',
         '.svg':'벡터 이미지', '.geojson':'지리 데이터', '.json':'데이터·메타데이터',
         '.md':'문서', '.gdshader':'셰이더', '.gdshaderinc':'셰이더', '.tres':'리소스'}


def collect(root, previous):
    bases=[root/'godot_project/assets',root/'godot_project/shaders']
    metadata={}
    for path in bases[0].rglob('manifest.json'):
        try:
            doc=json.loads(path.read_text(encoding='utf-8-sig'))
            entries=doc.get('assets',{})
            if not isinstance(entries,dict): continue
            for key,entry in entries.items():
                if not isinstance(entry,dict): continue
                target=entry.get('file_path','')
                if target.startswith('res://'): target='godot_project/'+target[6:]
                elif not target: target=(path.parent/key).relative_to(root).as_posix()
                metadata[target]=entry
        except (OSError,ValueError): pass
    old={item['path']:item for item in previous.get('files',[])}
    files=[]; pending=[]
    for base in bases:
        for path in sorted(base.rglob('*')):
            if not path.is_file() or path.suffix in ('.import','.tmp','.lock','.uid'): continue
            if path.name in ('asset_index.json','ASSET_INDEX.md'): continue
            if any(p in ('.godot','__pycache__') for p in path.parts): continue
            relative=path.relative_to(root).as_posix()
            try:
                before=path.stat()
                if relative in old and old[relative].get('mtime_ns')==before.st_mtime_ns and old[relative]['size_bytes']==before.st_size:
                    digest=old[relative]['sha256']
                else:
                    with path.open('rb') as source:
                        digest=hashlib.file_digest(source,'sha256').hexdigest()
                after=path.stat()
                if (before.st_mtime_ns,before.st_size)!=(after.st_mtime_ns,after.st_size): raise OSError('조사 도중 변경')
            except OSError:
                pending.append(relative)
                if relative in old: files.append(old[relative])
                continue
            parts=path.relative_to(base).parts
            if base.name=='shaders': category='shaders'
            elif parts[0]=='generated':
                category=parts[1] if len(parts)>2 else 'asset_metadata' if path.name=='manifest.json' else 'terrain'
            else: category=parts[0] if len(parts)>1 else 'ui' if path.suffix in ('.png','.svg') else 'asset_metadata'
            entry=metadata.get(relative,{})
            details=entry.get('metadata',{})
            files.append({'path':relative,'category':category,'category_ko':CATEGORIES.get(category,'기타'),
                          'role':'도로 노반 선분' if 'road_formation' in parts and path.suffix=='.f32' else ROLES.get(path.suffix,'기타 파일'), 'sha256':digest,
                          'size_bytes':after.st_size,'mtime_ns':after.st_mtime_ns,
                          'revision':next((parts[parts.index(key)+1] for key in ('revisions','road_revisions') if key in parts and len(parts)>parts.index(key)+1),None),
                          'bbox':entry.get('bbox',details.get('bbox')),
                          'elevation_min':entry.get('elevation_min',details.get('elevation_min')),
                          'elevation_max':entry.get('elevation_max',details.get('elevation_max')),
                          'resolution':entry.get('resolution',details.get('resolution')),
                          'label_ko':details.get('label_ko'),
                          'metadata_source': 'existing_manifest' if entry else None})
            if details.get('detail_profile'):
                files[-1].update(detail_profile=details['detail_profile'],
                                 external_textures=details.get('external_textures'),
                                 material_style=details.get('material_style'))
                for field in ('triangles', 'triangle_count_method', 'indexed_geometry', 'collision_geometry_preserved', 'connections_preserved'):
                    if field in details: files[-1][field]=details[field]
    return files,pending
