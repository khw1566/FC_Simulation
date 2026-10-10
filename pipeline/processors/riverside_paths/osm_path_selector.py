"""OSM 보행로·자전거길 선형에서 둔치 권역 안 구간을 골라 일정 간격 접속점으로 나눈다."""
from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from pathlib import Path

from .riverside_zone import RiversideZone

DENSIFY_STEP_M = 2.0


@dataclass
class PathRun:
    """권역 안에서 끊기지 않고 이어지는 보행로 한 구간. nodes는 월드 미터 접속점이다."""

    osm_id: int
    highway: str
    surface: str | None
    name: str | None
    nodes: list[tuple[float, float]] = field(default_factory=list)

    @property
    def length_m(self) -> float:
        return sum(math.dist(a, b) for a, b in zip(self.nodes[:-1], self.nodes[1:]))


class OsmPathSelector:
    def __init__(self, zone: RiversideZone, settings: dict):
        self.zone = zone
        self.settings = settings

    def select(self, roads_raw: Path) -> list[PathRun]:
        data = json.loads(roads_raw.read_text(encoding="utf-8"))
        highways = set(self.settings["path_highways"])
        runs: list[PathRun] = []
        for element in data.get("elements", []):
            tags = element.get("tags", {})
            if element.get("type") != "way" or tags.get("highway") not in highways:
                continue
            if tags.get("bridge") not in (None, "no") or tags.get("tunnel") not in (None, "no"):
                continue
            geometry = [p for p in element.get("geometry", []) if "lon" in p]
            if len(geometry) < 2 or (tags.get("area") == "yes"):
                continue
            if tags.get("highway") == "pedestrian" and geometry[0] == geometry[-1]:
                continue  # 광장 면형은 선형 보도가 아니다
            points = [self.zone.lonlat_to_world(p["lon"], p["lat"]) for p in geometry]
            dense = _densify(points, DENSIFY_STEP_M)
            if not all(self.zone.inside_map(x, z) for x, z in dense):
                continue
            flags = [self.zone.in_zone(x, z) for x, z in dense]
            if sum(flags) / len(flags) < self.settings["min_zone_share"]:
                continue
            for piece in _split(dense, flags):
                nodes = _resample(piece, self.settings["segment_length_m"])
                run = PathRun(element["id"], tags["highway"], tags.get("surface"), tags.get("name"), nodes)
                if len(nodes) >= 2 and run.length_m >= self.settings["min_run_m"]:
                    runs.append(run)
        return runs


def _densify(points: list[tuple[float, float]], step: float) -> list[tuple[float, float]]:
    out = [points[0]]
    for a, b in zip(points[:-1], points[1:]):
        count = max(1, int(math.dist(a, b) / step))
        out.extend((a[0] + (b[0] - a[0]) * t / count, a[1] + (b[1] - a[1]) * t / count) for t in range(1, count + 1))
    return out


def _split(points: list[tuple[float, float]], flags: list[bool]) -> list[list[tuple[float, float]]]:
    pieces, current = [], []
    for point, ok in zip(points, flags):
        if ok:
            current.append(point)
        elif current:
            pieces.append(current)
            current = []
    if current:
        pieces.append(current)
    return [p for p in pieces if len(p) >= 2]


def _resample(points: list[tuple[float, float]], spacing: float) -> list[tuple[float, float]]:
    """선형을 같은 호 길이 간격의 접속점으로 다시 나눈다. 간격은 spacing에 가장 가깝게 맞춘다."""
    lengths = [0.0]
    for a, b in zip(points[:-1], points[1:]):
        lengths.append(lengths[-1] + math.dist(a, b))
    total = lengths[-1]
    count = max(1, round(total / spacing))
    nodes, j = [], 0
    for k in range(count + 1):
        target = total * k / count
        while j < len(points) - 2 and lengths[j + 1] < target:
            j += 1
        span = lengths[j + 1] - lengths[j]
        t = 0.0 if span <= 0 else (target - lengths[j]) / span
        a, b = points[j], points[j + 1]
        nodes.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return nodes
