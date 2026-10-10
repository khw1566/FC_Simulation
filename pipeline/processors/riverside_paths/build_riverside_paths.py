"""OSM 보행로 선형과 둔치 지형 마스크로 태화강 둔치 보도·벤치 배치를 생성한다.

출력(godot_project/assets/generated/riverside_trial):
- paths.json: 보도 체인. 각 체인은 접속점 위경도 배열이고 게임에서 접속점 사이에 보도 조각을 놓는다.
- placements.json: 벤치 등 개별 시설물(RiversideAssetPlacer 스키마와 같은 lonlat 형식).
실행: python -m pipeline.processors.riverside_paths.build_riverside_paths [--map-dir 경로]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import Counter
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageDraw

from .osm_path_selector import OsmPathSelector, PathRun
from .path_styles import BENCH_SCENE, style_for
from .riverside_zone import RiversideZone

ROOT = Path(__file__).resolve().parents[3]
CONFIG = ROOT / "config" / "riverside_paths.json"
DUNCHI_ROOT = ROOT.parent / "FC_Simulation_dunchi"
DEFAULT_MAP_DIR = DUNCHI_ROOT / "godot_project" / "assets" / "maps" / "taehwagang_dunchi"
OUT_DIR = ROOT / "godot_project" / "assets" / "generated" / "riverside_trial"
ASSET_LENGTH_M = 12.0
WALK_HALF_WIDTH_M = 1.5
PREVIEW_PX = 2048


def build_chains(runs: list[PathRun], zone: RiversideZone, config: dict) -> list[dict]:
    chains = []
    for index, run in enumerate(runs):
        mid = run.nodes[len(run.nodes) // 2]
        lon_mid = zone.world_to_lonlat(*mid)[0]
        chains.append({
            "id": f"path_{run.osm_id}_{index}",
            "osm_id": run.osm_id,
            "highway": run.highway,
            "surface": run.surface,
            "scene": style_for(run.highway, run.surface, lon_mid, config["garden_lon_range"]),
            "half_width_m": WALK_HALF_WIDTH_M,
            "nodes": [[round(v, 9) for v in zone.world_to_lonlat(x, z)] for x, z in run.nodes],
        })
    return chains


def build_benches(runs: list[PathRun], zone: RiversideZone, settings: dict) -> list[dict]:
    benches = []
    for run in runs:
        if run.highway not in settings["highways"]:
            continue
        distance = settings["spacing_m"] * 0.5
        travelled = 0.0
        side = 1.0
        for a, b in zip(run.nodes[:-1], run.nodes[1:]):
            length = math.dist(a, b)
            while length > 0 and distance <= travelled + length:
                t = (distance - travelled) / length
                dx, dz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
                normal = (dz, -dx)
                placed = False
                for s in (side, -side):
                    x = a[0] + (b[0] - a[0]) * t + normal[0] * settings["lateral_m"] * s
                    z = a[1] + (b[1] - a[1]) * t + normal[1] * settings["lateral_m"] * s
                    if zone.on_water(x, z) or (settings["require_placeable"] and not zone.placeable(x, z)):
                        continue
                    yaw = math.degrees(math.atan2(dx, dz)) + 90.0 * s
                    lon, lat = zone.world_to_lonlat(x, z)
                    benches.append({
                        "id": f"bench_{run.osm_id}_{len(benches):04d}",
                        "scene": BENCH_SCENE,
                        "lonlat": [round(lon, 9), round(lat, 9)],
                        "ground": "terrain",
                        "y_offset_m": 0.0,
                        "yaw_degrees": round(yaw, 2),
                        "scale": 1.0,
                        "footprint_half_m": [0.9, 0.26],
                    })
                    placed = True
                    break
                if placed:
                    side = -side
                distance += settings["spacing_m"]
            travelled += length
    return benches


def draw_preview(zone: RiversideZone, runs: list[PathRun], benches: list[dict], path: Path) -> None:
    step = zone.width // PREVIEW_PX
    base = Image.new("L", (PREVIEW_PX, PREVIEW_PX), 255)
    small_mask = zone.mask[::step, ::step]
    small_water = zone.water[::step, ::step]
    pixels = base.load()
    for y in range(PREVIEW_PX):
        for x in range(PREVIEW_PX):
            if small_water[y, x]:
                pixels[x, y] = 200
            elif small_mask[y, x]:
                pixels[x, y] = 232
    draw = ImageDraw.Draw(base)

    def to_px(x: float, z: float) -> tuple[float, float]:
        px, py = zone.world_to_pixel(x, z)
        return px / step, py / step

    for run in runs:
        draw.line([to_px(*n) for n in run.nodes], fill=0, width=2)
    for bench in benches:
        bx, by = to_px(*zone.lonlat_to_world(*bench["lonlat"]))
        draw.ellipse([bx - 2, by - 2, bx + 2, by + 2], fill=90)
    base.save(path)


def write_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map-dir", type=Path, default=DEFAULT_MAP_DIR, help="taehwagang_dunchi 지도 폴더")
    parser.add_argument("--roads-raw", type=Path, default=None, help="OSM 도로 원자료(roads_raw.json)")
    args = parser.parse_args()
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    roads_raw = args.roads_raw or DUNCHI_ROOT / config["roads_raw"]
    zone = RiversideZone(args.map_dir, config["zone_dilate_m"])
    runs = OsmPathSelector(zone, config).select(roads_raw)
    chains = build_chains(runs, zone, config)
    benches = build_benches(runs, zone, config["bench"])
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_json(OUT_DIR / "paths.json", {
        "version": 1,
        "map_id": config["map_id"],
        "note_ko": "OSM 보행로 선형 기반 둔치 보도. 접속점 사이마다 보도 조각 하나를 놓고 진행축 배율로 길이를 맞춘다.",
        "asset_length_m": ASSET_LENGTH_M,
        "chains": chains,
    })
    write_json(OUT_DIR / "placements.json", {
        "version": 1,
        "map_id": config["map_id"],
        "note_ko": "보도 옆 벤치. taehwagang_dunchi placements.json 스키마와 같다.",
        "placements": benches,
    })
    draw_preview(zone, runs, benches, OUT_DIR / "preview.png")
    stats = {
        "chains": len(chains),
        "segments": sum(len(c["nodes"]) - 1 for c in chains),
        "length_m_by_highway": {k: round(v) for k, v in _length_by(runs).items()},
        "chains_by_scene": dict(Counter(c["scene"].rsplit("/", 1)[-1] for c in chains)),
        "benches": len(benches),
    }
    write_json(OUT_DIR / "manifest.json", {
        "last_updated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "map_id": config["map_id"],
        "sources": {"roads_raw": str(roads_raw), "map_dir": str(args.map_dir)},
        "bbox": zone.bbox,
        "stats": stats,
        "assets": {
            name: {
                "file_path": f"res://assets/generated/riverside_trial/{name}",
                "sha256": hashlib.sha256((OUT_DIR / name).read_bytes()).hexdigest(),
                "size_bytes": (OUT_DIR / name).stat().st_size,
            }
            for name in ("paths.json", "placements.json", "preview.png")
        },
    })
    print(json.dumps(stats, ensure_ascii=False, indent=1))


def _length_by(runs: list[PathRun]) -> Counter:
    totals: Counter = Counter()
    for run in runs:
        totals[run.highway] += run.length_m
    return totals


if __name__ == "__main__":
    main()
