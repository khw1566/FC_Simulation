"""전용 GLB, 조사 카탈로그, 격리 Godot 작업 공간을 생성한다."""
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
    __package__="ulsan_dams"
from .geometry import build, PALETTE
from custom_lowpoly.glb import export

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/"godot_project/assets/generated/ulsan_dams"
STAGE=ROOT/"previews/ulsan_dams/project"


def main():
    spec=json.loads((ROOT/"config/ulsan_dams.json").read_text(encoding="utf-8"))
    OUT.mkdir(parents=True,exist_ok=True)
    STAGE.mkdir(parents=True,exist_ok=True)
    catalog={**spec,"palette":PALETTE,"models":[]}
    for dam in spec["dams"]:
        lods=[]
        for far in (False,True):
            lod="far" if far else "near"
            mesh=build(dam,spec["model_policy"],far)
            path=OUT/f"{dam['id']}_{lod}.glb"
            export(mesh,path,path.stem,PALETTE)
            points=[p for f in mesh.faces for p in f[:3]]
            lods.append({"lod":lod,"file_path":"res://assets/generated/ulsan_dams/"+path.name,
                         "triangles":len(mesh.faces),"size_bytes":path.stat().st_size,
                         "sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
                         "aabb_min_m":[min(p[i] for p in points) for i in range(3)],
                         "aabb_max_m":[max(p[i] for p in points) for i in range(3)]})
            shutil.copy2(path,STAGE/path.name)
        a,b=dam["axis_lonlat"]
        lat=(a[1]+b[1])/2
        dx=(b[0]-a[0])*111320*math.cos(math.radians(lat))
        dz=(a[1]-b[1])*111320
        catalog["models"].append({**dam,"anchor":{"lon":(a[0]+b[0])/2,"lat":lat},
              "axis_length_m":math.hypot(dx,dz),"axis_yaw_rad":math.atan2(-dz,dx),
              "scene_path":f"res://assets/generated/ulsan_dams/{dam['id']}.tscn","lods":lods})
    (OUT/"catalog.json").write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding="utf-8")
    shutil.copy2(OUT/"catalog.json",STAGE/"catalog.json")
    (STAGE/"project.godot").write_text('config_version=5\n[application]\nconfig/name="UlsanDamsIsolated"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n[display]\nwindow/size/viewport_width=1100\nwindow/size/viewport_height=680\n',encoding="utf-8")
    for name in ("bake.gd","preview.gd","fixture.gd","terrain_fixture.gd"):
        shutil.copy2(Path(__file__).with_name(name),STAGE/name)
    (STAGE/"scripts/terrain").mkdir(parents=True,exist_ok=True)
    for name in ("dam_landmark_manager.gd","dam_terrain_fit.gd"):
        source=ROOT/"godot_project/scripts/terrain"/name
        shutil.copy2(source,STAGE/"scripts/terrain"/name)
        shutil.copy2(source,STAGE/name)
    print(f"울산 댐 {len(catalog['models'])}종, GLB 10개 생성")


if __name__=="__main__":
    main()
