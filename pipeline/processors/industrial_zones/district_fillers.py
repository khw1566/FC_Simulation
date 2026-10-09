"""용도별 블록 채움 규칙.

블록의 최소 회전 사각형 방향을 기준 좌표계로 삼아 줄 단위로 설비를 채운다.
무작위 시도 대신 결정적 줄 배치를 사용하므로 블록 전체를 일정한 밀도로 채운다.
"""
import math

from shapely.affinity import rotate, translate
from shapely.geometry import box
from shapely.prepared import prep

# 용도별 채움 단계. 앞 단계의 대형 설비를 먼저 놓고 다음 단계가 남은 틈을 채운다.
# band_m: 해당 단계를 블록의 바다 쪽(또는 시작 변)에서 이 거리 안으로 제한한다.
RECIPES = {
    "tank_farm": {"passes": [{"liquid_storage_tank": 4, "lpg_sphere": 1}, {"lpg_sphere": 1, "cooling_fan_bank": 1}],
                  "gap": 14, "margin": 12},
    "process": {"passes": [{"process_column": 3, "scrubber_tower": 2, "stack_steel": 1, "stack_triple": 1, "flare_lattice": 1},
                           {"distillation_tower": 2, "cooling_fan_bank": 2}], "gap": 10, "margin": 10},
    "factory": {"passes": [{"factory_gable": 3, "factory_sawtooth": 2, "factory_flat": 2},
                           {"factory_flat": 2, "cooling_fan_bank": 2, "industrial_chimney": 1}], "gap": 16, "margin": 10},
    "shipyard": {"passes": [{"gantry_crane": 1}, {"shipbuilding_hangar": 1}, {"tower_crane": 2, "factory_flat": 1}],
                 "bands": [70, None, None], "gap": 24, "margin": 12, "water_first": True},
    "logistics": {"passes": [{"factory_flat": 4, "factory_gable": 1}, {"cooling_fan_bank": 1}], "gap": 14, "margin": 10},
    "utility": {"passes": [{"cooling_tower": 2, "cooling_fan_bank": 3, "industrial_chimney": 1, "transmission_tower": 1}],
                "gap": 12, "margin": 8},
}
SCAN_STEP_M = 6.0


class IndustrialDistrictFiller:
    def __init__(self, inputs, catalog, rng, zone_id, planner):
        self.inputs = inputs
        self.catalog = catalog
        self.rng = rng
        self.zone_id = zone_id
        self.planner = planner
        self.max_step = float(inputs.config.get("max_foundation_height_m", 3.5))

    def fill(self, record, start_index):
        recipe = RECIPES[record["district"]]
        block = record["geometry"]
        area = block.buffer(-recipe["margin"], join_style=2)
        if area.is_empty:
            return []
        angle, origin = self._frame(block)
        local = rotate(translate(area, -origin[0], -origin[1]), -angle, origin=(0, 0), use_radians=False)
        if recipe.get("water_first") and self._water_on_max_side(block, angle, origin, local):
            local = rotate(local, 180, origin=(0, 0))
            angle += 180
        fits = prep(local)
        min_x, min_y, max_x, max_y = local.bounds
        gap = recipe["gap"]
        occupied, placements = [], []
        for stage, weights in enumerate(recipe["passes"]):
            band = (recipe.get("bands") or [None] * len(recipe["passes"]))[stage]
            limit_y = min(max_y, min_y + band) if band else max_y
            y = min_y
            while y < limit_y:
                kind = self._pick(weights)
                width, depth, footprint = self._size(kind)
                placed_in_row, x = False, min_x
                while x + width <= max_x and y + depth <= max_y:
                    rect = (x, y, x + width, y + depth)
                    if not any(self._overlap(rect, other, gap) for other in occupied) and fits.covers(box(*rect)):
                        placement = self._place(kind, footprint, x + width / 2, y + depth / 2, angle, origin, record, start_index + len(placements))
                        if placement:
                            placements.append(placement)
                            occupied.append(rect)
                            placed_in_row = True
                            x += width + gap
                            continue
                    x += SCAN_STEP_M
                # 줄에 설비를 놓았으면 그 깊이만큼, 아니면 작은 간격만 내려가 다음 줄을 찾는다.
                y += depth + gap if placed_in_row else SCAN_STEP_M
        return placements

    @staticmethod
    def _overlap(a, b, gap):
        return a[0] < b[2] + gap and b[0] < a[2] + gap and a[1] < b[3] + gap and b[1] < a[3] + gap

    def _place(self, kind, footprint, local_x, local_y, angle, origin, record, index):
        spec = self.catalog[kind]
        x0, z0, x1, z1 = footprint
        # 설비 중심을 칸 중심에 맞추도록 footprint 중심 오프셋을 보정한다.
        offset_x, offset_z = (x0 + x1) / 2, (z0 + z1) / 2
        theta = math.radians(angle)
        world_x = origin[0] + local_x * math.cos(theta) - local_y * math.sin(theta)
        world_z = origin[1] + local_x * math.sin(theta) + local_y * math.cos(theta)
        world_x -= offset_x * math.cos(theta) - offset_z * math.sin(theta)
        world_z -= offset_x * math.sin(theta) + offset_z * math.cos(theta)
        shape = translate(rotate(box(x0, z0, x1, z1), angle, origin=(0, 0)), world_x, world_z)
        heights = [self.inputs.sample(px, pz) for px, pz in shape.exterior.coords]
        # 큰 설비일수록 조성 단차를 더 허용한다(대각 길이의 4%).
        if max(heights) - min(heights) > max(self.max_step, 0.04 * math.hypot(x1 - x0, z1 - z0)):
            return None
        return {"id": f"zone_{self.zone_id}_asset_{index}", "zone_id": self.zone_id, "parcel_id": record["block_id"],
                "district": record["district"], "asset_type": kind, "scene_path": spec["scene_path"],
                "glb_path": spec["scene_path"].replace(".tscn", ".glb"),
                "position": [round(world_x, 3), round(max(heights) + 0.12, 3), round(world_z, 3)],
                "yaw_degrees": round(-angle, 3), "scale": 1.0,
                "aabb_min_m": spec["aabb_min_m"], "aabb_max_m": spec["aabb_max_m"],
                "footprint_xz": [[round(px, 3), round(pz, 3)] for px, pz in shape.exterior.coords],
                "foundation_bottom_y": round(min(heights) - 0.75, 3), "night_lighting": spec.get("night_lighting", {}),
                "attachments": spec.get("attachments", []), "smoke_outlets_m": spec.get("smoke_outlets_m", [])}

    def _size(self, kind):
        footprint = self.catalog[kind]["footprint_xz_m"]
        return footprint[2] - footprint[0], footprint[3] - footprint[1], footprint

    def _pick(self, weights):
        names = sorted(weights)
        return self.rng.choices(names, [weights[n] for n in names])[0]

    @staticmethod
    def _frame(block):
        rect = list(block.minimum_rotated_rectangle.exterior.coords)
        a, b = max(((rect[i], rect[i + 1]) for i in range(4)), key=lambda e: math.dist(*e))
        angle = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
        c = block.centroid
        return angle, (c.x, c.y)

    def _water_on_max_side(self, block, angle, origin, local):
        """조선소는 바다에 가까운 쪽부터 크레인 줄을 놓기 위해 블록의 바다 방향을 찾는다."""
        min_x, min_y, max_x, max_y = local.bounds
        theta = math.radians(angle)
        def world(lx, ly):
            return (origin[0] + lx * math.cos(theta) - ly * math.sin(theta), origin[1] + lx * math.sin(theta) + ly * math.cos(theta))
        mid = (min_x + max_x) / 2
        low = sum(self.planner._water_near(*world(mid + dx, min_y)) for dx in (-60, 0, 60))
        high = sum(self.planner._water_near(*world(mid + dx, max_y)) for dx in (-60, 0, 60))
        return high > low
