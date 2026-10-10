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

    def write_forest_masses(self, labels, placeable, blocked=None):
        """대숲·활엽수림 구역을 닫힘 연산으로 덩어리화한 셀 목록(라벨 격자 좌표)을 기록한다."""
        ids = {zone["key"]: zone["id"] for zone in self.config["zones"]}
        masses = []
        specs = self.config.get("forest_masses", []) if self.config.get("forest_masses_enabled", True) else []
        for spec in specs:
            mask = labels == ids[spec["zone"]]
            steps = int(round(float(spec.get("close_m", 0.0)) / self.raster.cell_m))
            if steps:
                mask = ~self.raster.dilate(~self.raster.dilate(mask, steps), steps) & placeable
            if blocked is not None:
                mask &= ~blocked
            ramp = float(spec.get("edge_ramp_m", 12.0))
            inside = self.raster.distance_m(~mask, ramp + self.raster.cell_m)
            # 셀 수관 높이 비율(0~255): 가장자리에서 ramp 거리만큼 올라가고, 가우스 흐림으로 윤곽 계단을 지면 쪽에 묻는다.
            t = np.where(mask, np.clip(inside / ramp, 0.0, 1.0), 0.0)
            raw = Image.fromarray(np.round(255 * t * t * (3 - 2 * t)).astype(np.uint8), "L")
            blurred = np.array(raw.filter(ImageFilter.GaussianBlur(float(spec.get("edge_blur_cells", 1.5)))))
            keep = blurred >= 6
            if blocked is not None:
                # 흐림으로 번진 수관 가장자리가 도로·건물·수면 위로 나가지 않게 한다.
                keep &= ~blocked
            rows, cols = np.nonzero(keep)
            level = blurred[rows, cols].astype(int)
            entry = {k: v for k, v in spec.items() if k not in ("close_m", "edge_ramp_m")}
            entry["texture"] = f"{self.res}/ground/{spec['texture']}.png"
            entry["cell_count"] = int(mask.sum())
            entry["area_m2"] = round(float(mask.sum()) * self.raster.cell_m ** 2, 1)
            entry["cells"] = np.stack([cols, rows, level], axis=1).ravel().astype(int).tolist()
            masses.append(entry)
        data = {
            "version": 1,
            "coordinate_system_ko": "cells는 [열, 행, 수관 높이 비율 0~255] 평면 배열(라벨 격자 픽셀, 흐림으로 가장자리가 0에 가깝게 내려간다). 픽셀 중심의 원천 월드 좌표 = (픽셀 / (label_size - 1) - 0.5) * source_world_size_m.",
            "source_bbox": self.raster.bbox,
            "source_world_size_m": self.raster.world_size_m,
            "label_size": self.raster.size,
            "cell_m": round(self.raster.cell_m, 4),
            "masses": masses,
        }
        path = self.folder / "forest_masses.json"
        self._save_json(data, path, indent=None)
        return path

    def write_ground(self):
        """지형 셰이더 바닥 혼합에 쓰는 스플랫·텍스처 경로와 원천 좌표를 기록한다."""
        blend = self.config.get("ground_blend", {})
        data = {
            "version": 1,
            "source_bbox": self.raster.bbox,
            "source_world_size_m": self.raster.world_size_m,
            "splat_a": f"{self.res}/ecozone_splat_a_rgba.png",
            "splat_b": f"{self.res}/ecozone_splat_b_rgba.png",
            "textures": {name: f"{self.res}/ground/{name}.png" for name in ("lawn", "silvergrass_ground", "bamboo_litter", "reed_mud", "woodland_soil", "meadow", "canopy_bamboo", "canopy_broadleaf")},
            "tile_m": blend.get("tile_m", 6.0),
            "fade_distance_m": blend.get("fade_distance_m", 6000.0),
            "flat_near_m": blend.get("flat_near_m", 150.0),
            "flat_far_m": blend.get("flat_far_m", 450.0),
            "silvergrass_field": blend.get("silvergrass_field"),
        }
        path = self.folder / "ground_blend.json"
        self._save_json(data, path)
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
                "preview": "ecozone_preview", "scatter": "ecozone_scatter", "forest_masses": "ecozone_forest_mass",
                "ground_blend": "ecozone_ground_blend"}.get(key, "ecozone_asset")

    def _merge_master(self, assets):
        master_path = self.folder.parent / "manifest.json"
        master = json.loads(master_path.read_text(encoding="utf-8"))
        for key, entry in assets.items():
            master.setdefault("assets", {})["taehwagang_ecozones_" + key] = entry
        self._save_json(master, master_path)
