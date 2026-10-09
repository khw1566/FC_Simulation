"""태화강 둔치 생태 구역 분할과 구역별 규칙 배치 생성 진입점.

실행: python pipeline/processors/taehwagang_ecozones/generate.py [--refresh-osm]
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "pipeline/collectors"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from ecozone_landcover_collector import EcozoneLandcoverCollector  # noqa: E402
from geo_raster import GeoRaster  # noqa: E402
from ground_textures import render_all  # noqa: E402
from scatter_planner import ScatterPlanner  # noqa: E402
from source_masks import DunchiSourceMasks  # noqa: E402
from zone_classifier import ZoneClassifier  # noqa: E402
from zone_exporter import ZoneExporter  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(ROOT / "config/taehwagang_ecozones.json"))
    parser.add_argument("--refresh-osm", action="store_true")
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text(encoding="utf-8"))

    source = DunchiSourceMasks(ROOT, config["source_map_folders"])
    raster = GeoRaster(source.bbox, config["working_resolution"], source.world_size_m)
    water, placeable = source.masks(raster.size)
    print(f"원천: {source.folder} / 작업 격자 {raster.size}px, {raster.cell_m:.2f}m")

    collector = EcozoneLandcoverCollector(ROOT / "data/raw/taehwagang_ecozones/osm_landcover.json", config["overpass_endpoints"])
    osm = collector.collect(source.bbox, refresh=args.refresh_osm)
    osm_layers = raster.rasterize_classes(osm.get("elements", []), config["osm_classes"])

    classifier = ZoneClassifier(raster, config["zones"])
    labels, stats = classifier.classify(placeable, water, osm_layers)
    for key, value in stats.items():
        print(f"  구역 {key}: {value['area_m2'] / 10000:.2f} ha")

    planner = ScatterPlanner(raster, source.heights(), config["random_seed"])
    ids = {zone["key"]: zone["id"] for zone in config["zones"]}
    edges = {}
    layers = []
    for index, rule in enumerate(config["scatter"]):
        zone_id = ids[rule["zone"]]
        if zone_id not in edges:
            edges[zone_id] = classifier.edge_distance(labels, zone_id)
        layer = planner.plan(rule, index, labels, zone_id, edges[zone_id])
        layers.append(layer)
        print(f"  배치 {rule['zone']}/{rule['kind']}: {layer['count']}")

    exporter = ZoneExporter(ROOT, config, raster)
    files = exporter.write_rasters(labels, placeable)
    files["preview"] = exporter.write_preview(labels, water, layers)
    files["scatter"] = exporter.write_scatter(layers)
    for name, path in render_all(exporter.folder / "ground", config["random_seed"]).items():
        files["ground_" + name] = path
    osm_meta = {"cache": "data/raw/taehwagang_ecozones/osm_landcover.json", "elements": len(osm.get("elements", [])),
                "endpoint": osm.get("source_endpoint"), "osm_timestamp": osm.get("osm3s", {}).get("timestamp_osm_base")}
    exporter.write_catalog(files, stats, layers, source.provenance(), osm_meta)
    print("완료:", exporter.folder)


if __name__ == "__main__":
    main()
