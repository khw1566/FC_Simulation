"""저다각형 항구 모듈 생성. 지리 배치나 게임 연결을 수행하지 않는다."""
import json
import os
from pathlib import Path
import sys
import shutil
import struct

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from harbor_assets import breakwaters,quays,lighthouses,cranes,containers,infrastructure,assemblies
from harbor_assets.scenes import scene,assembly
from harbor_assets.publish import publish
from harbor_assets.mesh import PALETTE
from simple_maps.publish import atomic
from custom_lowpoly.glb import inspect

OUTPUT=ROOT/"godot_project/assets/generated/harbor_assets"


def write(path,text):
    temporary=path.with_name(path.name+f".{os.getpid()}.pending")
    temporary.write_text(text,encoding="utf-8"); os.replace(temporary,path)


def emission(path):
    data=path.read_bytes(); size,_=struct.unpack_from("<II",data,12)
    doc=json.loads(data[20:20+size]); binary=data[20+size:]
    doc["asset"]["generator"]="Kanmon modular low-poly harbor assets"
    for material in doc["materials"]:
        if material["name"].startswith("lens_"):
            material["emissiveFactor"]=list(PALETTE[material["name"]])
    payload=json.dumps(doc,separators=(",",":")).encode(); payload+=b" "*(-len(payload)%4)
    path.write_bytes(struct.pack("<III",0x46546C67,2,20+len(payload)+len(binary))+struct.pack("<II",len(payload),0x4E4F534A)+payload+binary)


def main():
    OUTPUT.mkdir(parents=True,exist_ok=True)
    lock=OUTPUT/"generation.lock"
    descriptor=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY)
    try:
        config=json.loads((ROOT/"config/harbor_assets.json").read_text(encoding="utf-8"))
        assets=[asset for module in (breakwaters,quays,lighthouses,cranes,containers,infrastructure) for asset in module.build()]
        models={a.key:a for a in assets}; assert len(models)==len(assets)
        catalog={"version":1,"family":"harbor_assets","config":config,"models":{},"assemblies":{},"connections_checked":0}
        for asset in assets:
            if len(asset.mesh.faces)>config["max_triangles_per_model"]: raise ValueError("삼각형 예산 초과: "+asset.key)
            path=OUTPUT/(asset.key+".glb"); temporary=path.with_suffix(".glb.pending")
            asset.mesh.export(temporary,asset.key); emission(temporary); os.replace(temporary,path)
            assert inspect(path)["triangles"]==len(asset.mesh.faces)
            text=scene(asset)
            assert all(f'name="{port["name"]}" type="Marker3D"' in text for port in asset.ports)
            write(path.with_suffix(".tscn"),text)
            catalog["models"][asset.key]={"scene_path":"res://assets/generated/harbor_assets/"+asset.key+".tscn",**asset.metadata()}
        for key,example in assemblies.specs().items():
            catalog["connections_checked"]+=assemblies.validate(models,example)
            example.update(assemblies.bounds(models,example,ROOT/"godot_project"))
            catalog["assemblies"][key]=example
            write(OUTPUT/(key+".tscn"),assembly(key,example))
        atomic(OUTPUT/"catalog.json",catalog)
        shutil.copy2(Path(__file__).parent/"README.md",OUTPUT/"README.md")
        from road_assets import preview
        preview.PALETTE=PALETTE
        selection=["breakwater_straight_12m","breakwater_curve_90","breakwater_head","tetrapod_2.5m",
            "lighthouse_red","lighthouse_green","lighthouse_square","lighthouse_lattice",
            "fishing_crane_post","fishing_crane_hydraulic","container_crane_sts","container_crane_rtg",
            "container_6m_blue","container_stack_3x2x3","quay_12x12_sea_edge","quay_ramp_rise2m",
            "pier_pile_8m","fishing_shed","fish_auction","shore_power_water"]
        preview.render([(models[key].label,models[key].mesh) for key in selection],OUTPUT/"preview.png","저다각형 항구 에셋 / 대표 20종",columns=4)
        preview.render([(value["label_ko"],assemblies.combined(models,value)) for value in catalog["assemblies"].values()],OUTPUT/"assembly_preview.png","항구 혼합 조립 / 실제 지형 배치 전 예제",columns=3,cell_width=600,cell_height=420)
        report=publish(ROOT,OUTPUT,catalog,models)
        print(json.dumps(report,ensure_ascii=False),flush=True)
    finally:
        os.close(descriptor); lock.unlink()


if __name__=="__main__": main()
