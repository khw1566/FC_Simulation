import os
import json
import numpy as np
from PIL import Image, ImageDraw

class VectorMapRenderer:
    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        self.bbox = self.config["bbox"]
        self.width = self.config["resolution"]["target_width"]   # 2048
        self.height = self.config["resolution"]["target_height"] # 2048

    def _coord_to_pixel(self, lat, lon):
        y = (self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"]) * self.height
        x = (lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"]) * self.width
        return (float(x), float(y))

    def render_tactical_vector_map(self, infra_json_path, dem_tiff_path, landmarks_json_path, output_png_path):
        print(f"[VectorMapRenderer] Generating tactical vector map with contours & infra...")

        # 1. 고도 데이터 로드 및 등고선(Contour) 래스터 생성
        from PIL import ImageFilter
        with Image.open(dem_tiff_path) as d_img:
            dem_data = np.array(d_img, dtype=np.float32)
        
        # 해상도 2048x2048 리샘플링
        import cv2
        if dem_data.shape != (self.height, self.width):
            dem_data = cv2.resize(dem_data, (self.width, self.height), interpolation=cv2.INTER_CUBIC)

        # 등고선 마스크 계산 (25m 간격, 100m 주곡선)
        contour_interval = 25.0
        dist = np.abs((dem_data % contour_interval) - (contour_interval * 0.5))
        is_contour = (dist < 1.2) & (dem_data > 2.0)
        
        # 100m 주곡선
        major_dist = np.abs((dem_data % 100.0) - 50.0)
        is_major = (major_dist < 2.0) & (dem_data > 2.0)

        # 2. 흑백 모노크롬 베이스 캔버스 생성 (어두운 전술 지도 테마)
        map_img = Image.new("RGBA", (self.width, self.height), (18, 20, 24, 255))
        draw = ImageDraw.Draw(map_img)

        # 해양 구역 (고도 <= 0m) 어두운 네이비블랙 채우기
        sea_mask = (dem_data <= 0.5)
        # 등고선 픽셀 알파 블렌딩
        contour_pixels = np.zeros((self.height, self.width, 4), dtype=np.uint8)
        contour_pixels[is_contour] = [70, 75, 82, 120]
        contour_pixels[is_major] = [100, 105, 115, 200]
        c_img = Image.fromarray(contour_pixels, mode="RGBA")
        map_img.alpha_composite(c_img)

        # 3. OSM 벡터 로드 및 드로잉 (해안선, 도로, 철도)
        with open(infra_json_path, "r", encoding="utf-8") as f:
            osm_data = json.load(f)

        nodes = {}
        ways = []
        for elem in osm_data.get("elements", []):
            if elem.get("type") == "node":
                nodes[elem["id"]] = (elem["lat"], elem["lon"])
            elif elem.get("type") == "way":
                ways.append(elem)

        coastlines = []
        railways = []
        highways_primary = []
        highways_secondary = []

        for w in ways:
            tags = w.get("tags", {})
            pts = [self._coord_to_pixel(*nodes[nid]) for nid in w.get("nodes", []) if nid in nodes]
            if len(pts) < 2:
                continue

            if tags.get("natural") == "coastline":
                coastlines.append(pts)
            elif "railway" in tags:
                railways.append(pts)
            elif tags.get("highway") in ["motorway", "trunk", "primary"]:
                highways_primary.append(pts)
            elif tags.get("highway") in ["secondary", "tertiary"]:
                highways_secondary.append(pts)

        # 3.1. 해안선 렌더링 (굵은 청백색 외곽선)
        for pts in coastlines:
            draw.line(pts, fill=(180, 200, 220, 240), width=3)

        # 3.2. 일반 간선 도로 렌더링 (그레이 라인)
        for pts in highways_secondary:
            draw.line(pts, fill=(75, 80, 88, 180), width=2)

        # 3.3. 주요 고속도로/간선도로 렌더링 (선명한 화이트 라인)
        for pts in highways_primary:
            draw.line(pts, fill=(220, 225, 230, 240), width=3)

        # 3.4. 철도망 렌더링 (점선 패턴 느낌의 듀얼 라인)
        for pts in railways:
            draw.line(pts, fill=(140, 145, 155, 220), width=2)

        # 4. 주요 랜드마크 점(Point) 및 명칭 표기
        if os.path.exists(landmarks_json_path):
            with open(landmarks_json_path, "r", encoding="utf-8") as f:
                landmarks = json.load(f)

            for lm in landmarks:
                lat = float(lm.get("lat", 0.0))
                lon = float(lm.get("lon", 0.0))
                name = lm.get("name_ko", "")
                px, py = self._coord_to_pixel(lat, lon)

                # 외부 링
                r_out = 9
                draw.ellipse([(px - r_out, py - r_out), (px + r_out, py + r_out)], outline=(255, 255, 255, 255), width=2)
                # 내부 채움 점
                r_in = 4
                draw.ellipse([(px - r_in, py - r_in), (px + r_in, py + r_in)], fill=(255, 255, 255, 255))
                # 랜드마크 라벨 텍스트
                draw.text((px + 12, py - 6), name, fill=(240, 245, 255, 255))

        os.makedirs(os.path.dirname(output_png_path), exist_ok=True)
        map_img.save(output_png_path, "PNG")
        print(f"[VectorMapRenderer] Vector tactical map saved to: {output_png_path}")
        return output_png_path
