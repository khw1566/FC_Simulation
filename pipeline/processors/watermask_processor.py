import os
import json
import numpy as np
import cv2

class WatermaskProcessor:
    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)

    def generate_water_mask(self, osm_json_path, output_png_path):
        print(f"[WatermaskProcessor] Parsing OSM waterways & water bodies from {osm_json_path}")
        with open(osm_json_path, "r", encoding="utf-8") as f:
            osm_data = json.load(f)

        bbox = self.config["bbox"]
        target_w = self.config["resolution"]["target_width"]
        target_h = self.config["resolution"]["target_height"]

        # 0: 육지, 255: 바다/하천/호수
        mask = np.zeros((target_h, target_w), dtype=np.uint8)

        nodes = {}
        for elem in osm_data.get("elements", []):
            if elem.get("type") == "node":
                nodes[elem["id"]] = (elem["lat"], elem["lon"])

        def coord_to_pixel(lat, lon):
            y = int((bbox["north"] - lat) / (bbox["north"] - bbox["south"]) * target_h)
            x = int((lon - bbox["west"]) / (bbox["east"] - bbox["west"]) * target_w)
            return np.clip(x, 0, target_w - 1), np.clip(y, 0, target_h - 1)

        # 1. Relation multipolygon 수역 파싱 (태화강 등 광폭 하천 외곽 및 내측 섬)
        rel_outer_ways = set()
        rel_inner_ways = set()
        for elem in osm_data.get("elements", []):
            if elem.get("type") == "relation":
                tags = elem.get("tags", {})
                if tags.get("natural") == "water" or tags.get("water") in ["river", "lake", "reservoir"]:
                    for m in elem.get("members", []):
                        if m.get("role") == "outer":
                            rel_outer_ways.add(m.get("ref"))
                        elif m.get("role") == "inner":
                            rel_inner_ways.add(m.get("ref"))

        # 맵의 실제 물리적 크기(meters) 및 픽셀당 미터 해상도 계산
        world_size_m = float(self.config.get("world_size_meters", self.config.get("area_km", 28.0) * 1000.0))
        m_per_px = world_size_m / max(target_w, 1)

        # 실측 하천/수로 폭(미터) 기준 픽셀 두께 산정:
        # 주요 본류 하천 (river): 기본 60m 폭 (최소 1px, 2048해상도 5km맵 기준 약 25px, 60km맵 4px, 140km맵 2px)
        # 지류/소하천/운하 (stream, canal 등 waterway): 기본 20m 폭 (최소 1px)
        # 해안선 (coastline): 1px (단순 경계선)
        river_px = max(1, int(round(60.0 / m_per_px)))
        waterway_px = max(1, int(round(20.0 / m_per_px)))
        coastline_px = max(1, int(round(15.0 / m_per_px)))

        # 2. 수역/호수 폐곡선(Polygon) 및 하천(River/Stream) 렌더링
        for elem in osm_data.get("elements", []):
            if elem.get("type") == "way":
                tags = elem.get("tags") or {}
                wid = elem.get("id")
                way_nodes = elem.get("nodes", [])
                pts = [coord_to_pixel(*nodes[nid]) for nid in way_nodes if nid in nodes]

                if len(pts) > 1:
                    pts_arr = np.array(pts, dtype=np.int32)
                    is_water_poly = tags.get("natural") == "water" or tags.get("water") in ["lake", "reservoir", "river"] or (wid in rel_outer_ways)

                    if is_water_poly and len(pts) >= 3:
                        # 호수/저수지/광폭 하천(태화강 본류 등) 실제 외곽 폴리곤 면적 채우기
                        cv2.fillPoly(mask, [pts_arr], color=255)
                    elif tags.get("waterway") == "river":
                        # 중심선만 정의된 하천: 실측 강폭(60m) 비례 픽셀 두께 적용
                        cv2.polylines(mask, [pts_arr], isClosed=False, color=255, thickness=river_px)
                    elif "waterway" in tags:
                        # 소하천, 개울, 수로: 실측 폭(20m) 비례 픽셀 두께 적용
                        cv2.polylines(mask, [pts_arr], isClosed=False, color=255, thickness=waterway_px)
                    elif tags.get("natural") == "coastline":
                        cv2.polylines(mask, [pts_arr], isClosed=False, color=255, thickness=coastline_px)

        # 3. Relation 내측 섬(Inner ways) 구멍 뚫기
        for elem in osm_data.get("elements", []):
            if elem.get("type") == "way" and elem.get("id") in rel_inner_ways:
                way_nodes = elem.get("nodes", [])
                pts = [coord_to_pixel(*nodes[nid]) for nid in way_nodes if nid in nodes]
                if len(pts) >= 3:
                    cv2.fillPoly(mask, [np.array(pts, dtype=np.int32)], color=0)

        os.makedirs(os.path.dirname(output_png_path), exist_ok=True)
        cv2.imwrite(output_png_path, mask)
        print(f"[WatermaskProcessor] Complete water mask generated at: {output_png_path} (pixels: {np.sum(mask > 0)})")
        return output_png_path

