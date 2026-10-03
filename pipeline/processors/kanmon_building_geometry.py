"""출처가 있는 건물 외곽선과 높이 속성을 정규화한다."""
import math
from shapely.geometry import Polygon, box
from shapely import make_valid, normalize, set_precision


class KanmonBuildingGeometry:
    def __init__(self, meta):
        self.meta = meta
        self.bbox = meta["bbox"]
        self.size = meta["world_size_meters"]
        self.clip = box(-self.size/2, -self.size/2, self.size/2, self.size/2)

    def world(self, lon, lat):
        return ((lon-self.bbox["west"])/(self.bbox["east"]-self.bbox["west"])-.5)*self.size, ((self.bbox["north"]-lat)/(self.bbox["north"]-self.bbox["south"])-.5)*self.size

    def polygons(self, rings):
        if not rings or len(rings[0]) < 4:
            return []
        shape = make_valid(Polygon([self.world(*p) for p in rings[0]], [[self.world(*p) for p in ring] for ring in rings[1:] if len(ring) >= 4])).intersection(self.clip)
        shapes = [shape] if shape.geom_type == "Polygon" else list(getattr(shape, "geoms", []))
        return [set_precision(p, .01) for p in shapes if p.geom_type == "Polygon" and p.area > 3]

    @staticmethod
    def height(tags):
        try:
            value = str(tags.get("height", "")).replace("m", "").strip()
            if value.endswith("ft"):
                height = float(value[:-2]) * .3048
            else:
                height = float(value)
            if math.isfinite(height) and 1 <= height <= 400:
                return height, "osm_height"
        except ValueError:
            pass
        try:
            levels = float(tags.get("building:levels", ""))
            if math.isfinite(levels) and 0 < levels < 100:
                return levels * 3.2, "osm_levels_estimate"
        except ValueError:
            pass
        kind = tags.get("building", "yes")
        return (16 if kind in ("apartments", "office", "hotel") else 10 if kind in ("industrial", "warehouse") else 8), "default_estimate"

    @staticmethod
    def key(polygon):
        return normalize(polygon).wkb
