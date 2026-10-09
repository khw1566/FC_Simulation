"""본류 하상과 끊김 없는 수변 둔치 띠를 정형한다.

둔치는 본류 수면에서 잰 구간별 폭(`band_m`, `band_overrides`)의 연속 띠로 정의하고
수위 + `flat_rise_m`의 일정 높이로 평탄화한다. 거친 고도에서 얻은 연결 영역은 조각나고
시가지로 번지므로 쓰지 않는다. 생태 권역 배치 부지(config/taehwagang_ecozones.json)와
같은 폭을 쓴다. 강변도로가 있는 구간은 LeveeProfileShaper가 이 결과를 다시 정형한다.
"""
import cv2
import numpy as np


def _smoothstep(edge0, edge1, value):
    t = np.clip((value - edge0) / np.maximum(edge1 - edge0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class RiverbankShaper:
    def __init__(self, grid, water_settings, dunchi_settings):
        self.grid = grid
        self.water = water_settings
        self.dunchi = dunchi_settings

    def water_level(self):
        profile = np.asarray(self.water["water_level_profile"], dtype=np.float64)
        per_column = np.interp(self.grid.column_lons(), profile[:, 0], profile[:, 1])
        return np.broadcast_to(per_column[None, :], (self.grid.height, self.grid.width)).astype(np.float32)

    def band_width(self):
        lons = self.grid.column_lons()
        width = np.full(lons.shape, float(self.dunchi["band_m"]), np.float32)
        for override in self.dunchi.get("band_overrides", []):
            for low, high in override["lon_ranges"]:
                width[(lons >= low) & (lons <= high)] = float(override["band_m"])
        width = cv2.GaussianBlur(width[None, :], (0, 0), sigmaX=max(40.0 / self.grid.pixel_m, 1.0)).ravel()
        return np.broadcast_to(width[None, :], (self.grid.height, self.grid.width))

    def _distance(self, mask):
        return cv2.distanceTransform(mask.astype(np.uint8), cv2.DIST_L2, 5) * self.grid.pixel_m

    def shape(self, heights, river):
        d = self.dunchi
        level = self.water_level()
        result = heights.astype(np.float32).copy()
        if not river.any():
            return result, np.zeros_like(river), {"river_pixels": 0, "dunchi_pixels": 0}
        dist_in = self._distance(river)
        dist_out = self._distance(~river)
        depth = np.minimum(self.water["bed_max_depth_m"], 0.3 + dist_in / self.water["bank_slope_run_per_rise"])
        result[river] = (level - depth)[river]

        land = ~river
        band = self.band_width()
        plain = land & (dist_out <= band)
        flat = level + d["flat_rise_m"]
        target = level + (flat - level) * _smoothstep(0.0, d["bank_ramp_m"], dist_out)
        weight = np.where(land, 1.0 - _smoothstep(band, band + d["band_edge_blend_m"], dist_out), 0.0)
        result = np.where(river, result, result * (1.0 - weight) + target * weight).astype(np.float32)
        placeable = plain & (dist_out > d["bank_ramp_m"])
        stats = {"river_pixels": int(river.sum()), "dunchi_pixels": int(plain.sum()),
                 "placeable_pixels": int(placeable.sum()),
                 "placeable_area_m2": round(float(placeable.sum()) * self.grid.pixel_m ** 2, 1)}
        return result, placeable, stats
