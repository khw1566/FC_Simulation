"""지도 bbox 격자에서 위경도 변환, OSM 다각형 래스터화, 거리 밴드 계산을 담당한다."""
import numpy as np
from PIL import Image, ImageDraw


class GeoRaster:
    def __init__(self, bbox, size, world_size_m):
        self.bbox = bbox
        self.size = int(size)
        self.world_size_m = float(world_size_m)
        self.cell_m = self.world_size_m / (self.size - 1)

    def to_pixel(self, lat, lon):
        b = self.bbox
        u = (lon - b["west"]) / (b["east"] - b["west"]) * (self.size - 1)
        v = (b["north"] - lat) / (b["north"] - b["south"]) * (self.size - 1)
        return u, v

    def column_longitudes(self):
        b = self.bbox
        return b["west"] + np.arange(self.size) / (self.size - 1) * (b["east"] - b["west"])

    def world_to_pixel(self, x, z):
        # 월드 원점은 지도 중앙, +X 동쪽, +Z 남쪽(RiversideAssetPlacer와 동일).
        u = (np.asarray(x) / self.world_size_m + 0.5) * (self.size - 1)
        v = (np.asarray(z) / self.world_size_m + 0.5) * (self.size - 1)
        return u, v

    @staticmethod
    def _rings(element):
        if element.get("type") == "way":
            geometry = element.get("geometry") or []
            return [("outer", geometry)] if len(geometry) >= 3 else []
        rings = []
        for member in element.get("members", []):
            geometry = member.get("geometry") or []
            if member.get("type") == "way" and len(geometry) >= 2:
                rings.append((member.get("role") or "outer", geometry))
        return rings

    def rasterize_classes(self, elements, class_tags):
        layers = {name: Image.new("L", (self.size, self.size), 0) for name in class_tags}
        for element in elements:
            tags = element.get("tags", {})
            names = [name for name, pairs in class_tags.items() if any(tags.get(k) == v for k, v in pairs)]
            if not names:
                continue
            outers = [ring for role, ring in self._rings(element) if role != "inner"]
            inners = [ring for role, ring in self._rings(element) if role == "inner"]
            for name in names:
                draw = ImageDraw.Draw(layers[name])
                self._draw(draw, outers, 255)
                self._draw(draw, inners, 0)
        return {name: np.array(image) > 0 for name, image in layers.items()}

    def rasterize_polygons(self, polygons):
        """[[경도, 위도], ...] 다각형 목록을 채운 마스크."""
        image = Image.new("L", (self.size, self.size), 0)
        draw = ImageDraw.Draw(image)
        for polygon in polygons:
            draw.polygon([self.to_pixel(lat, lon) for lon, lat in polygon], fill=255)
        return np.array(image) > 0

    def _draw(self, draw, rings, value):
        for ring in self._stitch(rings):
            if len(ring) >= 3:
                draw.polygon([self.to_pixel(p["lat"], p["lon"]) for p in ring], fill=value)

    @staticmethod
    def _stitch(rings):
        # 멀티폴리곤 구성 웨이를 끝점 기준으로 이어 닫힌 고리로 만든다.
        pending = [list(r) for r in rings]
        closed = []
        while pending:
            ring = pending.pop(0)
            changed = True
            while changed and (ring[0]["lat"], ring[0]["lon"]) != (ring[-1]["lat"], ring[-1]["lon"]):
                changed = False
                tail = (ring[-1]["lat"], ring[-1]["lon"])
                for i, other in enumerate(pending):
                    if (other[0]["lat"], other[0]["lon"]) == tail:
                        ring += other[1:]
                    elif (other[-1]["lat"], other[-1]["lon"]) == tail:
                        ring += other[::-1][1:]
                    else:
                        continue
                    pending.pop(i)
                    changed = True
                    break
            closed.append(ring)
        return closed

    @staticmethod
    def dilate(mask, steps):
        result = mask.copy()
        for step in range(int(steps)):
            grown = result.copy()
            grown[1:, :] |= result[:-1, :]
            grown[:-1, :] |= result[1:, :]
            grown[:, 1:] |= result[:, :-1]
            grown[:, :-1] |= result[:, 1:]
            if step % 2:
                grown[1:, 1:] |= result[:-1, :-1]
                grown[:-1, :-1] |= result[1:, 1:]
                grown[1:, :-1] |= result[:-1, 1:]
                grown[:-1, 1:] |= result[1:, :-1]
            result = grown
        return result

    @staticmethod
    def reconstruct(seed, mask):
        """seed에서 출발해 mask 안에서 이어지는 영역(형태학적 재구성)."""
        region = seed & mask
        while True:
            grown = GeoRaster.dilate(region, 8) & mask
            if np.array_equal(grown, region):
                return region
            region = grown

    def distance_m(self, mask, max_m):
        """대상 마스크로부터의 근사 거리(4·8 이웃 교대 확장, 팔각형 근사). 범위 밖은 inf."""
        distance = np.full(mask.shape, np.inf, dtype=np.float32)
        distance[mask] = 0.0
        front = mask.copy()
        for step in range(1, int(np.ceil(max_m / self.cell_m)) + 1):
            grown = self.dilate(front, 1) if step % 2 else self._dilate8(front)
            distance[grown & ~front] = step * self.cell_m
            front = grown
        return distance

    @staticmethod
    def _dilate8(mask):
        grown = GeoRaster.dilate(mask, 1)
        grown[1:, 1:] |= mask[:-1, :-1]
        grown[:-1, :-1] |= mask[1:, 1:]
        grown[1:, :-1] |= mask[:-1, 1:]
        grown[:-1, 1:] |= mask[1:, :-1]
        return grown
