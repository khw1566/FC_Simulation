"""스트리밍용 건물 자료의 용량을 줄인다.

- 지나치게 작은 부지의 낮은 건물은 제외한다.
- 밑면 폴리곤의 중복·근접 꼭짓점을 정리하고 형상 오차 한도 안에서 단순화한다.
- 원·타원에 가까운 곡면 건물은 꼭짓점 대신 타원 매개변수(round)로 저장하고
  게임에서 둘레 길이에 맞는 분할 수로 복원한다.
"""
import math
from collections import Counter

from shapely.geometry import Polygon


class BuildingOptimizer:
    VERSION = 1
    MIN_AREA_M2 = 20.0          # 이보다 작은 부지는 제외
    KEEP_HEIGHT_M = 10.0        # 작은 부지라도 이 높이 이상(굴뚝·탑 등)은 유지
    PRECISION = 1               # 좌표 소수 자릿수(0.1m)
    SIMPLIFY_M = 0.5            # 일반 건물 단순화 허용 오차
    CURVE_SIMPLIFY_M = 1.0      # 꼭짓점이 많은 곡면 건물 단순화 허용 오차
    CURVE_VERTEX_LIMIT = 16
    MAX_AREA_CHANGE = 0.05
    ROUND_MIN_VERTICES = 12     # 원형 판정 대상 최소 꼭짓점 수
    ROUND_MIN_ERROR_M = 0.8
    ROUND_RELATIVE_ERROR = 0.05
    SPECIAL_KEYS = ("roof_triangles", "holes", "inner_rings")

    def __init__(self):
        self.stats = Counter()

    def parameters(self):
        return {"version": self.VERSION, "min_area_m2": self.MIN_AREA_M2, "keep_height_m": self.KEEP_HEIGHT_M,
                "precision_m": 10 ** -self.PRECISION, "simplify_m": self.SIMPLIFY_M,
                "curve_simplify_m": self.CURVE_SIMPLIFY_M, "max_area_change": self.MAX_AREA_CHANGE,
                "round_error_m": [self.ROUND_MIN_ERROR_M, self.ROUND_RELATIVE_ERROR]}

    def optimize(self, item):
        """최적화된 건물을 반환하고, 제외 대상이면 None을 반환한다."""
        self.stats["input"] += 1
        raw = item.get("polygon") or []
        self.stats["input_vertices"] += len(raw)
        if len(raw) < 3 or any(key in item for key in self.SPECIAL_KEYS):
            # 안뜰 등 꼭짓점 번호를 참조하는 자료는 형상을 바꾸지 않는다.
            self.stats["kept_unchanged"] += 1
            self.stats["output_vertices"] += len(raw)
            return item
        points = self._clean(raw)
        if len(points) < 3:
            self.stats["dropped_degenerate"] += 1
            return None
        shape = Polygon(points)
        if not shape.is_valid:
            shape = shape.buffer(0)
            if shape.geom_type != "Polygon" or shape.is_empty:
                self.stats["kept_invalid"] += 1
                self.stats["output_vertices"] += len(raw)
                return item
        if shape.area < self.MIN_AREA_M2 and float(item.get("height", 0.0)) < self.KEEP_HEIGHT_M:
            self.stats["dropped_small"] += 1
            return None
        result = dict(item)
        ring = list(shape.exterior.coords)[:-1]
        ellipse = self._fit_round(shape, len(ring))
        if ellipse is not None:
            result.pop("polygon", None)
            result["round"] = ellipse
            self.stats["round"] += 1
            self.stats["round_replaced_vertices"] += len(ring)
            self._update_extent(result, shape)
            return result
        simplified = self._simplify(shape, len(ring))
        result["polygon"] = simplified
        self.stats["output_vertices"] += len(simplified)
        if len(simplified) < len(raw):
            self.stats["simplified"] += 1
        self._update_extent(result, Polygon(simplified))
        return result

    def _clean(self, raw):
        """닫는 점과 반올림 후 중복되는 꼭짓점을 제거한다."""
        points = []
        for p in raw:
            q = (round(float(p[0]), self.PRECISION), round(float(p[1]), self.PRECISION))
            if not points or q != points[-1]:
                points.append(q)
        if len(points) > 1 and points[0] == points[-1]:
            points.pop()
        return points

    def _simplify(self, shape, count):
        tolerance = self.CURVE_SIMPLIFY_M if count > self.CURVE_VERTEX_LIMIT else self.SIMPLIFY_M
        for tol in (tolerance, self.SIMPLIFY_M, self.SIMPLIFY_M * 0.5):
            candidate = shape.simplify(tol, preserve_topology=True)
            if candidate.geom_type != "Polygon" or not candidate.is_valid:
                continue
            if abs(candidate.area - shape.area) > shape.area * self.MAX_AREA_CHANGE:
                continue
            coords = [(round(x, self.PRECISION), round(y, self.PRECISION)) for x, y in candidate.exterior.coords[:-1]]
            if len(coords) >= 3 and Polygon(coords).is_valid:
                return [list(c) for c in coords]
        return [list(c) for c in shape.exterior.coords[:-1]]

    def _fit_round(self, shape, count):
        """최소 회전 사각형 방향과 면적을 보존한 타원으로 근사하고 오차가 작을 때만 채택한다."""
        if count < self.ROUND_MIN_VERTICES:
            return None
        rect = list(shape.minimum_rotated_rectangle.exterior.coords)
        edge_a = (rect[1][0] - rect[0][0], rect[1][1] - rect[0][1])
        edge_b = (rect[2][0] - rect[1][0], rect[2][1] - rect[1][1])
        half_a, half_b = math.hypot(*edge_a) * 0.5, math.hypot(*edge_b) * 0.5
        if half_a < 0.5 or half_b < 0.5:
            return None
        scale = math.sqrt(shape.area / (math.pi * half_a * half_b))
        rx, rz = half_a * scale, half_b * scale
        angle = math.atan2(edge_a[1], edge_a[0])
        center = shape.centroid
        ellipse = Polygon(self.ellipse_points(center.x, center.y, rx, rz, angle, 64))
        error = shape.hausdorff_distance(ellipse)
        if error > max(self.ROUND_MIN_ERROR_M, self.ROUND_RELATIVE_ERROR * max(rx, rz)):
            return None
        return [round(center.x, self.PRECISION), round(center.y, self.PRECISION),
                round(rx, 2), round(rz, 2), round(math.degrees(angle), 1)]

    @staticmethod
    def ellipse_points(cx, cz, rx, rz, angle, segments):
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        points = []
        for i in range(segments):
            t = math.tau * i / segments
            x, z = rx * math.cos(t), rz * math.sin(t)
            points.append((cx + x * cos_a - z * sin_a, cz + x * sin_a + z * cos_a))
        return points

    def _update_extent(self, item, shape):
        min_x, min_z, max_x, max_z = shape.bounds
        center = item.get("center", [0, 0, 0])
        c = shape.centroid
        item["center"] = [round(c.x, self.PRECISION), center[1] if len(center) > 1 else 0.0, round(c.y, self.PRECISION)]
        size = item.get("size", [0, 0, 0])
        item["size"] = [round(max_x - min_x, 2), size[1] if len(size) > 1 else 0.0, round(max_z - min_z, 2)]
