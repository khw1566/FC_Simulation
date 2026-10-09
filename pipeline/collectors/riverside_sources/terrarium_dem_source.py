"""키 없이 쓰는 공개 Terrarium 고도 타일 대체 수집기와 방향 검증 기준."""
import math
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from regional_elevation_tiles import RegionalElevationTiles  # noqa: E402


class TerrariumDemSource:
    name = "terrarium"

    def __init__(self, root, settings):
        self.tiles = RegionalElevationTiles(root, zoom=int(settings.get("zoom", 15)))

    def collect(self, bbox):
        """Web Mercator 모자이크를 위도 등간격 격자로 바꿔 반환한다. 행 0이 북쪽이다."""
        mosaic, extent, _ = self.tiles.collect(bbox)
        mosaic = self._despike(mosaic)
        n = 2 ** self.tiles.zoom
        rows = mosaic.shape[0]
        north_y = (1 - math.asinh(math.tan(math.radians(extent["north"]))) / math.pi) / 2 * n
        lats = np.linspace(extent["north"], extent["south"], rows)
        tile_y = (1 - np.arcsinh(np.tan(np.radians(lats))) / np.pi) / 2 * n
        source_rows = np.clip((tile_y - north_y) * 256.0, 0, rows - 1)
        lower = np.floor(source_rows).astype(int)
        upper = np.minimum(lower + 1, rows - 1)
        weight = (source_rows - lower)[:, None].astype(np.float32)
        linear = mosaic[lower] * (1 - weight) + mosaic[upper] * weight
        return linear.astype(np.float32), extent

    def _despike(self, mosaic, threshold_m=50.0):
        """Terrarium 타일의 고립 결측 스파이크(-수천 m)를 5x5 중앙값으로 대체한다."""
        median = cv2.medianBlur(mosaic.astype(np.float32), 5)
        spikes = np.abs(mosaic - median) > threshold_m
        self.despiked = int(spikes.sum())
        return np.where(spikes, median, mosaic)

    def meta(self):
        return {"source": self.name, "zoom": self.tiles.zoom, "new_requests": self.tiles.requests,
                "despiked_pixels": getattr(self, "despiked", 0)}
