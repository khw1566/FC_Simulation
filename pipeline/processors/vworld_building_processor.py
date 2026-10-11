import os
import json
import numpy as np
from PIL import Image

class VWorldBuildingProcessor:
    """
    디지털 트윈국토(VWorld) 국가공간정보 건물통합정보(LT_C_SPBD) GeoJSON으로부터
    정밀 실측 다각형 밑면 및 실제 층수/높이를 반영한 3D 건물 데이터를 생성하는 프로세서
    위성영상 추출 필요 없이 국가 공간정보 공공데이터의 기하(Geometry)를 100% 직접 활용합니다.
    """
    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        self.bbox = self.config["bbox"]
        self.world_size = float(self.config.get("world_size_meters", self.config.get("area_km", 5.0) * 1000.0))

    def _geo_to_world_2d(self, lat, lon):
        frac_x = (lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"])
        frac_z = (self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"])
        world_x = (frac_x - 0.5) * self.world_size
        world_z = (frac_z - 0.5) * self.world_size
        return world_x, world_z

    def process_vworld_buildings(self, vworld_geojson_path, dem_tiff_path, output_json_path, watermask_png_path=None):
        print(f"[VWorldBuildingProcessor] Processing VWorld building features from {vworld_geojson_path}...")

        with open(vworld_geojson_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        features = data.get("features", [])

        # DEM 고도 맵 로드
        dem_data = None
        min_elev = float(self.config.get("elevation_range", {}).get("min_meters", -30.0))
        max_elev = float(self.config.get("elevation_range", {}).get("max_meters", 1250.0))

        if os.path.exists(dem_tiff_path):
            with Image.open(dem_tiff_path) as img:
                dem_data = np.array(img, dtype=np.float32)
                # 만약 16비트 정수 높이맵 PNG인 경우 (0~65535), 물리적 실제 고도(m)로 역변환
                if dem_data.max() > 2000.0 or dem_tiff_path.lower().endswith(".png"):
                    dem_data = min_elev + (dem_data / 65535.0) * (max_elev - min_elev)
                else:
                    dem_data[dem_data < -100.0] = 0.0

        # 수계 마스크 로드
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

        for feat in features:
            props = feat.get("properties", {})
            geom = feat.get("geometry", {})
            g_type = geom.get("type", "")
            coords = geom.get("coordinates", [])

            bldg_id = str(props.get("bd_mgt_sn", props.get("buld_no", len(buildings))))
            if bldg_id in seen_bldg_ids:
                continue

            # 폴리곤 링 추출 (Polygon or MultiPolygon)
            polygons_to_process = []
            if g_type == "Polygon" and coords:
                polygons_to_process.append(coords[0]) # 외부 링
            elif g_type == "MultiPolygon" and coords:
                for poly in coords:
                    if poly:
                        polygons_to_process.append(poly[0])

            for ring in polygons_to_process:
                if len(ring) < 3:
                    continue

                # 경위도 좌표계: VWorld GeoJSON은 [lon, lat]
                poly_geo = [(p[1], p[0]) for p in ring] # (lat, lon)
                
                # 바운딩 박스 내부 필터링
                mean_lat = sum(p[0] for p in poly_geo) / len(poly_geo)
                mean_lon = sum(p[1] for p in poly_geo) / len(poly_geo)

                if not (self.bbox["south"] <= mean_lat <= self.bbox["north"] and self.bbox["west"] <= mean_lon <= self.bbox["east"]):
                    continue

                # 수계 내부 건물 배제
                if is_in_water(mean_lat, mean_lon):
                    continue

                # 월드 좌표계 변환
                world_pts = [self._geo_to_world_2d(p[0], p[1]) for p in poly_geo]
                xs = [p[0] for p in world_pts]
                zs = [p[1] for p in world_pts]

                min_x, max_x = min(xs), max(xs)
                min_z, max_z = min(zs), max(zs)
                width = max(max_x - min_x, 3.0)
                depth = max(max_z - min_z, 3.0)
                cx = (min_x + max_x) * 0.5
                cz = (min_z + max_z) * 0.5

                corner_elevs = [get_terrain_elevation(p[0], p[1]) for p in poly_geo]
                max_corner_y = max(corner_elevs) if corner_elevs else 0.0
                center_y = get_terrain_elevation(mean_lat, mean_lon)
                base_y = max(max_corner_y, center_y)

                # 층수 기반 실제 높이 계산 (gro_flo_co)
                floor_str = str(props.get("gro_flo_co", "1")).strip()
                try:
                    floors = float(floor_str) if floor_str else 1.0
                except Exception:
                    floors = 1.0

                if floors <= 0:
                    floors = 1.0

                # 층당 3.3m + 지붕 파라펫 0.5m
                height = round(floors * 3.3 + 0.5, 2)

                bldg_name = props.get("buld_nm", "").strip()
                if not bldg_name:
                    rd_nm = props.get("rd_nm", "").strip()
                    bno = props.get("buld_no", "").strip()
                    bldg_name = f"{rd_nm} {bno}".strip()

                poly_2d = [[round(p[0], 2), round(p[1], 2)] for p in world_pts]
                seen_bldg_ids.add(bldg_id)

                buildings.append({
                    "id": bldg_id,
                    "name": bldg_name,
                    "floors": int(floors),
                    "center": [round(cx, 2), round(base_y, 2), round(cz, 2)],
                    "size": [round(width, 2), round(height, 2), round(depth, 2)],
                    "base_y": round(base_y, 2),
                    "height": round(height, 2),
                    "polygon": poly_2d
                })

        # 기존 파일에 구축된 도로/터널망이 있다면 보존 병합
        existing_roads = []
        existing_tunnels = []
        existing_road_source = None
        if os.path.exists(output_json_path):
            try:
                with open(output_json_path, "r", encoding="utf-8") as ef:
                    old_data = json.load(ef)
                    existing_roads = old_data.get("roads", [])
                    existing_tunnels = old_data.get("tunnels", [])
                    existing_road_source = old_data.get("road_source")
            except Exception:
                pass

        os.makedirs(os.path.dirname(output_json_path), exist_ok=True)
        out_dict = {
            "building_count": len(buildings),
            "road_count": len(existing_roads),
            "tunnel_count": len(existing_tunnels),
            "source": "VWorld_LT_C_SPBD",
            "region": self.config.get("region_name", "ulsan_uc_west"),
            "buildings": buildings,
            "roads": existing_roads,
            "tunnels": existing_tunnels
        }
        if existing_road_source is not None:
            out_dict["road_source"] = existing_road_source

        with open(output_json_path, "w", encoding="utf-8") as f:
            json.dump(out_dict, f, indent=2, ensure_ascii=False)

        print(f"[VWorldBuildingProcessor] Successfully processed and exported {len(buildings)} buildings to {output_json_path}")
        return output_json_path
