"""OSM 교량 선형과 공개 제원을 런타임 교량 카탈로그로 변환한다."""
import hashlib
import json
from pathlib import Path


class TaehwaBridgeCatalog:
    ROOT = Path(__file__).resolve().parents[2]

    def run(self):
        raw = self.ROOT / "data/raw/ulsan_metro_80km/bridges/bridges_osm.json"
        elements = {e["id"]: e for e in json.loads(raw.read_text(encoding="utf-8"))["elements"] if e["type"] == "way"}
        definitions = [
            ("울산대교", "suspension", [997824965, 997824969], 25.6, {"main_span_m": 1150, "deck_elevation_assumed_m": 65, "tower_elevation_assumed_m": 203}),
            ("십리대밭교", "arch", [283957517], 6.0, {"main_span_m": 120, "bank_clearance_m": 1.0}),
            ("삼호교", "beam", [67599129], 12.0, {"pier_spacing_m": 30}),
            ("구삼호교", "historic", [699304322], 5.0, {"pier_spacing_m": 9.6}),
            ("신삼호교_남행", "beam", [1094525634], 12.0, {"pier_spacing_m": 35}),
            ("신삼호교_북행", "beam", [1094525635], 12.0, {"pier_spacing_m": 35}),
        ]
        bridges = []
        for name, kind, ids, width, extra in definitions:
            geometry = elements[ids[0]]["geometry"]
            if kind == "suspension":
                # 방향별 선형의 중심을 재표본화해 양방향 도로를 하나의 상판으로 대체.
                import numpy as np
                first = np.array([[p["lon"], p["lat"]] for p in geometry])
                second = np.array([[p["lon"], p["lat"]] for p in reversed(elements[ids[1]]["geometry"])])
                paths = []
                for path in [first, second]:
                    distances = np.r_[0, np.cumsum(np.linalg.norm(np.diff(path, axis=0) * [0.814, 1.0], axis=1))]
                    paths.append(np.column_stack([np.interp(np.linspace(0, distances[-1], 180), distances, path[:, k]) for k in [0, 1]]))
                geometry = [{"lon": float(p[0]), "lat": float(p[1])} for p in (paths[0] + paths[1]) / 2]
            bridges.append(dict(name=name, kind=kind, osm_ids=ids, width_m=width, geometry=geometry, preview_scene=f"res://assets/generated/bridges/bridge_{len(bridges):02d}.scn", **extra))
        output = self.ROOT / "godot_project/assets/generated/taehwa_bridges.json"
        payload = {"schema_version": 1, "attribution": "© OpenStreetMap contributors, ODbL 1.0", "source": "https://www.openstreetmap.org/copyright", "accuracy": "지도 선형 및 공개 제원 기반 근사 모델. 주탑 위치와 상세 부재는 측량값이 아님.", "bridges": bridges, "stepping_stones": {"status": "placement_pending", "reason": "사용자가 지정하는 태화강 징검다리 위치 확인 필요", "kind": "stepping_stones", "width_m": 1.25}}
        output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        manifest_path = output.parent / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
        manifest["taehwa_bridges"] = {"path": "res://assets/generated/taehwa_bridges.json", "sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "source_sha256": hashlib.sha256(raw.read_bytes()).hexdigest(), "bbox": {"west": 129.270, "east": 129.405, "south": 35.510, "north": 35.556}, "elevation_min_m": None, "elevation_max_m": None, "resolution": "OSM vector", "model_count": len(bridges), "elevation_note": "상판은 런타임 지형 샘플과 근사 설계고로 생성"}
        manifest["taehwa_bridges"]["scene_assets"] = [{"path": "res://assets/generated/bridges/" + p.name, "sha256": hashlib.sha256(p.read_bytes()).hexdigest(), "bbox": None, "elevation_min_m": None, "elevation_max_m": None, "resolution": "procedural mesh", "coordinate_space": "첫 경로점 기준 로컬 좌표, 배치 고도 미적용 미리보기"} for p in sorted((output.parent / "bridges").glob("bridge_*.scn"))]
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        modules = [
            ("BridgeGeometry", "godot_project/scripts/terrain/bridge_geometry.gd", "교량 부재 재질별 메시 병합"),
            ("BridgeLandmarkBuilder", "godot_project/scripts/terrain/bridge_landmark_builder.gd", "현수교·아치교·일반교·징검다리 모델 생성"),
            ("BridgeLandmarkManager", "godot_project/scripts/terrain/bridge_landmark_manager.gd", "지도 좌표 배치 및 기존 OSM 교량 중복 대체"),
            ("BridgeAssetExport", "godot_project/scripts/terrain/bridge_asset_export.gd", "독립 교량 씬 에셋 생성"),
            ("TaehwaBridgeCatalog", "pipeline/processors/build_taehwa_bridge_catalog.py", "교량 배치 카탈로그 및 매니페스트 생성"),
            ("TaehwaBridgeCollector", "pipeline/collectors/taehwa_bridge_collector.py", "교량 원본 OSM 데이터 수집"),
        ]
        for index_path in [self.ROOT / "module_index.json", self.ROOT / "godot_project/module_index.json"]:
            index = json.loads(index_path.read_text(encoding="utf-8"))
            domain = index["domains"].setdefault("bridges", {"description": "태화강 교량 모델 및 배치", "modules": []})
            domain["modules"] = [dict(class_name=name, path=path, description=description) for name, path, description in modules]
            index_path.write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Bridge catalog generated: {len(bridges)} models")


if __name__ == "__main__":
    TaehwaBridgeCatalog().run()
