"""공단 구역을 도로로 나눈 블록 목록을 만든다.

기존 도로가 1차 경계가 되고, 기준보다 큰 블록은 긴 축에 수직인 새 도로로 재귀 분할한다.
분할 도로는 블록 경계(기존 도로 또는 다른 분할 도로)에서 끝나므로 도로망이 서로 이어진다.
"""
import math

from shapely.geometry import LineString, Polygon
from shapely.ops import unary_union, nearest_points


class IndustrialBlockDivider:
    MIN_BLOCK_AREA_M2 = 2500.0
    MIN_BLOCK_WIDTH_M = 24.0
    SPLIT_FRACTIONS = (0.5, 0.42, 0.58, 0.34, 0.66)
    CONNECTOR_LIMIT_M = 600.0
    GRADE_WINDOW_M = 40.0
    FORCE_SPLIT_FACTOR = 2.5  # 기준 면적의 이 배수를 넘는 블록은 경사가 커도 중앙에서 나눈다

    def __init__(self, inputs, profile, rng):
        self.inputs = inputs
        self.rng = rng
        self.max_area = float(profile.get("max_block_area_m2", 90000))
        self.local_width = float(profile["local_road_width_m"])
        self.main_width = float(profile["main_road_width_m"])
        self.roads = []

    def build(self, zone, land):
        existing = [self.inputs.roads[int(i)] for i in self.inputs.road_tree.query(zone)]
        existing = [r for r in existing if r["line"].intersects(zone)]
        cuts = unary_union([r["line"].buffer(r["width"] / 2 + 3, cap_style=2) for r in existing]) if existing else None
        base = land.difference(cuts) if cuts is not None else land
        blocks = []
        for piece in self._polygons(base):
            self._split(piece, blocks, depth=0)
        blocks = [b for b in blocks if self._usable(b)]
        self._connect(existing)
        network = unary_union([r["line"] for r in existing] + [LineString(r["points_xz"]) for r in self.roads])
        return {"blocks": blocks, "roads": self.roads, "network": network, "existing_road_count": len(existing)}

    def _split(self, polygon, blocks, depth):
        if polygon.area <= self.max_area or depth > 9:
            blocks.append(polygon)
            return
        rect = list(polygon.minimum_rotated_rectangle.exterior.coords)
        edges = [(rect[i], rect[i + 1]) for i in range(4)]
        long_a, long_b = max(edges, key=lambda e: math.dist(*e))
        axis = ((long_b[0] - long_a[0]), (long_b[1] - long_a[1]))
        length = math.hypot(*axis)
        axis = (axis[0] / length, axis[1] / length)
        normal = (-axis[1], axis[0])
        reach = length * 2
        width = self.main_width if depth == 0 else self.local_width
        forced = polygon.area > self.max_area * self.FORCE_SPLIT_FACTOR
        for attempt, fraction in enumerate(self.SPLIT_FRACTIONS + ((0.5,) if forced else ())):
            force = forced and attempt == len(self.SPLIT_FRACTIONS)
            jitter = fraction + (0.0 if force else self.rng.uniform(-0.04, 0.04))
            center = (long_a[0] + axis[0] * length * jitter, long_a[1] + axis[1] * length * jitter)
            cutter = LineString([(center[0] - normal[0] * reach, center[1] - normal[1] * reach),
                                 (center[0] + normal[0] * reach, center[1] + normal[1] * reach)])
            road = cutter.intersection(polygon)
            segments = [g for g in self._lines(road) if g.length >= 20]
            if not segments or not (force or all(self._gentle(s) for s in segments)):
                continue
            pieces = self._polygons(polygon.difference(unary_union([s.buffer(width / 2, cap_style=2) for s in segments])))
            if len(pieces) < 2:
                continue
            for segment in segments:
                self.roads.append({"id": f"block_{len(self.roads)}", "width_m": width,
                                   "points_xz": [[round(x, 2), round(z, 2)] for x, z in segment.coords], "kind": "district_divider"})
            for piece in pieces:
                self._split(piece, blocks, depth + 1)
            return
        blocks.append(polygon)

    def _connect(self, existing):
        """기존 도로와 닿지 않는 분할 도로 묶음은 가장 가까운 기존 도로까지 접속로를 낸다."""
        if not self.roads or not existing:
            return
        reach = unary_union([r["line"].buffer(r["width"] / 2 + self.local_width) for r in existing])
        lines = [LineString(r["points_xz"]) for r in self.roads]
        groups, seen = [], set()
        for start in range(len(lines)):
            if start in seen:
                continue
            stack, group = [start], []
            while stack:
                index = stack.pop()
                if index in seen:
                    continue
                seen.add(index)
                group.append(index)
                stack.extend(j for j in range(len(lines)) if j not in seen and lines[index].distance(lines[j]) < self.local_width)
            groups.append(group)
        existing_lines = unary_union([r["line"] for r in existing])
        for group in groups:
            members = unary_union([lines[i] for i in group])
            if members.intersects(reach):
                continue
            start, join = nearest_points(members, existing_lines)
            connector = LineString([start, join])
            if 5 < connector.length <= self.CONNECTOR_LIMIT_M and self._gentle(connector):
                self.roads.append({"id": f"block_{len(self.roads)}", "width_m": self.local_width,
                                   "points_xz": [[round(p[0], 2), round(p[1], 2)] for p in connector.coords], "kind": "connector"})

    def _gentle(self, line):
        """구간 평균 경사로 판정해 고도 자료의 국소 잡음에 분할이 막히지 않게 한다."""
        count = max(1, math.ceil(line.length / self.GRADE_WINDOW_M))
        limit = float(self.inputs.config.get("district_road_grade", 0.14))
        heights = [self.inputs.sample(*line.interpolate(i / count, normalized=True).coords[0]) for i in range(count + 1)]
        step = line.length / count
        return all(abs(b - a) / step <= limit for a, b in zip(heights, heights[1:]))

    def _usable(self, block):
        return block.area >= self.MIN_BLOCK_AREA_M2 and not block.buffer(-self.MIN_BLOCK_WIDTH_M / 2).is_empty

    @staticmethod
    def _polygons(geometry):
        if geometry.is_empty:
            return []
        if isinstance(geometry, Polygon):
            return [geometry]
        return [g for g in getattr(geometry, "geoms", []) if isinstance(g, Polygon)]

    @staticmethod
    def _lines(geometry):
        if geometry.is_empty:
            return []
        if geometry.geom_type == "LineString":
            return [geometry]
        return [g for g in getattr(geometry, "geoms", []) if g.geom_type == "LineString"]
