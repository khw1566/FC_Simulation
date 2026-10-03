import os
import json
import numpy as np

class DistrictProcessor:
    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        self.bbox = self.config["bbox"]
        self.world_size = 18000.0 # 18km scale

    def _geo_to_world(self, lat, lon):
        # lat: North -> -world_size/2, South -> +world_size/2 (Godot Z축)
        # lon: West -> -world_size/2, East -> +world_size/2 (Godot X축)
        frac_z = (self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"])
        frac_x = (lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"])
        
        world_x = (frac_x - 0.5) * self.world_size
        world_z = (frac_z - 0.5) * self.world_size
        return round(float(world_x), 1), round(float(world_z), 1)

    def _point_in_poly(self, x, z, poly):
        # Ray casting algorithm
        n = len(poly)
        inside = False
        p1x, p1z = poly[0]
        for i in range(n + 1):
            p2x, p2z = poly[i % n]
            if z > min(p1z, p2z):
                if z <= max(p1z, p2z):
                    if x <= max(p1x, p2x):
                        if p1z != p2z:
                            xinters = (z - p1z) * (p2x - p1x) / (p2z - p1z) + p1x
                        if p1x == p2x or x <= xinters:
                            inside = not inside
            p1x, p1z = p2x, p2z
        return inside

    def process_districts(self, raw_boundary_json, output_json_path):
        print(f"[DistrictProcessor] Processing real boundaries from {raw_boundary_json}...")
        with open(raw_boundary_json, "r", encoding="utf-8") as f:
            data = json.load(f)

        nodes = {}
        ways = {}
        relations = []
        landmarks_raw = []

        for elem in data.get("elements", []):
            etype = elem.get("type")
            if etype == "node":
                nodes[elem["id"]] = (elem["lat"], elem["lon"])
                tags = elem.get("tags", {})
                name = tags.get("name:ko") or tags.get("name") or tags.get("name:en")
                if name and ("historic" in tags or "tourism" in tags):
                    wx, wz = self._geo_to_world(elem["lat"], elem["lon"])
                    landmarks_raw.append({"name": name, "x": wx, "z": wz})
            elif etype == "way":
                ways[elem["id"]] = elem.get("nodes", [])
            elif etype == "relation":
                if elem.get("tags", {}).get("boundary") == "administrative":
                    relations.append(elem)

        districts_output = []

        # 주요 타깃 구역 매핑 테이블 (한국어, 영어, 관할 지자체)
        target_names = {
            "下関市": {"id": "shimonoseki", "ko": "시모노세키시 (야마구치현)", "en": "Shimonoseki City", "pref": "야마구치현", "city": "시모노세키시"},
            "門司区": {"id": "moji_ku", "ko": "기타큐슈시 모지구 (후쿠오카현)", "en": "Moji Ward, Kitakyushu", "pref": "후쿠오카현", "city": "기타큐슈시 모지구"},
            "小倉北区": {"id": "kokurakita_ku", "ko": "기타큐슈시 고쿠라키타구 (후쿠오카현)", "en": "Kokurakita Ward, Kitakyushu", "pref": "후쿠오카현", "city": "기타큐슈시 고쿠라키타구"},
            "小倉南区": {"id": "kokuraminami_ku", "ko": "기타큐슈시 고쿠라미나미구 (후쿠오카현)", "en": "Kokuraminami Ward, Kitakyushu", "pref": "후쿠오카현", "city": "기타큐슈시 고쿠라미나미구"},
            "北九州市": {"id": "kitakyushu", "ko": "기타큐슈시 연안", "en": "Kitakyushu Coastal District", "pref": "후쿠오카현", "city": "기타큐슈시"}
        }

        for rel in relations:
            tags = rel.get("tags", {})
            name = tags.get("name", "")
            target_info = None
            for key, info in target_names.items():
                if key in name:
                    target_info = info
                    break

            if not target_info:
                continue

            # 관계 내 'outer' 역할을 가진 way들 수집
            outer_points = []
            for member in rel.get("members", []):
                if member.get("role") in ["outer", ""]:
                    ref_id = member.get("ref")
                    if ref_id in ways:
                        for nid in ways[ref_id]:
                            if nid in nodes:
                                outer_points.append(self._geo_to_world(*nodes[nid]))

            if len(outer_points) < 10:
                continue

            # 다각형 버텍스 경량화 (다운샘플링: 40~60개 점)
            step = max(1, len(outer_points) // 50)
            simplified_poly = outer_points[::step]

            # 구역 내 랜드마크 바인딩
            matched_landmarks = []
            for lm in landmarks_raw:
                if self._point_in_poly(lm["x"], lm["z"], simplified_poly):
                    matched_landmarks.append(lm["name"])

            # 랜드마크 중복 제거 및 최대 4개 선정
            unique_lms = list(dict.fromkeys(matched_landmarks))[:4]
            if not unique_lms:
                if "shimonoseki" in target_info["id"]:
                    unique_lms = ["간몬교 시모노세키 주탑", "카라토 시장", "단노우라 전장"]
                elif "moji" in target_info["id"]:
                    unique_lms = ["모지코역(중요문화재)", "메카리 전망대", "간몬교 모지 주탑"]
                else:
                    unique_lms = ["고쿠라성", "차차타운", "아다치산 능선"]

            districts_output.append({
                "id": target_info["id"],
                "name_ko": target_info["ko"],
                "name_en": target_info["en"],
                "prefecture": target_info["pref"],
                "city": target_info["city"],
                "polygon": simplified_poly,
                "landmarks": unique_lms
            })

        # 간몬 해협 주항로(해상 구역) 기본 폴리곤 추가
        districts_output.append({
            "id": "kanmon_strait_channel",
            "name_ko": "간몬 해협 주항로",
            "name_en": "Kanmon Straits Main Channel",
            "prefecture": "국토교통성 해상보안청",
            "city": "간몬 항로 관제구역",
            "polygon": [
                [-9000.0, -1200.0], [9000.0, -1200.0],
                [9000.0, 1200.0], [-9000.0, 1200.0]
            ],
            "landmarks": ["간몬교(현수교)", "간몬 터널 수저구간", "하야토모 세토 급류"]
        })

        os.makedirs(os.path.dirname(output_json_path), exist_ok=True)
        with open(output_json_path, "w", encoding="utf-8") as f:
            json.dump(districts_output, f, indent=2, ensure_ascii=False)

        print(f"[DistrictProcessor] Successfully generated {len(districts_output)} real polygon districts -> {output_json_path}")
        return output_json_path
