"""설정의 배치 부지 다각형을 단일 높이로 평탄화하고 주변과 완만하게 잇는다."""
import cv2
import numpy as np


class PadFlattener:
    def __init__(self, grid):
        self.grid = grid

    def apply(self, heights, pads):
        result = heights.copy()
        records = []
        for pad in pads:
            x, y = self.grid.lonlat_to_pixel([p[0] for p in pad["polygon"]], [p[1] for p in pad["polygon"]])
            mask = np.zeros(result.shape, np.uint8)
            cv2.fillPoly(mask, [np.round(np.stack([x, y], axis=1)).astype(np.int32)], 255)
            inside = mask > 0
            if not inside.any():
                records.append({"id": pad["id"], "status": "bbox 밖"})
                continue
            level = pad.get("height_m")
            level = float(np.median(result[inside])) if level is None else float(level)
            blend = float(pad.get("blend_m", 15.0))
            distance = cv2.distanceTransform((~inside).astype(np.uint8), cv2.DIST_L2, 5) * self.grid.pixel_m
            t = np.clip(distance / max(blend, 1e-3), 0.0, 1.0)
            weight = 1.0 - t * t * (3.0 - 2.0 * t)
            result = result * (1.0 - weight) + level * weight
            records.append({"id": pad["id"], "name_ko": pad.get("name_ko"), "height_m": round(level, 3),
                            "area_m2": round(float(inside.sum()) * self.grid.pixel_m ** 2, 1), "status": "적용"})
        return result.astype(np.float32), records
