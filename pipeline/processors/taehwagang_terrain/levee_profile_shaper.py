"""강변도로 기준 단면 정형.

본류에서 강변도로까지(둔치 쪽)는 일정 높이의 평탄 둔치로 두고, 강변도로 가장자리에서
`slope_width_m` 안쪽 띠에만 S자 곡면 경사를 준다. 강변도로와 그 바깥 시가지는 도로 높이로
일관되게 평탄화하되, 도로 높이보다 `hill_threshold_m` 이상 높은 산지는 원 지형을 유지한다.
강변도로가 `road_search_m` 안에 없는 구간은 기존 둔치 정형 결과를 그대로 쓴다.
"""
import cv2
import numpy as np


def _smoothstep(edge0, edge1, value):
    t = np.clip((value - edge0) / max(edge1 - edge0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class LeveeProfileShaper:
    def __init__(self, grid, settings, bank_ramp_m):
        self.grid = grid
        self.s = settings
        self.bank_ramp_m = bank_ramp_m

    def _nearest_road(self, road, distance_to_river):
        """도로 가장자리까지 거리와, 가장 가까운 도로 지점의 본류 거리(D)를 함께 구한다."""
        source = (~road).astype(np.uint8)
        distance, labels = cv2.distanceTransformWithLabels(source, cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
        road_index = np.flatnonzero(road.ravel())
        road_river = distance_to_river.ravel()[road_index]
        lookup = np.concatenate([[np.inf], road_river]).astype(np.float32)
        return distance * self.grid.pixel_m, lookup[labels]

    def shape(self, base, base_placeable, dem, river, riverside_road, distance_to_river, level):
        s = self.s
        if not riverside_road.any():
            return base, base_placeable, {"levee_profile_pixels": 0}, np.zeros_like(river)
        dr, road_river = self._nearest_road(riverside_road, distance_to_river)
        dunchi_h = level + s["dunchi_rise_m"]
        road_h = level + s["road_rise_m"]
        land = ~river
        context = land & (dr <= s["road_search_m"]) & (road_river <= s["road_search_m"])
        # 도로와 본류 사이에 있는 화소만: 맞은편 기슭 화소는 dr + dw가 D보다 훨씬 크다.
        between = (distance_to_river < road_river) & (dr + distance_to_river <= road_river * 1.25 + 30.0)
        river_side = context & between & ~riverside_road

        u = np.clip(dr / max(s["slope_width_m"], 1e-3), 0.0, 1.0)
        bank = road_h + (dunchi_h - road_h) * _smoothstep(0.0, 1.0, u)
        bank = level + (bank - level) * _smoothstep(0.0, self.bank_ramp_m, distance_to_river)

        hill = _smoothstep(s["hill_threshold_m"], s["hill_threshold_m"] + s["hill_blend_m"], dem - road_h)
        city_reach = 1.0 - _smoothstep(s["city_flatten_m"] - 200.0, s["city_flatten_m"], dr)
        city = land & ~river_side & (distance_to_river >= road_river) & (dr < distance_to_river) & (dr <= s["city_flatten_m"])

        fade = 1.0 - _smoothstep(s["road_search_m"] - 60.0, s["road_search_m"], np.maximum(dr, road_river))
        result = base.copy()
        w_river = np.where(river_side, fade, 0.0)
        result = result * (1.0 - w_river) + bank * w_river
        w_city = np.where(city, (1.0 - hill) * city_reach, 0.0)
        w_city = np.where(riverside_road, 1.0, w_city)
        result = result * (1.0 - w_city) + road_h * w_city
        placeable = river_side & (u >= 1.0) & (distance_to_river > self.bank_ramp_m) & (fade > 0.95)
        placeable |= base_placeable & ~context
        stats = {"levee_profile_pixels": int(river_side.sum()), "levee_slope_pixels": int((river_side & (u < 1.0)).sum()),
                 "city_flatten_pixels": int((w_city > 0.5).sum()), "levee_placeable_pixels": int(placeable.sum())}
        return result.astype(np.float32), placeable, stats, river_side & (u < 1.0)
