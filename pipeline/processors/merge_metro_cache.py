import os
import sys
import json
import glob

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from pipeline.processors.vworld_building_processor import VWorldBuildingProcessor

def merge_and_export_metro_buildings():
    map_id = "ulsan_metro_60km"
    cache_dir = f"godot_project/assets/maps/{map_id}/buildings_cache"
    output_merged_geojson = os.path.join(cache_dir, "metro_all_merged_features.geojson")
    output_godot_json = f"godot_project/assets/maps/{map_id}/buildings_and_roads.json"
    config_path = f"config/{map_id}.json"
    with open(f"godot_project/assets/maps/{map_id}/map_meta.json", encoding="utf-8") as meta_file:
        assets = json.load(meta_file)["assets"]
    dem_tiff = assets["heightmap"].replace("res://", "godot_project/")
    watermask_png = assets["watermask"].replace("res://", "godot_project/")

    cell_files = glob.glob(os.path.join(cache_dir, "phase*.json"))
    print(f"[Merge] Found {len(cell_files)} cell files to merge.")

    all_features = []
    seen_sns = set()

    for fpath in cell_files:
        try:
            with open(fpath, "r", encoding="utf-8") as f:
                cdata = json.load(f)
                feats = cdata.get("features", [])
                for feat in feats:
                    sn = feat.get("properties", {}).get("bd_mgt_sn", "")
                    if sn and sn in seen_sns:
                        continue
                    if sn:
                        seen_sns.add(sn)
                    all_features.append(feat)
        except Exception as e:
            print(f"[Merge] Error reading {fpath}: {e}")

    print(f"[Merge] Total unique features merged: {len(all_features)}")

    with open(output_merged_geojson, "w", encoding="utf-8") as f:
        json.dump({
            "type": "FeatureCollection",
            "features": all_features
        }, f, ensure_ascii=False)

    print(f"[Merge] Saved temporary GeoJSON to {output_merged_geojson}. Running VWorldBuildingProcessor...")

    processor = VWorldBuildingProcessor(config_path)
    processor.process_vworld_buildings(
        vworld_geojson_path=output_merged_geojson,
        dem_tiff_path=dem_tiff,
        output_json_path=output_godot_json,
        watermask_png_path=watermask_png
    )
    print(f"[Merge] Completed export to {output_godot_json}!")

if __name__ == "__main__":
    merge_and_export_metro_buildings()
