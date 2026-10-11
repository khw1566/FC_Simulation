"""설정의 우선순위 규칙으로 둔치 픽셀마다 생태 구역 ID를 하나씩 부여한다."""
import numpy as np


class ZoneClassifier:
    def __init__(self, raster, zones):
        self.raster = raster
        self.zones = zones

    def classify(self, placeable, water, osm_layers):
        max_water = max([r.get("water_distance_m", [0, 0])[1] for z in self.zones for r in z["rules"]] + [10])
        water_distance = self.raster.distance_m(water, max_water)
        longitudes = np.broadcast_to(self.raster.column_longitudes()[None, :], placeable.shape)
        buffered = {}
        labels = np.zeros(placeable.shape, dtype=np.uint8)
        free = placeable.copy()
        stats = {}
        for zone in self.zones:
            hit = np.zeros_like(placeable)
            for rule in zone["rules"]:
                hit |= self._rule(rule, placeable, water_distance, longitudes, osm_layers, buffered)
            hit &= free
            labels[hit] = zone["id"]
            free &= ~hit
            area = float(hit.sum()) * self.raster.cell_m ** 2
            stats[zone["key"]] = {"id": zone["id"], "pixels": int(hit.sum()), "area_m2": round(area, 1)}
        return labels, stats

    def _rule(self, rule, placeable, water_distance, longitudes, osm_layers, buffered):
        hit = placeable.copy()
        if "water_distance_m" in rule:
            low, high = rule["water_distance_m"]
            hit &= (water_distance >= low) & (water_distance <= high)
        if "lon_ranges" in rule:
            inside = np.zeros_like(hit)
            for west, east in rule["lon_ranges"]:
                inside |= (longitudes >= west) & (longitudes <= east)
            hit &= inside
        if "polygons_lonlat" in rule:
            hit &= self.raster.rasterize_polygons(rule["polygons_lonlat"])
        buffer_m = float(rule.get("osm_buffer_m", 0.0))
        if "osm_any" in rule:
            hit &= self._osm(rule["osm_any"], buffer_m, osm_layers, buffered)
        if "osm_none" in rule:
            hit &= ~self._osm(rule["osm_none"], 0.0, osm_layers, buffered)
        return hit

    def _osm(self, classes, buffer_m, osm_layers, buffered):
        result = np.zeros(next(iter(osm_layers.values())).shape, dtype=bool)
        for name in classes:
            key = (name, buffer_m)
            if key not in buffered:
                steps = int(round(buffer_m / self.raster.cell_m))
                buffered[key] = self.raster.dilate(osm_layers[name], steps) if steps else osm_layers[name]
            result |= buffered[key]
        return result

    def edge_distance(self, labels, zone_id, max_m=24.0):
        """구역 내부 픽셀의 경계까지 근사 거리(가장자리 군집·내부 숲 타일 구분용)."""
        return self.raster.distance_m(labels != zone_id, max_m)
