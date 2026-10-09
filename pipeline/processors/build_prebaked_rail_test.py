"""울산 소구역을 추출하고 격리 Godot에서 사전 보정 테스트 자산을 생성한다."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / 'godot_project'
DEST = PROJECT / 'assets/generated/prebaked_rail_test'
WORK = ROOT / 'results/prebaked_rail_test'
RUNTIME_CONFIG = '''config_version=5
[application]
config/name="철로 사전 보정 테스트"
run/main_scene="res://scenes/testing/prebaked_rail_test.tscn"
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
environment/defaults/default_clear_color=Color(0.16,0.16,0.16,1)
'''


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def clip(points, bounds):
    """구역 경계에서 선분을 자르고, 떨어진 구간을 연결하지 않는다."""
    lo, hi = bounds
    groups, current = [], []
    for a, b in zip(points, points[1:]):
        t0, t1 = 0.0, 1.0
        for axis in (0, 2):
            delta = b[axis]-a[axis]
            if abs(delta)<1e-9:
                if not lo[axis]<=a[axis]<=hi[axis]:
                    t0, t1 = 1.0, 0.0
                    break
            else:
                s, e = sorted(((lo[axis]-a[axis])/delta, (hi[axis]-a[axis])/delta))
                t0, t1 = max(t0,s), min(t1,e)
        if t0>t1:
            if len(current)>1:
                groups.append(current)
            current=[]
            continue
        start=[a[k]+(b[k]-a[k])*t0 for k in range(3)]
        end=[a[k]+(b[k]-a[k])*t1 for k in range(3)]
        if current and sum((current[-1][k]-start[k])**2 for k in range(3))>0.0001:
            if len(current)>1:
                groups.append(current)
            current=[]
        if not current:
            current.append(start)
        if sum((current[-1][k]-end[k])**2 for k in range(3))>0.0001:
            current.append(end)
    if len(current)>1:
        groups.append(current)
    return groups


def engine(project, *args, log):
    env = os.environ.copy()
    env['APPDATA'] = str(WORK/'appdata')
    env['LOCALAPPDATA'] = str(WORK/'appdata/local')
    cmd = [str(ROOT/'tools/godot/Godot_v4.3-stable_win64_console.exe'), '--headless', '--path', str(project), '--log-file', str(log), *args]
    result = subprocess.run(cmd, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
    (log.with_suffix('.console.txt')).write_text(result.stdout+result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(f'격리 Godot 실패: {log}\n{result.stdout[-2500:]}{result.stderr[-2500:]}')


def build():
    sources = [PROJECT/'assets/generated/railway/alignment.json', PROJECT/'assets/generated/railway/graded_heightmap_16bit.png', PROJECT/'assets/generated/railway/tunnel_void.png', PROJECT/'assets/generated/railway/services.json']
    # 출력 중 다른 작성자와 경합하지 않는다.
    DEST.mkdir(parents=True, exist_ok=True)
    lock = DEST/'.build.lock'
    with lock.open('x'):
        pass
    try:
        stamps=[(p.stat().st_size,p.stat().st_mtime_ns) for p in sources]
        alignment=read(sources[0])
        terrain=np.asarray(Image.open(sources[1]), dtype=np.uint16)
        n=terrain.shape[0]
        pixel=80000/(n-1)
        count=round(2000/pixel)
        x0=round((7000+40000)/pixel-count/2)
        z0=round((3700+40000)/pixel-count/2)
        x1,z1=x0+count,z0+count
        size=count*pixel
        center=[(x0+x1)*pixel/2-40000,(z0+z1)*pixel/2-40000]
        bounds=([x0*pixel-40000,0,z0*pixel-40000],[x1*pixel-40000,0,z1*pixel-40000])
        data={'center':center,'world_size':size,'settings':alignment['settings'],'profiles':{p['id']:p for p in read(sources[3])['services']},'tracks':[],'tunnels':[]}
        for kind in ('tracks','tunnels'):
            for record in alignment[kind]:
                for group in clip(record['points'],bounds):
                    data[kind].append({**record,'points':group})
        assert data['tunnels'] and any(not t['bridge'] and not t['tunnel'] for t in data['tracks'])
        stage=WORK/'bake_project'
        inputs=stage/'inputs'
        inputs.mkdir(parents=True,exist_ok=True)
        (stage/'output').mkdir(exist_ok=True)
        for filename in ['terrain_chunk.gd','railway_terrain_void.gd','railway_terrain_grader.gd','railway_track_builder.gd','railway_route.gd','railway_night_lighting.gd','railway_formation_builder.gd','railway_tunnel_geometry.gd','bridge_geometry.gd']:
            target=stage/'scripts/terrain'/filename
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(PROJECT/'scripts/terrain'/filename,target)
        for filename in ['prebaked_rail_sampler.gd','prebaked_rail_baker.gd']:
            target=stage/'scripts/testing'/filename
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(PROJECT/'scripts/testing'/filename,target)
        lighting=stage/'assets/generated/railway/night_lighting.json'
        lighting.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(PROJECT/'assets/generated/railway/night_lighting.json',lighting)
        (stage/'project.godot').write_text('config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf-8')
        crop=(terrain[z0:z1+1,x0:x1+1].astype('<f4')/65535).astype('<f4')
        (inputs/'height.rf32').write_bytes(struct.pack('<II',count+1,count+1)+crop.tobytes())
        mask=np.asarray(Image.open(sources[2]).convert('RGBA'))[z0:z1+1,x0:x1+1]
        (inputs/'void.rgba8').write_bytes(struct.pack('<II',count+1,count+1)+mask.tobytes())
        write(inputs/'selection.json',data)
        engine(stage,'--editor','--import',log=WORK/'bake_import.log')
        engine(stage,'--script','res://scripts/testing/prebaked_rail_baker.gd',log=WORK/'bake.log')
        report=read(stage/'output/bake_report.json')
        if [(p.stat().st_size,p.stat().st_mtime_ns) for p in sources]!=stamps:
            raise RuntimeError('원본 변경 감지: 생성 결과를 게시하지 않습니다.')
        for path in (stage/'output').glob('*.scn'):
            shutil.copy2(path,DEST/path.name)
        meta=read(PROJECT/'assets/maps/ulsan_metro_80km/map_meta.json')
        box=meta['bbox']
        def geo(x,z):
            return [box['west']+(x/80000+0.5)*(box['east']-box['west']),box['north']-(z/80000+0.5)*(box['north']-box['south'])]
        west,north=geo(bounds[0][0],bounds[0][2]); east,south=geo(bounds[1][0],bounds[1][2])
        bbox={'south':south,'north':north,'west':west,'east':east}
        open_track=next(t for t in data['tracks'] if not t['bridge'] and not t['tunnel'] and len(t['points'])>3)
        probe=open_track['points'][len(open_track['points'])//2]
        local=[probe[0]-center[0],probe[1],probe[2]-center[1]]
        target=data['tunnels'][1]['points'][0]
        target=[target[0]-center[0],target[1],target[2]-center[1]]
        tunnel_points=data['tunnels'][1]['points']
        direction=np.array(tunnel_points[1])-np.array(tunnel_points[0])
        direction/=np.linalg.norm(direction)
        entry=np.array(target)
        eye=(entry-direction*55+np.array([0,9,0])).tolist()
        aim=(entry+direction*20+np.array([0,3,0])).tolist()
        catalog={'id':'prebaked_rail_test','name_ko':'울산 철로 사전 보정 테스트','world_size_meters':size,'source_center':center,'bbox':bbox,'camera_position':[local[0]+100,local[1]+90,local[2]+150],'camera_target':target,'collision_probe':local,'default_quality':'light','sources':[{'file_path':'res://'+p.relative_to(PROJECT).as_posix(),'sha256':digest(p)} for p in sources], 'bake':report, 'runtime_policy':'사전 생성 씬 읽기 및 배치만 수행. 원본 래스터·철도 JSON·생성기는 실행 프로젝트에 포함하지 않음.'}
        catalog['views']=[{'name_ko':'선로 가까이','position':[local[0]+12,local[1]+6,local[2]+15],'target':local},{'name_ko':'터널 입구','position':eye,'target':aim},{'name_ko':'전체 구역','position':catalog['camera_position'],'target':target}]
        catalog['generator_sources']=[{'file_path':p.relative_to(ROOT).as_posix(),'sha256':digest(p)} for p in [Path(__file__),PROJECT/'scripts/testing/prebaked_rail_baker.gd',PROJECT/'scripts/testing/prebaked_rail_sampler.gd',*[PROJECT/'scripts/terrain'/p.name for p in sorted((stage/'scripts/terrain').glob('*.gd'))]]]
        write(DEST/'catalog.json',catalog)
        manifest={'assets':{}}
        for path in sorted(DEST.glob('*.scn')):
            manifest['assets'][path.name]={'file_path':'res://'+path.relative_to(PROJECT).as_posix(),'type':'prebaked_rail_test','sha256':digest(path),'size_bytes':path.stat().st_size,'bbox':bbox,'elevation_min':-30,'elevation_max':1300,'resolution':{'source_raster':[count+1,count+1],'terrain_grids':[32,64,128],'rail_edge_m':10},'metadata':{'source_hashes':catalog['sources'],'godot_version':'4.3','collision_quality':'고품질 고정, 품질 변경 시 재계산 없음'}}
        write(DEST/'manifest.json',manifest)
        common_path=PROJECT/'assets/generated/manifest.json'
        common=read(common_path)
        for key,value in manifest['assets'].items():
            common['assets']['prebaked_rail_test/'+key]=value
        write(common_path,common)
        runtime=WORK/'runtime'
        runtime.mkdir(exist_ok=True)
        (runtime/'project.godot').write_text(RUNTIME_CONFIG,encoding='utf-8')
        for filename in ['prebaked_rail_test.gd','prebaked_rail_camera.gd']:
            target=runtime/'scripts/testing'/filename
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(PROJECT/'scripts/testing'/filename,target)
        target=runtime/'scenes/testing/prebaked_rail_test.tscn'
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(PROJECT/'scenes/testing/prebaked_rail_test.tscn',target)
        shutil.copytree(DEST,runtime/'assets/generated/prebaked_rail_test',dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.lock'))
        print(json.dumps({'world_size_m':size,'tracks':len(data['tracks']),'tunnels':len(data['tunnels']),'asset_bytes':sum(p.stat().st_size for p in DEST.glob('*.scn')),'bake':report},ensure_ascii=False))
    finally:
        lock.unlink()


if __name__=='__main__':
    argparse.ArgumentParser(description=__doc__).parse_args()
    build()
