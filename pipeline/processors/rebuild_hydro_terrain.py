"""수계 분리 래스터 및 해안 기준 지형 후보정. 원본 자산은 보존한다."""
import hashlib
import json
from pathlib import Path
import cv2
import numpy as np
from PIL import Image
from hydro_geometry import HydroGeometry
from build_tactical_atlas import TacticalAtlasBuilder


class HydroTerrainBuilder:
    ROOT = Path(__file__).resolve().parents[2]

    @staticmethod
    def read(path):
        return json.loads(path.read_text(encoding="utf-8-sig"))

    @staticmethod
    def write(path, data):
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    def build(self, map_id, groups):
        folder = self.ROOT / "godot_project/assets/maps" / map_id
        meta = self.read(folder / "map_meta.json")
        config = self.read(self.ROOT / "config" / f"{map_id}.json")
        n = config["resolution"]["target_width"]
        b = meta["bbox"]
        pad = 160
        shape = (n + pad * 2, n + pad * 2)
        meters = meta["world_size_meters"] / (n - 1)
        def points(coords):
            return np.rint([[(p[0]-b['west'])/(b['east']-b['west'])*(n-1)+pad, (b['north']-p[1])/(b['north']-b['south'])*(n-1)+pad] for p in coords]).astype(np.int32)
        output = folder / "hydro"
        output.mkdir(exist_ok=True)
        coast = np.zeros(shape, np.uint8)
        for f in groups["coastline"]:
            for line in f["geometry"]["coordinates"]:
                cv2.polylines(coast, [points(line)], False, 255, 1)
        # 동쪽 경계는 동해 해상이다. 연결된 바다만 채우므로 섬은 육지로 보존된다.
        sea = (coast == 0).astype(np.uint8)
        cv2.floodFill(sea, None, (shape[1]-1, shape[0]//2), 2)
        sea = (sea == 2).astype(np.uint8) * 255
        if sea[pad+n//2, pad] or not sea[pad+n//2, pad+n-1]:
            raise ValueError("해안선 연결 누락: 동해/서쪽 육지 분리에 실패하여 적용 중단")
        masks = {"sea": sea, "coastline": coast}
        for kind in ("river", "lake"):
            mask = np.zeros(shape, np.uint8)
            for feature in groups[kind]:
                geom, props = feature["geometry"], feature["properties"]
                if geom["type"] == "MultiPolygon":
                    local = np.zeros(shape, np.uint8)
                    for poly in geom["coordinates"]:
                        cv2.fillPoly(local, [points(poly[0])], 255)
                    for ring in props["inner_rings"]:
                        cv2.fillPoly(local, [points(ring)], 0)
                    np.maximum(mask, local, out=mask)
                else:
                    tags = props["tags"]
                    try:
                        width = float(str(tags.get("width", "")).replace(" m", ""))
                    except ValueError:
                        width = 25 if tags.get("waterway") == "river" else 6
                    for line in geom["coordinates"]:
                        cv2.polylines(mask, [points(line)], False, 255, max(1, round(min(width, 500)/meters)))
            masks[kind] = mask
        for kind, features in groups.items():
            self.write(output / f"{kind}.geojson", {"type": "FeatureCollection", "attribution": "OpenStreetMap contributors, ODbL", "features": features})
        crop = np.s_[pad:pad+n, pad:pad+n]
        sea_distance = cv2.distanceTransform((sea > 0).astype(np.uint8), cv2.DIST_L2, 5)[crop] * meters
        land_distance = cv2.distanceTransform(((sea == 0) & (coast == 0)).astype(np.uint8), cv2.DIST_L2, 5)[crop] * meters
        masks = {key: value[crop].copy() for key, value in masks.items()}
        for kind in ("river", "lake"):
            masks[kind][masks["sea"] > 0] = 0
        combined = np.maximum.reduce([masks[k] for k in ("sea", "river", "lake")])
        masks["water"] = combined
        for kind, mask in masks.items():
            Image.fromarray(mask).save(output / f"{kind}_mask.png")
        original = meta.get("hydro_source_heightmap", meta["assets"]["heightmap"])
        source_path = self.ROOT / "godot_project" / original.removeprefix("res://")
        heights = np.asarray(Image.open(source_path), dtype=np.float32) / 65535
        low, high = meta["min_elevation"], meta["max_elevation"]
        heights = low + heights * (high-low)
        original_heights = heights.copy()
        ocean = masks["sea"] > 0
        # 0m 경계에서 육지 DEM으로 150m 폭의 매끄러운 연결.
        t = np.clip(land_distance / 150, 0, 1)
        heights[~ocean] *= (t*t*(3-2*t))[~ocean]
        heights[ocean] = -np.minimum(20, sea_distance[ocean] * 0.08)
        heights[masks["coastline"] > 0] = 0
        encoded = np.rint(np.clip((heights-low)/(high-low), 0, 1)*65535).astype(np.uint16)
        Image.fromarray(encoded).save(output / "coastal_heightmap_16bit.png")
        delta = heights-original_heights
        stats = {"resolution": n, "meters_per_pixel": meters, "sea_pixels": int(ocean.sum()), "max_raise_m": float(delta.max()), "max_lower_m": float(delta.min()), "land_blend_m": 150, "coast_target_m": 0, "features": {k: len(v) for k,v in groups.items()}, "river_width_note": "OSM width 없는 중심선은 river 25m, stream/canal 6m 추정", "marine_depth_note": "해저 -20m까지 시각화용 경사, 실측 수심 아님"}
        self.write(output / "processing_report.json", stats)
        prefix = f"res://assets/maps/{map_id}/hydro/"
        meta["hydro_source_heightmap"] = original
        meta["coastal_heightmap_corrected"] = True
        meta["assets"].update(heightmap=prefix+"coastal_heightmap_16bit.png", watermask=prefix+"water_mask.png", sea_mask=prefix+"sea_mask.png", river_mask=prefix+"river_mask.png", lake_mask=prefix+"lake_mask.png")
        self.write(folder / "map_meta.json", meta)
        for manifest_path in (folder/"manifest.json", self.ROOT/"godot_project/assets/generated/manifest.json"):
            manifest = self.read(manifest_path)
            for path in output.iterdir():
                entry = {"file_path": prefix+path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "size_bytes": path.stat().st_size, "bbox": b, "resolution": {"width": n, "height": n} if path.suffix == ".png" else {"type": "vector_or_report"}, "elevation": {"min_meters": low, "max_meters": high}}
                manifest["assets"][f"{map_id}/hydro/{path.name}"] = entry
            self.write(manifest_path, manifest)
        print(map_id, stats, flush=True)


if __name__ == "__main__":
    builder = HydroTerrainBuilder()
    raw = builder.read(builder.ROOT / "data/raw/ulsan_metro_80km/hydro_refresh/water_raw.json")
    groups = HydroGeometry().classify(raw)
    for map_id in ("ulsan_metro_80km"):
        builder.build(map_id, groups)
        TacticalAtlasBuilder().build(map_id)

