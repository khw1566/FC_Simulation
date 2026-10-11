"""공원 공용 군락을 전용 경로에 생성하고 메타데이터를 병합한다."""
import hashlib
import json
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
    __package__="park_vegetation"
from .models import SPECS,build,ports
from .glb import export
from .scenes import write_support,write_compositions
from rail_bridge_lowpoly.publish import update


def main():
    root=Path(__file__).resolve().parents[3]
    out=root/"godot_project/assets/generated/park_vegetation"
    out.mkdir(parents=True,exist_ok=True)
    assets={}; models=[]
    for key,(label,kind,distances,width) in SPECS.items():
        stages=[]
        for lod,end in enumerate(distances):
            mesh=build(key,lod)
            path=out/f"{key}_lod{lod}.glb"
            export(mesh,path,f"{key}_lod{lod}")
            points=[p for f in mesh.faces for p in f[:3]]
            low=[min(p[i] for p in points) for i in range(3)]
            high=[max(p[i] for p in points) for i in range(3)]
            uri="res://"+path.relative_to(root/"godot_project").as_posix()
            metadata={"family":kind,"model_id":key,"lod_level":lod,"triangles":len(mesh.faces),
                "surfaces":1,"bbox":None,"resolution":None,"aabb_min_m":low,"aabb_max_m":high,
                "elevation_min":low[1],"elevation_max":high[1],"placement_status":"asset_only",
                "detail_profile":"park_opaque_vertex_v1","visibility_begin_m":0 if lod==0 else distances[lod-1],
                "visibility_end_m":end,"connection_ports":ports(key),"species_status":"generic_procedural",
                "external_textures":False,"collision_shapes":0}
            assets[path.name]={"file_path":uri,"scene_path":uri,"format":"GLB","type":"park_model",
                "size_bytes":path.stat().st_size,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"metadata":metadata}
            stages.append({"path":uri,**metadata})
        models.append({"id":key,"label":label,"kind":kind,"lods":stages,"connection_ports":ports(key)})
    write_support(out)
    write_compositions(root,out,models)
    for path in out.rglob("*"):
        if not path.is_file() or path.name in ("manifest.json","catalog.json") or path.name in assets: continue
        uri="res://"+path.relative_to(root/"godot_project").as_posix()
        assets[path.relative_to(out).as_posix()]={"file_path":uri,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
            "size_bytes":path.stat().st_size,"metadata":{"bbox":None,"resolution":None,"elevation_min":None,
            "elevation_max":None,"placement_status":"asset_only","detail_profile":"park_opaque_vertex_v1"}}
    catalog={"version":1,"units":"metres","up_axis":"Y","origin":"ground","models":models,
        "ground_profiles":["lawn","meadow","soil","gravel","bamboo_litter"],
        "batch":{"cell_size_m":32,"shadows":False,"lod_policy":"per_instance_distance_range"},
        "status":"generic_procedural_not_site_survey"}
    (out/"catalog.json").write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding="utf-8")
    update(out/"manifest.json",lambda doc:doc.update(version=1,assets=assets))
    def merge(doc):
        entries=doc.setdefault("assets",{})
        for key,value in assets.items(): entries["park_vegetation/"+key]=value
    update(root/"godot_project/assets/generated/manifest.json",merge)
    print(f"PARK GENERATED: {len(models)} kinds, {sum(len(m['lods']) for m in models)} LOD models")


if __name__=="__main__": main()
