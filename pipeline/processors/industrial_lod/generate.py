"""원본 28종을 보존하고 공단 원경·초원경 자산을 별도 등록한다."""
import hashlib
import json
from pathlib import Path
import shutil
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from industrial_lod.models import build
from industrial_lod.scene import static_scene,auto_scene
from industrial.preview import render
from custom_lowpoly.glb import export,inspect
from vessels.mesh import PALETTE
from rail_bridge_lowpoly.publish import update

ROOT=Path(__file__).resolve().parents[3]
ASSETS=ROOT/"godot_project/assets/generated"
OUT=ASSETS/"industrial_lod"
REPORT=ROOT/"results/261009_industrial_lod"
URI="res://assets/generated/industrial_lod"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    REPORT.mkdir(parents=True,exist_ok=True)
    protected={}
    for family in ("industrial","industrial_plant","industrial_lighting"):
        for p in (ASSETS/family).rglob("*"):
            if p.is_file() and p.suffix not in (".import",".uid"):
                protected[str(p.relative_to(ROOT))]=digest(p)
    catalogs={f:json.loads((ASSETS/f/"catalog.json").read_text(encoding="utf-8"))["assets"]
              for f in ("industrial","industrial_plant")}
    entries={}; selectors={}; models=[]; comparisons=[]
    for family,catalog in catalogs.items():
        for key,source_meta in catalog.items():
            source=ASSETS/family/(key+".glb")
            if not source.exists(): continue
            before=inspect(source)
            folder=OUT/family; folder.mkdir(exist_ok=True)
            size=max(source_meta["aabb_max_m"][i]-source_meta["aabb_min_m"][i] for i in range(3))
            distances=[max(350,round(size*5)),max(1200,round(size*15)),max(10000,round(size*75))]
            counts=[]
            for level in (1,2):
                mesh=build(key,level)
                name=f"{key}_lod{level}"
                path=folder/(name+".glb")
                export(mesh,path,name,{"steel":PALETTE["steel"]})
                after=inspect(path)
                if after["triangles"]>=before["triangles"]:
                    raise RuntimeError("원본보다 가벼워야 함: "+str(path))
                points=[p for f in mesh.faces for p in f[:3]]
                low=[min(p[i] for p in points) for i in range(3)]
                high=[max(p[i] for p in points) for i in range(3)]
                meta={"label_ko":source_meta["label_ko"]+f" LOD{level}","source_asset":f"{family}/{key}",
                      "source_sha256":digest(source),"source_scene":"res://assets/generated/"+family+"/"+key+".tscn",
                      "source_triangles":before["triangles"],"triangles":after["triangles"],
                      "triangle_count_method":"gltf_primitive_indices","lod_level":level,
                      "reduction_percent":round(100*(1-after["triangles"]/before["triangles"]),2),
                      "detail_profile":"industrial_distance_silhouette_v1","surface_count":1,
                      "units":"meters","ground_y_m":0,"origin_preserved":True,
                      "aabb_min_m":low,"aabb_max_m":high,"source_aabb_min_m":source_meta["aabb_min_m"],
                      "source_aabb_max_m":source_meta["aabb_max_m"],"bbox":None,"resolution":None,
                      "elevation_min":low[1],"elevation_max":high[1],"georeferenced":False,
                      "pipe_connectors_m":source_meta.get("pipe_connectors_m",[]),
                      "pipe_connector_directions":source_meta.get("pipe_connector_directions",[]),
                      "smoke_outlets_m":source_meta.get("smoke_outlets_m",[]),
                      "external_textures":False,"collision_count":0,"local_light_count":0,"particle_count":0,
                      "casts_shadows":False,"lod_distances_m":distances,
                      "limitations":"실루엣 재구성. 사다리·난간·세부 트러스·부속물 생략. 초원경 배관은 3열 묶음. 동일 원점, 외곽 AABB는 상세 모델과 다를 수 있음."}
                uri=f"{URI}/{family}/{name}.glb"
                scene=path.with_suffix(".tscn")
                scene.write_text(static_scene(name,uri,meta),encoding="utf-8")
                entries[f"{family}_{name}"]={"file_path":uri,"scene_path":uri[:-4]+".tscn","format":"GLB",
                    "type":"industrial_distant_model","sha256":digest(path),"size_bytes":path.stat().st_size,
                    "scene_sha256":digest(scene),"metadata":meta}
                counts.append(after["triangles"])
                models.append((f"{family}_{name}",meta["label_ko"],mesh))
            selector=folder/(key+"_auto_lod.tscn")
            selector.write_text(auto_scene(key,family,URI,distances),encoding="utf-8")
            selectors[f"{family}_{key}_auto_lod"]={"file_path":f"{URI}/{family}/{key}_auto_lod.tscn",
                "format":"TSCN","type":"industrial_lod_selector","sha256":digest(selector),
                "size_bytes":selector.stat().st_size,"metadata":{"source_asset":f"{family}/{key}",
                    "lod_distances_m":distances,"bbox":None,"resolution":None,
                    "elevation_min":source_meta["aabb_min_m"][1],"elevation_max":source_meta["aabb_max_m"][1]}}
            comparisons.append({"asset":f"{family}/{key}","before":before["triangles"],"lod1":counts[0],"lod2":counts[1],
                                "source_bytes":before["size_bytes"],"lod1_bytes":(folder/(key+"_lod1.glb")).stat().st_size,
                                "lod2_bytes":(folder/(key+"_lod2.glb")).stat().st_size})
    # 각 원경 메시의 그림자 비용을 제거한다. GLB 기본 노드는 아래 스크립트로 제어한다.
    shutil.copy2(Path(__file__).with_name("lod_selector.gd"),OUT/"lod_selector.gd")
    shutil.copy2(Path(__file__).with_name("far_visual.gd"),OUT/"far_visual.gd")
    for relative,expected in protected.items():
        if digest(ROOT/relative)!=expected: raise RuntimeError("원본 동시 변경으로 보류: "+relative)
    dependencies={name:digest(OUT/name) for name in ("lod_selector.gd","far_visual.gd")}
    update(OUT/"manifest.json",lambda d:d.update({"version":1,"assets":entries,"selectors":selectors,"dependencies_sha256":dependencies}))
    update(OUT/"catalog.json",lambda d:d.update({"version":1,"assets":entries,"selectors":selectors,"comparisons":comparisons}))
    update(ASSETS/"manifest.json",lambda d:d.setdefault("assets",{}).update({"industrial_lod_"+k:v for k,v in {**entries,**selectors}.items()}))
    summary={"base_models":len(comparisons),"derived_models":len(entries),"auto_lod_scenes":len(comparisons),
             "triangles_total":{k:sum(c[k] for c in comparisons) for k in ("before","lod1","lod2")},
             "comparisons":comparisons,"source_hashes_preserved":protected}
    (REPORT/"generation.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
    for level in (1,2):
        render([m for m in models if m[0].endswith(f"lod{level}")],OUT/f"lod{level}_preview.png")
    (OUT/"README.md").write_text("# 공단 원경 에셋\n\n28종에 각각 원경 LOD1·초원경 LOD2, 선택형 auto_lod 씬을 제공한다.\n\n- GLB는 단일 표면·무광 단색, 외부 텍스처 없음.\n- 개별 원경 씬에는 실제 광원·충돌·파티클 없음. 연결·배출구 마커는 보존.\n- auto_lod는 근경 원본과 원경 2단계를 0.25초마다 선택한다. 5% 히스테리시스 사용.\n- 기본 거리 350/1200/10000m 이상이며 모델 크기에 따라 확대. 카탈로그 참조.\n- 대량 반복 배치는 GLB를 MultiMesh로 구성하는 것을 권장. 자동 씬은 개별 확인·소규모 사용용.\n- 게임·공단 배치 데이터에는 자동 적용하지 않음. 전체 맵 성능 검증 없음.\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in summary.items() if k not in ("comparisons","source_hashes_preserved")},ensure_ascii=True))


if __name__=="__main__": main()
