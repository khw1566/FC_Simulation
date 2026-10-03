import os
import json
import hashlib
import time

class AssetIndexer:
    def __init__(self, manifest_path):
        self.manifest_path = manifest_path

    def _compute_hash(self, file_path):
        hasher = hashlib.sha256()
        with open(file_path, "rb") as f:
            while chunk := f.read(65536):
                hasher.update(chunk)
        return hasher.hexdigest()

    def update_manifest(self, region_config, asset_entries):
        manifest_data = {
            "last_updated": time.strftime("%Y-%m-%d %H:%M:%S"),
            "region": region_config.get("region_name"),
            "bbox": region_config.get("bbox"),
            "elevation_calibration": region_config.get("elevation_range"),
            "assets": {}
        }

        if os.path.exists(self.manifest_path):
            try:
                with open(self.manifest_path, "r", encoding="utf-8") as f:
                    existing = json.load(f)
                    manifest_data["assets"] = existing.get("assets", {})
            except Exception:
                pass

        for name, entry in asset_entries.items():
            fpath = entry.get("file_path")
            if os.path.exists(fpath):
                entry["sha256"] = self._compute_hash(fpath)
                entry["size_bytes"] = os.path.getsize(fpath)
            manifest_data["assets"][name] = entry

        os.makedirs(os.path.dirname(self.manifest_path), exist_ok=True)
        with open(self.manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest_data, f, indent=2, ensure_ascii=False)

        print(f"[AssetIndexer] Manifest successfully written: {self.manifest_path}")
        return self.manifest_path

    def index_map_folder(self, map_folder_path):
        meta_path = os.path.join(map_folder_path, "map_meta.json")
        if not os.path.exists(meta_path):
            return None

        with open(meta_path, "r", encoding="utf-8") as f:
            meta = json.load(f)

        manifest_data = {
            "indexed_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "map_id": meta.get("id"),
            "name_ko": meta.get("name_ko"),
            "name_en": meta.get("name_en"),
            "world_size_meters": meta.get("world_size_meters"),
            "min_elevation": meta.get("min_elevation"),
            "max_elevation": meta.get("max_elevation"),
            "sea_level": meta.get("sea_level"),
            "bbox": meta.get("bbox"),
            "assets": {}
        }

        for fname in os.listdir(map_folder_path):
            if fname == "manifest.json":
                continue
            full_p = os.path.join(map_folder_path, fname)
            if os.path.isfile(full_p):
                ext = os.path.splitext(fname)[1].lower()
                category = "metadata"
                if "heightmap" in fname:
                    category = "heightmap"
                elif "watermask" in fname:
                    category = "watermask"
                elif "splatmap" in fname:
                    category = "splatmap"
                elif "tactical_map" in fname or "vector" in fname:
                    category = "tactical_map"
                elif "districts" in fname:
                    category = "districts"
                elif "buildings" in fname or "roads" in fname:
                    category = "buildings_and_roads"
                elif "landmarks" in fname:
                    category = "landmarks"

                manifest_data["assets"][fname] = {
                    "category": category,
                    "file_name": fname,
                    "extension": ext,
                    "size_bytes": os.path.getsize(full_p),
                    "sha256": self._compute_hash(full_p)
                }

        out_manifest_p = os.path.join(map_folder_path, "manifest.json")
        with open(out_manifest_p, "w", encoding="utf-8") as f:
            json.dump(manifest_data, f, indent=2, ensure_ascii=False)

        print(f"[AssetIndexer] Indexed map '{meta.get('id')}' -> {out_manifest_p}")
        return manifest_data
