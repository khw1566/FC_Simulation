"""격리 검사 후 게시하며 공통 매니페스트의 다른 계열 항목을 보존한다."""
import hashlib
import json
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image,ImageDraw,ImageFont

if __package__ in (None,''):
    sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
    __package__='taehwa_civil'
from .survey import ROOT,OUT,STAGE,Survey
from .hydro import Hydro
from custom_lowpoly.glb import inspect
from rail_bridge_lowpoly.publish import update


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    fixture=json.loads((STAGE/'fixture_results.json').read_text(encoding='utf-8'))
    assert fixture['passed']
    assert 'TAEHWA_RENDER_OK' in (STAGE.parent/'preview.log').read_text(encoding='utf-8')
    for log in ['preview.log','preview_forward.log','fixture_render.log']:
        p=STAGE.parent/log
        assert p.exists() and 'ERROR:' not in p.read_text(encoding='utf-8'),log
    catalog=json.loads((OUT/'catalog.json').read_text(encoding='utf-8'))
    survey=Survey();hydro=Hydro(survey)
    assert survey.source_hash==json.loads((OUT/'bed_patch.json').read_text())['source_sha256']
    assert survey.river.distance(hydro.weir)<1
    assert all(a>=b for a,b in zip(hydro.levels,hydro.levels[1:]))
    measurements=[]
    for spec in catalog['models']:
        assert inspect(OUT/(spec['id']+'.glb'))['triangles']==spec['triangles']
        measurements.append({'id':spec['id'],'triangles':spec['triangles'],'status':spec['placement_status']})
    surface_area=0.;stored_water_triangles=0;shore_triangles=0
    for spec in catalog['hydro_chunks']:
        d=json.loads((STAGE/(spec['id']+'.json')).read_text())
        v=np.asarray(d['vertices']).reshape(-1,3,8)[:,:,[0,2]]
        a=v[:,1]-v[:,0];b=v[:,2]-v[:,0]
        area=np.abs(a[:,0]*b[:,1]-a[:,1]*b[:,0]).sum()/2
        if spec['bed_only']:shore_triangles+=spec['triangles']
        else:surface_area+=float(area);stored_water_triangles+=spec['triangles']
    expected=survey.river.area+sum(p.area for p in survey.basins)
    assert abs(surface_area-expected)/expected<.0001,(surface_area,expected)
    a=np.asarray(Image.open(STAGE/'water_flow_0.png')).astype(float)
    b=np.asarray(Image.open(STAGE/'water_flow_2.png')).astype(float)
    fraction=float(np.mean(np.max(np.abs(a-b),axis=2)>2));assert fraction>.01
    for spec in [*catalog['models'],*catalog['hydro_chunks']]:
        path=STAGE/'assets/generated/taehwa_civil'/(spec['id']+'.tscn')
        assert path.is_file()
        shutil.copy2(path,OUT/path.name)
    readme='''# 태화강 토목시설과 투명 수면

- 반천 부근 보·어도, 여천 유수지 사석 호안, 여천 배수문 3곳을 울산 80km 지도에 연결한다.
- 배수 암거 및 20m 호안 모듈은 재사용용이며 실제 좌표에 자동 배치하지 않는다.
- 보 축선과 유수지 경계는 공개 OSM, 배수문 축선과 세부 단면은 영상 기반 추정이다. 공식 보 명칭은 미확인이다.
- 하류는 공개 수역 면, 면이 없는 상류는 중심선과 추정 폭을 사용한다. 구간과 근거는 catalog.json boundary_status에 기록한다.
- 별도 하상, 투명 PBR 수면, 하류 방향 UV, 수심 감쇠, Fresnel 반사, 잔물결과 보 주변 포말을 사용한다.
- 수위·수심·유속·포말은 시각화 값이다. 실제 수문 운전·유량·침수 계산을 포함하지 않는다.
- 18m 이내 강변 경사면으로 기존 지형과 연결한다. 원본 DEM은 보존하고 실행 중 복사본에만 국소 패치를 적용한다.
- 기존 지형 충돌도 패치된 높이맵을 사용하며 정밀 하상에는 별도 충돌이 있다. 지형 높이 범위가 다른 지도에는 적용하지 않는다.
- GLB와 대응 TSCN은 동일 모델의 표현이다. 수면·하상 구역 씬은 시설 종류 수에 합산하지 않는다.
- 수면은 투명도와 환경 반사를 사용한다. 화면 굴절, 실제 유체 해석, 실측 수위·조석, 수중 시점은 미구현이다.
- Godot 4.3 Compatibility와 Forward+의 깊이 버퍼 범위를 구분한다. 전체 지도 실행과 전체 FPS는 검증하지 않았다.
- 재생성: generate.py → 전용 bake.gd → 전용 fixture.gd/preview.gd → publish.py → 중앙 build_asset_index.py.
- 프리뷰 작업 공간 및 APPDATA/LOCALAPPDATA는 previews/taehwa_civil 아래를 사용한다. 원본 Godot 임포터를 실행하지 않는다.
- OpenStreetMap contributors / ODbL-1.0. 원천·배제 항목은 config/taehwa_civil.json 및 조사 보고서 참조.
'''
    (OUT/'README.md').write_text(readme,encoding='utf-8')
    assets={}
    model_lookup={spec['id']:spec for spec in catalog['models']}
    chunk_lookup={spec['id']:spec for spec in catalog['hydro_chunks']}
    corners=[survey.lonlat(*p) for p in [hydro.ground_coverage.bounds[:2],hydro.ground_coverage.bounds[2:]]]
    bbox={'west':corners[0][0],'east':corners[1][0],'south':corners[1][1],'north':corners[0][1]}
    for path in sorted(OUT.iterdir()):
        if path.name=='manifest.json' or not path.is_file():continue
        spec=model_lookup.get(path.stem,chunk_lookup.get(path.stem,{}))
        meta={'detail_profile':'taehwa_civil_research_v1','bbox':bbox if path.stem in chunk_lookup or path.suffix in ['.png','.rf32z','.geojson'] else None,
              'elevation_min':None,'elevation_max':None,'resolution':None,'surveyed':False,
              'placement_status':spec.get('placement_status','visual_hydro_estimate'),'triangles':spec.get('triangles'),
              'coordinate_reference':'map_80km_world_m' if path.stem in chunk_lookup else 'local_model_m',
              'label_ko':spec.get('name_ko',path.stem)}
        if path.suffix=='.png':meta['resolution']=list(Image.open(path).size)
        if path.suffix=='.rf32z':
            patch=json.loads((OUT/'bed_patch.json').read_text());meta.update(resolution=patch['pixel_rect'][2:],elevation_min=patch['elevation_min_m'],elevation_max=patch['elevation_max_m'],elevation_reference='estimated_visual_bed_m')
        if path.stem in chunk_lookup:
            data=json.loads((STAGE/(path.stem+'.json')).read_text());heights=[v[1]-v[5] for v in data['vertices']]
            meta.update(elevation_min=min(heights),elevation_max=max(v[1] for v in data['vertices']),coordinate_reference='map_80km_world_m',bed_only=spec['bed_only'],triangles=spec['triangles']*(1 if spec['bed_only'] else 2),triangle_count_method='stored_bed_plus_water')
        if path.stem in model_lookup:
            meta.update(status=spec['status'],elevation_reference='local_anchor',elevation_min=spec['aabb_min_m'][1],elevation_max=spec['aabb_max_m'][1],aabb_min_m=spec['aabb_min_m'],aabb_max_m=spec['aabb_max_m'],axis_lonlat=spec.get('axis_lonlat'),depth_status='visual_estimate')
        assets[path.name]={'file_path':'res://assets/generated/taehwa_civil/'+path.name,'sha256':digest(path),'size_bytes':path.stat().st_size,'metadata':meta}
    update(OUT/'manifest.json',lambda d:d.update(version=1,assets=assets))
    preserved={}
    def merge(doc):
        entries=doc.setdefault('assets',{});before={k:v for k,v in entries.items() if not k.startswith('taehwa_civil/')}
        entries.update({'taehwa_civil/'+key:value for key,value in assets.items()})
        assert before=={k:v for k,v in entries.items() if not k.startswith('taehwa_civil/')}
        preserved['non_target_entries_preserved']=len(before)
    update(ROOT/'godot_project/assets/generated/manifest.json',merge)
    modules=[{'path':p.relative_to(ROOT).as_posix(),'lines':len(p.read_text(encoding='utf-8').splitlines())} for p in sorted(Path(__file__).parent.iterdir()) if p.suffix in ['.py','.gd']]
    modules.extend({'path':'godot_project/'+p} for p in ['scripts/water/river_bed_grade.gd','scripts/water/taehwa_water_manager.gd','scripts/terrain/taehwa_civil_manager.gd','shaders/taehwa_flow_water.gdshader','shaders/river_gravel.gdshader'])
    for index in [ROOT/'module_index.json',ROOT/'godot_project/module_index.json']:
        update(index,lambda d:d.setdefault('domains',{}).update(taehwa_civil={'description':'태화강 토목시설 및 투명 유향 수면·하상','modules':modules}))
    receipt={'passed':True,'facility_models':measurements,'placed_facilities':3,'hydro_chunks':len(catalog['hydro_chunks']),
             'water_triangles':stored_water_triangles,'shore_triangles':shore_triangles,'bed_triangles':stored_water_triangles+shore_triangles,
             'water_area_m2':surface_area,'expected_area_m2':expected,'flow_changed_pixel_fraction':fraction,
             'source_dem_unchanged':True,'published_assets':len(assets),'pending':[],**preserved,'fixture':fixture}
    (ROOT/'results/261011_TaehwaCivilVerification.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
    montage()
    print(json.dumps({k:v for k,v in receipt.items() if k not in ['fixture','facility_models']},ensure_ascii=False))


def montage():
    font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',22)
    canvas=Image.new('RGB',(1440,1016),'#111111');draw=ImageDraw.Draw(canvas)
    for i,(name,label) in enumerate([('bancheon_weir','반천 부근 보·어도 | 축선 확인, 단면 추정'),('yeocheon_gate','여천 유수지 배수문 | 영상 기반 형상'),('water_flow_0','투명 수면 | 하류 방향 잔물결·하상 투과'),('yeocheon_basin','여천 유수지 | 공개 경계·사석 호안')]):
        x=(i%2)*720;y=(i//2)*508
        canvas.paste(Image.open(STAGE/(name+'.png')).convert('RGB').resize((720,456)),(x,y+45))
        draw.text((x+15,y+10),label,font=font,fill='white')
    canvas.save(ROOT/'results/261011_TaehwaCivilPreview.png')


if __name__=='__main__':main()
