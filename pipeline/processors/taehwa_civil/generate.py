"""전용 에셋과 격리 프리뷰 프로젝트만 생성한다."""
import json
import shutil
import sys
from pathlib import Path
from shapely.geometry import Point

if __package__ in (None,''):
    sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
    __package__='taehwa_civil'
from .survey import Survey,ROOT,OUT,STAGE
from .hydro import Hydro
from .geometry import build,PALETTE
from custom_lowpoly.glb import export


def main():
    OUT.mkdir(parents=True,exist_ok=True); STAGE.mkdir(parents=True,exist_ok=True)
    survey=Survey(); hydro=Hydro(survey)
    chunks=hydro.create()
    catalog={**survey.spec,'palette':PALETTE,'reference_bbox':survey.bbox,'reference_world_size':80000,
             'hydro_chunks':chunks,'models':[],'boundary_status':survey.boundary_status,
             'profile':{'chainage_m':hydro.stations.tolist(),'level_m':hydro.levels.tolist()}}
    catalog['flow_step_m']=float(hydro.stations[1]-hydro.stations[0])
    probe=hydro.vertex(round(hydro.weir.x-15,5),round(hydro.weir.y-35,5))
    catalog['fixture_probe_world_m']=[probe[0],probe[1]-probe[5],probe[2]]
    catalog['flow_samples']=[]
    for station in hydro.stations:
        a,b=survey.line.interpolate(max(0,station-10)),survey.line.interpolate(min(survey.line.length,station+10))
        delta=[b.x-a.x,b.y-a.y];length=__import__('math').hypot(*delta)
        catalog['flow_samples'].append([d/length for d in delta])
    for spec in survey.spec['facilities']:
        mesh,placement=build(spec,survey,hydro)
        points=[p for face in mesh.faces for p in face[:3]]
        path=OUT/(spec['id']+'.glb');export(mesh,path,spec['id'],PALETTE)
        catalog['models'].append({**spec,**placement,'triangles':len(mesh.faces),
                                  'aabb_min_m':[min(p[i] for p in points) for i in range(3)],
                                  'aabb_max_m':[max(p[i] for p in points) for i in range(3)],
                                  'scene_path':f"res://assets/generated/taehwa_civil/{spec['id']}.tscn"})
    for name,model,size in [('bancheon',catalog['models'][0],800),('yeocheon',catalog['models'][1],1700)]:
        anchor=model['anchor_world_m'];vertices=[];grid=64
        def point(i,j):
            x=anchor[0]+(i/grid-.5)*size;z=anchor[2]+(j/grid-.5)*size
            y=float(survey.height(x,z));p=Point(x,z)
            if hydro.ground_coverage.covers(p):
                basin=next((i for i,g in enumerate(survey.basins) if g.covers(p)),-1)
                v=hydro.vertex(round(x,5),round(z,5),basin) if hydro.coverage.covers(p) else hydro.shore_vertex(round(x,5),round(z,5))
                y=v[1]-v[5]
            return [x,y,z]
        for j in range(grid):
            for i in range(grid):
                a,b,c,d=point(i,j),point(i+1,j),point(i+1,j+1),point(i,j+1)
                vertices.extend([a,b,c,a,c,d])
        (STAGE/(name+'_terrain.json')).write_text(json.dumps({'vertices':vertices},separators=(',',':')),encoding='utf-8')
    (OUT/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
    stage_assets=STAGE/'assets/generated/taehwa_civil';stage_assets.mkdir(parents=True,exist_ok=True)
    for p in OUT.iterdir():
        if p.is_file():shutil.copy2(p,stage_assets/p.name)
    shutil.copy2(OUT/'catalog.json',STAGE/'catalog.json')
    for p in Path(__file__).parent.glob('*.gd'):shutil.copy2(p,STAGE/p.name)
    for folder,names in {'scripts/water':['taehwa_water_manager.gd','river_bed_grade.gd','kanmon_water_manager.gd'],
                          'scripts/terrain':['taehwa_civil_manager.gd'],
                          'scripts/services':['map_image_preloader.gd'],
                          'shaders':['taehwa_flow_water.gdshader','river_gravel.gdshader','procedural_terrain.gdshader',
                                     'kanmon_water.gdshader','water_mask_filter.gdshaderinc','water_surface.gdshaderinc','ecozone_ground.gdshaderinc']}.items():
        dest=STAGE/folder;dest.mkdir(parents=True,exist_ok=True)
        for name in names:shutil.copy2(ROOT/'godot_project'/folder/name,dest/name)
    (STAGE/'project.godot').write_text('config_version=5\n[application]\nconfig/name="TaehwaCivilIsolated"\n[display]\nwindow/size/viewport_width=1200\nwindow/size/viewport_height=760\n[rendering]\nrenderer/rendering_method="gl_compatibility"\nshader_compiler/shader_cache/enabled=false\ntextures/default_filters/use_nearest_mipmap_filter=false\n',encoding='utf-8')
    print(json.dumps({'models':len(catalog['models']),'hydro_chunks':len(chunks),'water_triangles':sum(c['triangles'] for c in chunks),'source_unchanged':survey.source_hash==__import__('hashlib').sha256(survey.source.read_bytes()).hexdigest()}))


if __name__=='__main__':main()
