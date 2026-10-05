"""제작된 교량 에셋의 지도 선형과 월드 배치 카탈로그를 생성한다."""
import hashlib
import json
import math
import xml.etree.ElementTree as ET
from pathlib import Path


class PedestrianBridgePlacements:
    ROOT = Path(__file__).resolve().parents[2]

    def run(self):
        raw_dir = self.ROOT / "data/raw/ulsan_metro_80km/bridges"
        raw = json.loads((raw_dir / "bridges_osm.json").read_text(encoding="utf-8"))
        seonbawi = next(e for e in raw["elements"] if e["id"] == 153128115)
        xml = ET.parse(raw_dir / "gulhwa_daun_area.osm").getroot()
        nodes = {n.get("id"): {"lon": float(n.get("lon")), "lat": float(n.get("lat"))} for n in xml.findall("node")}
        crossing = next(w for w in xml.findall("way") if w.get("id") == "472077914")
        route = [nodes[n.get("ref")] for n in crossing.findall("nd")]
        bridge_route = seonbawi["geometry"]
        first, last = bridge_route[0], bridge_route[-1]
        length = math.hypot((last["lon"]-first["lon"])*90500, (last["lat"]-first["lat"])*111000)
        before = {key: first[key] - (last[key]-first[key])*40/length for key in ("lon", "lat")}
        after = {key: last[key] + (last[key]-first[key])*40/length for key in ("lon", "lat")}
        definitions = [
            {"id": "seonbawi_bridge", "name_ko": "선바위교", "scene_path": "res://assets/generated/pedestrian_bridges/seonbawi_bridge.scn", "markers": ["RoadA", "RoadB"], "osm_ids": [153128115], "geometry": bridge_route, "approaches": [[before,first],[last,after]], "approach_width_m":24.9, "width_m":24.9, "clearance_m": 0.12, "accuracy": "OSM 선바위교 양끝에 원본 에셋의 배치 기준점을 정렬. 직선 모델의 길이와 표고를 DEM에 맞추며 양안에 40m 지형 접속 램프를 추가."},
            {"id": "gulhwa_daun_crossing", "name_ko": "굴화리–다운동 도보 징검다리", "scene_path": "res://assets/generated/pedestrian_bridges/gulhwa_daun_crossing.scn", "markers": ["BankA", "BankB"], "osm_ids": [472077914], "geometry": [route[4], route[5]], "approaches": [route[:5], route[5:]], "approach_width_m":1.0, "width_m":1.0, "clearance_m": 0.20, "accuracy": "기사의 다운동–굴화 연결 위치와 OSM 보행로 472077914를 대조한 근사 배치. 중앙 직선 횡단 구간에 길이를 맞추며 양안 진입로를 유지. 원본 tunnel=yes 태그 대신 지상 저상 보행교로 표현."},
        ]
        for definition in definitions:
            for marker in definition["markers"]:
                if not marker:
                    raise ValueError("배치 기준점이 없습니다")
        output = self.ROOT / "godot_project/assets/generated/pedestrian_bridges/placements.json"
        payload = {"version": 1, "map_ids": ["ulsan_metro_80km", "southeast_mega_140km", "ulsan_uc_west"], "attribution": "OpenStreetMap contributors / ODbL", "placements": definitions, "unplaced_assets": [{"id": "generic_pedestrian_overpass", "reason": "사용자 요청: 범용 육교는 보관만 함"}]}
        output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        coordinates = [p for d in definitions for p in d["geometry"]]
        bbox = {"west": min(p["lon"] for p in coordinates), "east": max(p["lon"] for p in coordinates), "south": min(p["lat"] for p in coordinates), "north": max(p["lat"] for p in coordinates)}
        shared_path = self.ROOT / "godot_project/assets/generated/manifest.json"
        shared = json.loads(shared_path.read_text(encoding="utf-8-sig"))
        shared.setdefault("assets", {})["pedestrian_bridge_placements"] = {"file_path": "res://assets/generated/pedestrian_bridges/placements.json", "sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "bbox": bbox, "elevation_min": None, "elevation_max": None, "resolution": "OSM vector", "elevation_note": "지도별 DEM 양안 고도를 실행 시 샘플링", "type": "bridge_placement_catalog", "placement_count": 2}
        for path in [shared_path, output.parent / "manifest.json"]:
            manifest = shared if path == shared_path else json.loads(path.read_text(encoding="utf-8-sig"))
            for definition in definitions:
                asset = manifest.get("assets", {}).get(definition["id"]) or manifest.get("assets", {}).get("pedestrian_bridge_" + definition["id"])
                if asset:
                    asset.setdefault("metadata", {}).update(placement_status="world_placed", placement_catalog="res://assets/generated/pedestrian_bridges/placements.json")
            path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        print("교량 배치 카탈로그 생성: 선바위교, 굴화리-다운동 징검다리")


if __name__ == "__main__":
    PedestrianBridgePlacements().run()
