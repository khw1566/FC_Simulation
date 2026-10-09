"""하천 마스크를 하곡 바닥 기준 매끄러운 수면으로 정지한다. 지형은 낮추기만 한다.

1) 하도 안 국소 최저 고도(반경 `floor_radius_m`)를 하곡 바닥으로 삼는다.
2) 하도 내부에서만 가중 평균해 매끄러운 수면을 만들고, 바닥보다 높아지지 않게 한다.
3) 원 고도가 수면보다 `carve_max_m` 넘게 높은 화소는 마스크가 하곡 비탈로 번진 것으로 보고
   수면에서 빼며 깎지 않는다.
4) 수면 경사가 `max_visible_grade`를 넘는 산지 계류도 수면 표시에서 뺀다.
5) 남은 하도는 수면 - `channel_depth_m`로, 기슭은 `bank_blend_m` 폭으로 수면 + `bank_rise_m`까지 낮춰 잇는다.
"""
import cv2
import numpy as np


def _smoothstep(edge0, edge1, value):
    t = np.clip((value - edge0) / max(edge1 - edge0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class RiverLeveler:
    def __init__(self, pixel_m, settings):
        self.pixel_m = pixel_m
        self.s = settings

    def _floor(self, heights, river):
        radius = max(1, int(round(self.s["floor_radius_m"] / self.pixel_m)))
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (radius * 2 + 1, radius * 2 + 1))
        masked = np.where(river, heights, np.float32(1e6)).astype(np.float32)
        return np.where(river, cv2.erode(masked, kernel), heights)

    def _smooth(self, values, river):
        sigma = max(self.s["smooth_m"] / self.pixel_m, 0.5)
        weight = river.astype(np.float32)
        numerator = cv2.GaussianBlur(np.where(river, values, 0.0).astype(np.float32), (0, 0), sigma)
        denominator = cv2.GaussianBlur(weight, (0, 0), sigma)
        return np.where(river, numerator / np.maximum(denominator, 1e-4), values).astype(np.float32)

    def apply(self, heights, river):
        s = self.s
        floor = self._floor(heights, river)
        surface = np.minimum(self._smooth(floor, river), floor)
        gy, gx = np.gradient(np.where(river, surface, np.nan).astype(np.float32))
        grade = np.nan_to_num(np.hypot(gx, gy) / self.pixel_m, nan=0.0)
        grade = cv2.GaussianBlur(grade, (0, 0), max(60.0 / self.pixel_m, 1.0))
        on_floor = river & (heights - surface <= s["carve_max_m"])
        visible = on_floor & (grade <= s["max_visible_grade"])

        result = heights.copy()
        result[visible] = np.minimum(heights, surface - s["channel_depth_m"])[visible]
        distance, label_map = cv2.distanceTransformWithLabels((~visible).astype(np.uint8), cv2.DIST_L2, 5,
                                                              labelType=cv2.DIST_LABEL_PIXEL)
        index = np.flatnonzero(visible.ravel())
        nearest = np.concatenate([[np.nan], surface.ravel()[index]]).astype(np.float32)[label_map]
        distance_m = distance * self.pixel_m
        bank = nearest + s["bank_rise_m"]
        target = bank + (heights - bank) * _smoothstep(0.0, s["bank_blend_m"], distance_m)
        lower = (~visible) & (distance_m <= s["bank_blend_m"]) & (heights > target)
        result[lower] = target[lower]
        stats = {"river_pixels": int(river.sum()), "visible_pixels": int(visible.sum()),
                 "removed_slope_pixels": int((river & ~on_floor).sum()),
                 "removed_steep_pixels": int((on_floor & ~visible).sum()),
                 "max_lowered_m": round(float((heights - result).max()), 2)}
        return result.astype(np.float32), visible, stats
