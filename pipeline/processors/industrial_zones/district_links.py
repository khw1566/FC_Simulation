"""용도 구역 사이의 연결 설비.

- 저장고 블록과 이웃 공정 블록 사이를 지상 파이프랙으로 잇는다(도로 위는 고가로 통과).
- 지원 시설 블록을 가까운 순서로 송전탑 선로로 잇는다.
설비 footprint와 겹치는 위치는 건너뛴다.
"""
import math

from shapely.affinity import rotate, translate
from shapely.geometry import box, LineString, Polygon
from shapely.ops import nearest_points
from shapely.strtree import STRtree


class IndustrialDistrictLinker:
    RACK_LINK_GAP_M = 80.0
    TOWER_SPACING_M = 240.0
    TOWER_LINK_LIMIT_M = 2500.0

    def __init__(self, inputs, catalog, zone_id):
        self.inputs = inputs
        self.catalog = catalog
        self.zone_id = zone_id

    def link(self, records, placements):
        shapes = [Polygon(p["footprint_xz"]) for p in placements]
        tree = STRtree(shapes) if shapes else None
        links = []
        tanks = [r for r in records if r["district"] == "tank_farm"]
        plants = [r for r in records if r["district"] == "process"]
        for tank in tanks:
            for plant in plants:
                if tank["geometry"].distance(plant["geometry"]) > self.RACK_LINK_GAP_M:
                    continue
                b = nearest_points(tank["geometry"].centroid, plant["geometry"])[1]
                start = nearest_points(tank["geometry"], b)[0]
                links += self._chain(LineString([start, b]), "rack_straight", 24.0, tree, shapes, len(placements) + len(links), tank)
        utilities = [r for r in records if r["district"] == "utility"]
        if len(utilities) >= 2:
            order, remaining = [utilities[0]], utilities[1:]
            while remaining:
                last = order[-1]["geometry"].centroid
                nearest = min(remaining, key=lambda r: r["geometry"].centroid.distance(last))
                remaining.remove(nearest)
                line = LineString([last, nearest["geometry"].centroid])
                if line.length <= self.TOWER_LINK_LIMIT_M:
                    links += self._chain(line, "transmission_tower", self.TOWER_SPACING_M, tree, shapes, len(placements) + len(links), nearest)
                order.append(nearest)
        return links

    def _chain(self, line, kind, spacing, tree, shapes, start_index, record):
        spec = self.catalog[kind]
        x0, z0, x1, z1 = spec["footprint_xz_m"]
        angle = math.degrees(math.atan2(line.coords[-1][1] - line.coords[0][1], line.coords[-1][0] - line.coords[0][0]))
        count = max(1, int(line.length // spacing))
        result = []
        for i in range(count + 1):
            point = line.interpolate(min(line.length, (i + 0.5) * spacing if kind == "rack_straight" else i * spacing))
            if kind == "rack_straight" and (i + 0.5) * spacing > line.length:
                break
            shape = translate(rotate(box(x0, z0, x1, z1), angle, origin=(0, 0)), point.x, point.y)
            if tree is not None and any(shapes[int(j)].intersects(shape) for j in tree.query(shape)):
                continue
            heights = [self.inputs.sample(px, pz) for px, pz in shape.exterior.coords]
            if max(heights) - min(heights) > float(self.inputs.config.get("max_foundation_height_m", 3.5)) * 1.5:
                continue
            result.append({"id": f"zone_{self.zone_id}_link_{start_index + len(result)}", "zone_id": self.zone_id,
                           "parcel_id": record["block_id"], "district": "link", "asset_type": kind,
                           "scene_path": spec["scene_path"], "glb_path": spec["scene_path"].replace(".tscn", ".glb"),
                           "position": [round(point.x, 3), round(max(heights) + 0.12, 3), round(point.y, 3)],
                           "yaw_degrees": round(-angle, 3), "scale": 1.0,
                           "aabb_min_m": spec["aabb_min_m"], "aabb_max_m": spec["aabb_max_m"],
                           "footprint_xz": [[round(px, 3), round(pz, 3)] for px, pz in shape.exterior.coords],
                           "foundation_bottom_y": round(min(heights) - 0.75, 3), "night_lighting": spec.get("night_lighting", {}),
                           "attachments": [], "smoke_outlets_m": []})
        return result
