"""구역 라벨·스플랫·미리보기·배치 JSON을 쓰고 계열 매니페스트와 공통 매니페스트를 갱신한다."""
import hashlib
import json
import os
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SPLAT_A = ["lawn", "silvergrass", "bamboo", "reed"]
SPLAT_B = ["woodland", "meadow"]


class ZoneExporter:
    def __init__(self, root, config, raster):
        self.root = Path(root)
        self.config = config
        self.raster = raster
        self.folder = self.root / "godot_project/assets/generated/taehwagang_ecozones"
        self.res = "res://assets/generated/taehwagang_ecozones"

    @staticmethod
    def _save_png(image, path):
        temporary = path.with_name(path.stem + ".partial.png")
        image.save(temporary)
        os.replace(temporary, path)

    @staticmethod
    def _save_json(data, path, indent=2):
        temporary = path.with_suffix(".ecozones.tmp")
        temporary.write_text(json.dumps(data, ensure_ascii=False, indent=indent) + "\n", encoding="utf-8")
        os.replace(temporary, path)

    def write_rasters(self, labels, placeable):
        self.folder.mkdir(parents=True, exist_ok=True)
        files = {"labels": self.folder / "ecozone_labels_8bit.png"}
        self._save_png(Image.fromarray(labels, "L"), files["labels"])
        ids = {zone["key"]: zone["id"] for zone in self.config["zones"]}
        for name, keys, extra in (("splat_a", SPLAT_A, None), ("splat_b", SPLAT_B, placeable)):
            channels = [self._weight(labels == ids[key]) for key in keys]
            while len(channels) < 3:
                channels.append(np.zeros(labels.shape, np.uint8))
            if extra is not None:
                channels.append(self._weight(extra))
            files[name] = self.folder / f"ecozone_{name}_rgba.png"
            self._save_png(Image.merge("RGBA", [Image.fromarray(c, "L") for c in channels]), files[name])
        return files

    @staticmethod
    def _weight(mask):
        image = Image.fromarray(np.where(mask, 255, 0).astype(np.uint8), "L")
        return np.array(image.filter(ImageFilter.GaussianBlur(1.5)))

    def write_preview(self, labels, water, layers):
        colors = np.full(labels.shape + (3,), 238, dtype=np.uint8)
        colors[water] = (96, 140, 210)
        for zone in self.config["zones"]:
            colors[labels == zone["id"]] = zone["color"]
        image = Image.fromarray(colors, "RGB")
        draw = ImageDraw.Draw(image)
        for layer in layers:
            data = np.asarray(layer["data"], dtype=np.float32).reshape(-1, 5)
            u, v = self.raster.world_to_pixel(data[:, 0], data[:, 2])
            shade = (20, 50, 20) if layer["family"] != "silvergrass" else (230, 220, 190)
            for x, y in zip(u[::3], v[::3]):
                draw.point((float(x), float(y)), fill=shade)
        path = self.folder / "ecozone_preview.png"
        self._save_png(image, path)
        return path

    def write_scatter(self, layers):
        path = self.folder / "scatter_instances.json"
        data = {
            "version": 1,
            "map_id": self.config["target_map_id"],
            "coordinate_system_ko": "원천 지도 월드 미터. 원점은 원천 지도 중앙, +X 동쪽, +Z 남쪽, y는 생성 시 둔치 높이맵 표본. 다른 지도에서는 source_bbox로 위경도를 거쳐 변환한다.",
            "source_bbox": self.raster.bbox,
            "source_world_size_m": self.raster.world_size_m,
            "families": self.config["families"],
            "layers": layers,
        }
        self._save_json(data, path, indent=None)
        return path

    def write_catalog(self, files, stats, layers, provenance, osm_meta):
        assets = {}
        for key, path in files.items():
            entry = {
                "file_path": f"{self.res}/{path.relative_to(self.folder).as_posix()}",
                "format": path.suffix.lstrip(".").upper(),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "size_bytes": path.stat().st_size,
                "type": self._type(key),
                "metadata": {"bbox": None, "resolution": None, "elevation_min": None, "elevation_max": None},
            }
            if key in ("labels", "splat_a", "splat_b", "preview"):
                entry["metadata"].update({"bbox": self.raster.bbox, "resolution": [self.raster.size, self.raster.size], "pixel_spacing_m": round(self.raster.cell_m, 4)})
            if key == "scatter":
                ys = [v for layer in layers for v in layer["data"][1::5]]
                entry["metadata"].update({"bbox": self.raster.bbox, "elevation_min": round(min(ys), 2) if ys else None, "elevation_max": round(max(ys), 2) if ys else None, "instances": sum(layer["count"] for layer in layers)})
            assets[key] = entry
        zones = [{"id": z["id"], "key": z["key"], "name_ko": z["name_ko"], "ground": z["ground"], **stats[z["key"]]} for z in self.config["zones"]]
        catalog = {
            "version": 1,
            "map_id": self.config["target_map_id"],
            "status": "generated_estimate",
            "zone_basis_ko": self.config["zone_basis_ko"],
            "label_encoding_ko": "8bit 픽셀값=구역 ID, 0=비대상(수면·제방 밖·비평탄). 북쪽이 0행.",
            "splat_channels": {"ecozone_splat_a_rgba.png": SPLAT_A, "ecozone_splat_b_rgba.png": SPLAT_B + ["unused", "placeable"]},
            "zones": zones,
            "layers": [{k: layer[k] for k in ("zone", "family", "kind", "lattice", "spacing_m", "count")} for layer in layers],
            "source_masks": provenance,
            "osm_landcover": osm_meta,
            "assets": assets,
        }
        self._save_json(catalog, self.folder / "catalog.json")
        manifest = {"version": 1, "last_updated": time.strftime("%Y-%m-%d %H:%M:%S"), "assets": assets}
        self._save_json(manifest, self.folder / "manifest.json")
        self._merge_master(assets)
        return catalog

    @staticmethod
    def _type(key):
        if key.startswith("ground_"):
            return "ecozone_ground_texture"
        return {"labels": "ecozone_label_mask", "splat_a": "ecozone_splat", "splat_b": "ecozone_splat",
                "preview": "ecozone_preview", "scatter": "ecozone_scatter"}.get(key, "ecozone_asset")

    def _merge_master(self, assets):
        master_path = self.folder.parent / "manifest.json"
        master = json.loads(master_path.read_text(encoding="utf-8"))
        for key, entry in assets.items():
            master.setdefault("assets", {})["taehwagang_ecozones_" + key] = entry
        self._save_json(master, master_path)
