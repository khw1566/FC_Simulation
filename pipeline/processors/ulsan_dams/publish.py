"""전용 씬과 조사 근거를 게시하고 비대상 매니페스트 항목을 보존한다."""
import hashlib
import json
import shutil
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
    __package__="ulsan_dams"
from rail_bridge_lowpoly.publish import update
from .generate import ROOT,OUT,STAGE


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    fixture=json.loads((STAGE/"fixture_results.json").read_text(encoding="utf-8"))
    assert fixture["passed"]
    catalog=json.loads((OUT/"catalog.json").read_text(encoding="utf-8"))
    assets={}
    for spec in catalog["models"]:
        scene=STAGE/f"{spec['id']}.tscn"
        assert scene.is_file() and "ext_resource" not in scene.read_text(encoding="utf-8")
        shutil.copy2(scene,OUT/scene.name)
        a,b=spec["axis_lonlat"]
        bbox={"west":min(a[0],b[0]),"east":max(a[0],b[0]),"south":min(a[1],b[1]),"north":max(a[1],b[1])}
        for path in [OUT/scene.name]+[OUT/f"{spec['id']}_{lod}.glb" for lod in ("near","far")]:
            lod=next((item for item in spec["lods"] if path.name.endswith(item["lod"]+".glb")),None)
            triangles=lod["triangles"] if lod else sum(item["triangles"] for item in spec["lods"])
            metadata={"label_ko":spec["name_ko"],"detail_profile":"ulsan_dam_low_poly_v1",
                      "model_id":spec["id"],"status":"research_based_simplified",
                      "bbox":None,"axis_bbox":bbox,"resolution":None,
                      "elevation_min":-spec["official_height_m"],"elevation_max":.72,
                      "elevation_reference":"local_crest","external_textures":False,
                      "triangles":triangles,"triangle_count_method":"gltf_primitive_indices" if lod else "near_plus_far_stored",
                      "axis_status":spec["axis_status"],"placement_status":"runtime_map_bbox_and_dem",
                      "official_length_m":spec["official_length_m"],"official_height_m":spec["official_height_m"]}
            if lod:
                metadata.update(lod=lod["lod"],aabb_min_m=lod["aabb_min_m"],aabb_max_m=lod["aabb_max_m"])
                metadata["elevation_max"]=lod["aabb_max_m"][1]
            assets[path.name]={"file_path":"res://assets/generated/ulsan_dams/"+path.name,
                               "sha256":digest(path),"size_bytes":path.stat().st_size,"metadata":metadata}
    readme=("# 울산 용수댐 경량 모델과 배치\n"
            "사연·대곡·대암·선암·회야댐 5종. 공식 길이·높이, 공개 축선, 추정 단면을 구분한 시각화 모델입니다.\n\n"
            "- 근경·원경 GLB 10개, 충돌 및 거리 LOD를 포함하는 자체 완결 TSCN 5개.\n"
            "- 원점은 댐마루 중앙, Y 위, -Z 저수지측, 미터 단위.\n"
            "- 마루 폭 6m, 사면비 상류 1:2 / 하류 1:2.2, 난간은 시각화용 추정입니다.\n"
            "- 대암·선암 축선은 공개 도로·산책로와 저수지 경계로 추정했습니다. 나머지 3곳은 공개 OSM 댐 축선을 사용합니다.\n"
            "- 지도상 축선 길이를 보존하므로 공식 제원 길이와 차이가 나는 경우 X 방향으로 맞춥니다.\n"
            "- 댐마루 표고는 현재 지도 DEM의 내부 17개 표본 90백분위 + 0.35m이며 측량 표고가 아닙니다.\n"
            "- 미조사 여수로·취수탑·관리동·수문과 미래 공사는 생략했습니다. 기존 수역·DEM을 수정하지 않습니다.\n"
            "- DEM에 이미 포함된 제방을 이중으로 올리지 않도록 상부·사면을 지표 +0.45m 이상에 맞추고 충돌도 갱신합니다. 양 끝 사면 폭은 시각화용으로 줄입니다.\n"
            "- 근경 3.5km / 원경 24km 거리 소거. 충돌은 근경 메시 기준이며 실제 지도 통행은 미확인입니다.\n"
            "- BuildingRoadManager에서 지도 범위가 포함하는 댐을 배치합니다. 실행 중 생성·색인은 하지 않습니다.\n"
            "- 재생성: `.venv_campus/Scripts/python.exe pipeline/processors/ulsan_dams/generate.py` 후 전용 Godot 프로젝트의 `bake.gd`, `fixture.gd`, `publish.py`, 중앙 색인 순서. Godot 사용자 경로도 previews/ulsan_dams 안으로 지정합니다.\n"
            "- 조사 근거: `config/ulsan_dams.json`, `results/261011_UlsanDamsReport.md`. OSM: OpenStreetMap contributors / ODbL-1.0.\n")
    (OUT/"README.md").write_text(readme,encoding="utf-8")
    for path in [OUT/"catalog.json",OUT/"README.md"]:
        assets[path.name]={"file_path":"res://assets/generated/ulsan_dams/"+path.name,"sha256":digest(path),
                           "size_bytes":path.stat().st_size,"metadata":{"bbox":None,"resolution":None,
                           "elevation_min":None,"elevation_max":None,"status":"research_based_simplified"}}
    update(OUT/"manifest.json",lambda doc:doc.update(version=1,assets=assets))
    preservation={}
    def merge(doc):
        entries=doc.setdefault("assets",{})
        before={k:v for k,v in entries.items() if not k.startswith("ulsan_dams/")}
        for key,value in assets.items():
            entries["ulsan_dams/"+key]=value
        assert before=={k:v for k,v in entries.items() if not k.startswith("ulsan_dams/")}
        preservation.update(non_target_entries_preserved=len(before))
    update(ROOT/"godot_project/assets/generated/manifest.json",merge)
    modules=[{"path":p.relative_to(ROOT).as_posix(),"lines":len(p.read_text(encoding="utf-8").splitlines())}
             for p in sorted(Path(__file__).parent.iterdir()) if p.suffix in (".py",".gd")]
    modules.extend([{"path":"godot_project/scripts/terrain/"+name,"responsibility":purpose} for name,purpose in
                    [("dam_landmark_manager.gd","댐 지리 축선 및 DEM 배치"),("dam_terrain_fit.gd","제방 표면과 충돌의 DEM 맞춤")]])
    for index in [ROOT/"module_index.json",ROOT/"godot_project/module_index.json"]:
        update(index,lambda doc:doc.setdefault("domains",{}).update(ulsan_dams={"description":"울산 용수댐 조사·경량 모델·좌표 배치","modules":modules}))
    shutil.copy2(STAGE/"fixture_results.json",ROOT/"results/261011_UlsanDamsFixture.json")
    (ROOT/"results/261011_UlsanDamsPublish.json").write_text(json.dumps({"assets":len(assets),"pending":[],**preservation},indent=2),encoding="utf-8")
    print(json.dumps({"published_files":len(assets),**preservation}))


if __name__=="__main__":
    main()
