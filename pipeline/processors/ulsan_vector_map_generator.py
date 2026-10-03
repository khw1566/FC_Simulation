import os
import json
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw
import numpy as np

class UlsanVectorMapGenerator:
    """
    울산과학대학교 서부캠퍼스 5km 권역의 VWorld 실측 건물 및 수계, 등고선 데이터를 결합하여
    1) 2D 벡터 이미지 (SVG 형식: building_footprints.svg)
    2) 미니맵 및 M키 전체화면 지도용 래스터 텍스처 (ulsan_vector_tactical_map.png)
    를 생성하는 프로세서
    """
    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        self.bbox = self.config["bbox"]
        res = self.config.get("resolution", {})
        self.width = res.get("target_width", 2048)
        self.height = res.get("target_height", 2048)

    def _coord_to_pixel(self, lat, lon):
        frac_x = (lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"])
        frac_y = (self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"])
        return (float(frac_x * self.width), float(frac_y * self.height))

    def generate_building_svg_and_tactical_map(self, vworld_raw_json, dem_tiff_path, watermask_png_path, out_svg_path, out_tactical_png_path, out_index_json_path=None):
        print(f"[UlsanVectorMapGenerator] Generating SVG & Tactical Map from {vworld_raw_json}...")

        with open(vworld_raw_json, "r", encoding="utf-8") as f:
            v_data = json.load(f)

        features = v_data.get("features", [])

        # 1. 2D 벡터 SVG 생성
        svg_root = ET.Element("svg", {
            "xmlns": "http://www.w3.org/2000/svg",
            "version": "1.1",
            "width": str(self.width),
            "height": str(self.height),
            "viewBox": f"0 0 {self.width} {self.height}",
            "data-region": "ulsan_uc_west",
            "data-building-count": str(len(features))
        })

        # 배경 흑색
        ET.SubElement(svg_root, "rect", {
            "x": "0", "y": "0",
            "width": str(self.width), "height": str(self.height),
            "fill": "#121418", "id": "background"
        })

        bldg_group = ET.SubElement(svg_root, "g", {"id": "vworld_buildings", "fill-rule": "evenodd"})

        # 2. 래스터 전술 지도용 PIL 캔버스 초기화 (미니맵 및 M키 전체지도용)
        map_img = Image.new("RGBA", (self.width, self.height), (18, 20, 24, 255))
        draw = ImageDraw.Draw(map_img)

        # 등고선 래스터 생성
        if os.path.exists(dem_tiff_path):
            with Image.open(dem_tiff_path) as dem_img:
                import cv2
                dem_arr = np.array(dem_img, dtype=np.float32)
                if dem_arr.shape != (self.height, self.width):
                    dem_arr = cv2.resize(dem_arr, (self.width, self.height), interpolation=cv2.INTER_CUBIC)

                contour_interval = 20.0
                dist = np.abs((dem_arr % contour_interval) - (contour_interval * 0.5))
                is_contour = (dist < 1.2) & (dem_arr > 1.0)
                is_major = (np.abs((dem_arr % 100.0) - 50.0) < 2.0) & (dem_arr > 1.0)

                contour_rgba = np.zeros((self.height, self.width, 4), dtype=np.uint8)
                contour_rgba[is_contour] = [60, 65, 75, 130]
                contour_rgba[is_major] = [90, 95, 105, 210]
                map_img.alpha_composite(Image.fromarray(contour_rgba, mode="RGBA"))

        # 수계(하천/호수) 블렌딩 (지정된 경우에만 적용)
        if watermask_png_path and os.path.exists(watermask_png_path):
            with Image.open(watermask_png_path) as wm_img:
                wm_arr = np.array(wm_img.resize((self.width, self.height), Image.Resampling.NEAREST), dtype=np.uint8)
                water_rgba = np.zeros((self.height, self.width, 4), dtype=np.uint8)
                water_rgba[wm_arr > 50] = [25, 45, 65, 230] # 어두운 수역 청록톤
                map_img.alpha_composite(Image.fromarray(water_rgba, mode="RGBA"))

        indexed_buildings = []
        bldg_num = 1

        for feat in features:
            props = feat.get("properties", {})
            geom = feat.get("geometry", {})
            g_type = geom.get("type", "")
            coords = geom.get("coordinates", [])

            polygons = []
            if g_type == "Polygon" and coords:
                polygons.append(coords[0])
            elif g_type == "MultiPolygon" and coords:
                for poly in coords:
                    if poly:
                        polygons.append(poly[0])

            bldg_name = props.get("buld_nm", "").strip()
            if not bldg_name:
                rd_nm = props.get("rd_nm", "").strip()
                bno = props.get("buld_no", "").strip()
                bldg_name = f"{rd_nm} {bno}".strip()

            floors = int(props.get("gro_flo_co", 1) or 1)
            bldg_id = str(props.get("bd_mgt_sn", bldg_num))

            # 층수별 지도 색상 (모노크롬 밝기 차등: 1층은 어두운 회색, 고층은 밝은 흰색)
            brightness = min(255, 120 + floors * 8)
            fill_hex = f"#{brightness:02x}{brightness:02x}{brightness:02x}"
            fill_rgb = (brightness, brightness, brightness, 240)

            for ring in polygons:
                if len(ring) < 3:
                    continue

                pts_px = [self._coord_to_pixel(p[1], p[0]) for p in ring]

                # 1. SVG 폴리곤 엘리먼트 추가
                pts_str = " ".join([f"{round(p[0], 1)},{round(p[1], 1)}" for p in pts_px])
                ET.SubElement(bldg_group, "polygon", {
                    "id": f"bldg_{bldg_num}",
                    "data-sn": bldg_id,
                    "data-name": bldg_name,
                    "data-floors": str(floors),
                    "points": pts_str,
                    "fill": fill_hex,
                    "stroke": "#ffffff",
                    "stroke-width": "0.5"
                })

                # 2. PIL 전술 지도 드로잉
                poly_draw = [(int(p[0]), int(p[1])) for p in pts_px]
                draw.polygon(poly_draw, fill=fill_rgb, outline=(255, 255, 255, 255))

            indexed_buildings.append({
                "number": bldg_num,
                "id": bldg_id,
                "name": bldg_name,
                "floors": floors,
                "fill": fill_hex
            })
            bldg_num += 1

        # SVG 파일 저장
        os.makedirs(os.path.dirname(out_svg_path), exist_ok=True)
        tree = ET.ElementTree(svg_root)
        ET.indent(tree, space="  ")
        tree.write(out_svg_path, encoding="utf-8", xml_declaration=True)
        print(f"[UlsanVectorMapGenerator] Exported SVG: {out_svg_path}")

        # 래스터 전술 지도 PNG 저장
        os.makedirs(os.path.dirname(out_tactical_png_path), exist_ok=True)
        map_img.save(out_tactical_png_path, format="PNG")
        print(f"[UlsanVectorMapGenerator] Exported Tactical Map PNG: {out_tactical_png_path}")

        # 인덱스 JSON 저장
        if out_index_json_path:
            with open(out_index_json_path, "w", encoding="utf-8") as f:
                json.dump({
                    "total_buildings": len(indexed_buildings),
                    "region": "ulsan_uc_west",
                    "buildings": indexed_buildings
                }, f, indent=2, ensure_ascii=False)
            print(f"[UlsanVectorMapGenerator] Exported Building Index: {out_index_json_path}")

        return out_svg_path, out_tactical_png_path
