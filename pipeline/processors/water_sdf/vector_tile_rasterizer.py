"""하천·호수 벡터를 지도 격자보다 촘촘한 타일 단위로 그려 부호 거리(미터)를 구한다.

지도 격자 1화소(약 14m)보다 좁은 하천도 끊기지 않도록 선형 수로에 최소 폭을 적용하고,
`supersample`배 해상도에서 거리 변환한 뒤 지도 격자로 평균해 경계가 화소 계단 없이 이어지게 한다.
"""
import cv2
import numpy as np


class VectorTileRasterizer:
    SHIFT = 4  # cv2 소수점 좌표 비트 수

    def __init__(self, bbox, size, meters_per_pixel, supersample=4, tile=256, clamp_m=40.0, min_line_width_m=16.0):
        self.bbox = bbox
        self.size = size
        self.meters = meters_per_pixel
        self.ss = supersample
        self.tile = tile
        self.clamp = clamp_m
        self.min_width = min_line_width_m
        self.pad = int(np.ceil(clamp_m / (meters_per_pixel / supersample))) + 2
        self.items = []

    def _pixels(self, coords):
        b, n = self.bbox, self.size
        array = np.asarray(coords, dtype=np.float64)[:, :2]
        x = (array[:, 0] - b["west"]) / (b["east"] - b["west"]) * (n - 1)
        y = (b["north"] - array[:, 1]) / (b["north"] - b["south"]) * (n - 1)
        return np.stack([x, y], axis=1)

    def add_feature(self, feature):
        geometry, props = feature["geometry"], feature.get("properties", {})
        if geometry["type"] == "MultiPolygon":
            outer = [self._pixels(poly[0]) for poly in geometry["coordinates"] if len(poly[0]) >= 3]
            inner = [self._pixels(ring) for ring in props.get("inner_rings", []) if len(ring) >= 3]
            if outer:
                self.items.append(("polygon", outer, inner, 0.0))
            return
        tags = props.get("tags", {})
        try:
            width = float(str(tags.get("width", "")).replace(" m", "").replace("m", ""))
        except ValueError:
            width = 25.0 if tags.get("waterway") == "river" else 6.0
        lines = [self._pixels(line) for line in geometry["coordinates"] if len(line) >= 2]
        if lines:
            self.items.append(("line", lines, [], max(min(width, 500.0), self.min_width)))

    def _bounds(self):
        bounds = []
        for kind, parts, _, width in self.items:
            stacked = np.concatenate(parts)
            margin = width / self.meters / 2.0 + self.clamp / self.meters + 2.0
            bounds.append((stacked[:, 0].min() - margin, stacked[:, 1].min() - margin,
                           stacked[:, 0].max() + margin, stacked[:, 1].max() + margin))
        return np.asarray(bounds) if bounds else np.zeros((0, 4))

    def _draw(self, canvas, origin_x, origin_y, index):
        kind, parts, inner, width = self.items[index]
        def local(points):
            # 지도 격자 화소 중심(정수 좌표) -> 고해상도 화소 중심
            hx = (points[:, 0] * self.ss + (self.ss - 1) / 2.0) - origin_x * self.ss + self.pad
            hy = (points[:, 1] * self.ss + (self.ss - 1) / 2.0) - origin_y * self.ss + self.pad
            return np.rint(np.stack([hx, hy], axis=1) * (1 << self.SHIFT)).astype(np.int32)

        if kind == "polygon":
            layer = np.zeros_like(canvas)
            cv2.fillPoly(layer, [local(p) for p in parts], 255, cv2.LINE_8, self.SHIFT)
            if inner:
                cv2.fillPoly(layer, [local(p) for p in inner], 0, cv2.LINE_8, self.SHIFT)
            np.maximum(canvas, layer, out=canvas)
        else:
            thickness = max(1, int(round(width / (self.meters / self.ss))))
            cv2.polylines(canvas, [local(p) for p in parts], False, 255, thickness, cv2.LINE_8, self.SHIFT)

    def signed_distance(self, progress=None):
        """지도 격자 크기의 부호 거리(미터, 수면 안쪽 음수)를 반환한다."""
        n, t, ss, pad = self.size, self.tile, self.ss, self.pad
        result = np.full((n, n), self.clamp, np.float32)
        bounds = self._bounds()
        hi_m = self.meters / ss
        tiles = [(x, y) for y in range(0, n, t) for x in range(0, n, t)]
        for count, (tx, ty) in enumerate(tiles):
            w, h = min(t, n - tx), min(t, n - ty)
            hit = np.flatnonzero((bounds[:, 2] >= tx) & (bounds[:, 0] <= tx + w) &
                                 (bounds[:, 3] >= ty) & (bounds[:, 1] <= ty + h)) if len(bounds) else []
            if len(hit) == 0:
                continue
            canvas = np.zeros((h * ss + pad * 2, w * ss + pad * 2), np.uint8)
            for index in hit:
                self._draw(canvas, tx, ty, index)
            water = canvas > 0
            if not water.any():
                continue
            outside = cv2.distanceTransform((~water).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
            inside = cv2.distanceTransform(water.astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
            signed = (outside - inside) * hi_m
            core = signed[pad:pad + h * ss, pad:pad + w * ss]
            block = core.reshape(h, ss, w, ss).mean(axis=(1, 3))
            result[ty:ty + h, tx:tx + w] = np.minimum(result[ty:ty + h, tx:tx + w], np.clip(block, -self.clamp, self.clamp))
            if progress and count % 50 == 0:
                progress(count, len(tiles))
        return result
