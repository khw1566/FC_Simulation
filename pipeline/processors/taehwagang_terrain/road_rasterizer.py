"""도로 중심선을 폭을 가진 마스크로 래스터화하고, 본류와 나란한 강변도로를 골라낸다.

교량·터널 구간은 지형 정형에서 제외한다. 자동 선택 결과는 설정의 포함/제외 OSM id와
수동 선형으로 보정한다(위성 영상 겹침 확인 후).
"""
import cv2
import numpy as np


class RoadRasterizer:
    DEFAULT_WIDTH_M = {"motorway": 22.0, "trunk": 20.0, "primary": 18.0, "secondary": 14.0, "tertiary": 10.0,
                       "unclassified": 7.0, "residential": 6.0, "service": 4.0, "pedestrian": 4.0,
                       "cycleway": 3.0, "footway": 2.5, "path": 2.0}

    def __init__(self, grid, settings):
        self.grid = grid
        self.settings = settings

    def _width(self, tags):
        try:
            return float(str(tags.get("width", "")).replace("m", "").strip())
        except ValueError:
            pass
        if str(tags.get("lanes", "")).isdigit():
            return int(tags["lanes"]) * 3.3 + 2.0
        return self.DEFAULT_WIDTH_M.get(tags.get("highway", "").replace("_link", ""), 5.0)

    def _pixels(self, coordinates):
        x, y = self.grid.lonlat_to_pixel([c[0] for c in coordinates], [c[1] for c in coordinates])
        return np.stack([x, y], axis=1)

    @staticmethod
    def _densify(points, step=4.0):
        out = [points[0]]
        for a, b in zip(points[:-1], points[1:]):
            count = max(1, int(np.hypot(*(b - a)) / step))
            out.extend(a + (b - a) * t for t in np.linspace(1.0 / count, 1.0, count))
        return np.array(out)

    def _river_share(self, points, distance_to_river):
        dense = self._densify(points)
        h, w = distance_to_river.shape
        xs = np.clip(np.round(dense[:, 0]).astype(int), 0, w - 1)
        ys = np.clip(np.round(dense[:, 1]).astype(int), 0, h - 1)
        inside = (dense[:, 0] >= 0) & (dense[:, 0] < w) & (dense[:, 1] >= 0) & (dense[:, 1] < h)
        near = (distance_to_river[ys, xs] <= self.settings["max_distance_to_river_m"]) & inside
        return float(near.mean()) if len(near) else 0.0

    def rasterize(self, data, distance_to_river):
        s = self.settings
        size = (self.grid.height, self.grid.width)
        all_roads = np.zeros(size, np.uint8)
        riverside = np.zeros(size, np.uint8)
        include = set(s.get("include_osm_ids", []))
        exclude = set(s.get("exclude_osm_ids", []))
        classes = set(s["riverside_highway_classes"])
        selected = []
        for element in data.get("elements", []):
            tags = element.get("tags", {})
            if element.get("type") != "way" or tags.get("bridge") not in (None, "no") or tags.get("tunnel") not in (None, "no"):
                continue
            coordinates = [(p["lon"], p["lat"]) for p in element.get("geometry", []) if "lon" in p]
            if len(coordinates) < 2:
                continue
            points = self._pixels(coordinates)
            thickness = max(1, int(round(self._width(tags) / self.grid.pixel_m)))
            polyline = [np.round(points).astype(np.int32)]
            cv2.polylines(all_roads, polyline, False, 255, thickness)
            length_m = float(np.hypot(*np.diff(points, axis=0).T).sum() * self.grid.pixel_m)
            auto = (tags.get("highway", "").replace("_link", "") in classes and length_m >= s["min_length_m"]
                    and self._river_share(points, distance_to_river) >= s["min_river_share"])
            if element["id"] in include or (auto and element["id"] not in exclude):
                cv2.polylines(riverside, polyline, False, 255, thickness)
                selected.append({"osm_id": element["id"], "name": tags.get("name"), "highway": tags.get("highway"),
                                 "length_m": round(length_m, 1), "manual": element["id"] in include})
        for line in s.get("manual_lines", []):
            points = self._pixels(line["lonlat"])
            thickness = max(1, int(round(float(line.get("width_m", 12.0)) / self.grid.pixel_m)))
            cv2.polylines(riverside, [np.round(points).astype(np.int32)], False, 255, thickness)
            cv2.polylines(all_roads, [np.round(points).astype(np.int32)], False, 255, thickness)
            selected.append({"manual_line": line.get("id"), "name": line.get("name_ko")})
        return all_roads > 0, riverside > 0, selected
