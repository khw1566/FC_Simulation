"""태화강 둔치 정밀 지형 생성 진입점.

실행 예 (프로젝트 루트, PowerShell):
  $env:VWORLD_API_KEY = "<발급 키>"
  & 'C:\\Users\\khw\\AppData\\Local\\Programs\\Python\\Python312\\python.exe' pipeline/processors/taehwagang_terrain/generate.py
옵션: --source auto|vworld|terrarium, --refresh-water, --refresh-roads, --no-satellite, --dry-run
확인 이미지: results/dunchi_check/ (위성 영상 위 수면·강변도로·제방 경사·배치 가능 둔치)
"""
import argparse
import json

import cv2
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "pipeline/collectors"))
sys.path.insert(0, str(ROOT / "pipeline/processors"))

from riverside_sources import (  # noqa: E402
    ApiKeyResolver, RiversideRoadCollector, RiversideWaterCollector, SatelliteImagerySource)
from taehwagang_terrain.height_source_selector import HeightSourceSelector  # noqa: E402
from taehwagang_terrain import (  # noqa: E402
    CheckOverlayRenderer, LeveeProfileShaper, PadFlattener, RiverbankShaper, RoadRasterizer,
    TerrainExporter, TerrainGrid, WaterRasterizer)

CONFIG = ROOT / "config/taehwagang_dunchi_terrain.json"


def main():
    parser = argparse.ArgumentParser(description="태화강 둔치 정밀 지형 생성")
    parser.add_argument("--source", choices=["auto", "vworld", "terrarium"], default=None)
    parser.add_argument("--refresh-water", action="store_true")
    parser.add_argument("--refresh-roads", action="store_true")
    parser.add_argument("--no-satellite", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="키 위치와 VWorld 요청 수만 확인")
    args = parser.parse_args()

    config = json.loads(CONFIG.read_text(encoding="utf-8-sig"))
    grid = TerrainGrid(config)
    selector = HeightSourceSelector(ROOT, config, grid)
    heights, source_meta = selector.select(args.source, dry_run=args.dry_run)
    if args.dry_run:
        print(json.dumps(source_meta, ensure_ascii=False, indent=2))
        return

    water_data = RiversideWaterCollector(ROOT, config["water"]).collect(config["bbox"], refresh=args.refresh_water)
    rasterizer = WaterRasterizer(grid, config["water"])
    river, other_water = rasterizer.rasterize(water_data)
    riverbank = RiverbankShaper(grid, config["water"], config["dunchi"])
    base, base_placeable, stats = riverbank.shape(heights, river)
    distance_to_river = cv2.distanceTransform((~river).astype("uint8"), cv2.DIST_L2, 5) * grid.pixel_m

    road_data = RiversideRoadCollector(ROOT, config["water"]["overpass_endpoints"]).collect(config["bbox"], refresh=args.refresh_roads)
    all_roads, riverside_road, selected_roads = RoadRasterizer(grid, config["roads"]).rasterize(road_data, distance_to_river)
    levee = LeveeProfileShaper(grid, config["levee_profile"], config["dunchi"]["bank_ramp_m"])
    shaped, placeable, levee_stats, slope_band = levee.shape(
        base, base_placeable, heights, river, riverside_road, distance_to_river, riverbank.water_level())
    stats.update(levee_stats)
    shaped, pads = PadFlattener(grid).apply(shaped, config.get("placement_pads", []))
    stats["skipped_open_relations"] = rasterizer.skipped

    satellite, satellite_meta = None, None
    if not args.no_satellite:
        settings = config["height_source"]
        key, _ = ApiKeyResolver(ROOT, settings["api_key_env"], settings["api_key_file_field"]).resolve()
        try:
            source = SatelliteImagerySource(ROOT, config["satellite"], key)
            satellite = source.collect(config["bbox"], grid.width, grid.height)
            satellite_meta = source.meta()
        except Exception as error:
            print(f"[generate] 위성 영상 생략: {error}", flush=True)
    checks = CheckOverlayRenderer(ROOT).render(
        shaped, None if satellite is None else satellite[:, :, ::-1], river, all_roads, riverside_road, slope_band, placeable)
    extra = {"riverside_roads": selected_roads, "satellite": satellite_meta, "check_images": checks}
    outputs = TerrainExporter(ROOT, config).export(
        shaped, river | other_water, placeable, source_meta, stats, pads, satellite=satellite, extra_meta=extra)
    print(json.dumps({"height_source": source_meta.get("source"), "stats": stats,
                      "riverside_roads": len(selected_roads), "outputs": outputs}, ensure_ascii=False, indent=2))
    print("에셋 색인 갱신: pipeline/indexer/build_asset_index.py 를 수동 실행하세요.")


if __name__ == "__main__":
    main()
