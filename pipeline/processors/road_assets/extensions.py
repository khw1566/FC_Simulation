"""기존 에셋을 보존하며 혼합 교차로·데크 확장만 생성하고 등록."""
import hashlib
import json
import os
import struct
import sys
from collections import Counter
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from road_assets import junctions,decks,assembly,extension_assembly,preview,cached_mesh
from road_assets.generate import metadata,write
from simple_maps.publish import atomic,merge

OUT=ROOT/"godot_project/assets/generated/road_assets"
SET="mixed_junction_deck_v1"


def generate():
    catalog_path=OUT/"catalog.json"; before=catalog_path.read_bytes(); document=json.loads(before)
    catalog=document["assets"]; meshes={}; added=[]
    for key,label,mesh,ports,info in list(junctions.models())+list(decks.models()):
        if key in catalog and catalog[key].get("extension_set")!=SET: raise RuntimeError("기존 에셋 이름 충돌: "+key)
        meta=metadata(mesh,ports,{"label_ko":label,"extension_set":SET,"detail_profile":"low_poly_flat_v1","external_textures":False,"material_style":"flat_color_coarse_lines",**info})
        temporary=OUT/f"{key}.glb.{os.getpid()}.tmp"; mesh.export(temporary,key)
        data=temporary.read_bytes()
        if struct.unpack_from("<III",data)!=(0x46546C67,2,len(data)): raise RuntimeError("GLB 오류: "+key)
        os.replace(temporary,OUT/f"{key}.glb")
        overlay=info.get("suggested_marking")
        write(OUT/f"{key}.tscn",assembly.model_scene(key,ports,overlay))
        catalog[key]={**meta,"scene_path":assembly.URI+key+".tscn","model_path":assembly.URI+key+".glb",
                      "detachable_marking":overlay}
        added.append(key); meshes[key]=mesh
    items=extension_assembly.placements()
    for p in items:
        key=p["asset"]
        if key not in catalog: raise RuntimeError("조립 부품 누락: "+key)
        if key not in meshes: meshes[key]=cached_mesh.read(OUT/(key+".glb"))
    visuals=items[:]
    for p in items:
        overlay=catalog[p["asset"]].get("detachable_marking")
        if overlay:
            if overlay not in meshes: meshes[overlay]=cached_mesh.read(OUT/(overlay+".glb"))
            visuals.append({**p,"asset":overlay})
    write(OUT/"mixed_intersection_deck_demo.tscn",extension_assembly.scene(items))
    road_cards=[]
    for main,branch in junctions.PAIRS:
        for shape in ("tee","cross"):
            parts=extension_assembly.junction_parts(main,branch,shape)
            road_cards.append((f"{main}·{branch}차선 / {'T자' if shape=='tee' else '십자'} 혼합",preview.combine(parts,meshes)))
    preview.render(road_cards,OUT/"preview_mixed_junctions.png","혼합 교차로 / 중앙부·진입부·횡단 표시 분리")
    keys=["deck_wood_long_w3_straight","deck_weathered_w3_straight","deck_wood_cross_w3_curve90","deck_stone_w3_curve45",
          "deck_stone_plaza_6m","deck_wood_cross_plaza_12m","deck_wood_long_w3_tee","deck_weathered_w3_cross",
          "deck_ramp_w3_rise1m","deck_rail_wood_6m","deck_rail_cable_w3_curve90_right","deck_rail_steel_rise1m",
          "deck_rail_steel_1.5m","deck_support_w3_h1.5","deck_support_w4.5_h3","deck_support_w3_h6"]
    preview.render([(catalog[k]["label_ko"],meshes[k]) for k in keys],OUT/"preview_decks.png","보행 데크 / 직선·곡선·광장·분기·경사·난간·지지대")
    preview.render([("서로 다른 차도·기존 보행로·데크·높이 전환의 혼합",preview.combine(visuals,meshes))],
                   OUT/"preview_junction_deck_mix.png","교차로·보행 데크 혼합 예제 / 게임 미적용",columns=1,cell_width=1400,cell_height=1100)
    document["counts"]=dict(Counter(v["kind"] for v in catalog.values()))
    document["extensions"]={**document.get("extensions",{}),SET:{"model_count":len(added),"asset_keys":added,
        "demo_scene":assembly.URI+"mixed_intersection_deck_demo.tscn","placements":items,
        "connection_rules_ko":["기존 보행로와 데크는 walk 단면의 폭·표면 높이를 맞춘다.",
            "교차로 진입부의 안쪽 포트를 중앙부와 결합한다. 바깥 포트는 기존 차도와 결합한다.",
            "횡단 표시를 사용하려면 모든 해당 진입부를 먼저 배치한다.",
            "광장 포트는 중앙 3m 개구부다. 남는 가장자리는 마감 난간으로 닫는다.",
            "곡선 난간은 같은 폭·곡선 모듈과 원점을 맞추고 Y=0.15m에 둔다.",
            "지지대 상단을 프레임의 support_mount_y_m에 맞춘다."],
        "runtime_applied":False}}
    if catalog_path.read_bytes()!=before: raise RuntimeError("카탈로그 동시 변경: 재실행 필요")
    atomic(catalog_path,document)
    manifest_path=OUT/"manifest.json"; manifest_before=manifest_path.read_bytes()
    manifest=json.loads(manifest_before)
    names=[name for key in added for name in (key+".glb",key+".tscn")]
    names += ["catalog.json","README.md","MIXED_JUNCTION_DECK_GUIDE.md","mixed_intersection_deck_demo.tscn",
              "preview_mixed_junctions.png","preview_decks.png","preview_junction_deck_mix.png"]
    entries={}
    for name in names:
        path=OUT/name; meta=catalog.get(path.stem,{})
        if path.suffix==".png":
            with Image.open(path) as image: resolution={"width":image.width,"height":image.height}
        else: resolution=meta.get("resolution")
        entries[name]={"file_path":assembly.URI+name,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
            "size_bytes":path.stat().st_size,"type":"modular_road_asset","metadata":meta,
            "bbox":None,"elevation_min":meta.get("elevation_min"),"elevation_max":meta.get("elevation_max"),"resolution":resolution}
    manifest.setdefault("assets",{}).update(entries)
    if manifest_path.read_bytes()!=manifest_before: raise RuntimeError("매니페스트 동시 변경: 재실행 필요")
    atomic(manifest_path,manifest);merge(OUT.parent/"manifest.json",{"road_assets/"+k:v for k,v in entries.items()})
    modules=[]
    for path in sorted(Path(__file__).parent.glob("*.py")):
        source=path.read_text(encoding="utf-8")
        if len(source.splitlines())>=600: raise RuntimeError("모듈 분리 필요: "+path.name)
        modules.append({"path":path.relative_to(ROOT).as_posix(),"lines":len(source.splitlines()),
                        "responsibility":source.splitlines()[0].strip('"')})
    for path in (ROOT/"module_index.json",ROOT/"godot_project/module_index.json"):
        original=path.read_bytes(); doc=json.loads(original)
        section=next(k for k in doc if k!="metadata" and isinstance(doc[k],dict))
        doc[section]["road_assets"]={"description":"혼합 도로·보행로·교차로·데크 독립 에셋","modules":modules}
        if path.read_bytes()!=original: raise RuntimeError("모듈 인덱스 동시 변경")
        atomic(path,doc)
    print(json.dumps({"added_models":len(added),"added_counts":dict(Counter(catalog[k]["kind"] for k in added)),
                      "total_models":len(catalog),"runtime_applied":False},ensure_ascii=False))


if __name__=="__main__":
    lock=OUT/"generation.lock"; descriptor=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY)
    try: generate()
    finally:
        os.close(descriptor); lock.unlink()
