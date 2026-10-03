import os
import sys

sys.path.insert(0, os.path.abspath('pipeline'))
from processors.watermask_processor import WatermaskProcessor
from processors.heightmap_processor import HeightmapProcessor
from processors.ulsan_vector_map_generator import UlsanVectorMapGenerator

cfg_path = os.path.abspath('config/ulsan_uc_west.json')
raw_water_json = os.path.abspath('data/raw/ulsan_uc_west/waterways/ulsan_water.json')
dem_tif = os.path.abspath('data/raw/ulsan_uc_west/dem/ulsan_uc_west_COP30.tif')
bldg_json = os.path.abspath('godot_project/assets/maps/ulsan_uc_west/buildings_and_roads.json')
vworld_json = os.path.abspath('data/raw/ulsan_uc_west/buildings/vworld_full_region_buildings.json')

wm_out = os.path.abspath('godot_project/assets/maps/ulsan_uc_west/ulsan_watermask_8bit.png')
hm_out = os.path.abspath('godot_project/assets/maps/ulsan_uc_west/ulsan_heightmap_16bit.png')
svg_out = os.path.abspath('godot_project/assets/maps/ulsan_uc_west/building_footprints.svg')
tac_out = os.path.abspath('godot_project/assets/maps/ulsan_uc_west/ulsan_vector_tactical_map.png')

print("1. Generating Taehwa River Watermask...")
wm_proc = WatermaskProcessor(cfg_path)
wm_proc.generate_water_mask(raw_water_json, wm_out)

print("2. Generating Heightmap with Riverbed Flattening & Carving...")
hm_proc = HeightmapProcessor(cfg_path)
hm_proc.process_dem_to_16bit(
    dem_tiff_path=dem_tif,
    output_png_path=hm_out,
    infra_json_path=None,
    buildings_json_path=bldg_json,
    coastlines_json_path=None,
    watermask_png_path=wm_out
)

print("3. Updating Tactical Map & SVG with Taehwa River overlay...")
vm_gen = UlsanVectorMapGenerator(cfg_path)
vm_gen.generate_building_svg_and_tactical_map(
    vworld_raw_json=vworld_json,
    dem_tiff_path=dem_tif,
    watermask_png_path=wm_out,
    out_svg_path=svg_out,
    out_tactical_png_path=tac_out
)

print("ALL PIPELINE STEPS COMPLETED SUCCESSFULLY!")
