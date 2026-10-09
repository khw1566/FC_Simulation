"""정형된 높이맵·수면·둔치 마스크를 Godot 지도 폴더로 내보내고 지도 목록과 매니페스트를 갱신한다."""
import hashlib
import json
import time
from pathlib import Path

import numpy as np
from PIL import Image


class TerrainExporter:
    def __init__(self, root, config):
        self.root = Path(root)
        self.config = config
        self.map_id = config["region_name"]
        self.folder = self.root / "godot_project/assets/maps" / self.map_id
        self.res = f"res://assets/maps/{self.map_id}"

    @staticmethod
    def _write_png(array, path, mode):
        temporary = path.with_name(path.stem + ".partial.png")
        Image.fromarray(array, mode=mode).save(temporary)
        temporary.replace(path)

    @staticmethod
    def _sha256(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def _write_json(self, path, data):
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(path)

    def export(self, heights, water, placeable, source_meta, shape_stats, pads, satellite=None, extra_meta=None):
        self.folder.mkdir(parents=True, exist_ok=True)
        low = float(self.config["elevation_range"]["min_meters"])
        high = float(self.config["elevation_range"]["max_meters"])
        normalized = (np.clip(heights, low, high) - low) / (high - low)
        files = {
            "heightmap": (self.folder / "dunchi_heightmap_16bit.png", (normalized * 65535.0).round().astype(np.uint16), "I;16"),
            "watermask": (self.folder / "dunchi_watermask_8bit.png", np.where(water, 255, 0).astype(np.uint8), "L"),
            "placement_mask": (self.folder / "dunchi_placement_mask_8bit.png", np.where(placeable, 255, 0).astype(np.uint8), "L"),
        }
        for path, array, mode in files.values():
            self._write_png(array, path, mode)
        if satellite is not None:
            path = self.folder / "dunchi_satellite.jpg"
            temporary = path.with_name("dunchi_satellite.partial.jpg")
            Image.fromarray(satellite, mode="RGB").save(temporary, quality=88)
            temporary.replace(path)
            files["satellite"] = (path, None, "JPEG")
        self.extra_meta = extra_meta or {}
        self._write_meta()
        self._write_manifest(files, heights, source_meta, shape_stats, pads)
        self._register()
        return {name: str(path.relative_to(self.root).as_posix()) for name, (path, _, _) in files.items()}

    def _write_meta(self):
        c = self.config
        meta = {
            "id": self.map_id,
            "name_ko": c["name_ko"],
            "name_en": c["name_en"],
            "description_ko": c["description_ko"],
            "description_en": c["description_en"],
            "preview_image": "",
            "world_size_meters": c["world_size_meters"],
            "min_elevation": c["elevation_range"]["min_meters"],
            "max_elevation": c["elevation_range"]["max_meters"],
            "sea_level": -999.0,
            "spawn_position": c["spawn_position"],
            "bbox": c["bbox"],
            "coastal_heightmap_corrected": True,
            "assets": {
                "heightmap": f"{self.res}/dunchi_heightmap_16bit.png",
                "watermask": f"{self.res}/dunchi_watermask_8bit.png",
                "placement_mask": f"{self.res}/dunchi_placement_mask_8bit.png",
                "riverside_placements": f"{self.res}/placements.json",
                "satellite_reference": f"{self.res}/dunchi_satellite.jpg",
            },
            "category": "korea",
        }
        self._write_json(self.folder / "map_meta.json", meta)

    def _write_manifest(self, files, heights, source_meta, shape_stats, pads):
        c = self.config
        assets = {}
        for name, (path, _, mode) in files.items():
            entry = {"file_path": f"{self.res}/{path.name}", "format": {"I;16": "PNG16", "L": "PNG8"}.get(mode, mode),
                     "sha256": self._sha256(path), "size_bytes": path.stat().st_size,
                     "bbox": c["bbox"], "resolution": [c["resolution"]["target_width"], c["resolution"]["target_height"]]}
            if name == "heightmap":
                entry.update({"elevation_min": round(float(heights.min()), 3), "elevation_max": round(float(heights.max()), 3),
                              "encoding_range_m": [c["elevation_range"]["min_meters"], c["elevation_range"]["max_meters"]]})
            assets[name] = entry
        manifest = {
            "last_updated": time.strftime("%Y-%m-%d %H:%M:%S"),
            "region": self.map_id,
            "bbox": c["bbox"],
            "pixel_spacing_m": round(c["world_size_meters"] / (c["resolution"]["target_width"] - 1), 4),
            "height_source": source_meta,
            "riverbank_shaping": shape_stats,
            "water_level_basis": c["water"]["water_level_profile_basis"],
            "placement_pads": pads,
            "surveyed": False,
            **self.extra_meta,
            "assets": assets,
        }
        self._write_json(self.folder / "manifest.json", manifest)

    def _register(self):
        registry_path = self.root / "godot_project/assets/maps/maps_registry.json"
        registry = json.loads(registry_path.read_text(encoding="utf-8-sig"))
        if any(m.get("id") == self.map_id for m in registry.get("maps", [])):
            return
        registry["maps"].append({"id": self.map_id, "folder": self.map_id, "meta_file": f"{self.res}/map_meta.json"})
        self._write_json(registry_path, registry)
