"""도로로 나뉜 블록마다 공단 내 용도(저장고·공정·공장·조선·물류·지원 시설)를 정한다.

해안 접촉 비율·면적·간선 도로 접근성과 공단 프로필을 함께 보고, 저장고 옆 블록은
공정 설비로 우선 지정해 실제 석유화학 단지처럼 저장-공정 흐름이 이어지게 한다.
"""
import numpy as np
from PIL import Image

DISTRICTS = ("tank_farm", "process", "factory", "shipyard", "logistics", "utility")

# 공단 프로필별 내륙 블록 용도 가중치
INLAND_WEIGHTS = {
    "petrochemical": {"process": 4, "tank_farm": 3, "utility": 1, "factory": 1},
    "shipbuilding": {"factory": 4, "logistics": 1, "utility": 1},
    "logistics": {"logistics": 5, "factory": 2, "utility": 1},
    "general_factory": {"factory": 6, "logistics": 2, "utility": 1},
}
COASTAL_DISTRICT = {"petrochemical": "tank_farm", "shipbuilding": "shipyard", "logistics": "logistics", "general_factory": "logistics"}


class IndustrialDistrictPlanner:
    COAST_DISTANCE_M = 90.0
    COASTAL_RATIO = 0.18
    SMALL_BLOCK_M2 = 9000.0
    SHIPYARD_MIN_M2 = 30000.0
    NEIGHBOR_GAP_M = 45.0

    def __init__(self, inputs, rng):
        self.inputs = inputs
        self.rng = rng
        # 하천을 제외한 바다 마스크로 해안 블록을 판정한다. 없으면 전체 수계 마스크를 쓴다.
        relative = inputs.meta["assets"].get("sea_mask", "")
        path = inputs.root / "godot_project" / relative.removeprefix("res://")
        if relative and path.exists():
            with Image.open(path) as image:
                sea = image.convert("L").resize((inputs.resolution, inputs.resolution), Image.Resampling.NEAREST)
            self.water = np.asarray(sea) >= 128
        else:
            self.water = np.asarray(inputs.water) > 0

    def plan(self, blocks, profile_name, signals):
        """signals는 블록과 같은 순서의 기존 건물 단서 목록이다."""
        records = []
        for index, block in enumerate(blocks):
            records.append({"block_id": index, "geometry": block, "area_m2": block.area,
                            "coast_ratio": self._coast_ratio(block), "signals": signals[index], "district": None})
        coastal = any(r["coast_ratio"] >= self.COASTAL_RATIO for r in records)
        profile_name = self.zone_profile(signals, profile_name, coastal)
        for record in records:
            record["district"] = self._from_evidence(record, profile_name)
        if profile_name == "petrochemical":
            # 저장고와 맞닿은 내륙 블록을 공정 구역으로 묶어 배관 흐름을 만든다.
            tanks = [r["geometry"] for r in records if r["district"] == "tank_farm"]
            for record in records:
                if record["district"] is None and any(record["geometry"].distance(t) < self.NEIGHBOR_GAP_M for t in tanks):
                    record["district"] = "process"
        weights = INLAND_WEIGHTS.get(profile_name, INLAND_WEIGHTS["general_factory"])
        names, values = list(weights), list(weights.values())
        for record in sorted(records, key=lambda r: -r["area_m2"]):
            if record["district"] is None:
                record["district"] = self.rng.choices(names, values)[0]
        return records, profile_name

    @staticmethod
    def zone_profile(signals, fallback, coastal=True):
        """구역 전체 기존 건물 단서로 공단 성격을 다시 판정한다."""
        total = {}
        for signal in signals:
            for key, value in signal.items():
                total[key] = total.get(key, 0) + value
        count = max(1, total.get("count", 0))
        # 큰 구역일수록 우연한 단서가 쌓이므로 개수와 비율을 함께 본다.
        # 조선 단서는 바다에 면한 블록이 있을 때만 인정한다(내륙의 소규모 중공업 업체 제외).
        if coastal and total.get("ship", 0) >= 3 and total["ship"] / count >= 0.01:
            return "shipbuilding"
        if (total.get("round_count", 0) >= 8 and total["round_count"] / count >= 0.02) or                 (total.get("petro", 0) >= 4 and total["petro"] / count >= 0.02):
            return "petrochemical"
        if total.get("logistics", 0) >= 5 and total["logistics"] / count >= 0.02:
            return "logistics"
        return fallback

    def _from_evidence(self, record, profile_name):
        s, coastal = record["signals"], record["coast_ratio"] >= self.COASTAL_RATIO
        if record["area_m2"] < self.SMALL_BLOCK_M2:
            return "utility"
        if s["round_count"] >= 3 or (s["area"] > 0 and s["round_area"] / s["area"] > 0.2):
            return "tank_farm"
        if s["petro"] >= 1:
            return "tank_farm" if coastal else "process"
        if (s["ship"] >= 1 and profile_name == "shipbuilding") or (coastal and profile_name == "shipbuilding"):
            return "shipyard" if coastal and record["area_m2"] >= self.SHIPYARD_MIN_M2 else "factory"
        if s["logistics"] >= 1:
            return "logistics"
        if s["power"] >= 1:
            return "utility"
        if coastal:
            district = COASTAL_DISTRICT.get(profile_name, "logistics")
            return "factory" if district == "shipyard" and record["area_m2"] < self.SHIPYARD_MIN_M2 else district
        if s["count"] and s["area"] / s["count"] > 3000:
            return "factory"
        return None

    def _coast_ratio(self, block):
        boundary = block.exterior
        count = max(8, int(boundary.length / 20))
        near = 0
        for i in range(count):
            point = boundary.interpolate(i / count, normalized=True)
            near += self._water_near(point.x, point.y)
        return near / count

    def _water_near(self, x, z):
        size, resolution = self.inputs.size, self.water.shape[0]
        radius = max(1, int(self.COAST_DISTANCE_M / self.inputs.cell))
        px = int((x / size + 0.5) * (resolution - 1))
        py = int((z / size + 0.5) * (resolution - 1))
        window = self.water[max(0, py - radius):py + radius + 1, max(0, px - radius):px + radius + 1]
        return bool(window.any())
