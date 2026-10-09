"""새 항구 계열만 등록하며 공유 매니페스트는 기존 항목을 보존한다."""
import hashlib
import json
from pathlib import Path
from simple_maps.publish import atomic,merge
from rail_bridge_lowpoly.publish import update


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def publish(root,output,catalog,models):
    entries={}
    for path in sorted(output.iterdir()):
        if path.name=="manifest.json" or path.suffix not in (".glb",".tscn",".json",".png",".md"):
            continue
        uri="res://"+path.relative_to(root/"godot_project").as_posix()
        meta=catalog["models"].get(path.stem,{})
        if path.stem in catalog["assemblies"]:
            example=catalog["assemblies"][path.stem]
            meta={"label_ko":example["label_ko"],"bbox":None,"elevation_min":example.get("aabb_min_m",[0,None])[1],
                  "elevation_max":example.get("aabb_max_m",[0,None])[1],"aabb_min_m":example.get("aabb_min_m"),"aabb_max_m":example.get("aabb_max_m"),
                  "resolution":{"type":"modular_assembly","instances":len(example["placements"])+len(example.get("external_instances",[]))},"placement_status":"synthetic_assembly"}
        resolution=meta.get("resolution")
        if path.suffix==".png":
            from PIL import Image
            with Image.open(path) as image: resolution={"width":image.width,"height":image.height}
        entries[path.name]={"file_path":uri,"sha256":digest(path),"size_bytes":path.stat().st_size,
            "type":"harbor_modular_asset","bbox":None,"elevation_min":meta.get("elevation_min"),"elevation_max":meta.get("elevation_max"),
            "resolution":resolution,"metadata":meta}
    existing=json.loads((output/"manifest.json").read_text(encoding="utf-8")) if (output/"manifest.json").exists() else {}
    existing.setdefault("assets",{}).update(entries)
    existing.update(version=1,family="harbor_assets")
    atomic(output/"manifest.json",existing)
    merge(output.parent/"manifest.json",{"harbor_assets/"+key:value for key,value in entries.items()})
    modules=[{"path":path.relative_to(root).as_posix(),"lines":len(path.read_text(encoding="utf-8").splitlines()),
              "responsibility":path.read_text(encoding="utf-8").splitlines()[0].strip('"')} for path in sorted(Path(__file__).parent.glob("*")) if path.suffix in (".py",".gd")]
    for index in (root/"module_index.json",root/"godot_project/module_index.json"):
        update(index,lambda doc:doc.setdefault("domains",{}).update(harbor_assets={"description":"지형에 조합 배치하는 저다각형 항구 모듈·접속 규약","modules":modules}))
    report={"models":len(models),"assemblies":len(catalog["assemblies"]),"triangles_total":sum(len(a.mesh.faces) for a in models.values()),
            "triangles_max":max(len(a.mesh.faces) for a in models.values()),"model_files_bytes":sum((output/(key+".glb")).stat().st_size for key in models),
            "external_textures":False,"pending":[],"connections_checked":catalog["connections_checked"]}
    atomic(root/"results/261008_HarborAssetsVerification.json",report)
    (root/"results/261008_HarborAssetsReport.md").write_text(
        f"# 저다각형 항구 에셋 생성\n\n독립 모델 {len(models)}종과 조립 예제 {len(catalog['assemblies'])}종을 생성했습니다. 게임과 실제 지형에는 적용하지 않았습니다.\n\n"
        f"- 모델 삼각형 합계 {report['triangles_total']:,}, 최대 {report['triangles_max']:,}.\n"
        "- 무광 단색 인덱스 GLB, 외부 텍스처 없음. 대응 Godot 씬에 접속점과 간단한 충돌 포함.\n"
        "- 콘크리트 방파제·호안·부두·기초·지지말뚝·높이 전환·등대·어업용 크레인·컨테이너 크레인·단위 테트라포드·컨테이너 적재·기반시설.\n"
        "- 실제 항구 좌표와 수위는 미지정이며 DEM 표본을 이용하는 지지대 선택 함수와 배치 지침을 제공합니다.\n"
        "- 지형 보정 시 상판과 시설은 수평·수직을 유지하고 기초·말뚝을 독립 조정합니다.\n"
        "- 색인 갱신 결과는 완료 후 기록합니다.\n",encoding="utf-8")
    return report
