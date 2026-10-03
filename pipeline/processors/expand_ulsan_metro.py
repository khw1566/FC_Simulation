"""보관 지형을 합성하고 80km 행정경계·매니페스트를 생성한다."""
import hashlib
import json
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

from ulsan_admin_boundary_processor import UlsanAdminBoundaryProcessor


class UlsanMetroExpansion:
    ROOT = Path(__file__).resolve().parents[2]
    MAP_ID = "ulsan_metro_80km"
    RESOLUTION = 5632

    def __init__(self):
        self.maps = self.ROOT / "godot_project/assets/maps"
        self.output = self.maps / self.MAP_ID
        self.output.mkdir(exist_ok=True)
        self.core = self.read(self.maps / "ulsan_metro_60km/map_meta.json")
        self.outer = self.read(self.maps / "southeast_mega_140km/map_meta.json")
        old = self.core["bbox"]
        self.bbox = {}
        for low, high in (("south", "north"), ("west", "east")):
            center = (old[low] + old[high]) / 2
            half = (old[high] - old[low]) * 2 / 3
            self.bbox.update({low: center - half, high: center + half})

    @staticmethod
    def read(path):
        return json.loads(Path(path).read_text(encoding="utf-8-sig"))

    @staticmethod
    def write(path, payload):
        Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    def image(self, meta, asset):
        path = self.ROOT / "godot_project" / meta["assets"][asset].removeprefix("res://")
        values = np.asarray(Image.open(path), dtype=np.float32)
        if asset == "heightmap":
            values = values / 65535 * (meta["max_elevation"] - meta["min_elevation"]) + meta["min_elevation"]
        return values

    @staticmethod
    def sample(values, bbox, lon, lat):
        x = np.clip((lon - bbox["west"]) / (bbox["east"] - bbox["west"]) * (values.shape[1] - 1), 0, values.shape[1] - 1)
        y = np.clip((bbox["north"] - lat) / (bbox["north"] - bbox["south"]) * (values.shape[0] - 1), 0, values.shape[0] - 1)
        ix, iy = x.astype(np.int32), y.astype(np.int32)
        jx, jy = np.minimum(ix + 1, values.shape[1] - 1), np.minimum(iy + 1, values.shape[0] - 1)
        dx, dy = x - ix, y - iy
        return ((values[iy, ix] * (1 - dx) + values[iy, jx] * dx) * (1 - dy)
                + (values[jy, ix] * (1 - dx) + values[jy, jx] * dx) * dy)

    def build_raster(self, asset):
        core, outer = self.image(self.core, asset), self.image(self.outer, asset)
        n = self.RESOLUTION
        result = np.empty((n, n), dtype=np.float32)
        lon = np.linspace(self.bbox["west"], self.bbox["east"], n)[None, :]
        latitudes = np.linspace(self.bbox["north"], self.bbox["south"], n)
        # 기존 60km 영역 내부는 그대로 유지하고 외부 1km에서만 접합한다.
        world_x = np.linspace(-40000, 40000, n)[None, :]
        for start in range(0, n, 128):
            lat = latitudes[start:start + 128, None]
            world_z = np.linspace(-40000, 40000, n)[start:start + 128, None]
            distance = np.maximum(np.abs(world_x), np.abs(world_z)) - 30000
            weight = np.clip(1 - distance / 1000, 0, 1)
            weight = weight * weight * (3 - 2 * weight)
            inner = self.sample(core, self.core["bbox"], lon, lat)
            outside = self.sample(outer, self.outer["bbox"], lon, lat)
            result[start:start + 128] = inner * weight + outside * (1 - weight)
        if asset == "heightmap":
            pixels = np.rint(np.clip((result + 30) / 1330, 0, 1) * 65535).astype(np.uint16)
            suffix = "heightmap_16bit.png"
        else:
            pixels = np.rint(np.clip(result, 0, 255)).astype(np.uint8)
            suffix = "watermask_8bit.png"
        Image.fromarray(pixels).save(self.output / f"{self.MAP_ID}_{suffix}")
        print(f"생성: {asset}, {n} x {n}", flush=True)
        return result

    def run(self):
        config = self.read(self.ROOT / "config/ulsan_metro_60km.json")
        config.update(region_name=self.MAP_ID, display_name="Ulsan Metropolitan 80km", name_ko="울산광역시 광역권 (80km x 80km)", area_km=80, world_size_meters=80000, bbox=self.bbox)
        config["resolution"] = {"target_width": self.RESOLUTION, "target_height": self.RESOLUTION}
        config["elevation_range"] = {"min_meters": -30, "max_meters": 1300}
        config["quota_limits"] = {"daily_vworld_calls": 700, "cell_step_deg": 0.025}
        config["terrain_sources"] = [self.core["id"], self.outer["id"]]
        config_path = self.ROOT / f"config/{self.MAP_ID}.json"
        self.write(config_path, config)
        height = self.build_raster("heightmap")
        water = self.build_raster("watermask")
        shade = np.clip(80 + height / 1300 * 150, 45, 230).astype(np.uint8)
        shade[water > 127] = 38
        Image.fromarray(shade).convert("RGB").resize((640, 640), Image.Resampling.LANCZOS).save(self.output / f"{self.MAP_ID}_tactical_map.png")
        districts_path = self.output / "real_districts.json"
        UlsanAdminBoundaryProcessor(str(config_path)).process(str(self.ROOT / "data/raw/ulsan_metro_60km/boundaries"), str(districts_path))
        districts = self.read(districts_path)
        counts = Counter(str(item["admin_level"]) for item in districts)
        summary = {"map_id": self.MAP_ID, "polygon_counts": dict(counts), "unique_unit_counts": {str(level): len({d["boundary_id"] for d in districts if d["admin_level"] == level}) for level in (4, 6, 8, 10)}, "sido": sorted({d["name_ko"] for d in districts if d["admin_level"] == 4}), "bbox": self.bbox}
        self.write(self.output / "administrative_summary.json", summary)
        meta = self.core.copy()
        meta.update(id=self.MAP_ID, name_ko=config["name_ko"], name_en="Ulsan Metropolitan Wide Area (80km x 80km)", description_ko="기존 울산 60km 자산을 유지하고 사방 10km를 확장한 지형. 외곽은 기존 140km 지형을 사용하며 건물·도로 상세 수집 범위는 기존 60km입니다.", description_en="80km terrain with retained 60km buildings, roads and airport; outer terrain derived from the cached 140km map.", world_size_meters=80000, max_elevation=1300, bbox=self.bbox)
        meta["assets"] = dict(self.core["assets"])
        for asset, suffix in (("heightmap", "heightmap_16bit.png"), ("watermask", "watermask_8bit.png"), ("tactical_map", "tactical_map.png")):
            meta["assets"][asset] = f"res://assets/maps/{self.MAP_ID}/{self.MAP_ID}_{suffix}"
        meta["assets"]["districts"] = f"res://assets/maps/{self.MAP_ID}/real_districts.json"
        meta["preview_image"] = meta["assets"]["tactical_map"]
        meta["coverage"] = {"terrain_km": 80, "administrative_km": 80, "detailed_vectors_source": self.core["id"], "outer_buildings_roads_collected": False, "seam_blend_outside_core_m": 1000}
        self.write(self.output / "map_meta.json", meta)
        registry_path = self.maps / "maps_registry.json"
        registry = self.read(registry_path)
        registry["maps"] = [m for m in registry["maps"] if m["id"] != self.MAP_ID]
        registry["maps"].append({"id": self.MAP_ID, "folder": self.MAP_ID, "meta_file": f"res://assets/maps/{self.MAP_ID}/map_meta.json"})
        self.write(registry_path, registry)
        manifest = {"map_id": self.MAP_ID, "sources": config["terrain_sources"], "assets": {}}
        for path in sorted(self.output.iterdir()):
            if path.suffix not in (".json", ".png") or path.name == "manifest.json":
                continue
            resolution = {"type": "records"}
            if path.suffix == ".png":
                with Image.open(path) as image:
                    resolution = {"width": image.width, "height": image.height}
            manifest["assets"][path.name] = {"file_path": f"res://assets/maps/{self.MAP_ID}/{path.name}", "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "size_bytes": path.stat().st_size, "bbox": self.bbox, "elevation": {"min_meters": -30, "max_meters": 1300}, "resolution": resolution}
        self.write(self.output / "manifest.json", manifest)
        generated_path = self.ROOT / "godot_project/assets/generated/manifest.json"
        generated = self.read(generated_path)
        for name, entry in manifest["assets"].items():
            generated["assets"][f"{self.MAP_ID}/{name}"] = entry
        self.write(generated_path, generated)
        print(json.dumps(summary, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    UlsanMetroExpansion().run()
