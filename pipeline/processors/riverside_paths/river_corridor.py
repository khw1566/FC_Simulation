"""하천 중심선을 따라가는 좌표계. 지역 미터 좌표 변환, 중심선 표본, 수면 판정을 제공한다."""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

LAT0 = 35.55
M_PER_DEG_LAT = 110574.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(LAT0))


def to_m(lon: float, lat: float) -> tuple[float, float]:
    return (lon - 129.0) * M_PER_DEG_LON, (LAT0 - lat) * M_PER_DEG_LAT


def to_lonlat(x: float, z: float) -> tuple[float, float]:
    return 129.0 + x / M_PER_DEG_LON, LAT0 - z / M_PER_DEG_LAT


class WaterMask:
    """게임 지도(울산 80km)의 수면 마스크로 수면 여부를 판정한다."""

    def __init__(self, map_dir: Path):
        meta = json.loads((map_dir / "map_meta.json").read_text(encoding="utf-8"))
        self.bbox = meta["bbox"]
        relative = meta["assets"]["watermask"].replace("res://assets/maps/" + map_dir.name + "/", "")
        self.mask = np.array(Image.open(map_dir / relative).convert("L")) > 127
        self.height, self.width = self.mask.shape

    def is_water(self, x: float, z: float) -> bool:
        lon, lat = to_lonlat(x, z)
        b = self.bbox
        px = int((lon - b["west"]) / (b["east"] - b["west"]) * self.width)
        py = int((b["north"] - lat) / (b["north"] - b["south"]) * self.height)
        if px < 0 or py < 0 or px >= self.width or py >= self.height:
            return False
        return bool(self.mask[py, px])


class RiverCorridor:
    """하천 중심선 표본(일정 간격)과 각 표본의 단위 법선. 법선은 진행 방향 오른쪽이다."""

    def __init__(self, rivers_raw: Path, step_m: float, smooth_m: float = 80.0):
        elements = json.loads(rivers_raw.read_text(encoding="utf-8"))["elements"]
        line = _join_ways([[to_m(p["lon"], p["lat"]) for p in e["geometry"]] for e in elements])
        self.points = _resample(np.array(line), step_m)
        self.step_m = step_m
        tangent = np.gradient(self.points, axis=0)
        window = max(1, int(smooth_m / step_m))
        kernel = np.ones(2 * window + 1) / (2 * window + 1)
        tangent = np.stack([np.convolve(np.pad(tangent[:, i], window, mode="edge"), kernel, "valid") for i in range(2)], 1)
        tangent /= np.linalg.norm(tangent, axis=1, keepdims=True)
        self.normals = np.stack([tangent[:, 1], -tangent[:, 0]], 1)

    def nearest(self, points: np.ndarray, chunk: int = 4096) -> tuple[np.ndarray, np.ndarray]:
        """각 점에서 가장 가까운 중심선 표본 번호와 거리."""
        index = np.empty(len(points), int)
        distance = np.empty(len(points))
        for start in range(0, len(points), chunk):
            block = points[start:start + chunk]
            d = np.linalg.norm(block[:, None, :] - self.points[None, :, :], axis=2)
            index[start:start + chunk] = d.argmin(1)
            distance[start:start + chunk] = d.min(1)
        return index, distance

    def side(self, points: np.ndarray, index: np.ndarray) -> np.ndarray:
        """중심선 오른쪽(+1)·왼쪽(-1) 구분."""
        return np.sign(((points - self.points[index]) * self.normals[index]).sum(1))


def _join_ways(ways: list[list[tuple[float, float]]]) -> list[tuple[float, float]]:
    """끝점이 맞닿은 하천 조각들을 하나의 선으로 잇는다(가장 긴 조각에서 시작)."""
    remaining = sorted(ways, key=len, reverse=True)
    line = list(remaining.pop(0))
    joined = True
    while remaining and joined:
        joined = False
        for i, way in enumerate(remaining):
            if math.dist(line[-1], way[0]) < 1.0:
                line += way[1:]
            elif math.dist(line[-1], way[-1]) < 1.0:
                line += way[::-1][1:]
            elif math.dist(line[0], way[-1]) < 1.0:
                line = way[:-1] + line
            elif math.dist(line[0], way[0]) < 1.0:
                line = way[::-1][:-1] + line
            else:
                continue
            remaining.pop(i)
            joined = True
            break
    return line


def _resample(points: np.ndarray, step: float) -> np.ndarray:
    lengths = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(points, axis=0), axis=1))])
    targets = np.arange(0.0, lengths[-1], step)
    return np.stack([np.interp(targets, lengths, points[:, i]) for i in range(2)], 1)
