"""
해안선/수계 OSM 데이터에서 방파제(Breakwater) 구조물을 감지/추출하여
buildings_and_roads.json에 breakwaters 배열로 병합하는 프로세서

감지 기준:
1. man_made=breakwater/pier/groyne/jetty 태그 명시 구조물
2. natural=coastline 중 폐곡선이면서 종횡비 >= 2.0, 폭 < 80m, 길이 > 30m인 좁고 긴 선형 지형
"""
import os
import json
import math
import numpy as np
from PIL import Image


class BreakwaterProcessor:
    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        self.bbox = self.config["bbox"]
        self.world_size = float(self.config.get("world_size_meters", 28000.0))

    def _geo_to_world(self, lat, lon):
        fx = (lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"])
        fz = (self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"])
        return (fx - 0.5) * self.world_size, (fz - 0.5) * self.world_size

    def _geo_distance_m(self, lat1, lon1, lat2, lon2):
        dx = (lon2 - lon1) * 111000.0 * math.cos(math.radians((lat1 + lat2) * 0.5))
        dy = (lat2 - lat1) * 111000.0
        return math.sqrt(dx * dx + dy * dy)

    def extract_breakwaters(self, water_json_path, dem_tiff_path=None):
        """OSM 수계 JSON에서 방파제 폴리라인을 추출"""
        if not os.path.exists(water_json_path):
            print(f"[BreakwaterProcessor] Water JSON not found: {water_json_path}")
            return []

        with open(water_json_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        # DEM 로드 (방파제 기저 고도용)
        dem_data = None
        if dem_tiff_path and os.path.exists(dem_tiff_path):
            with Image.open(dem_tiff_path) as img:
                dem_data = np.array(img, dtype=np.float32)
                dem_data[dem_data < -100.0] = 0.0

        def get_elev(lat, lon):
            if dem_data is None:
                return 0.0
            h_h, h_w = dem_data.shape
            v = (self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"]) * (h_h - 1)
            u = (lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"]) * (h_w - 1)
            x0, y0 = int(np.clip(u, 0, h_w - 1)), int(np.clip(v, 0, h_h - 1))
            return float(dem_data[y0, x0])

        nodes = {}
        for elem in data.get("elements", []):
            if elem.get("type") == "node":
                nodes[elem["id"]] = (elem["lat"], elem["lon"])

        breakwaters = []

        for elem in data.get("elements", []):
            if elem.get("type") != "way":
                continue
            tags = elem.get("tags", {})
            mm = tags.get("man_made", "")
            is_tagged = mm in ("breakwater", "pier", "groyne", "jetty")
            is_coast = tags.get("natural") == "coastline"

            if not is_tagged and not is_coast:
                continue

            way_nodes = elem.get("nodes", [])
            geo_pts = [(nodes[nid][0], nodes[nid][1]) for nid in way_nodes if nid in nodes]
            if len(geo_pts) < 2:
                continue

            # 바운딩 박스 기반 종횡비 분석
            lats = [p[0] for p in geo_pts]
            lons = [p[1] for p in geo_pts]
            center_lat = sum(lats) / len(lats)
            lat_span = (max(lats) - min(lats)) * 111000.0
            lon_span = (max(lons) - min(lons)) * 111000.0 * math.cos(math.radians(center_lat))

            width = min(lat_span, lon_span)
            length = max(lat_span, lon_span)
            aspect = length / max(width, 1.0)

            # 방파제 판정 조건
            if is_tagged:
                pass  # 태그 명시 → 무조건 포함
            elif is_coast and aspect >= 2.0 and width < 80.0 and length > 30.0:
                pass  # 좁고 긴 해안선 → 방파제 후보
            else:
                continue

            # 폐곡선 → 중심선(스켈레톤) 추출
            is_closed = len(way_nodes) > 2 and way_nodes[0] == way_nodes[-1]
            if is_closed and len(geo_pts) >= 4:
                centerline = self._extract_centerline(geo_pts)
            else:
                centerline = geo_pts

            # 월드 좌표 변환
            world_pts = []
            for lat, lon in centerline:
                wx, wz = self._geo_to_world(lat, lon)
                wy = max(get_elev(lat, lon), 0.5)
                world_pts.append([round(wx, 2), round(wy, 2), round(wz, 2)])

            if len(world_pts) < 2:
                continue

            # 총 길이 계산
            total_len = 0.0
            for i in range(len(world_pts) - 1):
                dx = world_pts[i + 1][0] - world_pts[i][0]
                dz = world_pts[i + 1][2] - world_pts[i][2]
                total_len += math.sqrt(dx * dx + dz * dz)

            breakwaters.append({
                "id": elem.get("id", 0),
                "type": mm if is_tagged else "auto_detected",
                "width_m": round(width, 1),
                "length_m": round(total_len, 1),
                "points": world_pts,
                "has_lighthouse": total_len >= 50.0
            })

        print(f"[BreakwaterProcessor] Extracted {len(breakwaters)} breakwater structures")
        return breakwaters

    def _extract_centerline(self, geo_pts):
        """폐곡선 폴리곤에서 장축 방향 중심선을 추출"""
        lats = [p[0] for p in geo_pts]
        lons = [p[1] for p in geo_pts]
        center_lat = sum(lats) / len(lats)

        lat_span = max(lats) - min(lats)
        lon_span = (max(lons) - min(lons)) * math.cos(math.radians(center_lat))

        # 장축 방향 판정 (위도 vs 경도)
        if lat_span >= lon_span:
            # 남북 방향 장축: 경도 기준 좌우 분리 후 평균
            sorted_pts = sorted(geo_pts, key=lambda p: p[0])
        else:
            # 동서 방향 장축: 위도 기준 상하 분리 후 평균
            sorted_pts = sorted(geo_pts, key=lambda p: p[1])

        n = len(sorted_pts)
        half = n // 2
        # 양쪽 절반의 대응점을 평균내어 중심선 생성
        centerline = []
        step = max(1, half // 8)
        for i in range(0, half, step):
            j = n - 1 - i
            if j < half:
                break
            avg_lat = (sorted_pts[i][0] + sorted_pts[j][0]) * 0.5
            avg_lon = (sorted_pts[i][1] + sorted_pts[j][1]) * 0.5
            centerline.append((avg_lat, avg_lon))

        if len(centerline) < 2:
            centerline = [sorted_pts[0], sorted_pts[-1]]

        return centerline

    def inject_into_buildings_roads(self, buildings_roads_json, breakwaters):
        """기존 buildings_and_roads.json에 breakwaters 배열을 추가 병합"""
        if not breakwaters:
            return

        with open(buildings_roads_json, "r", encoding="utf-8") as f:
            data = json.load(f)

        data["breakwaters"] = breakwaters
        data["breakwater_count"] = len(breakwaters)

        with open(buildings_roads_json, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

        print(f"[BreakwaterProcessor] Injected {len(breakwaters)} breakwaters into {buildings_roads_json}")
