"""Overpass 수계 요소를 본류 마스크와 기타 수면 마스크로 래스터화한다."""
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from hydro_geometry import HydroGeometry  # noqa: E402


class WaterRasterizer:
    STREAM_WIDTH_M = 5.0

    def __init__(self, grid, water_settings):
        self.grid = grid
        self.settings = water_settings
        self.geometry = HydroGeometry()
        self.skipped = 0

    def _points(self, ring):
        lon = [p[0] for p in ring]
        lat = [p[1] for p in ring]
        x, y = self.grid.lonlat_to_pixel(lon, lat)
        return np.round(np.stack([x, y], axis=1)).astype(np.int32)

    def _rings(self, element):
        if element["type"] == "relation":
            outer, inner = [], []
            for role, dest in (("outer", outer), ("inner", inner)):
                parts = [self.geometry.coordinates(m.get("geometry", [])) for m in element.get("members", [])
                         if m.get("type") == "way" and m.get("role", "outer") == role]
                dest.extend(self.geometry.rings(parts))
            return outer, inner
        return [self.geometry.coordinates(element.get("geometry", []))], []

    @staticmethod
    def _is_river_area(tags):
        return tags.get("waterway") == "riverbank" or tags.get("water") in ("river", "canal")

    def rasterize(self, data):
        size = (self.grid.height, self.grid.width)
        river = np.zeros(size, np.uint8)
        other = np.zeros(size, np.uint8)
        centerlines = []
        for element in data.get("elements", []):
            tags = element.get("tags", {})
            if element["type"] == "node":
                continue
            waterway = tags.get("waterway")
            if waterway in ("river", "stream", "canal") and element["type"] == "way":
                centerlines.append((waterway, self._points(self.geometry.coordinates(element.get("geometry", [])))))
                continue
            try:
                outer, inner = self._rings(element)
            except ValueError:
                self.skipped += 1
                continue
            target = river if self._is_river_area(tags) else other
            for ring in outer:
                if len(ring) >= 3:
                    cv2.fillPoly(target, [self._points(ring)], 255)
            for ring in inner:
                if len(ring) >= 3:
                    cv2.fillPoly(target, [self._points(ring)], 0)
        has_river_area = river.any()
        for kind, points in centerlines:
            if len(points) < 2:
                continue
            if kind == "river" and not has_river_area:
                width = self.settings["centerline_width_m"]
                cv2.polylines(river, [points], False, 255, max(1, int(width / self.grid.pixel_m)))
            elif kind != "river":
                cv2.polylines(other, [points], False, 255, max(1, int(self.STREAM_WIDTH_M / self.grid.pixel_m)))
        return river > 0, (other > 0) & ~(river > 0)
