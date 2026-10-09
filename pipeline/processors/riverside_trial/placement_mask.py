"""둔치 배치 가능 마스크 조회와 위경도·월드 좌표 변환."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image


class PlacementMask:
    """map_meta.json과 배치 가능 마스크로 월드 좌표의 배치 가능 여부를 판정한다.

    월드 좌표는 RiversideAssetPlacer.world_xz와 같다. x는 동쪽, z는 남쪽, 지도 중심이 원점이다.
    """

    def __init__(self, map_dir: Path):
        meta = json.loads((map_dir / "map_meta.json").read_text(encoding="utf-8"))
        self.bbox = meta["bbox"]
        self.size_m = float(meta["world_size_meters"])
        mask_name = Path(meta["assets"]["placement_mask"]).name
        self.mask = np.array(Image.open(map_dir / mask_name)) > 127
        self.height, self.width = self.mask.shape
        self.m_per_px = self.size_m / self.width

    def lonlat_to_world(self, lon: float, lat: float) -> tuple[float, float]:
        b = self.bbox
        x = ((lon - b["west"]) / (b["east"] - b["west"]) - 0.5) * self.size_m
        z = ((b["north"] - lat) / (b["north"] - b["south"]) - 0.5) * self.size_m
        return x, z

    def world_to_lonlat(self, x: float, z: float) -> tuple[float, float]:
        b = self.bbox
        lon = b["west"] + (x / self.size_m + 0.5) * (b["east"] - b["west"])
        lat = b["north"] - (z / self.size_m + 0.5) * (b["north"] - b["south"])
        return lon, lat

    def world_to_pixel(self, x: float, z: float) -> tuple[float, float]:
        return (x / self.size_m + 0.5) * self.width, (z / self.size_m + 0.5) * self.height

    def placeable(self, x: float, z: float) -> bool:
        px, py = self.world_to_pixel(x, z)
        ix, iy = int(px), int(py)
        if ix < 0 or iy < 0 or ix >= self.width or iy >= self.height:
            return False
        return bool(self.mask[iy, ix])

    def placeable_points(self, center: tuple[float, float], radius_m: float, step_m: float):
        """중심 반경 안의 배치 가능 격자점을 중심에 가까운 순서로 반환한다."""
        cx, cz = center
        steps = np.arange(-radius_m, radius_m + step_m, step_m)
        points = [
            (cx + dx, cz + dz)
            for dz in steps
            for dx in steps
            if dx * dx + dz * dz <= radius_m * radius_m and self.placeable(cx + dx, cz + dz)
        ]
        points.sort(key=lambda p: (p[0] - cx) ** 2 + (p[1] - cz) ** 2)
        return points
