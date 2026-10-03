import os
import json
import hashlib
from datetime import datetime
import xml.etree.ElementTree as ET

class BuildingSvgProcessor:
    """
    OSM 실측 건물 풋프린트 다각형 데이터를 파싱하여
    각 건물별 고유 식별 번호(ID/Numbering)를 색상(RGB/Hex)으로 매핑하고
    지리 정합된 2D 벡터 SVG(Scalable Vector Graphics) 파일 및 인덱스 매니페스트로 추출하는 프로세서
    """
    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        self.bbox = self.config["bbox"]
        res = self.config.get("resolution", {})
        self.svg_width = res.get("target_width", 4096)
        self.svg_height = res.get("target_height", 4096)

    def _geo_to_svg_pixel(self, lat, lon):
        """
        WGS84 위경도 좌표를 0~svg_width, 0~svg_height 평면 SVG 픽셀 좌표로 변환
        """
        frac_x = (lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"])
        frac_y = (self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"])
        pixel_x = frac_x * self.svg_width
        pixel_y = frac_y * self.svg_height
        return pixel_x, pixel_y

    @staticmethod
    def _index_to_rgb(idx):
        """
        건물 고유 넘버링(1 ~ 16,777,215)을 24-bit RGB 색상으로 1:1 무손실 인코딩
        R = (idx >> 16) & 0xFF
        G = (idx >> 8) & 0xFF
        B = idx & 0xFF
        """
        r = (idx >> 16) & 0xFF
        g = (idx >> 8) & 0xFF
        b = idx & 0xFF
        hex_color = f"#{r:02x}{g:02x}{b:02x}"
        rgb_color = f"rgb({r},{g},{b})"
        return r, g, b, hex_color, rgb_color

    def generate_building_svg(self, raw_buildings_path, landmarks_json_path, output_svg_path, output_index_json_path=None):
        """
        건물 원시 JSON 데이터에서 폴리곤을 추출하여 색상 넘버링 기반 SVG 및 메타데이터 인덱스 파일 생성
        """
        print(f"[BuildingSvgProcessor] Parsing building footprints from {raw_buildings_path}...")
        
        buildings_data = []
        seen_building_ids = set()
        current_building_number = 1

        # 1. 랜드마크 주요 건물 수집
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

                # 대략적인 위경도 박스 변환 (1도 위도 약 111,000m, 1도 경도 약 92,000m)
                d_lat = (spec["d"] * 0.5) / 111000.0
                d_lon = (spec["w"] * 0.5) / 92000.0

                poly_geo = [
                    (lat - d_lat, lon - d_lon),
                    (lat - d_lat, lon + d_lon),
                    (lat + d_lat, lon + d_lon),
                    (lat + d_lat, lon - d_lon)
                ]

                pts_svg = [self._geo_to_svg_pixel(p[0], p[1]) for p in poly_geo]
                r, g, b, hex_c, rgb_c = self._index_to_rgb(current_building_number)

                seen_building_ids.add(lid)
                buildings_data.append({
                    "building_number": current_building_number,
                    "id": lid,
                    "osm_id": None,
                    "name": lm.get("name_ko", ""),
                    "color_rgb": [r, g, b],
                    "color_hex": hex_c,
                    "levels": max(1, int(spec["h"] / 3.5)),
                    "height": spec["h"],
                    "points_svg": pts_svg,
                    "geo_points": poly_geo
                })
                current_building_number += 1

        # 2. OSM 실측 건물 풋프린트 수집
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
                    if way_id in seen_building_ids:
                        continue

                    way_nodes = elem.get("nodes", [])
                    poly_geo = [bldg_nodes[nid] for nid in way_nodes if nid in bldg_nodes]
                    if len(poly_geo) < 3:
                        continue

                    tags = elem.get("tags", {})
                    name = tags.get("name", tags.get("name:en", ""))
                    
                    # 층수 및 높이 산출
                    height = 0.0
                    if "height" in tags:
                        try:
                            h_str = tags["height"].replace("m", "").replace("M", "").strip()
                            height = float(h_str)
                        except Exception:
                            height = 0.0

                    levels = 1
                    if "building:levels" in tags:
                        try:
                            levels = max(1, int(float(tags["building:levels"])))
                            if height <= 0.0:
                                height = levels * 3.4
                        except Exception:
                            levels = 1

                    if height <= 0.0:
                        height = 7.0 if levels == 1 else levels * 3.4

                    pts_svg = [self._geo_to_svg_pixel(p[0], p[1]) for p in poly_geo]
                    r, g, b, hex_c, rgb_c = self._index_to_rgb(current_building_number)

                    seen_building_ids.add(way_id)
                    buildings_data.append({
                        "building_number": current_building_number,
                        "id": f"osm_{way_id}",
                        "osm_id": way_id,
                        "name": name,
                        "color_rgb": [r, g, b],
                        "color_hex": hex_c,
                        "levels": levels,
                        "height": round(height, 2),
                        "points_svg": pts_svg,
                        "geo_points": poly_geo
                    })
                    current_building_number += 1

        print(f"[BuildingSvgProcessor] Extracted {len(buildings_data)} building footprints.")

        # 3. SVG XML 문서 생성
        svg_elem = ET.Element("svg", {
            "xmlns": "http://www.w3.org/2000/svg",
            "version": "1.1",
            "width": str(self.svg_width),
            "height": str(self.svg_height),
            "viewBox": f"0 0 {self.svg_width} {self.svg_height}",
            "data-region": self.config.get("region_name", "kanmon_straits"),
            "data-building-count": str(len(buildings_data))
        })

        # 배경 흑색 캔버스 (ID 0 / 배경 무건물 영역 식별)
        ET.SubElement(svg_elem, "rect", {
            "x": "0",
            "y": "0",
            "width": str(self.svg_width),
            "height": str(self.svg_height),
            "fill": "#000000",
            "id": "background_void"
        })

        # 건물 그룹
        buildings_group = ET.SubElement(svg_elem, "g", {
            "id": "building_footprints_layer",
            "fill-rule": "evenodd"
        })

        for b in buildings_data:
            points_str = " ".join([f"{round(pt[0], 2)},{round(pt[1], 2)}" for pt in b["points_svg"]])
            poly_attrs = {
                "id": str(b["id"]),
                "data-building-number": str(b["building_number"]),
                "data-levels": str(b["levels"]),
                "data-height": str(b["height"]),
                "fill": b["color_hex"],
                "stroke": "#ffffff",
                "stroke-width": "0.3",
                "points": points_str
            }
            if b["name"]:
                poly_attrs["data-name"] = b["name"]

            ET.SubElement(buildings_group, "polygon", poly_attrs)

        # SVG 파일 저장
        os.makedirs(os.path.dirname(output_svg_path), exist_ok=True)
        tree = ET.ElementTree(svg_elem)
        ET.indent(tree, space="  ", level=0)
        tree.write(output_svg_path, encoding="utf-8", xml_declaration=True)
        print(f"[BuildingSvgProcessor] Saved SVG footprint file to {output_svg_path}")

        # 4. 건물 인덱스 메타데이터 JSON 파일 저장
        if output_index_json_path is None:
            output_index_json_path = os.path.splitext(output_svg_path)[0] + "_index.json"

        # 용량 최적화를 위해 경량 메타데이터 딕셔너리 생성
        index_payload = {
            "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "total_buildings": len(buildings_data),
            "svg_dimensions": [self.svg_width, self.svg_height],
            "bbox": self.bbox,
            "encoding": {
                "type": "24bit_rgb_id",
                "formula": "id = (R << 16) | (G << 8) | B"
            },
            "buildings": [
                {
                    "num": b["building_number"],
                    "id": b["id"],
                    "hex": b["color_hex"],
                    "rgb": b["color_rgb"],
                    "levels": b["levels"],
                    "height": b["height"],
                    "name": b["name"]
                }
                for b in buildings_data
            ]
        }

        with open(output_index_json_path, "w", encoding="utf-8") as f:
            json.dump(index_payload, f, indent=2, ensure_ascii=False)
        print(f"[BuildingSvgProcessor] Saved Building Index JSON to {output_index_json_path}")

        # 매니페스트 갱신
        self._update_manifest(output_svg_path, output_index_json_path, len(buildings_data))
        return output_svg_path, output_index_json_path

    def _update_manifest(self, svg_path, json_path, count):
        manifest_path = "godot_project/assets/generated/manifest.json"
        if not os.path.exists(manifest_path):
            return

        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = json.load(f)

        def get_sha256(p):
            with open(p, "rb") as f:
                return hashlib.sha256(f.read()).hexdigest()

        manifest["last_updated"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        manifest.setdefault("assets", {})

        manifest["assets"]["building_footprints_svg"] = {
            "file_path": os.path.abspath(svg_path),
            "type": "building_footprints",
            "format": "SVG",
            "metadata": {
                "width": self.svg_width,
                "height": self.svg_height,
                "building_count": count,
                "encoding": "24bit_rgb_numbering"
            },
            "sha256": get_sha256(svg_path),
            "size_bytes": os.path.getsize(svg_path)
        }

        manifest["assets"]["building_footprints_index"] = {
            "file_path": os.path.abspath(json_path),
            "type": "building_footprints_index",
            "format": "JSON",
            "metadata": {
                "building_count": count
            },
            "sha256": get_sha256(json_path),
            "size_bytes": os.path.getsize(json_path)
        }

        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)
        print(f"[BuildingSvgProcessor] Updated manifest.json with SVG assets.")
