import os
import json
import math

class DetailedDistrictProcessor:
    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        self.bbox = self.config["bbox"]
        self.world_size = 18000.0 # 18km

    def _geo_to_world(self, lat, lon):
        frac_z = (self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"])
        frac_x = (lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"])
        world_x = (frac_x - 0.5) * self.world_size
        world_z = (frac_z - 0.5) * self.world_size
        return round(float(world_x), 1), round(float(world_z), 1)

    def process_all_subdistricts(self, raw_json_path, output_json_path):
        print(f"[DetailedDistrictProcessor] Parsing fine-grained districts from {raw_json_path}...")
        with open(raw_json_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        nodes = {}
        ways = {}
        relations = []
        place_nodes = []
        landmarks = []

        for elem in data.get("elements", []):
            etype = elem.get("type")
            if etype == "node":
                lat, lon = elem["lat"], elem["lon"]
                nodes[elem["id"]] = (lat, lon)
                tags = elem.get("tags", {})
                name = tags.get("name:ko") or tags.get("name") or tags.get("name:en")
                if not name:
                    continue

                wx, wz = self._geo_to_world(lat, lon)
                if "place" in tags:
                    place_type = tags["place"]
                    place_nodes.append({
                        "name": name,
                        "type": place_type,
                        "x": wx,
                        "z": wz,
                        "tags": tags
                    })
                elif "historic" in tags or "tourism" in tags:
                    landmarks.append({
                        "name": name,
                        "x": wx,
                        "z": wz
                    })

            elif etype == "way":
                ways[elem["id"]] = elem.get("nodes", [])
            elif etype == "relation":
                tags = elem.get("tags", {})
                if tags.get("boundary") == "administrative":
                    relations.append(elem)

        districts_output = []
        processed_names = set()

        # 1. 관계(Relation) 기반의 폴리곤 경계 추출
        for rel in relations:
            tags = rel.get("tags", {})
            name = tags.get("name:ko") or tags.get("name") or tags.get("name:en")
            if not name or name in processed_names:
                continue

            admin_level = tags.get("admin_level", "")
            outer_points = []
            for m in rel.get("members", []):
                if m.get("role") in ["outer", ""]:
                    ref_id = m.get("ref")
                    if ref_id in ways:
                        for nid in ways[ref_id]:
                            if nid in nodes:
                                outer_points.append(self._geo_to_world(*nodes[nid]))

            if len(outer_points) < 8:
                continue

            # 폴리곤 단순화
            step = max(1, len(outer_points) // 35)
            poly = outer_points[::step]

            # 바운딩 박스 계산
            xs = [p[0] for p in poly]
            zs = [p[1] for p in poly]
            min_x, max_x = min(xs), max(xs)
            min_z, max_z = min(zs), max(zs)
            center_x = (min_x + max_x) * 0.5
            center_z = (min_z + max_z) * 0.5

            # 소속 도도부현/시구정촌 자동 판별
            pref = "야마구치현" if center_z < 0 else "후쿠오카현"
            city_str = "시모노세키시" if center_z < 0 else ("기타큐슈시 모지구" if center_x > 0 else "기타큐슈시 고쿠라키타구")

            # 인근 랜드마크 매칭
            matched_lms = []
            for lm in landmarks:
                dist = math.hypot(lm["x"] - center_x, lm["z"] - center_z)
                if dist < 2000.0:
                    matched_lms.append(lm["name"])

            districts_output.append({
                "id": f"dist_{len(districts_output)+1}",
                "name_ko": name,
                "name_en": tags.get("name:en", name),
                "admin_level": admin_level,
                "prefecture": pref,
                "city": city_str,
                "polygon": poly,
                "center": [center_x, center_z],
                "landmarks": list(dict.fromkeys(matched_lms))[:3]
            })
            processed_names.add(name)

        # 2. 동/초/정목(place=quarter/neighbourhood) 중심점 기반 반경 구역 보강 (Voronoi/Radius 구역)
        for p in place_nodes:
            name = p["name"]
            if name in processed_names:
                continue

            cx, cz = p["x"], p["z"]
            # 반경 400~800m 육각형 폴리곤 자동 생성
            radius = 650.0 if p["type"] in ["suburb", "town"] else 400.0
            hex_poly = []
            for i in range(6):
                angle = i * (math.pi / 3.0)
                hx = round(cx + radius * math.cos(angle), 1)
                hz = round(cz + radius * math.sin(angle), 1)
                hex_poly.append([hx, hz])

            pref = "야마구치현" if cz < 0 else "후쿠오카현"
            city_str = "시모노세키시" if cz < 0 else ("기타큐슈시 모지구" if cx > 0 else "기타큐슈시 고쿠라키타구")

            matched_lms = []
            for lm in landmarks:
                if math.hypot(lm["x"] - cx, lm["z"] - cz) < 1200.0:
                    matched_lms.append(lm["name"])

            districts_output.append({
                "id": f"sub_{len(districts_output)+1}",
                "name_ko": name,
                "name_en": p["tags"].get("name:en", name),
                "admin_level": "9-10",
                "prefecture": pref,
                "city": city_str,
                "polygon": hex_poly,
                "center": [cx, cz],
                "landmarks": list(dict.fromkeys(matched_lms))[:3]
            })
            processed_names.add(name)

        # 간몬 해협 주항로 기본 구역 보장
        districts_output.insert(0, {
            "id": "kanmon_strait_channel",
            "name_ko": "간몬 해협 주항로",
            "name_en": "Kanmon Straits Main Channel",
            "admin_level": "seaway",
            "prefecture": "국토교통성 해상보안청",
            "city": "간몬 항로 관제구역",
            "polygon": [
                [-9000.0, -1200.0], [9000.0, -1200.0],
                [9000.0, 1200.0], [-9000.0, 1200.0]
            ],
            "center": [0.0, 0.0],
            "landmarks": ["간몬교(현수교)", "간몬 터널 수저구간", "하야토모 세토 급류"]
        })

        os.makedirs(os.path.dirname(output_json_path), exist_ok=True)
        with open(output_json_path, "w", encoding="utf-8") as f:
            json.dump(districts_output, f, indent=2, ensure_ascii=False)

        print(f"[DetailedDistrictProcessor] Total {len(districts_output)} fine-grained districts processed -> {output_json_path}")
        return output_json_path
