"""독립 도로 에셋 생성과 카탈로그·매니페스트·모듈 색인 등록."""
import hashlib
import json
import math
import os
import struct
import sys
from collections import Counter
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from road_assets import profiles, surfaces, accessories, assembly, preview
from simple_maps.publish import atomic, merge

OUT=ROOT/"godot_project/assets/generated/road_assets"
URI=assembly.URI


def write(path,text):
    temporary=path.with_name(path.name+f".{os.getpid()}.tmp")
    temporary.write_text(text,encoding="utf-8"); os.replace(temporary,path)


def metadata(mesh, ports, info):
    points=[p for f in mesh.faces for p in f[:3]]
    if not points: raise ValueError("빈 메시")
    if not all(math.isfinite(v) for p in points for v in p): raise ValueError("유효하지 않은 좌표")
    lo=[min(p[k] for p in points) for k in range(3)]; hi=[max(p[k] for p in points) for k in range(3)]
    return {**info,"units":"meters","ground_y_m":0,"surface_y_m":ports[0]["position_m"][1] if ports else None,
        "aabb_min_m":lo,"aabb_max_m":hi,"footprint_xz_m":[lo[0],lo[2],hi[0],hi[2]],
        "bbox":None,"elevation_min":lo[1],"elevation_max":hi[1],
        "resolution":{"type":"triangle_mesh","triangles":len(mesh.faces)},
        "ports":ports,"scale_range":[1,1],"surveyed":False,"georeferenced":False,
        "runtime_applied":False,"collision_included":False}


def generate():
    OUT.mkdir(parents=True,exist_ok=True)
    config={"version":1,"length_m":profiles.LENGTH,"lane_width_m":profiles.LANE_WIDTH,
        "walk_surface_y_m":profiles.WALK_HEIGHT,"walk_widths_m":[1.5,3,4.5],
        "lane_count_policy":"total_lanes","road_types":profiles.ROAD_TYPES,
        "walk_types":profiles.WALK_TYPES,"palette":preview.PALETTE,
        "usage_ko":"생성만 수행한다. 게임 실행·지도·기존 도로 렌더러에 연결하지 않는다."}
    config_path=ROOT/"config/road_assets.json"
    if config_path.exists():
        original=json.loads(config_path.read_text(encoding="utf-8-sig"))
        for key in ("length_m","lane_width_m","walk_surface_y_m","walk_widths_m","lane_count_policy","road_types","walk_types","palette"):
            if original.get(key)!=json.loads(json.dumps(config[key])):
                raise RuntimeError("규격 설정은 profiles.py와 mesh.py에서 수정 후 config/road_assets.json도 갱신한다: "+key)
    else: atomic(config_path,config)
    meshes={}; catalog={}
    def save(key,label,mesh,ports,info,overlay=None):
        meta=metadata(mesh,ports,{"label_ko":label,**info})
        temp=OUT/f"{key}.glb.{os.getpid()}.tmp"; mesh.export(temp,key)
        data=temp.read_bytes()
        if struct.unpack_from("<III",data)!=(0x46546C67,2,len(data)): raise RuntimeError("GLB 헤더 오류: "+key)
        os.replace(temp,OUT/f"{key}.glb")
        write(OUT/f"{key}.tscn",assembly.model_scene(key,ports,overlay))
        meta.update(scene_path=URI+key+".tscn",model_path=URI+key+".glb",detachable_marking=overlay)
        catalog[key]=meta; meshes[key]=mesh
    for lanes in range(1,9):
        for shape in ("straight","curve45","curve90"):
            key=f"lane_overlay_{lanes}l_{shape}"
            save(key,f"{lanes}차선 표시 / {shape}",surfaces.marking(lanes,shape),[],
                 {"kind":"lane_overlay","lanes":lanes,"shape":shape,"placement_y_m":0})
    for spec in profiles.specs():
        mesh,ports=surfaces.build(spec)
        overlay=f"lane_overlay_{spec['lanes']}l_{spec['shape']}" if spec["kind"]=="road" and spec["style"]!="gravel" else None
        save(spec["key"],spec["label_ko"],mesh,ports,{k:v for k,v in spec.items() if k not in ("key","label_ko")},overlay)
    for shape in ("tee","cross"):
        for lanes in (2,4):
            mesh,ports,info=accessories.junction("road","urban",lanes,shape)
            save(f"road_urban_{lanes}l_{shape}",f"도시 {lanes}차선 {shape} 교차로",mesh,ports,info)
        for style in ("concrete","paver_gray","brick_running","stone_large","wood_cross","gravel"):
            mesh,ports,info=accessories.junction("walk",style,0,shape)
            save(f"walk_{style}_w3_{shape}",f"{profiles.WALK_TYPES[style][0]} / {shape} 분기",mesh,ports,info)
    for start,end in ((1,2),(2,4),(4,6),(6,8)):
        mesh,ports=accessories.transition("vehicle",start*profiles.LANE_WIDTH+1,end*profiles.LANE_WIDTH+1,
                                         start_lanes=start,end_lanes=end)
        save(f"road_lanes_{start}_to_{end}",f"{start}→{end}차선 전환부",mesh,ports,
             {"kind":"transition","transition_kind":"vehicle","start_lanes":start,"end_lanes":end})
    for start,end in ((1.5,3),(3,4.5)):
        mesh,ports=accessories.transition("walk",start,end,.15,.15)
        save(f"walk_width_{start:g}_to_{end:g}",f"보행로 폭 {start:g}→{end:g}m 전환부",mesh,ports,
             {"kind":"transition","transition_kind":"walk"})
    mesh,ports=accessories.transition("walk",3,3,0,.15)
    save("walk_curb_ramp_w3","보도 턱 낮춤 경사로",mesh,ports,{"kind":"transition","transition_kind":"walk","slope":.15/12})
    for key,label in accessories.ACCESSORIES.items():
        mesh,ports=accessories.accessory(key)
        save("addon_"+key,label,mesh,ports,{"kind":"accessory","placement_y_m":0})
    for key,label in accessories.DECALS.items():
        save("mark_"+key,label,accessories.decal(key),[],{"kind":"marking","placement_y_m":0})
    demo,placements=assembly.example(); write(OUT/"road_walk_mix_demo.tscn",demo)
    counts=dict(Counter(meta["kind"] for meta in catalog.values()))
    atomic(OUT/"catalog.json",{"version":1,"note_ko":"범용 게임 에셋. 실제 위치와 교통 규정의 재현을 보증하지 않는다.",
        "connector_axis":"-Z outward","lane_count_policy":"total_lanes","assets":catalog,
        "counts":counts,"walk_style_count":len(profiles.WALK_TYPES),"runtime_applied":False,
        "assembly_demo":{"scene_path":URI+"road_walk_mix_demo.tscn","placements":placements},
        "mix_rules":{"match":["profile.kind","profile.width_m","profile.surface_y_m"],
            "vehicle_match":["profile.lane_count"],"socket_rotation":"opposite outward directions",
            "scale":1,"material_change":"same width and height can use different styles",
            "width_change":"use transition modules","height_change":"use ramp or steps",
            "decorations":"use GroundOrigin and local footprint; do not occupy walking clearance",
            "external_families":["industrial","taehwagang","pedestrian_bridges","railway"]}})
    road_cards=[]
    for lanes in range(1,9):
        key=f"road_urban_{lanes}l_straight"
        visual=preview.combine([{ "asset":key,"position_m":[0,0,0],"rotation_y":0},
            {"asset":catalog[key]["detachable_marking"],"position_m":[0,0,0],"rotation_y":0}],meshes)
        road_cards.append((f"도시 도로 / 총 {lanes}차선",visual))
    for style in ("rural","highway","industrial","residential","gravel","concrete"):
        lanes=profiles.ROAD_TYPES[style][2][0]; key=f"road_{style}_{lanes}l_straight"
        road_cards.append((profiles.ROAD_TYPES[style][0],meshes[key]))
    for key in ("road_urban_4l_curve90","road_urban_2l_tee","road_lanes_2_to_4","road_lanes_6_to_8"):
        road_cards.append((catalog[key]["label_ko"],meshes[key]))
    preview.render(road_cards,OUT/"preview_roads.png","도로 / 1~8차선 · 7유형 · 접속부")
    preview.render([(profiles.WALK_TYPES[k][0],meshes[f"walk_{k}_w3_straight"]) for k in profiles.WALK_TYPES],
                   OUT/"preview_walks.png","보행로 / 24개 표면 유형 · 공통 연결 규격")
    selected=["walk_paver_gray_w3_curve90","walk_wood_cross_w3_curve90","walk_gravel_w3_curve90",
              "walk_concrete_w3_tee","walk_stone_large_w3_cross","walk_width_1.5_to_3","walk_curb_ramp_w3"]
    selected+= ["addon_"+key for key in accessories.ACCESSORIES]
    selected+= ["mark_zebra_crossing","mark_arrow_left","mark_cycle_symbol"]
    preview.render([(catalog[k]["label_ko"],meshes[k]) for k in selected],OUT/"preview_connectors.png","혼합용 모듈 / 곡선 · 분기 · 폭 전환 · 경계 · 노면 표시")
    visual_placements=placements[:]
    for item in placements:
        overlay=catalog[item["asset"]].get("detachable_marking")
        if overlay: visual_placements.append({**item,"asset":overlay})
    preview.render([("차도·블록·목재·석재·흙길 혼합 조립",preview.combine(visual_placements,meshes))],
                   OUT/"preview_mix.png","독립 혼합 조립 예제 / 게임 미적용",columns=1,cell_width=1200,cell_height=1000)
    entries={}
    for path in sorted(OUT.iterdir()):
        if path.suffix not in (".glb",".tscn",".json",".png",".md") or path.name=="manifest.json": continue
        meta=catalog.get(path.stem,{})
        if path.suffix==".png":
            with Image.open(path) as image: resolution={"width":image.width,"height":image.height}
        else: resolution=meta.get("resolution")
        entries[path.name]={"file_path":URI+path.name,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
            "size_bytes":path.stat().st_size,"type":"modular_road_asset","metadata":meta,
            "bbox":None,"elevation_min":meta.get("elevation_min"),"elevation_max":meta.get("elevation_max"),
            "resolution":resolution}
    atomic(OUT/"manifest.json",{"version":1,"assets":entries})
    merge(OUT.parent/"manifest.json",{"road_assets/"+k:v for k,v in entries.items()})
    modules=[]
    for path in sorted(Path(__file__).parent.glob("*.py")):
        source=path.read_text(encoding="utf-8")
        if len(source.splitlines())>=600: raise RuntimeError("모듈 분리가 필요하다: "+path.name)
        modules.append({"path":path.relative_to(ROOT).as_posix(),"lines":len(source.splitlines()),
                        "responsibility":source.splitlines()[0].strip('"')})
    for path in (ROOT/"module_index.json",ROOT/"godot_project/module_index.json"):
        before=path.read_bytes(); document=json.loads(before)
        section=next(k for k in document if k!="metadata" and isinstance(document[k],dict))
        document[section]["road_assets"]={"description":"혼합 조립용 독립 도로·보행로 에셋", "modules":modules}
        if path.read_bytes()!=before: raise RuntimeError("모듈 색인 동시 변경: 재실행 필요")
        atomic(path,document)
    print(json.dumps({"models":len(catalog),"counts":counts,"walk_styles":len(profiles.WALK_TYPES),"runtime_applied":False},ensure_ascii=False))

    if (Path(__file__).parent/"extensions.py").exists():
        from road_assets.extensions import generate as generate_extensions
        generate_extensions()


if __name__=="__main__":
    OUT.mkdir(parents=True,exist_ok=True)
    lock=OUT/"generation.lock"
    descriptor=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY)
    try: generate()
    finally:
        os.close(descriptor); lock.unlink()
