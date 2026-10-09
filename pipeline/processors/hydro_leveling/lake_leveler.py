"""호수·저수지 성분마다 단일 수위로 평탄화하고 기슭을 완만하게 잇는다.

수위보다 `keep_above_m` 이상 높은 화소는 다각형이 산비탈로 번진 것으로 보고 수면에서 빼며
지형은 깎지 않는다. 지형은 낮추기만 하고 올리지 않는다.
"""
import cv2
import numpy as np


def _smoothstep(edge0, edge1, value):
    t = np.clip((value - edge0) / max(edge1 - edge0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class LakeLeveler:
    def __init__(self, pixel_m, settings):
        self.pixel_m = pixel_m
        self.s = settings

    def apply(self, heights, lake):
        s = self.s
        result = heights.copy()
        count, labels, stats, _ = cv2.connectedComponentsWithStats(lake.astype(np.uint8), connectivity=8)
        surface = np.full(heights.shape, np.nan, np.float32)
        ring = int(np.ceil(s["shore_blend_m"] / self.pixel_m)) + 2
        report = []
        removed = 0
        kept = np.zeros(lake.shape, bool)
        for k in range(1, count):
            x, y, w, h, area = stats[k]
            y0, y1 = max(0, y - ring), min(heights.shape[0], y + h + ring)
            x0, x1 = max(0, x - ring), min(heights.shape[1], x + w + ring)
            polygon = labels[y0:y1, x0:x1] == k
            local = result[y0:y1, x0:x1]
            level = float(np.percentile(local[polygon], s["level_percentile"]))
            before = float(np.percentile(local[polygon], 95) - np.percentile(local[polygon], 5))
            inside = polygon & (local <= level + s["keep_above_m"])
            removed += int((polygon & ~inside).sum())
            distance = cv2.distanceTransform((~inside).astype(np.uint8), cv2.DIST_L2, 5) * self.pixel_m
            blend = _smoothstep(0.0, s["shore_blend_m"], distance)
            shore = level + s["shore_rise_m"] + (local - level - s["shore_rise_m"]) * blend
            lowered = np.where(local > shore, np.maximum(shore, local - s["shore_max_cut_m"]), local)
            local[:] = np.where(inside, np.minimum(local, level - s["depth_m"]),
                                np.where(distance <= s["shore_blend_m"], lowered, local))
            surface[y0:y1, x0:x1][inside] = level
            kept[y0:y1, x0:x1] |= inside
            if before > s["report_range_m"]:
                report.append({"component": int(k), "pixels": int(area), "level_m": round(level, 2),
                               "range_before_m": round(before, 1), "center_px": [int(x + w / 2), int(y + h / 2)]})
        report.sort(key=lambda r: -r["range_before_m"])
        stats = {"lakes": int(count - 1), "lakes_over_report_range": len(report),
                 "slope_pixels_removed_from_lakes": removed, "worst": report[:20]}
        return result, kept, stats
