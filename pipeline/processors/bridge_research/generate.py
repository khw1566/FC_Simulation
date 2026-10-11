"""교량 조사 초안과 메타데이터를 독립 경로에 생성한다."""
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from bridge_research.models import build, PALETTE
from bridge_research.specs import SPECS, PENDING, SOURCE
from bridge_research.preview import render
from custom_lowpoly.glb import export, inspect
from rail_bridge_lowpoly.publish import update

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/"godot_project/assets/generated/bridges/research_20261009"
REPORT=ROOT/"results/261009_bridge_research"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    REPORT.mkdir(parents=True,exist_ok=True)
    originals=list((OUT.parent).glob("bridge_*.scn"))
    original_hashes={str(p.relative_to(ROOT)):digest(p) for p in originals}
    source_hash=digest(Path(SOURCE))
    entries={}
    items=[]
    for spec in SPECS:
        mesh=build(spec)
        name=spec["id"]
        path=OUT/f"{name}.glb"
        export(mesh,path,name,PALETTE)
        metrics=inspect(path)
        points=[p for f in mesh.faces for p in f[:3]]
        low=[min(p[k] for p in points) for k in range(3)]
        high=[max(p[k] for p in points) for k in range(3)]
        uri="res://"+path.relative_to(ROOT/"godot_project").as_posix()
        scene=path.with_suffix(".tscn")
        deck=float(spec.get("deck",0))
        scene.write_text(f'''[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="{uri}" id="1"]

[node name="{name}" type="Node3D"]
metadata/status = "research_draft"
metadata/label_ko = "{spec['label']}"
metadata/georeferenced = false
metadata/deck_y_m = {deck}

[node name="Visual" parent="." instance=ExtResource("1")]

[node name="Start" type="Marker3D" parent="."]
position = Vector3(0, {deck}, {-spec['length']/2})
rotation = Vector3(0, 0, 0)

[node name="End" type="Marker3D" parent="."]
position = Vector3(0, {deck}, {spec['length']/2})
rotation = Vector3(0, 3.141592653589793, 0)
''',encoding="utf-8")
        meta={"label_ko":spec["label"],"status":"research_draft",
              "detail_profile":"custom_low_poly_flat_v1","georeferenced":False,
              "length_m":spec["length"],"model_deck_widths_m":spec["widths"],
              "units":"meters","longitudinal_axis":"Z",
              "center_reference_wgs84":spec["center"],"osm_ids":spec["osm"],
              "source_pdf":SOURCE,"source_pdf_sha256":source_hash,"source_page":spec["page"],
              "uncertainty":spec["uncertainty"],"bbox":None,"resolution":None,
              "aabb_min_m":low,"aabb_max_m":high,"elevation_min":low[1],"elevation_max":high[1],
              "triangles":metrics["triangles"],"triangle_count_method":"gltf_primitive_indices",
              "runtime_placement_changed":False,"external_textures":False,
              "collision_status":"none_draft","lighting_status":"not_added",
              "approximation":"직선화한 형상 확인용. 교각 간격·깊이·접속부·두 동 간격 0.8m는 근사값. 실제 선형·DEM·사진 검증 전."}
        if spec["kind"]=="suspension":
            meta.update(main_span_m=1150,tower_top_y_m=203,deck_y_assumed_m=65,
                        basis="현대건설 2016-01-27 사보 및 UNIST Magazine 26호; 상세 형상은 근사",
                        visual_sources=["https://www.hdec.kr/FileContents/OldFiles/HDEC_NEWSPAPER/005925539.pdf",
                                        "https://webzine.unist.ac.kr/pdf/unist_No.26.pdf"])
        if "spans" in spec:
            meta.update(span_lengths_model_m=spec["spans"],pier_kind=spec["pier_kind"],
                        dimensional_source=spec["source_url"],
                        source_status="사용자 PDF 및 민간 교량 DB 대조. 공식 준공도면 미확인")
        entries[name]={"file_path":uri,"scene_path":uri[:-4]+".tscn","format":"GLB",
                       "type":"bridge_model","metadata":meta,"sha256":digest(path),
                       "size_bytes":path.stat().st_size,"scene_sha256":digest(scene)}
        items.append((spec,mesh))
    for relative,expected in original_hashes.items():
        if digest(ROOT/relative)!=expected:
            raise RuntimeError("동시 변경 감지. 원본 보존 확인 보류: "+relative)
    manifest={"version":1,"assets":entries,"pending":PENDING,"source_pdf_sha256":source_hash}
    update(OUT/"manifest.json",lambda d:d.update(manifest))
    update(OUT/"catalog.json",lambda d:d.update({"models":[{"id":k,**v} for k,v in entries.items()],"pending":PENDING}))
    update(OUT.parent.parent/"manifest.json",lambda d:d.setdefault("assets",{}).update({"bridge_research_"+k:v for k,v in entries.items()}))
    (OUT/"README.md").write_text(f"# 태화강 조사 교량 초안\n\nPDF 기준 {len(entries)}개 독립 모델. GLB와 대응 씬은 하나의 모델이다.\n\n- 기존 교량을 교체하거나 지도에 자동 연결하지 않는다.\n- 좌표는 참고용이며 직선 로컬 모델이다.\n- 임시 치수는 catalog.json의 uncertainty에 기록한다.\n- 실제 선형·표고·사진 대조, 충돌·야간 조명은 미완료다.\n",encoding="utf-8")
    render(items,OUT/"research_preview.png")
    result={"models":len(entries),"triangles":{k:v["metadata"]["triangles"] for k,v in entries.items()},
            "original_scene_hashes_preserved":original_hashes,"pending_research":PENDING,
            "validation":"GLB 헤더·길이·인덱스 삼각형 수·유한 정점 검사, 메시 PNG 확인. Godot 임포트는 별도 기록."}
    (REPORT/"generation.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps(result,ensure_ascii=True))


if __name__=="__main__":
    main()
