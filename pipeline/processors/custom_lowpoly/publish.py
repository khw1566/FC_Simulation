"""검증된 모델과 대응 메타데이터만 기존 색인에 병합한다."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from rail_bridge_lowpoly.publish import update, atomic

PROFILE = "custom_low_poly_flat_v1"


def publish(root, stage, metrics, protected):
    project = root / "godot_project"
    for relative, expected in protected.items():
        if hashlib.sha256((project / relative).read_bytes()).hexdigest() != expected:
            raise RuntimeError("동시 변경으로 보류합니다: " + relative)
    entries, groups = {}, {}
    for item in metrics:
        relative = item["path"]
        source = stage / relative
        target = project / relative
        pending = target.with_name(target.name + ".custom_lowpoly.pending")
        shutil.copy2(source, pending)
        if hashlib.sha256(target.read_bytes()).hexdigest() != protected[relative]:
            pending.unlink()
            raise RuntimeError("게시 직전 에셋 변경: " + relative)
        os.replace(pending, target)
        after = item["after"]
        meta = {"detail_profile": PROFILE, "material_style": "flat_color", "external_textures": False,
                "triangles": after["triangles"], "triangle_count_method": "mesh_faces_times_instances" if target.suffix == ".scn" else "gltf_primitive_indices",
                "aabb_min_m": after["aabb_min_m"], "aabb_max_m": after["aabb_max_m"],
                "elevation_min": after["aabb_min_m"][1], "elevation_max": after["aabb_max_m"][1],
                "connections_preserved": True, "collision_geometry_preserved": True,
                "runtime_placement_changed": False, "indexed_geometry": target.suffix == ".glb"}
        if item.get("label_ko"):
            meta["label_ko"] = item["label_ko"]
        for path in ([target, target.with_suffix(".tscn")] if target.suffix == ".glb" else [target]):
            if not path.exists():
                continue
            uri = "res://" + path.relative_to(project).as_posix()
            entry = {"file_path": uri, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                     "size_bytes": path.stat().st_size, "metadata": meta}
            entries[uri] = entry
            groups.setdefault(path.parent, {})[path.name] = entry
    def refresh(document):
        if isinstance(document, list):
            for child in document:
                refresh(child)
        elif isinstance(document, dict):
            uri = next((document.get(key) for key in ("file_path", "path", "scene_path", "scene") if document.get(key) in entries), None)
            if uri:
                entry = entries[uri]
                if "metadata" in document or "sha256" in document:
                    document.update({k: v for k, v in entry.items() if k != "metadata"})
                    document.setdefault("metadata", {}).update(entry["metadata"])
                else:
                    document.update(entry["metadata"])
                resolution = document.get("resolution")
                if isinstance(resolution, dict) and "triangles" in resolution:
                    resolution["triangles"] = entry["metadata"]["triangles"]
                nested = document.get("metadata", {}).get("resolution")
                if isinstance(nested, dict) and "triangles" in nested:
                    nested["triangles"] = entry["metadata"]["triangles"]
            for key, child in list(document.items()):
                if key != "metadata":
                    refresh(child)
    master = project / "assets/generated/manifest.json"
    old_master = json.loads(master.read_text(encoding="utf-8"))
    for folder, additions in groups.items():
        def family_update(document):
            refresh(document)
            assets = document.setdefault("assets", {})
            for name, entry in additions.items():
                old_key = next((key for key, value in assets.items() if value.get("file_path") == entry["file_path"]), None)
                if old_key is None:
                    original = next((value for value in old_master.get("assets", {}).values() if value.get("file_path") == entry["file_path"]), {})
                    assets[name] = {**original, **entry, "metadata": {**original.get("metadata", {}), **entry["metadata"]}}
        update(folder / "manifest.json", family_update)
        catalog = folder / "catalog.json"
        if catalog.exists():
            update(catalog, refresh)
        else:
            models = [{"id": Path(name).stem, "scene_path": entry["file_path"], **entry["metadata"]}
                      for name, entry in additions.items() if name.endswith((".tscn", ".scn"))]
            atomic(catalog, {"version": 1, "models": models, "note_ko": "독립 에셋 표현의 경량화, 기존 지리 배치 유지"})
        readme = folder / "README.md"
        text = readme.read_text(encoding="utf-8") if readme.exists() else ""
        heading = "## 커스텀 에셋 경량 표현"
        if heading in text:
            text = text.split(heading)[0].rstrip() + "\n"
        readme.write_text(text + "\n" + heading + "\n\n"
            "외형과 조립 규격을 유지하며 곡면과 반복 장식을 단순화합니다. GLB는 중복 정점을 공유하고 무광 단색 재질을 사용합니다. 기존 조립 씬·연결점·조명·연기 설정과 충돌 형상은 보존합니다.\n\n"
            "- 규약: `custom_low_poly_flat_v1`\n"
            "- 재생성: `.venv_campus/Scripts/python.exe pipeline/processors/custom_lowpoly/build.py`\n"
            "- 게임·지도·실행 생성기 변경 없음. 원본 프로젝트에서 임포터를 실행하지 않습니다.\n"
            "- 이전 PNG는 과거 표현일 수 있습니다. 최신 모델은 독립 에셋 프리뷰에서 확인하세요.\n", encoding="utf-8")
    def master_update(document):
        refresh(document)
        assets = document.setdefault("assets", {})
        for uri, entry in entries.items():
            if not any(value.get("file_path") == uri for value in assets.values()):
                assets["custom_lowpoly/" + uri.removeprefix("res://assets/generated/")] = entry
    update(master, master_update)
    totals = {"before_triangles": sum(item["before"]["triangles"] for item in metrics),
              "after_triangles": sum(item["after"]["triangles"] for item in metrics),
              "before_bytes": sum(item.get("before_bytes", item["before"].get("size_bytes", 0)) for item in metrics),
              "after_bytes": sum(item.get("after_bytes", item["after"].get("size_bytes", 0)) for item in metrics)}
    report = {"profile": PROFILE, "model_count": len(metrics), "files_registered": len(entries),
              "totals": totals, "assets": metrics, "pending": []}
    atomic(root / "results/261008_CustomLowPolyVerification.json", report)
    shutil.copy2(stage / "custom_lowpoly_preview.png", root / "results/261008_CustomLowPolyPreview.png")
    triangle_drop = 100 * (1 - totals["after_triangles"] / totals["before_triangles"])
    byte_drop = 100 * (1 - totals["after_bytes"] / totals["before_bytes"])
    (root / "results/261008_CustomLowPolyReport.md").write_text(
        f"# 커스텀 에셋 경량화\n\n{len(metrics)}개 모델을 경량화했습니다. GLB와 대응 씬은 같은 모델로 계산합니다.\n\n"
        f"- 삼각형: {totals['before_triangles']:,} → {totals['after_triangles']:,} ({triangle_drop:.1f}% 감소)\n"
        f"- 모델 파일: {totals['before_bytes']:,} → {totals['after_bytes']:,} bytes ({byte_drop:.1f}% 감소)\n"
        "- 공장·플랜트·선박·태화강역·월성 발전소·울산 및 일본 공항·성곽 모델.\n"
        "- 원통 최대 8면, 구형·돔 곡면 분할 축소, 반복 창틀·난간·침목·배관 곡관·성벽 돌 단순화.\n"
        "- GLB 중복 정점 공유, 사용하지 않는 재질 제거, 금속 반사 없이 단색 무광 재질.\n"
        "- 주요 설비 수·건물 크기·선박 길이·폭·수면 기준과 배관 포트·방향은 기존 규격을 사용합니다.\n"
        "- GLB 조립 씬을 그대로 유지합니다. SCN은 저장 후 재로드하여 접속점·광원·충돌 형상 일치를 확인했습니다.\n"
        "- 전체 게임·맵·원본 임포터 실행 없음. 에셋 표현만 갱신하고 게임 배치와 실행 생성기를 유지했습니다.\n"
        "- 삼각형 수가 유지된 소형 모델도 중복 정점과 재질 정리로 파일 크기를 줄였습니다.\n"
        "- 색인 갱신 결과는 완료 후 기록합니다.\n", encoding="utf-8")
    for index in (root / "module_index.json", project / "module_index.json"):
        def modules_update(document):
            document.setdefault("domains", {})["custom_lowpoly"] = {"description": "커스텀 정적 모델 격리 경량화", "modules": [
                {"path": path.relative_to(root).as_posix(), "lines": len(path.read_text(encoding="utf-8").splitlines())}
                for path in sorted(Path(__file__).parent.glob("*")) if path.suffix in (".py", ".gd")]}
        update(index, modules_update)
    print(json.dumps(totals), flush=True)
