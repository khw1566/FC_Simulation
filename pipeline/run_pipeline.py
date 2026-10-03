import os
import sys
import json
import shutil

from collectors import DemCollector, OsmCollector
from processors import HeightmapProcessor, WatermaskProcessor
from indexer import AssetIndexer

def run_kanmon_pipeline():
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    config_file = os.path.join(project_root, "config", "kanmon_region.json")
    api_key_file = os.path.join(project_root, "data", "api_keys.json")
    
    raw_dir = os.path.join(project_root, "data", "raw")
    assets_dir = os.path.join(project_root, "godot_project", "assets", "generated")
    manifest_file = os.path.join(assets_dir, "manifest.json")

    print("==================================================")
    print("Kanmon Straits Automated 3D Pipeline Started")
    print("==================================================")

    # 1. DEM 수집
    dem_collector = DemCollector(config_file, api_key_file)
    dem_tiff = dem_collector.fetch_dem(os.path.join(raw_dir, "dem"))

    # 2. OSM 수계 및 해안선 수집
    osm_collector = OsmCollector(config_file)
    osm_json = osm_collector.fetch_waterways(os.path.join(raw_dir, "waterways"))

    # 3. 해안선, 주요 도로, 철도 인프라 수집
    from collectors.infrastructure_collector import InfrastructureCollector
    infra_collector = InfrastructureCollector(config_file)
    infra_raw_json = infra_collector.fetch_roads_railways_coastline(os.path.join(raw_dir, "infrastructure"))

    # 4. 실제 건물 풋프린트 수집
    from collectors.building_collector import BuildingCollector
    bldg_collector = BuildingCollector(config_file)
    bldg_raw_json = bldg_collector.fetch_buildings(os.path.join(raw_dir, "buildings"))

    # 5. 수계 마스크 변환
    water_processor = WatermaskProcessor(config_file)
    watermask_png = os.path.join(assets_dir, "kanmon_watermask_8bit.png")
    water_processor.generate_water_mask(osm_json, watermask_png)

    # 6. 16비트 높이맵 변환 (자연스러운 해안선 스무딩 및 도로/건물 절토 Carving 적용)
    height_processor = HeightmapProcessor(config_file)
    heightmap_png = os.path.join(assets_dir, "kanmon_heightmap_16bit.png")
    _, height_meta = height_processor.process_dem_to_16bit(
        dem_tiff, heightmap_png, 
        infra_json_path=infra_raw_json, 
        buildings_json_path=bldg_raw_json,
        coastlines_json_path=infra_raw_json
    )

    # 7. 실제 세부 행정구역 및 랜드마크 대량 수집 및 폴리곤 추출
    from collectors.detailed_district_collector import DetailedDistrictCollector
    from processors.detailed_district_processor import DetailedDistrictProcessor
    dist_collector = DetailedDistrictCollector(config_file)
    dist_raw_json = dist_collector.fetch_all_subdistricts(os.path.join(raw_dir, "boundaries"))
    dist_processor = DetailedDistrictProcessor(config_file)
    real_districts_json = os.path.join(assets_dir, "real_districts.json")
    dist_processor.process_all_subdistricts(dist_raw_json, real_districts_json)

    # 8. 전술 벡터 지도 렌더링
    landmarks_config = os.path.join(project_root, "config", "key_landmarks.json")
    from processors.vector_map_renderer import VectorMapRenderer
    vector_renderer = VectorMapRenderer(config_file)
    vector_map_png = os.path.join(assets_dir, "kanmon_vector_tactical_map.png")
    vector_renderer.render_tactical_vector_map(infra_raw_json, dem_tiff, landmarks_config, vector_map_png)

    # 9. 대규모 타일 분할 (Tiling Partitioning for Godot Streaming)
    from processors import TerrainTileProcessor
    tile_processor = TerrainTileProcessor(config_file)
    tiles_output_dir = os.path.join(assets_dir, "tiles")
    tiles_meta_file = tile_processor.slice_dem_to_tiles(dem_tiff, tiles_output_dir, tiles_x=4, tiles_y=4, tile_res=1024)

    # 10. 3D 박스 건물 및 도로 리본 추출 (수계 마스크 검사 및 침수 건물 배제)
    from processors import BuildingRoadProcessor
    bldg_processor = BuildingRoadProcessor(config_file)
    buildings_roads_json = os.path.join(assets_dir, "buildings_and_roads.json")
    bldg_processor.process_buildings_and_roads(
        bldg_raw_json, infra_raw_json, dem_tiff, landmarks_config, buildings_roads_json,
        watermask_png_path=watermask_png
    )

    with open(config_file, "r", encoding="utf-8") as f:
        config_data = json.load(f)

    # 10-1. 도로 세분화 분류 벡터 SVG 및 인덱스 추출
    from processors import RoadSvgProcessor
    sat_rgb_path = os.path.join(raw_dir, "satellite", f"{config_data.get('region_name', 'kanmon_straits')}_satellite_rgb.png")
    road_svg_processor = RoadSvgProcessor(config_file)
    road_svg_path = os.path.join(assets_dir, "road_vectors.svg")
    road_index_path = os.path.join(assets_dir, "road_vectors_index.json")
    road_svg_processor.generate_road_vector_svg(
        infra_raw_json, sat_rgb_path, dem_tiff, road_svg_path, road_index_path
    )

    # 11. 자산 인덱싱 매니페스트 기록

    indexer = AssetIndexer(manifest_file)
    asset_entries = {
        "heightmap_16bit": {
            "file_path": heightmap_png,
            "type": "heightmap",
            "format": "PNG16",
            "metadata": height_meta
        },
        "tiles_index": {
            "file_path": tiles_meta_file,
            "type": "terrain_tiles",
            "format": "JSON"
        },
        "buildings_and_roads": {
            "file_path": buildings_roads_json,
            "type": "buildings_and_roads",
            "format": "JSON"
        },
        "watermask_8bit": {
            "file_path": watermask_png,
            "type": "watermask",
            "format": "PNG8"
        },
        "real_districts": {
            "file_path": real_districts_json,
            "type": "district_polygons",
            "format": "JSON"
        },
        "vector_tactical_map": {
            "file_path": vector_map_png,
            "type": "vector_map",
            "format": "PNG"
        }
    }
    indexer.update_manifest(config_data, asset_entries)

    print("==================================================")
    print("Kanmon Pipeline Completed Successfully!")
    print(f"Artifacts ready in: {assets_dir}")
    print("==================================================")

if __name__ == "__main__":
    run_kanmon_pipeline()
