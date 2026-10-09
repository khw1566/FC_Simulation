"""위성 영상 위에 수면·강변도로·제방 경사·배치 가능 둔치를 겹친 확인용 이미지를 만든다."""
from pathlib import Path

import cv2
import numpy as np


class CheckOverlayRenderer:
    CROP_PX = 1024

    def __init__(self, root):
        self.folder = Path(root) / "results/dunchi_check"

    @staticmethod
    def _hillshade(heights):
        gy, gx = np.gradient(heights.astype(np.float32))
        shade = np.clip(0.6 - 0.25 * gx + 0.25 * gy, 0.0, 1.0)
        return np.repeat((shade * 255).astype(np.uint8)[:, :, None], 3, axis=2)

    def render(self, heights, satellite, river, all_roads, riverside_road, slope_band, placeable):
        self.folder.mkdir(parents=True, exist_ok=True)
        base = satellite if satellite is not None else self._hillshade(heights)
        image = base.copy()
        layers = [(placeable, (60, 200, 60), 0.30), (slope_band, (0, 210, 255), 0.55),
                  (river, (255, 140, 40), 0.35), (all_roads & ~riverside_road, (200, 200, 200), 0.35),
                  (riverside_road, (40, 40, 255), 0.70)]
        for mask, color, alpha in layers:
            image[mask] = (image[mask] * (1.0 - alpha) + np.array(color) * alpha).astype(np.uint8)
        written = []
        overview = cv2.resize(image, (2048, 2048), interpolation=cv2.INTER_AREA)
        cv2.imwrite(str(self.folder / "overview.jpg"), overview, [cv2.IMWRITE_JPEG_QUALITY, 85])
        written.append("overview.jpg")
        ys, xs = np.nonzero(river)
        if len(xs):
            y_center = int(np.median(ys))
            for i, x in enumerate(range(0, image.shape[1], self.CROP_PX)):
                column = river[:, x:x + self.CROP_PX]
                rows = np.nonzero(column.any(axis=1))[0]
                center = int(rows.mean()) if len(rows) else y_center
                top = int(np.clip(center - self.CROP_PX // 2, 0, image.shape[0] - self.CROP_PX))
                crop = image[top:top + self.CROP_PX, x:x + self.CROP_PX]
                name = f"crop_{i:02d}_x{x}_y{top}.jpg"
                cv2.imwrite(str(self.folder / name), crop, [cv2.IMWRITE_JPEG_QUALITY, 88])
                written.append(name)
        return written
