import os
import json
import numpy as np
from PIL import Image

class BuildingRoadProcessor:
    """
    OSM 실측 건물 풋프린트 다각형 및 도로망 인프라 데이터로부터
    실제 밑면 형상과 높이/층수를 반영한 3D 박스 건물 및 도로 리본을 생성하는 프로세서
    지형과의 교차 및 Z-fighting 방지를 위한 바이리니어 고도 보간 및 표고 우선 오프셋 적용
    """
    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        self.bbox = self.config["bbox"]
        self.world_size = 28000.0 # 28km

    def _geo_to_world_2d(self, lat, lon):
        frac_x = (lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"])
        frac_z = (self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"])
        world_x = (frac_x - 0.5) * self.world_size
        world_z = (frac_z - 0.5) * self.world_size
        return world_x, world_z

    def process_buildings_and_roads(self, raw_buildings_path, infra_json_path, dem_tiff_path, landmarks_json_path, output_json_path, watermask_png_path=None):
        print(f"[BuildingRoadProcessor] Processing 3D building boxes from {raw_buildings_path}...")

        # DEM 고도 맵 로드 (지표면 Y 높이 안착용)
        dem_data = None
        if os.path.exists(dem_tiff_path):
            with Image.open(dem_tiff_path) as img:
                dem_data = np.array(img, dtype=np.float32)
                dem_data[dem_data < -100.0] = 0.0

        # 수계(하천/호수/해양) 마스크 로드 (수면 위 건물 생성 방지)
        water_mask = None
        if watermask_png_path and os.path.exists(watermask_png_path):
            with Image.open(watermask_png_path) as wm_img:
                water_mask = np.array(wm_img, dtype=np.uint8)

        def is_in_water(lat, lon):
            if water_mask is None:
                return False
            wm_h, wm_w = water_mask.shape
            v = int(np.clip((self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"]) * (wm_h - 1), 0, wm_h - 1))
            u = int(np.clip((lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"]) * (wm_w - 1), 0, wm_w - 1))
            return water_mask[v, u] > 50

        def get_terrain_elevation(lat, lon):
            if dem_data is None:
                return 0.0
            h_h, h_w = dem_data.shape
            v = (self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"]) * (h_h - 1)
            u = (lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"]) * (h_w - 1)

            # 정밀 바이리니어 서브픽셀 보간으로 지형 버텍스와 100% 일치하는 고도 측정
            x0 = int(np.clip(np.floor(u), 0, h_w - 1))
            x1 = int(np.clip(np.ceil(u), 0, h_w - 1))
            y0 = int(np.clip(np.floor(v), 0, h_h - 1))
            y1 = int(np.clip(np.ceil(v), 0, h_h - 1))

            du = u - x0
            dv = v - y0

            h00 = dem_data[y0, x0]
            h10 = dem_data[y0, x1]
            h01 = dem_data[y1, x0]
            h11 = dem_data[y1, x1]

            top = h00 * (1.0 - du) + h10 * du
            bot = h01 * (1.0 - du) + h11 * du
            return float(top * (1.0 - dv) + bot * dv)

        buildings = []
        seen_bldg_ids = set()

        # 1. 랜드마크 주요 건물 추가
        if os.path.exists(landmarks_json_path):
            with open(landmarks_json_path, "r", encoding="utf-8") as f:
                landmarks = json.load(f)

            landmark_footprints = {
                "kokura_station": {"w": 160.0, "d": 75.0, "h": 55.0},
                "mojiko_station": {"w": 65.0, "d": 45.0, "h": 18.0},
                "shimonoseki_terminal": {"w": 120.0, "d": 60.0, "h": 28.0},
                "hinoyama_tower": {"w": 25.0, "d": 25.0, "h": 35.0},
                "kanmon_bridge": {"w": 40.0, "d": 40.0, "h": 140.0}
            }

            for lm in landmarks:
                lid = lm.get("id", "")
                lat = float(lm.get("lat", 0.0))
                lon = float(lm.get("lon", 0.0))
                spec = landmark_footprints.get(lid, {"w": 50.0, "d": 50.0, "h": 30.0})

                wx, wz = self._geo_to_world_2d(lat, lon)
                base_y = get_terrain_elevation(lat, lon)

                hw = spec["w"] * 0.5
                hd = spec["d"] * 0.5
                poly = [
                    [round(wx - hw, 2), round(wz - hd, 2)],
                    [round(wx + hw, 2), round(wz - hd, 2)],
                    [round(wx + hw, 2), round(wz + hd, 2)],
                    [round(wx - hw, 2), round(wz + hd, 2)]
                ]

                seen_bldg_ids.add(lid)
                buildings.append({
                    "id": lid,
                    "name": lm.get("name_ko", ""),
                    "center": [round(wx, 2), round(base_y, 2), round(wz, 2)],
                    "size": [round(spec["w"], 2), round(spec["h"], 2), round(spec["d"], 2)],
                    "base_y": round(base_y, 2),
                    "height": round(spec["h"], 2),
                    "polygon": poly
                })

        # 2. OSM 실측 건물 풋프린트(다각형 밑면 및 높이/층수) 파싱
        if os.path.exists(raw_buildings_path):
            with open(raw_buildings_path, "r", encoding="utf-8") as f:
                bldg_raw = json.load(f)

            bldg_nodes = {}
            for elem in bldg_raw.get("elements", []):
                if elem.get("type") == "node":
                    bldg_nodes[elem["id"]] = (elem["lat"], elem["lon"])

            for elem in bldg_raw.get("elements", []):
                if elem.get("type") == "way" and ("building" in elem.get("tags", {}) or elem.get("tags", {}).get("building") != "no"):
                    way_id = str(elem.get("id", ""))
                    if way_id in seen_bldg_ids:
                        continue

                    way_nodes = elem.get("nodes", [])
                    poly_geo = [bldg_nodes[nid] for nid in way_nodes if nid in bldg_nodes]
                    if len(poly_geo) < 3:
                        continue

                    # 월드 좌표계 변환
                    world_pts = [self._geo_to_world_2d(p[0], p[1]) for p in poly_geo]
                    xs = [p[0] for p in world_pts]
                    zs = [p[1] for p in world_pts]

                    min_x, max_x = min(xs), max(xs)
                    min_z, max_z = min(zs), max(zs)

                    width = max(max_x - min_x, 4.0)
                    depth = max(max_z - min_z, 4.0)
                    cx = (min_x + max_x) * 0.5
                    cz = (min_z + max_z) * 0.5

                    # 밑면 모든 정점의 지표면 고도를 측정하여 최댓값(지형 위로 완전히 노출) 또는 평균값 계산
                    corner_elevs = [get_terrain_elevation(p[0], p[1]) for p in poly_geo]
                    max_corner_y = max(corner_elevs) if corner_elevs else 0.0
                    mean_lat = sum(p[0] for p in poly_geo) / len(poly_geo)
                    mean_lon = sum(p[1] for p in poly_geo) / len(poly_geo)
                    center_y = get_terrain_elevation(mean_lat, mean_lon)

                    # 건물이 경사지에 파묻히지 않도록 최댓값 기준으로 base_y 설정
                    base_y = max(max_corner_y, center_y)

                    # 결함 방지 필터: 해수면 이하(base_y <= 0.2m)이거나 하천/바다 수계 마스크 구역 내 건물 생성 제외
                    if base_y <= 0.2 or is_in_water(mean_lat, mean_lon):
                        continue

                    # 실제 높이/층수 파싱
                    tags = elem.get("tags", {})
                    height = 0.0
                    if "height" in tags:
                        try:
                            h_str = tags["height"].replace("m", "").replace("M", "").strip()
                            height = float(h_str)
                        except Exception:
                            height = 0.0

                    if height <= 0.0 and "building:levels" in tags:
                        try:
                            levels = float(tags["building:levels"])
                            height = levels * 3.4
                        except Exception:
                            height = 0.0

                    if height <= 0.0:
                        footprint_area = width * depth
                        btype = tags.get("building", "yes").lower()
                        if btype in ["apartments", "commercial", "office", "hotel"]:
                            height = 24.0 if footprint_area > 300.0 else 16.0
                        elif btype in ["industrial", "warehouse"]:
                            height = 10.0
                        elif btype in ["house", "residential", "detached"]:
                            height = 7.0
                        else:
                            if footprint_area > 600.0:
                                height = 20.0
                            elif footprint_area > 200.0:
                                height = 12.0
                            else:
                                height = 7.5

                    poly_2d = [[round(p[0], 2), round(p[1], 2)] for p in world_pts]
                    seen_bldg_ids.add(way_id)
                    buildings.append({
                        "id": way_id,
                        "name": tags.get("name:ko", tags.get("name", "")),
                        "center": [round(cx, 2), round(base_y, 2), round(cz, 2)],
                        "size": [round(width, 2), round(height, 2), round(depth, 2)],
                        "base_y": round(base_y, 2),
                        "height": round(height, 2),
                        "polygon": poly_2d
                    })

        # 3. OSM 도로망 및 지하 10m 이하 터널 추출
        roads = []
        tunnels = []
        if os.path.exists(infra_json_path):
            with open(infra_json_path, "r", encoding="utf-8") as f:
                infra_data = json.load(f)

            nodes = {}
            for elem in infra_data.get("elements", []):
                if elem.get("type") == "node":
                    nodes[elem["id"]] = (elem["lat"], elem["lon"])

            for elem in infra_data.get("elements", []):
                if elem.get("type") == "way" and "highway" in elem.get("tags", {}):
                    tags = elem.get("tags", {})
                    hw_type = tags["highway"]
                    is_osm_tunnel = tags.get("tunnel") in ["yes", "building_passage"]
                    way_nodes = elem.get("nodes", [])
                    road_pts = []
                    
                    # 각 정점의 지표면 고도 측정
                    for nid in way_nodes:
                        if nid in nodes:
                            n_lat, n_lon = nodes[nid]
                            rx, rz = self._geo_to_world_2d(n_lat, n_lon)
                            terrain_y = get_terrain_elevation(n_lat, n_lon)
                            road_pts.append({
                                "pos": [round(rx, 2), round(terrain_y, 2), round(rz, 2)],
                                "lat": n_lat,
                                "lon": n_lon,
                                "terrain_y": terrain_y
                            })

                    if len(road_pts) >= 2:
                        # 도로 선형 높이 결정 및 10m 이상 지하 매설 구간 터널 판정
                        # 터널인 경우: 입구와 출구 표고를 선형 보간하여 산악 내부 관통 고도 산출
                        y_start = road_pts[0]["terrain_y"]
                        y_end = road_pts[-1]["terrain_y"]
                        total_cnt = len(road_pts)

                        points_out = []
                        buried_cnt = 0

                        for idx, pt in enumerate(road_pts):
                            t_ratio = float(idx) / float(total_cnt - 1) if total_cnt > 1 else 0.0
                            # 터널 관통 직선 고도
                            tunnel_y = y_start * (1.0 - t_ratio) + y_end * t_ratio
                            diff = pt["terrain_y"] - tunnel_y
                            if diff >= 10.0:
                                buried_cnt += 1

                        is_tunnel = is_osm_tunnel or (buried_cnt >= 2) or (buried_cnt > 0 and buried_cnt == total_cnt - 2)

                        # 간몬대교(Kanmon Bridge) 구간 자동 판정
                        # 모지코-시모노세키 해협 통과 고속도로 또는 OSM bridge=yes 구간
                        is_bridge = False
                        if not is_tunnel:
                            if tags.get("bridge") == "yes" and ("E2A" in tags.get("ref", "") or hw_type == "motorway"):
                                is_bridge = True
                            elif hw_type == "motorway" and any(33.957 <= pt["lat"] <= 33.965 and 130.958 <= pt["lon"] <= 130.966 for pt in road_pts):
                                is_bridge = True

                        for idx, pt in enumerate(road_pts):
                            if is_tunnel:
                                t_ratio = float(idx) / float(total_cnt - 1) if total_cnt > 1 else 0.0
                                ry = y_start * (1.0 - t_ratio) + y_end * t_ratio + 0.5
                            elif is_bridge:
                                # 간몬대교 해상 상판 표고: 해발 61.0m 유지 (육상 접속부와 부드러운 연결)
                                ry = max(61.0, pt["terrain_y"] + 2.0)
                            else:
                                ry = pt["terrain_y"] + 1.2

                            points_out.append([pt["pos"][0], round(ry, 2), pt["pos"][2]])

                        road_obj = {
                            "id": elem.get("id", 0),
                            "type": hw_type,
                            "is_tunnel": is_tunnel,
                            "is_bridge": is_bridge,
                            "name": tags.get("name:ko", tags.get("name", "")),
                            "points": points_out
                        }

                        if is_tunnel:
                            tunnels.append(road_obj)
                        roads.append(road_obj)

        os.makedirs(os.path.dirname(output_json_path), exist_ok=True)
        with open(output_json_path, "w", encoding="utf-8") as f:
            json.dump({
                "building_count": len(buildings),
                "road_count": len(roads),
                "tunnel_count": len(tunnels),
                "buildings": buildings,
                "roads": roads,
                "tunnels": tunnels
            }, f, indent=2, ensure_ascii=False)

        print(f"[BuildingRoadProcessor] Exported {len(buildings)} buildings, {len(roads)} roads ({len(tunnels)} tunnels) to {output_json_path}")
        return output_json_path
