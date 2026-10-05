"""상세 지형 경계와 실제 광역 DEM을 함께 색인하는 원경 생성 진입점."""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
from regional_horizon_atlas import RegionalHorizonAtlas
from simple_maps.publish import merge


class HorizonTerrainBuilder:
    ROOT = Path(__file__).resolve().parents[2]

    def run(self):
        root = self.ROOT
        config = json.loads((root / "config/atmosphere_horizon.json").read_text(encoding="utf-8"))
        regional = RegionalHorizonAtlas().build(root, config)
        metas = {p.parent.name: json.loads(p.read_text(encoding="utf-8-sig")) for p in (root / "godot_project/assets/maps").glob("*/map_meta.json")}
        atlases = {}
        for key, meta in metas.items():
            path = root / "godot_project" / meta["assets"]["heightmap"].removeprefix("res://")
            with Image.open(path) as image:
                values = np.asarray(image)
                maximum = 65535.0 if values.dtype.itemsize > 1 else 255.0
                normalized = Image.fromarray(values.astype(np.float32) / maximum)
                small = np.asarray(normalized.resize((config["atlas_resolution"],)*2, Image.Resampling.BILINEAR))
            height = meta["min_elevation"] + small * (meta["max_elevation"]-meta["min_elevation"])
            atlases[key] = {"bbox":meta["bbox"],"world_size_meters":meta["world_size_meters"],"heights":np.round(height,2).tolist(),"resolution":config["atlas_resolution"],"source_path":meta["assets"]["heightmap"],"elevation_min":float(height.min()),"elevation_max":float(height.max())}
        maps = {}
        for key, meta in metas.items():
            source = {"ulsan_uc_west":"ulsan_metro_80km", "ulsan_metro_80km":"southeast_mega_140km"}.get(key,key)
            maps[key] = {"bbox":meta["bbox"],"world_size_meters":meta["world_size_meters"],"sea_level":meta["sea_level"],"atlas_id":key,"regional_atlas_id":source,"flat":key=="flat_testing","extension_m":config["horizon_extension_m"],"mode":"실제 광역 DEM 및 지구 곡률"}
        path = root / "godot_project/assets/generated/horizon/terrain.json"
        path.parent.mkdir(parents=True,exist_ok=True)
        temporary = path.with_suffix('.tmp')
        temporary.write_text(json.dumps({"version":2,"settings":config,"regional":regional,"atlases":atlases,"maps":maps},ensure_ascii=False,separators=(",",":")),encoding="utf-8")
        temporary.replace(path)
        manifest_path = root / "godot_project/assets/generated/manifest.json"
        extended_bbox = {}
        for key, meta in metas.items():
            bbox = meta["bbox"]
            fraction = config["horizon_extension_m"] / meta["world_size_meters"]
            lon_margin = (bbox["east"]-bbox["west"]) * fraction
            lat_margin = (bbox["north"]-bbox["south"]) * fraction
            extended_bbox[key] = {"west":bbox["west"]-lon_margin,"east":bbox["east"]+lon_margin,"south":bbox["south"]-lat_margin,"north":bbox["north"]+lat_margin}
        entries = {"horizon_terrain": {"file_path":"res://assets/generated/horizon/terrain.json","sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"bbox":extended_bbox,"source_bbox":{key:meta["bbox"] for key,meta in metas.items()},"elevation_min":min(a["elevation_min"] for a in atlases.values()),"elevation_max":max(a["elevation_max"] for a in atlases.values()),"resolution":config["atlas_resolution"],"type":"regional_horizon_atlas","note":config["note"]}}
        for filename in ('regional_height.f32', 'regional_height_rgb.png'):
            asset = path.parent / filename
            entries['horizon/'+filename] = {'file_path':'res://assets/generated/horizon/'+filename,
                'sha256':hashlib.sha256(asset.read_bytes()).hexdigest(), 'bbox':regional['bbox'],
                'elevation_min':regional['elevation_min'], 'elevation_max':regional['elevation_max'],
                'resolution':regional['resolution'], 'projection':'EPSG:3857',
                'type':'regional_elevation_raster', 'attribution':regional['attribution']}
        merge(manifest_path, entries)
        merge(path.parent / 'manifest.json', entries)
        print("HORIZON_ATLASES", len(atlases), "BYTES", path.stat().st_size)


if __name__ == "__main__":
    HorizonTerrainBuilder().run()
