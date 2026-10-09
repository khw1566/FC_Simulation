"""본류 하상과 둔치를 정형한다.

둔치는 본류 수면에서 출발해 `max_rise_m` 이하 고도로만 이어지는 연결 영역으로 정의한다.
제방처럼 더 높은 지형이 연결을 끊으므로 제방 뒤 저지대 시가지는 정형하지 않는다.
"""
import cv2
import numpy as np


def _smoothstep(edge0, edge1, value):
    t = np.clip((value - edge0) / max(edge1 - edge0, 1e-6), 0.0, 1.0)
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

    def _distance(self, mask):
        return cv2.distanceTransform(mask.astype(np.uint8), cv2.DIST_L2, 5) * self.grid.pixel_m

    def _connected_floodplain(self, core, river):
        count, labels = cv2.connectedComponents(core.astype(np.uint8), connectivity=8)
        touching = cv2.dilate(river.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
        keep = np.zeros(count, bool)
        keep[np.unique(labels[touching & core])] = True
        keep[0] = False
        return keep[labels]

    def _masked_blur(self, heights, mask, sigma_m):
        sigma = max(sigma_m / self.grid.pixel_m, 0.5)
        weight = mask.astype(np.float32)
        numerator = cv2.GaussianBlur(heights * weight, (0, 0), sigma)
        denominator = cv2.GaussianBlur(weight, (0, 0), sigma)
        return np.where(denominator > 1e-4, numerator / np.maximum(denominator, 1e-4), heights)

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

        rise = heights - level
        reach = (~river) & (dist_out <= d["corridor_width_m"])
        core = reach & (rise <= d["max_rise_m"])
        plain = self._connected_floodplain(core, river)
        soft = reach & (rise <= d["max_rise_m"] + d["edge_blend_m"])
        soft = soft & (cv2.dilate(plain.astype(np.uint8), np.ones((9, 9), np.uint8)) > 0)

        surface = self._masked_blur(heights.astype(np.float32), plain, d["smoothing_sigma_m"])
        surface = np.maximum(surface, level + d["min_rise_m"])
        ramp = _smoothstep(0.0, d["bank_ramp_m"], dist_out)
        target = level + (surface - level) * ramp
        weight = (1.0 - _smoothstep(d["max_rise_m"], d["max_rise_m"] + d["edge_blend_m"], rise))
        weight *= 1.0 - _smoothstep(d["corridor_width_m"] - 40.0, d["corridor_width_m"], dist_out)
        weight = np.where(soft, weight, 0.0).astype(np.float32)
        result = np.where(river, result, result * (1.0 - weight) + target * weight)
        placeable = plain & (weight > 0.95) & (dist_out > d["bank_ramp_m"])
        stats = {"river_pixels": int(river.sum()), "dunchi_pixels": int(plain.sum()),
                 "placeable_pixels": int(placeable.sum()),
                 "placeable_area_m2": round(float(placeable.sum()) * self.grid.pixel_m ** 2, 1)}
        return result, placeable, stats
