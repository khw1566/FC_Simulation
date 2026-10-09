"""OSM 산업·항만 용지를 게임 공단 구역 경계로 변환한다.

인접한 필지는 짧은 간격을 메워 하나의 공단으로 합치고, 작은 산업 용지는 제외한다.
이름 태그로 공단 성격(석유화학·조선·물류·일반 제조)을 추정해 구역 프로필로 기록한다.
"""
import json
from pathlib import Path

from shapely.geometry import Polygon, MultiPolygon, LineString, box, mapping
from shapely.ops import unary_union, transform, polygonize

PROFILE_KEYWORDS = (
    ("shipbuilding", ("조선", "중공업", "미포", "heavy", "shipyard", "dockyard")),
    ("petrochemical", ("석유", "화학", "정유", "에너지", "oil", "chemical", "refinery", "petro", "gas", "lng", "lpg", "s-oil", "sk")),
    ("logistics", ("물류", "항만", "부두", "터미널", "logistics", "terminal", "port")),
)


class LanduseZoneBuilder:
    MERGE_GAP_M = 60.0       # 이 간격 이하로 떨어진 산업 용지는 한 공단으로 합친다
    MIN_ZONE_AREA_M2 = 400000.0
    SIMPLIFY_M = 8.0

    def __init__(self, meta):
        # 무거운 지형·시설 입력 없이 지도 좌표 변환만 사용한다.
        self.bbox, self.size = meta["bbox"], meta["world_size_meters"]

    def project(self, p):
        b = self.bbox
        return ((p[0]-b["west"])/(b["east"]-b["west"])*self.size-self.size/2,
                (b["north"]-p[1])/(b["north"]-b["south"])*self.size-self.size/2)

    def geographic(self, p):
        b = self.bbox
        return (b["west"]+(p[0]/self.size+0.5)*(b["east"]-b["west"]),
                b["north"]-(p[1]/self.size+0.5)*(b["north"]-b["south"]))

    def build(self, raw_path):
        data = json.loads(Path(raw_path).read_text(encoding="utf-8"))
        parcels = []
        for element in data.get("elements", []):
            polygon = self._polygon(element)
            if polygon is None:
                continue
            tags = element.get("tags", {})
            parcels.append({"geometry": polygon, "tags": tags})
        if not parcels:
            raise RuntimeError("산업 용지 경계가 없습니다")
        half = self.MERGE_GAP_M / 2
        merged = unary_union([p["geometry"].buffer(half, join_style=2) for p in parcels]).buffer(-half, join_style=2)
        # 지도 경계에 걸친 용지는 지도 안쪽만 사용한다.
        limit = self.size / 2 - 50
        merged = merged.intersection(box(-limit, -limit, limit, limit))
        zones = [merged] if merged.geom_type == "Polygon" else [g for g in getattr(merged, "geoms", []) if g.geom_type == "Polygon"]
        zones = [z.simplify(self.SIMPLIFY_M) for z in zones if z.area >= self.MIN_ZONE_AREA_M2]
        zones.sort(key=lambda z: (round(z.centroid.y), round(z.centroid.x)))
        features = []
        for zone_id, zone in enumerate(zones, 1):
            members = [p for p in parcels if p["geometry"].intersects(zone)]
            names = sorted({p["tags"].get("name", "") for p in members if p["tags"].get("name")})
            profile = self._profile(members)
            ring = transform(lambda x, z: tuple(self.geographic((x, z))), zone)
            features.append({"type": "Feature", "properties": {
                "zone_id": zone_id, "name_ko": (names[0] if names else f"산업 용지 {zone_id}") + " 공단",
                "profile": profile, "seed": 42017 + zone_id, "status": "confirmed", "source": "osm_landuse_industrial",
                "source_names": names[:12], "area_m2": round(zone.area),
                "accuracy": "OSM 산업·항만 용지 경계. 내부 시설 배치는 게임용 절차 생성"},
                "geometry": mapping(ring)})
        return features

    def _polygon(self, element):
        polygons = []
        if element["type"] == "way" and len(element.get("geometry", [])) >= 4:
            polygons.append(Polygon([self.project((p["lon"], p["lat"])) for p in element["geometry"]]))
        elif element["type"] == "relation":
            # 외곽 경계가 여러 way로 나뉘어 있으므로 선분을 이어 닫힌 면을 만든다.
            lines = [LineString([self.project((p["lon"], p["lat"])) for p in m["geometry"]])
                     for m in element.get("members", []) if m.get("role") == "outer" and len(m.get("geometry", [])) >= 2]
            polygons.extend(polygonize(unary_union(lines)) if lines else [])
        valid = []
        for polygon in polygons:
            polygon = polygon if polygon.is_valid else polygon.buffer(0)
            if not polygon.is_empty:
                valid.append(polygon)
        if not valid:
            return None
        merged = unary_union(valid)
        return merged if isinstance(merged, (Polygon, MultiPolygon)) else None

    @staticmethod
    def _profile(members):
        scores = {name: 0.0 for name, _ in PROFILE_KEYWORDS}
        for member in members:
            tags = member["tags"]
            text = " ".join(str(tags.get(k, "")) for k in ("name", "name:en", "industrial", "operator")).lower()
            weight = member["geometry"].area
            if tags.get("landuse") == "port":
                scores["logistics"] += weight
            for name, words in PROFILE_KEYWORDS:
                if any(word in text for word in words):
                    scores[name] += weight
        best = max(scores, key=scores.get)
        return best if scores[best] > 0 else "general_factory"
