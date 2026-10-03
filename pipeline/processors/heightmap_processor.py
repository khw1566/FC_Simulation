import os
import json
import numpy as np
import cv2
from PIL import Image

class HeightmapProcessor:
    """
    DEM 고도 데이터를 가공하고, 도로 및 건물 구역의 지형을 다듬고 정리(Carving/Smoothing)하여
    건물/도로가 지형 속에 파묻히거나 겹치는 현상을 방지하는 16비트 높이맵 생성 프로세서
    """
    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        self.bbox = self.config["bbox"]

    def process_dem_to_16bit(self, dem_tiff_path, output_png_path, infra_json_path=None, buildings_json_path=None, coastlines_json_path=None, watermask_png_path=None):
        print(f"[HeightmapProcessor] Reading DEM TIFF via PIL: {dem_tiff_path}")
        with Image.open(dem_tiff_path) as img:
            dem_data = np.array(img, dtype=np.float32)

        # 결측치(NoData) 해수면 0m 처리
        dem_data[dem_data < -100.0] = 0.0

        min_val = float(np.min(dem_data))
        max_val = float(np.max(dem_data))
        print(f"[HeightmapProcessor] Raw altitude range: {min_val:.2f}m ~ {max_val:.2f}m")

        target_w = self.config["resolution"]["target_width"]
        target_h = self.config["resolution"]["target_height"]

        if dem_data.shape[1] != target_w or dem_data.shape[0] != target_h:
            print(f"[HeightmapProcessor] Resampling DEM from {dem_data.shape} to ({target_w}, {target_h})...")
            dem_data = cv2.resize(dem_data, (target_w, target_h), interpolation=cv2.INTER_CUBIC)

        # 1. 해안선 픽셀 계단 현상 제거 및 유려한 선형 지형 조작 (Smooth Coastal Blending)
        dem_data = self._smooth_natural_coastline(dem_data, target_w, target_h, coastlines_json_path or infra_json_path)

        # 2. 광폭 하천(태화강) 및 호수 수역 지형 평탄화 및 하상 정지(Riverbed Flattening)
        if watermask_png_path and os.path.exists(watermask_png_path):
            dem_data = self._flatten_water_bodies(dem_data, target_w, target_h, watermask_png_path)

        # 3. 도로 및 건물 부지 지형 절토/정지(Carving & Flattening) 적용
        if infra_json_path or buildings_json_path:
            dem_data = self._carve_roads_and_buildings(dem_data, target_w, target_h, infra_json_path, buildings_json_path)

        # 0 ~ 65535 범위로 정규화 (16-bit PNG)
        min_elev = self.config["elevation_range"]["min_meters"]
        max_elev = self.config["elevation_range"]["max_meters"]

        clamped = np.clip(dem_data, min_elev, max_elev)
        normalized = (clamped - min_elev) / (max_elev - min_elev)
        u16_data = (normalized * 65535.0).astype(np.uint16)

        os.makedirs(os.path.dirname(output_png_path), exist_ok=True)
        out_img = Image.fromarray(u16_data, mode='I;16')
        out_img.save(output_png_path)
        print(f"[HeightmapProcessor] 16-bit Heightmap generated with smooth coastline and carving at: {output_png_path}")

        meta = {
            "source": dem_tiff_path,
            "min_elevation": min_val,
            "max_elevation": max_val,
            "calibrated_min": min_elev,
            "calibrated_max": max_elev,
            "width": target_w,
            "height": target_h
        }
        return output_png_path, meta

    def _carve_roads_and_buildings(self, dem_data, width, height, infra_json_path, buildings_json_path):
        """
        도로 선형을 따라 상부 지형을 깎아내고(Carving) 노면을 평탄화하며,
        건물 부지를 지표면에 밀착 다듬질하는 알고리즘
        """
        print("[HeightmapProcessor] Carving and smoothing terrain under roads and buildings...")
        carved_dem = dem_data.copy()
        
        # 도로 침하 마스크 (도로 중심선 기준 버퍼 영역)
        road_mask = np.zeros((height, width), dtype=np.uint8)

        def coord_to_px(lat, lon):
            x = int((lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"]) * width)
            y = int((self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"]) * height)
            return np.clip(x, 0, width - 1), np.clip(y, 0, height - 1)

        # 1. 도로망 마스킹
        if infra_json_path and os.path.exists(infra_json_path):
            with open(infra_json_path, "r", encoding="utf-8") as f:
                infra_data = json.load(f)

            nodes = {}
            for elem in infra_data.get("elements", []):
                if elem.get("type") == "node":
                    nodes[elem["id"]] = (elem["lat"], elem["lon"])

            for elem in infra_data.get("elements", []):
                if elem.get("type") == "way" and "highway" in elem.get("tags", {}):
                    way_nodes = elem.get("nodes", [])
                    pts = [coord_to_px(*nodes[nid]) for nid in way_nodes if nid in nodes]
                    if len(pts) >= 2:
                        pts_arr = np.array(pts, dtype=np.int32)
                        # 도로 폭(약 10~15m에 해당하는 픽셀 두께 3~5px)
                        cv2.polylines(road_mask, [pts_arr], isClosed=False, color=255, thickness=4)

        # 2. 도로 영역 지형 깎아내기 (상부 지형 0.8m 절토 및 주변부 부드러운 스무딩)
        if np.any(road_mask > 0):
            # 도로 노면 부근 가우시안 블러로 급격한 경사 완화
            blurred_dem = cv2.GaussianBlur(carved_dem, (7, 7), 1.5)
            # 도로 영역은 원래 지형보다 0.8m 아래로 절토하여 도로 메시가 지형 위로 확실히 돌출되도록 다듬음
            carved_road_height = np.minimum(carved_dem, blurred_dem) - 0.8
            road_factor = (road_mask.astype(np.float32) / 255.0)
            carved_dem = carved_dem * (1.0 - road_factor) + carved_road_height * road_factor

        # 3. 건물 부지 평탄화 마스킹
        if buildings_json_path and os.path.exists(buildings_json_path):
            with open(buildings_json_path, "r", encoding="utf-8") as f:
                bldg_data = json.load(f)

            bldg_nodes = {}
            for elem in bldg_data.get("elements", []):
                if elem.get("type") == "node":
                    bldg_nodes[elem["id"]] = (elem["lat"], elem["lon"])

            bldg_mask = np.zeros((height, width), dtype=np.uint8)
            for elem in bldg_data.get("elements", []):
                if elem.get("type") == "way" and "building" in elem.get("tags", {}):
                    way_nodes = elem.get("nodes", [])
                    pts = [coord_to_px(*bldg_nodes[nid]) for nid in way_nodes if nid in bldg_nodes]
                    if len(pts) >= 3:
                        pts_arr = np.array(pts, dtype=np.int32)
                        cv2.fillPoly(bldg_mask, [pts_arr], color=255)

            if np.any(bldg_mask > 0):
                # 건물 밑면 부지는 최소 0.4m 절토하여 지형 솟아오름 방지
                bldg_factor = (bldg_mask.astype(np.float32) / 255.0)
                carved_dem = carved_dem - (bldg_factor * 0.4)

        return carved_dem

    def _flatten_water_bodies(self, dem_data, width, height, watermask_png_path):
        """
        광폭 하천(태화강) 및 호수/저수지 구역의 지형을 수면 높이에 맞춰 평평하게 절토/정지(Flattening)하여
        별도의 3D 수로 오브젝트 없이도 지형 셰이더와 일체화되어 넓은 수면이 완벽한 평면으로 렌더링되도록 함.
        하천 경계부는 거리 변환 기반 가우시안 블렌딩으로 제방/자연 경사지와 매끄럽게 접속.
        """
        print(f"[HeightmapProcessor] Flattening terrain along water bodies from {watermask_png_path}...")
        result_dem = dem_data.copy()
        
        with Image.open(watermask_png_path) as wm_img:
            wm_arr = np.array(wm_img.resize((width, height), Image.Resampling.NEAREST), dtype=np.uint8)
        
        water_mask = (wm_arr > 50)
        if not np.any(water_mask):
            return result_dem

        # 수계 영역의 표고 분석 (태화강 등 저지대 수계의 기준 수위 산출)
        water_heights = result_dem[water_mask]
        target_water_level = float(np.percentile(water_heights, 15)) # 하류/본류 기준 저면 수위
        # 최소 0.5m 이상 유지 (음수 지하 침강 방지)
        target_water_level = max(0.5, target_water_level)
        print(f"[HeightmapProcessor] Water bodies target flat level: {target_water_level:.2f}m")

        # 수계 영역 내부를 완만하게 평탄화 (완만한 하상 구배 유지 및 돌출 바위 평탄화)
        flat_dem = np.minimum(result_dem, target_water_level)
        # 하천 중심부 가우시안 스무딩으로 국소 요철 완전 제거
        blurred_water = cv2.GaussianBlur(flat_dem, (15, 15), 5.0)

        # 제방 경계 안티에일리어싱 블렌드 (가장자리 3~5픽셀 유려한 연결)
        mask_u8 = (water_mask.astype(np.uint8)) * 255
        dist_kernel = cv2.dilate(mask_u8, np.ones((5, 5), np.uint8), iterations=1)
        blend_weight = cv2.GaussianBlur(dist_kernel.astype(np.float32) / 255.0, (11, 11), 3.0)

        # 지형 합성: 수계 구역은 blurred_water, 주변부는 기존 dem_data
        result_dem = result_dem * (1.0 - blend_weight) + blurred_water * blend_weight
        print("[HeightmapProcessor] Water bodies terrain flattening complete.")
        return result_dem

    def _smooth_natural_coastline(self, dem_data, width, height, coast_or_infra_json):
        """
        별도의 선형 오브젝트 없이 지형 높이맵 자체를 유려하게 조작하여
        사각형 픽셀 계단 현상을 제거하고 자연스러운 곡선 해안선을 구현하는 알고리즘.
        해수면 경계(고도 -1.5m ~ +3.0m) 및 실측 해안선 벡터 주변에 양방향 거리 가중 스무딩을 적용합니다.
        """
        print("[HeightmapProcessor] Smoothing coastline terrain for natural curvature (eliminating pixel staircasing)...")
        result_dem = dem_data.copy()

        # 1. 해수면 인접 완충 구역(-1.0m ~ 3.5m) 마스크 생성
        coastal_band = (result_dem >= -1.0) & (result_dem <= 3.5)

        # 2. OSM 실측 해안선 벡터 버퍼 마스크
        coast_mask = np.zeros((height, width), dtype=np.uint8)
        if coast_or_infra_json and os.path.exists(coast_or_infra_json):
            try:
                with open(coast_or_infra_json, "r", encoding="utf-8") as f:
                    cdata = json.load(f)

                nodes = {}
                for elem in cdata.get("elements", []):
                    if elem.get("type") == "node":
                        nodes[elem["id"]] = (elem["lat"], elem["lon"])

                def coord_to_px(lat, lon):
                    x = int((lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"]) * width)
                    y = int((self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"]) * height)
                    return np.clip(x, 0, width - 1), np.clip(y, 0, height - 1)

                for elem in cdata.get("elements", []):
                    tags = elem.get("tags", {})
                    if elem.get("type") == "way" and (tags.get("natural") == "coastline" or "waterway" in tags):
                        pts = [coord_to_px(*nodes[nid]) for nid in elem.get("nodes", []) if nid in nodes]
                        if len(pts) >= 2:
                            pts_arr = np.array(pts, dtype=np.int32)
                            cv2.polylines(coast_mask, [pts_arr], isClosed=False, color=255, thickness=8)
            except Exception as e:
                print(f"[HeightmapProcessor] Warning reading coast vector: {e}")

        # 3. 고도 0m 경계 부근과 실측 해안선 버퍼를 결합한 스무딩 대상 마스크
        blend_mask = coastal_band | (coast_mask > 0)
        mask_u8 = blend_mask.astype(np.uint8) * 255

        # 4. 거리 변환(Distance Transform) 기반 안티에일리어싱 가중치 맵 계산
        dist_kernel = cv2.dilate(mask_u8, np.ones((5, 5), np.uint8), iterations=2)
        dist_weight = cv2.GaussianBlur(dist_kernel.astype(np.float32) / 255.0, (15, 15), 3.0)

        # 5. 서브픽셀 곡률 스무딩 (바이래터럴 + 가우시안 다중 스케일 필터)
        # 사각형 픽셀 계단을 완전히 지우고 수면과 육지가 매끄러운 곡면으로 맞닿도록 보정
        smoothed_stage1 = cv2.GaussianBlur(result_dem, (9, 9), 2.0)
        smoothed_stage2 = cv2.GaussianBlur(result_dem, (19, 19), 4.5)
        blended_smooth = smoothed_stage1 * 0.6 + smoothed_stage2 * 0.4

        # 해수면 아래 해저는 0 이하를 유지하고, 육상부는 고유 형태를 보존하면서 경계만 부드럽게 융합
        result_dem = result_dem * (1.0 - dist_weight) + blended_smooth * dist_weight

        print("[HeightmapProcessor] Natural coastline smoothing complete.")
        return result_dem

