import json
import os


class UlsanAdminBoundaryProcessor:
    SOURCE = "통계청 SGIS·행정안전부, mapcn-kr (2026-07)"

    def __init__(self, config_path="config/ulsan_metro_60km.json"):
        with open(config_path, "r", encoding="utf-8") as source:
            self.config = json.load(source)
        self.bbox = self.config["bbox"]
        self.world_size = float(self.config["world_size_meters"])

    def _world_point(self, lon, lat):
        x = ((lon - self.bbox["west"]) / (self.bbox["east"] - self.bbox["west"]) - 0.5) * self.world_size
        z = ((self.bbox["north"] - lat) / (self.bbox["north"] - self.bbox["south"]) - 0.5) * self.world_size
        return [round(x, 1), round(z, 1)]

    def _intersects_map(self, ring):
        if not ring:
            return False
        lons = [point[0] for point in ring]
        lats = [point[1] for point in ring]
        if (
            max(lons) < self.bbox["west"] or min(lons) > self.bbox["east"]
            or max(lats) < self.bbox["south"] or min(lats) > self.bbox["north"]
        ):
            return False
        # 경계의 바운딩 박스만 겹치는 인접 시도는 제외한다.
        clipped = ring
        for axis, limit, direction in ((0, self.bbox["west"], 1),
                                       (0, self.bbox["east"], -1),
                                       (1, self.bbox["south"], 1),
                                       (1, self.bbox["north"], -1)):
            if not clipped:
                return False
            output = []
            previous = clipped[-1]
            for current in clipped:
                previous_inside = (previous[axis] - limit) * direction >= 0
                current_inside = (current[axis] - limit) * direction >= 0
                if previous_inside != current_inside:
                    ratio = (limit - previous[axis]) / (current[axis] - previous[axis])
                    output.append([previous[i] + ratio * (current[i] - previous[i]) for i in (0, 1)])
                if current_inside:
                    output.append(current)
                previous = current
            clipped = output
        return len(clipped) >= 3

    @staticmethod
    def _simplify_ring(points, tolerance=35.0):
        if len(points) <= 4:
            return points
        closed = points + [points[0]]
        keep = {0, len(closed) - 1}
        pending = [(0, len(closed) - 1)]
        while pending:
            first, last = pending.pop()
            start, end = closed[first], closed[last]
            dx, dy = end[0] - start[0], end[1] - start[1]
            divisor = dx * dx + dy * dy
            max_distance, split = 0.0, first
            for index in range(first + 1, last):
                point = closed[index]
                ratio = 0.0 if divisor == 0 else max(0.0, min(1.0, ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / divisor))
                distance = ((point[0] - start[0] - ratio * dx) ** 2 + (point[1] - start[1] - ratio * dy) ** 2) ** 0.5
                if distance > max_distance:
                    max_distance, split = distance, index
            if max_distance > tolerance:
                keep.add(split)
                pending.extend(((first, split), (split, last)))
        simplified = [point for index, point in enumerate(closed[:-1]) if index in keep]
        return simplified if len(simplified) >= 3 else points[:3]

    @staticmethod
    def _polygon_components(geometry):
        if not geometry:
            return []
        if geometry.get("type") == "Polygon":
            return geometry.get("coordinates", [])[:1]
        if geometry.get("type") == "MultiPolygon":
            return [polygon[0] for polygon in geometry.get("coordinates", []) if polygon]
        return []

    def _records_from_dataset(self, filename, level, name_field, english_field, code_field):
        with open(filename, "r", encoding="utf-8") as source:
            collection = json.load(source)
        records = []
        for feature in collection.get("features", []):
            properties = feature.get("properties", {})
            name = properties.get(name_field)
            if not name:
                continue
            for component_index, ring in enumerate(self._polygon_components(feature.get("geometry"))):
                if not self._intersects_map(ring):
                    continue
                polygon = self._simplify_ring([self._world_point(lon, lat) for lon, lat in ring[:-1]])
                if len(polygon) < 3:
                    continue
                is_ri = str(name).endswith("리")
                actual_level = 10 if level == 8 and is_ri else level
                records.append({
                    "id": f"admin_{actual_level}_{properties.get(code_field, name)}_{component_index}",
                    "name_ko": name,
                    "name_en": properties.get(english_field, name),
                    "admin_name": name,
                    "admin_level": actual_level,
                    "boundary_id": str(properties.get(code_field, name)),
                    "polygon": polygon,
                    "landmarks": [],
                    "source": self.SOURCE,
                    "license": "CC BY 4.0",
                })
        return records

    @staticmethod
    def _contains(point, polygon):
        x, y = point
        inside = False
        previous = polygon[-1]
        for current in polygon:
            if (current[1] > y) != (previous[1] > y):
                crossing = (previous[0] - current[0]) * (y - current[1]) / (previous[1] - current[1]) + current[0]
                if x < crossing:
                    inside = not inside
            previous = current
        return inside

    def _retain_landmarks(self, records, legacy_path):
        if not os.path.exists(legacy_path):
            return
        with open(legacy_path, "r", encoding="utf-8") as source:
            legacy = json.load(source)
        for old_region in legacy:
            center = old_region.get("center", [])
            if len(center) < 2:
                continue
            matches = [record for record in records if self._contains(center, record["polygon"])]
            if matches:
                deepest = max(matches, key=lambda record: record["admin_level"])
                deepest["landmarks"] = list(dict.fromkeys(deepest["landmarks"] + old_region.get("landmarks", [])))

    def process(self, input_dir, output_path, legacy_path=None):
        records = []
        records.extend(self._records_from_dataset(os.path.join(input_dir, "ulsan_sido_20260701.geojson"), 4, "sidonm", "sidonm", "sido"))
        records.extend(self._records_from_dataset(os.path.join(input_dir, "ulsan_sgg_20260701.geojson"), 6, "sggnm", "sggnm", "sgg"))
        records.extend(self._records_from_dataset(os.path.join(input_dir, "ulsan_emd_20260701.geojson"), 8, "dong", "dong", "adm_cd2"))
        for sido_code in ("26", "31", "47", "48"):
            records.extend(self._records_from_dataset(os.path.join(input_dir, f"ulsan_ri_{sido_code}_20260701.geojson"), 10, "li_nm", "li_nm", "li_cd"))
        if legacy_path:
            self._retain_landmarks(records, legacy_path)
        records.sort(key=lambda item: (item["admin_level"], item["name_ko"], item["id"]))
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as target:
            json.dump(records, target, ensure_ascii=False, indent=2)
        print(f"[UlsanAdminBoundaryProcessor] Exported {len(records)} administrative polygons to {output_path}")
        return output_path


if __name__ == "__main__":
    UlsanAdminBoundaryProcessor().process(
        "data/raw/ulsan_metro_60km/boundaries",
        "godot_project/assets/maps/ulsan_metro_60km/real_districts.json",
        "godot_project/assets/maps/ulsan_metro_60km/real_districts.json",
    )
