"""둔치 배치 가능 마스크를 제방·강변도로 폭만큼 넓힌 보도 배치 권역과 수면 판정."""
from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from pipeline.processors.riverside_trial.placement_mask import PlacementMask


class RiversideZone(PlacementMask):
    """PlacementMask에 넓힌 권역(zone)과 수면(water) 판정을 더한다. 좌표는 둔치 지도 월드 미터다."""

    def __init__(self, map_dir: Path, dilate_m: float):
        super().__init__(map_dir)
        water_name = Path(self._meta_assets(map_dir)["watermask"]).name
        self.water = np.array(Image.open(map_dir / water_name)) > 127
        radius = max(1, int(round(dilate_m / self.m_per_px)))
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * radius + 1, 2 * radius + 1))
        self.zone = cv2.dilate(self.mask.astype(np.uint8), kernel) > 0

    @staticmethod
    def _meta_assets(map_dir: Path) -> dict:
        import json
        return json.loads((map_dir / "map_meta.json").read_text(encoding="utf-8"))["assets"]

    def _sample(self, grid: np.ndarray, x: float, z: float) -> bool:
        px, py = self.world_to_pixel(x, z)
        ix, iy = int(px), int(py)
        if ix < 0 or iy < 0 or ix >= self.width or iy >= self.height:
            return False
        return bool(grid[iy, ix])

    def in_zone(self, x: float, z: float) -> bool:
        return self._sample(self.zone, x, z) and not self._sample(self.water, x, z)

    def on_water(self, x: float, z: float) -> bool:
        return self._sample(self.water, x, z)

    def inside_map(self, x: float, z: float) -> bool:
        half = self.size_m / 2.0
        return -half <= x < half and -half <= z < half
