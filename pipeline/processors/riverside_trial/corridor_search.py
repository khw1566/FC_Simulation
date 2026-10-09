"""배치 가능 마스크 안에서 가장 긴 직선 보도 구간을 찾는다."""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from .placement_mask import PlacementMask


@dataclass
class Corridor:
    """직선 보도 구간. 각 세그먼트 중심과 진행 방향(단위 벡터)을 가진다."""

    centers: list[tuple[float, float]]
    direction: tuple[float, float]

    @property
    def yaw_degrees(self) -> float:
        # 씬의 +Z 진행축을 월드 방향(dx, dz)에 맞추는 Y축 회전
        return math.degrees(math.atan2(self.direction[0], self.direction[1]))

    @property
    def normal(self) -> tuple[float, float]:
        return self.direction[1], -self.direction[0]


class CorridorSearch:
    def __init__(self, mask: PlacementMask, segment_m: float, half_width_m: float, yaw_sweep: list[float]):
        self.mask = mask
        self.segment_m = segment_m
        self.half_width_m = half_width_m
        self.yaw_sweep = yaw_sweep

    def find(self, center: tuple[float, float], radius_m: float, step_m: float, max_segments: int,
             max_candidates: int = 600) -> Corridor | None:
        points = self.mask.placeable_points(center, radius_m, step_m)
        if not points:
            return None
        cloud = np.array(points)
        best: Corridor | None = None
        for p in points[:max_candidates]:
            base = self._local_axis(cloud, p)
            for delta in self.yaw_sweep:
                d = _rotate(base, math.radians(delta))
                corridor = self._grow(p, d, max_segments)
                if best is None or len(corridor.centers) > len(best.centers):
                    best = corridor
                    if len(best.centers) >= max_segments:
                        return best
        return best if best and best.centers else None

    def _local_axis(self, cloud: np.ndarray, p: tuple[float, float], radius_m: float = 80.0) -> tuple[float, float]:
        near = cloud[np.hypot(cloud[:, 0] - p[0], cloud[:, 1] - p[1]) <= radius_m]
        if len(near) < 3:
            return 1.0, 0.0
        cov = np.cov((near - near.mean(axis=0)).T)
        values, vectors = np.linalg.eigh(cov)
        axis = vectors[:, int(np.argmax(values))]
        return float(axis[0]), float(axis[1])

    def _grow(self, p: tuple[float, float], d: tuple[float, float], max_segments: int) -> Corridor:
        centers: list[tuple[float, float]] = []
        if not self._segment_clear(p, d):
            return Corridor(centers, d)
        centers.append(p)
        forward, backward = 1, 1
        while len(centers) < max_segments:
            grown = False
            for sign in (1, -1):
                if len(centers) >= max_segments:
                    break
                k = forward if sign > 0 else backward
                c = (p[0] + d[0] * self.segment_m * k * sign, p[1] + d[1] * self.segment_m * k * sign)
                if k > 0 and self._segment_clear(c, d):
                    centers.append(c)
                    if sign > 0:
                        forward += 1
                    else:
                        backward += 1
                    grown = True
                elif sign > 0:
                    forward = -1
                else:
                    backward = -1
            if not grown:
                break
        centers.sort(key=lambda c: (c[0] - p[0]) * d[0] + (c[1] - p[1]) * d[1])
        return Corridor(centers, d)

    def _segment_clear(self, c: tuple[float, float], d: tuple[float, float]) -> bool:
        n = (d[1], -d[0])
        half = self.segment_m / 2.0
        for t in np.arange(-half, half + 0.01, 2.0):
            for s in (-self.half_width_m, -self.half_width_m / 2, 0.0, self.half_width_m / 2, self.half_width_m):
                if not self.mask.placeable(c[0] + d[0] * t + n[0] * s, c[1] + d[1] * t + n[1] * s):
                    return False
        return True


def _rotate(v: tuple[float, float], angle: float) -> tuple[float, float]:
    ca, sa = math.cos(angle), math.sin(angle)
    return v[0] * ca - v[1] * sa, v[0] * sa + v[1] * ca
