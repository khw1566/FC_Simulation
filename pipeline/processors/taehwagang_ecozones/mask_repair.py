"""원천 둔치 마스크의 구멍·돌출을 정리해 하천을 따라 끊기지 않는 배치 부지 띠를 만든다.

원천 마스크는 거친 공개 고도에서 얻은 것이라 둔치가 조각나고 시가지 쪽으로 번진다.
여기서는 일정 폭 이상인 수면에서 잰 거리 띠(구간별 폭)를 기본 부지로 삼고,
수면 가까이 있는 OSM 공원·잔디 다각형(국가정원 등 넓은 둔치)을 더한 뒤 작은 구멍을 메운다.
"""
import numpy as np


class MaskRepair:
    def __init__(self, raster, settings):
        self.raster = raster
        self.settings = settings

    def repair(self, water, source_placeable, osm_layers):
        s = self.settings
        river = self._main_river(self._wide_water(water, float(s.get("min_water_width_m", 16.0))))
        reach = max([float(s.get("band_m", 70.0))] + [float(o["band_m"]) for o in s.get("band_overrides", [])]
                    + [float(s.get("osm_max_water_distance_m", 0.0))])
        distance = self.raster.distance_m(river, reach)
        band_width = np.full(water.shape, float(s.get("band_m", 70.0)), dtype=np.float32)
        longitudes = np.broadcast_to(self.raster.column_longitudes()[None, :], water.shape)
        for override in s.get("band_overrides", []):
            for west, east in override["lon_ranges"]:
                band_width[(longitudes >= west) & (longitudes <= east)] = float(override["band_m"])
        placeable = distance <= band_width
        classes = s.get("osm_classes", [])
        if classes:
            osm = np.zeros(water.shape, dtype=bool)
            for name in classes:
                osm |= osm_layers[name]
            near = osm & (distance <= float(s.get("osm_max_water_distance_m", 0.0)))
            # 띠와 맞닿은 공원만 둔치로 본다(떨어진 도심 공원 제외).
            placeable |= self.raster.reconstruct(placeable, placeable | near)
        if s.get("keep_source", False):
            placeable |= source_placeable & (distance <= reach)
        placeable = self._close(placeable, float(s.get("close_m", 20.0)))
        placeable &= ~water
        stats = {"source_area_m2": round(float(source_placeable.sum()) * self.raster.cell_m ** 2, 1),
                 "repaired_area_m2": round(float(placeable.sum()) * self.raster.cell_m ** 2, 1)}
        return placeable, stats

    def _main_river(self, water):
        """설정한 지도 가장자리(기본 서쪽, 태화강 상류 유입부)에서 이어지는 수면만 남긴다.
        고립된 연못·저수지와 다른 수계(항만 등)는 제외한다."""
        border = np.zeros_like(water)
        edges = {"west": (slice(None), 0), "east": (slice(None), -1), "north": (0, slice(None)), "south": (-1, slice(None))}
        for edge in self.settings.get("river_seed_edges", ["west"]):
            border[edges[edge]] = True
        return self.raster.reconstruct(border & water, water)

    def _wide_water(self, water, min_width_m):
        steps = int(round(min_width_m / 2.0 / self.raster.cell_m))
        if steps <= 0:
            return water
        core = ~self.raster.dilate(~water, steps)
        return self.raster.dilate(core, steps) & water

    def _close(self, mask, close_m):
        steps = int(round(close_m / self.raster.cell_m))
        if steps <= 0:
            return mask
        return ~self.raster.dilate(~self.raster.dilate(mask, steps), steps)
