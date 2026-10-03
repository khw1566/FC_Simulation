import os
import json
import time
import requests

def fetch_ulsan_metro_highways():
    # 60km x 60km 울산 광역권 BBOX
    bbox = {'south': 35.2742, 'north': 35.8148, 'west': 128.9233, 'east': 129.5877}
    s, n, w, e = bbox['south'], bbox['north'], bbox['west'], bbox['east']

    # 울산 광역권 전역 간선 도로망 쿼리
    # 고속도로(motorway), 자동차전용도로/국도(trunk), 주간선도로(primary), 보조간선도로(secondary), 집산도로(tertiary)
    query = f"""[out:json][timeout:120];
    (
      way["highway"~"motorway|trunk|primary|secondary|tertiary"]({s},{w},{n},{e});
    );
    out body;
    >;
    out skel qt;
    """

    endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://lz4.overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter"
    ]
    headers = {
        "User-Agent": "UlsanMetroRoadPipeline/2.0 (Wide Highway Collector)"
    }

    raw_dir = os.path.abspath("data/raw/ulsan_metro_60km/highways")
    os.makedirs(raw_dir, exist_ok=True)
    raw_path = os.path.join(raw_dir, "overpass_ulsan_metro_highways.json")

    fetched_data = None
    if os.path.exists(raw_path):
        print(f"[HighwayCollector] Using merged OSM cache from {raw_path}")
        with open(raw_path, "r", encoding="utf-8") as f:
            fetched_data = json.load(f)
    else:
        print("[HighwayCollector] Requesting 60km road network from Overpass API...")
        for ep in endpoints:
            try:
                print(f"[HighwayCollector] Trying endpoint: {ep}...")
                resp = requests.post(ep, data={"data": query}, headers=headers, timeout=120)
                if resp.status_code == 200:
                    fetched_data = resp.json()
                    with open(raw_path, "w", encoding="utf-8") as f:
                        json.dump(fetched_data, f, ensure_ascii=False)
                    print(f"[HighwayCollector] Successfully saved raw highway JSON to {raw_path}")
                    break
            except Exception as exc:
                print(f"[HighwayCollector] Exception on {ep}: {exc}")

    if not fetched_data:
        print("[HighwayCollector] No usable raw highway data.")
        return

    # 월드 좌표계 변환 및 도로 리본 데이터 생성
    world_size = 60000.0 # 60km
    def geo_to_world(lat, lon):
        frac_x = (lon - w) / (e - w)
        frac_z = (n - lat) / (n - s)
        wx = (frac_x - 0.5) * world_size
        wz = (frac_z - 0.5) * world_size
        return round(wx, 2), round(wz, 2)

    # 도로 폭 표준 정의
    width_map = {
        "motorway": 22.0,
        "motorway_link": 12.0,
        "trunk": 18.0,
        "trunk_link": 10.0,
        "primary": 15.0,
        "primary_link": 9.0,
        "secondary": 12.0,
        "secondary_link": 8.0,
        "tertiary": 9.0,
        "tertiary_link": 7.0,
        "unclassified": 4.5,
        "residential": 5.5,
        "living_street": 4.5,
        "service": 3.5,
        "pedestrian": 2.4,
        "footway": 1.6,
        "path": 1.25,
        "steps": 1.8,
        "cycleway": 2.0,
        "track": 3.0,
        "bridleway": 1.6,
        "corridor": 1.4
    }

    def get_width(tags, highway):
        raw = str(tags.get("width", "")).lower().replace("meters", "").replace("meter", "").replace("m", "").strip()
        try:
            parsed = float(raw)
            if 0.6 <= parsed <= 80.0:
                return parsed
        except (ValueError, TypeError):
            pass
        tracktype = tags.get("tracktype", "")
        if highway == "track":
            return {"grade1": 3.5, "grade2": 3.0, "grade3": 2.6, "grade4": 2.2, "grade5": 1.8}.get(tracktype, 2.6)
        try:
            lanes = float(tags.get("lanes", ""))
            if 1.0 <= lanes <= 12.0:
                return max(width_map.get(highway, 4.0), lanes * 3.2 + 1.0)
        except (ValueError, TypeError):
            pass
        return width_map.get(highway, 4.0)

    nodes = {}
    ways = []
    for elem in fetched_data.get("elements", []):
        if elem.get("type") == "node":
            nodes[elem["id"]] = (elem["lat"], elem["lon"])
        elif elem.get("type") == "way":
            ways.append(elem)

    print(f"[HighwayCollector] Parsed {len(nodes)} nodes, {len(ways)} highway ways.")

    new_roads = []
    road_id_seq = 1

    for elem in ways:
        tags = elem.get("tags", {})
        hw_type = tags.get("highway", "primary")
        name = tags.get("name:ko", tags.get("name", ""))
        ref = tags.get("ref", "")
        road_label = f"{name} ({ref})".strip() if ref and name else (name or ref or hw_type)

        is_tunnel = tags.get("tunnel") in ["yes", "building_passage"]
        is_bridge = tags.get("bridge") in ["yes", "viaduct"]

        node_ids = elem.get("nodes", [])
        pts = []
        for nid in node_ids:
            if nid in nodes:
                nlat, nlon = nodes[nid]
                wx, wz = geo_to_world(nlat, nlon)
                # Y 고도는 Godot 런타임/높이맵에서 정밀 샘플링되므로 기본 0.0 설정
                pts.append([wx, 0.0, wz])

        if len(pts) >= 2:
            road_w = get_width(tags, hw_type)
            new_roads.append({
                "id": f"rd_metro_{road_id_seq}",
                "name": road_label,
                "width": road_w,
                "type": hw_type,
                "surface": tags.get("surface", ""),
                "tracktype": tags.get("tracktype", ""),
                "sac_scale": tags.get("sac_scale", ""),
                "smoothness": tags.get("smoothness", ""),
                "access": tags.get("access", ""),
                "foot": tags.get("foot", ""),
                "incline": tags.get("incline", ""),
                "tunnel": is_tunnel,
                "bridge": is_bridge,
                "points": pts
            })
            road_id_seq += 1

    print(f"[HighwayCollector] Generated {len(new_roads)} continuous arterial road ribbons for 60km region.")

    # 기존 buildings_and_roads.json 로드 후 roads 교체 및 병합
    target_json_path = os.path.abspath("godot_project/assets/maps/ulsan_metro_60km/buildings_and_roads.json")
    print(f"[HighwayCollector] Updating {target_json_path}...")
    with open(target_json_path, "r", encoding="utf-8") as f:
        dest_data = json.load(f)

    # 기존 512개 국소 도로 대신 광역권 전체 실측 도로로 교체
    dest_data["roads"] = new_roads
    dest_data["road_count"] = len(new_roads)

    with open(target_json_path, "w", encoding="utf-8") as f:
        json.dump(dest_data, f, ensure_ascii=False)

    print(f"[HighwayCollector] Success! Updated buildings_and_roads.json with {len(new_roads)} arterial roads across 60km region.")

if __name__ == "__main__":
    fetch_ulsan_metro_highways()
