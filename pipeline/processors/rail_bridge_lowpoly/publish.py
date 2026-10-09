"""검증된 정적 씬과 기존 매니페스트를 동시 변경 보호와 함께 갱신한다."""
import hashlib
import json
import os
from pathlib import Path
import shutil

PROFILE = "rail_bridge_low_poly_v1"


def atomic(path, document):
    temporary = path.with_name(path.name + f".{os.getpid()}.lowpoly.tmp")
    temporary.write_text(json.dumps(document, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def update(path, callback):
    lock = path.with_name(path.name + ".lowpoly.lock")
    fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    try:
        before = path.read_bytes() if path.exists() else b"{}"
        document = json.loads(before)
        callback(document)
        if path.exists() and path.read_bytes() != before:
            raise RuntimeError(f"동시 변경으로 보류합니다: {path}")
        atomic(path, document)
    finally:
        os.close(fd)
        lock.unlink()


def publish(root, stage, metrics, protected):
    project = root / "godot_project"
    for relative, expected in protected.items():
        if hashlib.sha256((project / relative).read_bytes()).hexdigest() != expected:
            raise RuntimeError(f"동시 에셋 변경으로 보류합니다: {relative}")
    entries = {}
    for item in metrics:
        relative = item["path"]
        target = project / relative
        temporary = target.with_name(target.name + ".lowpoly.pending")
        shutil.copy2(stage / relative, temporary)
        if hashlib.sha256(target.read_bytes()).hexdigest() != protected[relative]:
            temporary.unlink()
            raise RuntimeError(f"에셋 게시 직전 동시 변경: {relative}")
        os.replace(temporary, target)
        after = item["after"]
        entries["res://" + relative] = {"file_path": "res://" + relative, "format": "SCN",
            "type": "railway_night_asset" if "/night_assets/" in relative else "bridge_model",
            "sha256": item["sha256"], "size_bytes": item["after_bytes"],
            "metadata": {"detail_profile": PROFILE, "material_style": "flat_color", "external_textures": False,
                "triangles": after["triangles"], "triangle_count_method": "mesh_faces_times_instances",
                "aabb_min_m": after["aabb_min_m"], "aabb_max_m": after["aabb_max_m"],
                "elevation_min": after["aabb_min_m"][1], "elevation_max": after["aabb_max_m"][1],
                "bbox": None, "resolution": None, "placement_status": "asset_only",
                "collision_shapes": after["collisions"], "connections_preserved": True,
                "collision_geometry_preserved": True}}
    def refresh(document):
        if isinstance(document, list):
            for child in document:
                refresh(child)
        elif isinstance(document, dict):
            uri = next((document.get(k) for k in ("file_path", "path", "scene", "scene_path")
                        if document.get(k) in entries), None)
            if uri:
                entry = entries[uri]
                if "metadata" in document or "sha256" in document:
                    document.update({k: v for k, v in entry.items() if k != "metadata"})
                    document.setdefault("metadata", {}).update(entry["metadata"])
                else:
                    document.update(entry["metadata"])
            for key, child in list(document.items()):
                if key != "metadata":
                    refresh(child)
    groups = {}
    for uri, entry in entries.items():
        folder = (project / uri.removeprefix("res://")).parent
        groups.setdefault(folder, {})[Path(uri).stem] = entry
    for folder, additions in groups.items():
        def family_update(document):
            refresh(document)
            assets = document.setdefault("assets", {})
            for key, entry in additions.items():
                old = assets.get(key, {})
                assets[key] = {**old, **{k: v for k, v in entry.items() if k != "metadata"},
                               "metadata": {**old.get("metadata", {}), **entry["metadata"]}}
        update(folder / "manifest.json", family_update)
        catalog = folder / "catalog.json"
        if catalog.exists():
            update(catalog, refresh)
        else:
            atomic(catalog, {"version": 1, "models": [{"id": key, "scene_path": value["file_path"],
                   **value["metadata"]} for key, value in additions.items()]})
        readme = folder / "README.md"
        text = readme.read_text(encoding="utf-8") if readme.exists() else ""
        heading = "## 철로·교량 경량 표현"
        if heading in text:
            text = text.split(heading)[0].rstrip() + "\n"
        readme.write_text(text + "\n" + heading + "\n\n"
            "단색 재질과 성긴 반복 부재를 사용합니다. 접속점, 광원과 기존 충돌 형상은 보존합니다. "
            "계단과 징검다리의 보행판도 보존합니다. 외부 텍스처는 사용하지 않으며 야간 표시의 내장 그라데이션은 8×8입니다.\n\n"
            "- 품질 규약: `rail_bridge_low_poly_v1`\n"
            "- 재생성: 프로젝트 루트에서 `.venv_campus/Scripts/python.exe pipeline/processors/rail_bridge_lowpoly/build.py`\n"
            "- 생성은 독립 프리뷰 작업 공간에서만 수행합니다. 게임과 지도에 자동 적용하지 않습니다.\n"
            "- 기존 PNG 프리뷰는 이전 표현일 수 있습니다. 현재 SCN을 독립 에셋 프리뷰에서 확인하세요.\n", encoding="utf-8")
    def master_update(document):
        refresh(document)
        assets = document.setdefault("assets", {})
        for uri, entry in entries.items():
            existing = next((key for key, value in assets.items() if value.get("file_path") == uri), None)
            key = existing or "rail_bridge_lowpoly/" + uri.removeprefix("res://assets/generated/")
            old = assets.get(key, {})
            assets[key] = {**old, **{k: v for k, v in entry.items() if k != "metadata"},
                           "metadata": {**old.get("metadata", {}), **entry["metadata"]}}
    update(project / "assets/generated/manifest.json", master_update)
    total = {name: sum(item[side][field] if field != "bytes" else item[side + "_bytes"] for item in metrics)
             for name, side, field in (("before_triangles", "before", "triangles"), ("after_triangles", "after", "triangles"),
                                       ("before_bytes", "before", "bytes"), ("after_bytes", "after", "bytes"))}
    report = {"profile": PROFILE, "asset_count": len(metrics), "totals": total, "assets": metrics, "pending": []}
    atomic(root / "results/261008_RailBridgeLowPolyVerification.json", report)
    triangles = 100 * (1 - total["after_triangles"] / total["before_triangles"])
    sizes = 100 * (1 - total["after_bytes"] / total["before_bytes"])
    (root / "results/261008_RailBridgeLowPolyReport.md").write_text(
        f"# 철로·교량 경량화 결과\n\n{len(metrics)}개 정적 씬을 갱신했습니다. 게임·지도·실행용 생성기는 변경하지 않았습니다.\n\n"
        f"- 삼각형: {total['before_triangles']:,} → {total['after_triangles']:,} ({triangles:.1f}% 감소)\n"
        f"- 파일 크기: {total['before_bytes']:,} → {total['after_bytes']:,} bytes ({sizes:.1f}% 감소)\n"
        "- 철로 2종, 열차를 보존한 철로 조립 예제 2종, 철도교 10종, 일반 교량 8종, 보행교 3종.\n"
        "- 반복 인스턴스를 포함한 렌더 삼각형 수입니다. 기존 충돌 메시 크기는 유지합니다.\n"
        "- 저장 후 재로드하여 접속점·광원 위치와 에너지·충돌 형상 일치를 확인했습니다.\n"
        "- 궤간과 주요 구조 제원은 유지하고 침목·난간·트러스 패널·아치·케이블의 반복 수를 줄였습니다.\n"
        "- 무광 단색 재질, 외부 텍스처 없음, 야간 표시용 내장 그라데이션 8×8.\n"
        "- 일부 보행판의 삼각형 수는 보행 형상 보존을 위해 유지했습니다.\n"
        "- 전체 게임·맵 실행 없이 독립 생성과 구조 확인만 수행했습니다.\n"
        "- 에셋 색인 갱신 결과는 작업 완료 후 추가합니다.\n", encoding="utf-8")
    modules = [{"path": file.relative_to(root).as_posix(), "lines": len(file.read_text(encoding="utf-8").splitlines())}
               for file in sorted((root / "pipeline/processors/rail_bridge_lowpoly").glob("*")) if file.suffix in (".py", ".gd")]
    for index in (root / "module_index.json", project / "module_index.json"):
        update(index, lambda document: document.setdefault("domains", {}).update({"rail_bridge_lowpoly": {
            "description": "철로·교량 정적 씬의 격리 경량화 및 충돌·접속점 보존", "modules": modules}}))
    print(json.dumps(total), flush=True)
