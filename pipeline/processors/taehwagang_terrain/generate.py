"""태화강 둔치 정밀 지형 생성 진입점.

실행 예 (프로젝트 루트, PowerShell):
  $env:VWORLD_API_KEY = "<발급 키>"
  & 'C:\\Users\\khw\\AppData\\Local\\Programs\\Python\\Python312\\python.exe' pipeline/processors/taehwagang_terrain/generate.py
옵션: --source auto|vworld|terrarium, --refresh-water, --dry-run
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "pipeline/collectors"))
sys.path.insert(0, str(ROOT / "pipeline/processors"))

from riverside_sources import RiversideWaterCollector  # noqa: E402
from taehwagang_terrain.height_source_selector import HeightSourceSelector  # noqa: E402
from taehwagang_terrain import (  # noqa: E402
    PadFlattener, RiverbankShaper, TerrainExporter, TerrainGrid, WaterRasterizer)

CONFIG = ROOT / "config/taehwagang_dunchi_terrain.json"


def main():
    parser = argparse.ArgumentParser(description="태화강 둔치 정밀 지형 생성")
    parser.add_argument("--source", choices=["auto", "vworld", "terrarium"], default=None)
    parser.add_argument("--refresh-water", action="store_true")
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
    shaped, placeable, stats = RiverbankShaper(grid, config["water"], config["dunchi"]).shape(heights, river)
    shaped, pads = PadFlattener(grid).apply(shaped, config.get("placement_pads", []))
    stats["skipped_open_relations"] = rasterizer.skipped
    outputs = TerrainExporter(ROOT, config).export(shaped, river | other_water, placeable, source_meta, stats, pads)
    print(json.dumps({"height_source": source_meta.get("source"), "stats": stats, "outputs": outputs}, ensure_ascii=False, indent=2))
    print("에셋 색인 갱신: pipeline/indexer/build_asset_index.py 를 수동 실행하세요.")


if __name__ == "__main__":
    main()
