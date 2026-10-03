import os
import json
import time
import requests
import numpy as np
from PIL import Image

class UlsanInfraCollectorProcessor:
    """
    울산과학대학교 서부캠퍼스 5km 권역의
    1) VWorld 도로명주소 도로구간(LT_L_SPRD) 및 표준교통링크(LT_L_MOCTLINK) 도로망 수집 및 3D 노면 고도 일치 가공
    2) 태화강/무거천 실측 수계 하천망 벡터 수로(Coastlines & Waterways) 가공
    을 통합 수행하는 프로세서
    """
    VWORLD_URL = "https://api.vworld.kr/req/data"

    def __init__(self, config_path, api_key_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        with open(api_key_path, "r", encoding="utf-8") as f:
            self.keys = json.load(f)
        self.api_key = self.keys.get("vworld_api_key", "").strip()
        self.bbox = self.config["bbox"]
        self.world_size = float(self.config.get("world_size_meters", 5000.0))

    def _geo_to_world_2d(self, lat, lon):
        frac_x = (lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"])
        frac_z = (self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"])
        world_x = (frac_x - 0.5) * self.world_size
        world_z = (frac_z - 0.5) * self.world_size
        return world_x, world_z

    def fetch_and_process_all(self, raw_water_json, dem_tiff_path, buildings_roads_json_path, waterways_json_path):
        print("[UlsanInfra] Starting road and waterway collection & processing...")

        # 1. DEM 고도 맵 로드 (바이리니어 노면 고도 일치용)
        dem_data = None
        if os.path.exists(dem_tiff_path):
            with Image.open(dem_tiff_path) as img:
                dem_data = np.array(img, dtype=np.float32)
                dem_data[dem_data < -100.0] = 0.0

        def get_terrain_elevation(lat, lon):
            if dem_data is None:
                return 0.0
            h_h, h_w = dem_data.shape
            v = (self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"]) * (h_h - 1)
            u = (lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"]) * (h_w - 1)

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

        # 2. VWorld 도로구간(LT_L_SPRD) 전수 수집
        geom_filter = f"BOX({self.bbox['west']},{self.bbox['south']},{self.bbox['east']},{self.bbox['north']})"
        page = 1
        page_size = 100
        all_road_features = []

        print("[UlsanInfra] Fetching VWorld road segments (LT_L_SPRD)...")
        while True:
            params = {
                "service": "data",
                "request": "GetFeature",
                "data": "LT_L_SPRD",
                "key": self.api_key,
                "format": "json",
                "geometry": "true",
                "attribute": "true",
                "crs": "EPSG:4326",
                "geomFilter": geom_filter,
                "page": page,
                "size": page_size
            }
            try:
                resp = requests.get(self.VWORLD_URL, params=params, timeout=20)
                if resp.status_code != 200:
                    break
                data = resp.json()
                feats = data.get("response", {}).get("result", {}).get("featureCollection", {}).get("features", [])
                if not feats:
                    break
                all_road_features.extend(feats)
                total = int(data.get("response", {}).get("record", {}).get("total", 0))
                print(f" - Page {page}: fetched {len(feats)} roads (Accumulated: {len(all_road_features)}/{total})")
                if len(all_road_features) >= total:
                    break
                page += 1
                time.sleep(0.1)
            except Exception as e:
                print(f"Error fetching roads: {e}")
                break

        # 3. 도로 데이터 3D 좌표 변환
        processed_roads = []
        for feat in all_road_features:
            props = feat.get("properties", {})
            geom = feat.get("geometry", {})
            coords = geom.get("coordinates", [])
            g_type = geom.get("type", "")

            lines = []
            if g_type == "LineString":
                lines.append(coords)
            elif g_type == "MultiLineString":
                lines.extend(coords)

            road_name = props.get("rn", "도로").strip()
            # 도로 폭 결정 (대로/로: 14m, 길: 8m)
            width = 14.0 if ("대로" in road_name or "로" in road_name and "길" not in road_name) else 8.0

            for line in lines:
                if len(line) < 2:
                    continue

                pts_out = []
                for pt in line:
                    lon, lat = float(pt[0]), float(pt[1])
                    wx, wz = self._geo_to_world_2d(lat, lon)
                    ty = get_terrain_elevation(lat, lon)
                    # 도로면 지표면 위 0.4m 띄움 (Z-fighting 방지)
                    pts_out.append([round(wx, 2), round(ty + 0.4, 2), round(wz, 2)])

                processed_roads.append({
                    "id": f"rd_{len(processed_roads) + 1}",
                    "name": road_name,
                    "width": width,
                    "type": "residential",
                    "tunnel": False,
                    "bridge": False,
                    "points": pts_out
                })

        # 기존 건물 데이터 로드하여 도로망 병합 저장
        if os.path.exists(buildings_roads_json_path):
            with open(buildings_roads_json_path, "r", encoding="utf-8") as f:
                bldg_file_data = json.load(f)
        else:
            bldg_file_data = {"buildings": []}

        bldg_file_data["roads"] = processed_roads
        bldg_file_data["road_count"] = len(processed_roads)

        with open(buildings_roads_json_path, "w", encoding="utf-8") as f:
            json.dump(bldg_file_data, f, indent=2, ensure_ascii=False)
        print(f"[UlsanInfra] Successfully merged {len(processed_roads)} roads into {buildings_roads_json_path}")

        # 4. 태화강/무거천 수계 하천망 리본(Waterway Ribbons) 벡터 생성
        processed_waterways = []
        if os.path.exists(raw_water_json):
            with open(raw_water_json, "r", encoding="utf-8") as f:
                w_data = json.load(f)

            w_nodes = {}
            for elem in w_data.get("elements", []):
                if elem.get("type") == "node":
                    w_nodes[elem["id"]] = (elem["lat"], elem["lon"])

            for elem in w_data.get("elements", []):
                if elem.get("type") == "way" and ("waterway" in elem.get("tags", {}) or elem.get("tags", {}).get("natural") == "water"):
                    tags = elem.get("tags", {})
                    node_ids = elem.get("nodes", [])
                    geo_pts = [w_nodes[nid] for nid in node_ids if nid in w_nodes]
                    if len(geo_pts) < 2:
                        continue

                    # 태화강 본류는 폭 75m, 지류 소하천은 폭 18m
                    r_name = tags.get("name", tags.get("waterway", "하천"))
                    r_width = 75.0 if ("태화강" in r_name or tags.get("waterway") == "river") else 18.0

                    pts_out = []
                    for lat, lon in geo_pts:
                        wx, wz = self._geo_to_world_2d(lat, lon)
                        ty = get_terrain_elevation(lat, lon)
                        # 수면은 지표면 위 0.25m에 부드럽게 얹음
                        pts_out.append([round(wx, 2), round(ty + 0.25, 2), round(wz, 2)])

                    processed_waterways.append({
                        "id": f"wtr_{len(processed_waterways) + 1}",
                        "name": r_name,
                        "width": r_width,
                        "points": pts_out
                    })

        water_out = {
            "region": "ulsan_uc_west",
            "coastlines": [],
            "waterways": processed_waterways
        }
        os.makedirs(os.path.dirname(waterways_json_path), exist_ok=True)
        with open(waterways_json_path, "w", encoding="utf-8") as f:
            json.dump(water_out, f, indent=2, ensure_ascii=False)
        print(f"[UlsanInfra] Successfully exported {len(processed_waterways)} waterway channels into {waterways_json_path}")
        return len(processed_roads), len(processed_waterways)
