"""언양부터 시내까지 태화강 본류를 따라 이어지는 자전거길 체인을 생성한다.

OSM 자전거길 중 본류 가까운 선형을 그대로 쓰고, OSM에 없는 구간은 본류 중심선에서 수면을 벗어난
육지 쪽으로 띄운 선형으로 메운다. 출력은 둔치 보도와 같은 체인 형식(riverside_trial/cycleway.json)이다.
실행: python -m pipeline.processors.riverside_paths.build_taehwa_cycleway
"""
from __future__ import annotations

import hashlib
import json
import math
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from .build_riverside_paths import assign_tiers
from .osm_path_selector import PathRun, _densify, _resample, _split
from .river_corridor import RiverCorridor, WaterMask, to_lonlat, to_m

ROOT = Path(__file__).resolve().parents[3]
CONFIG = ROOT / "config" / "taehwa_cycleway.json"
MAP_DIR = ROOT / "godot_project" / "assets" / "maps" / "ulsan_metro_80km"
OUT_DIR = ROOT / "godot_project" / "assets" / "generated" / "riverside_trial"
HALF_WIDTH_M = 1.5


def select_osm(config: dict, corridor: RiverCorridor) -> list[PathRun]:
    raw = json.loads((ROOT / config["raw_dir"] / "cycleways_raw.json").read_text(encoding="utf-8"))
    lon_min, lon_max = config["route_lon_range"]
    runs = []
    for element in raw["elements"]:
        tags = element.get("tags", {})
        if tags.get("bridge") not in (None, "no") or tags.get("tunnel") not in (None, "no"):
            continue
        dense = _densify([to_m(p["lon"], p["lat"]) for p in element["geometry"]], 4.0)
        _, distance = corridor.nearest(np.array(dense))
        inside = [lon_min <= to_lonlat(*p)[0] <= lon_max and d <= config["max_distance_to_river_m"]
                  for p, d in zip(dense, distance)]
        for piece in _split(dense, inside):
            nodes = _resample(piece, config["segment_length_m"])
            run = PathRun(element["id"], "cycleway", tags.get("surface"), tags.get("name"), nodes)
            if run.length_m >= config["min_way_length_m"]:
                runs.append(run)
    return runs


def fill_gaps(config: dict, corridor: RiverCorridor, water: WaterMask, osm_runs: list[PathRun]) -> list[PathRun]:
    lon_min, lon_max = config["route_lon_range"]
    count = len(corridor.points)
    in_route = np.array([lon_min <= to_lonlat(*p)[0] <= lon_max for p in corridor.points])
    covered = np.zeros(count, bool)
    side_votes = np.zeros(count)
    reach = max(1, int(config["coverage_step_m"] / corridor.step_m))
    for run in osm_runs:
        dense = np.array(_densify(run.nodes, 4.0))
        index, _ = corridor.nearest(dense)
        sides = corridor.side(dense, index)
        for i, s in zip(index, sides):
            covered[max(0, i - reach):i + reach + 1] = True
            side_votes[i] += s
    gaps, start = [], None
    for i in range(count + 1):
        open_gap = i < count and in_route[i] and not covered[i]
        if open_gap and start is None:
            start = i
        elif not open_gap and start is not None:
            if (i - start) * corridor.step_m >= config["min_gap_m"]:
                gaps.append((start, i))
            start = None
    fills = []
    for index, (i0, i1) in enumerate(gaps):
        side = _gap_side(side_votes, i0, i1)
        offsets = [_land_offset(corridor, water, i, side, config) for i in range(i0, i1)]
        window = max(1, int(config["fill_smooth_m"] / corridor.step_m))
        valid = np.array([o is not None for o in offsets])
        values = np.array([o if o is not None else np.nan for o in offsets], float)
        smoothed = np.array([np.nanmax(values[max(0, k - window):k + window + 1]) if valid[k] else np.nan
                             for k in range(len(values))])
        points = [tuple(corridor.points[i] + corridor.normals[i] * side * smoothed[k]) for k, i in enumerate(range(i0, i1))]
        flags = [bool(v) and not water.is_water(*p) for v, p in zip(valid, points)]
        for piece in _split(points, flags):
            nodes = _resample(piece, config["segment_length_m"])
            run = PathRun(-(index + 1), "cycleway", None, "gap_fill", nodes)
            if run.length_m >= config["min_way_length_m"]:
                fills.append(run)
    return fills


def _gap_side(side_votes: np.ndarray, i0: int, i1: int, look: int = 40) -> float:
    vote = side_votes[max(0, i0 - look):i0].sum() + side_votes[i1:i1 + look].sum()
    return 1.0 if vote >= 0 else -1.0


def _land_offset(corridor: RiverCorridor, water: WaterMask, i: int, side: float, config: dict) -> float | None:
    """중심선에서 법선 방향으로 수면이 끝나는 거리에 여유를 더한 값. 탐색 범위 안에 육지가 없으면 None."""
    for d in np.arange(10.0, config["fill_search_m"], 5.0):
        p = corridor.points[i] + corridor.normals[i] * side * d
        if not water.is_water(*p):
            return float(d + config["fill_bank_margin_m"])
    return None


def chains_from(runs: list[PathRun], scene: str) -> list[dict]:
    tiers = assign_tiers(runs)
    return [{
        "id": f"cycle_{'fill' if run.osm_id < 0 else run.osm_id}_{i}",
        "osm_id": run.osm_id if run.osm_id > 0 else None,
        "highway": "cycleway",
        "source": "gap_fill" if run.osm_id < 0 else "osm",
        "scene": scene,
        "half_width_m": HALF_WIDTH_M,
        "tier": tiers[i],
        "nodes": [[round(v, 9) for v in to_lonlat(*p)] for p in run.nodes],
    } for i, run in enumerate(runs)]


def draw_preview(corridor: RiverCorridor, osm_runs: list[PathRun], fills: list[PathRun], path: Path) -> None:
    xs, zs = corridor.points[:, 0], corridor.points[:, 1]
    x0, z0 = xs.min() - 500, zs.min() - 500
    scale = 2400 / (xs.max() - x0 + 500)
    image = Image.new("L", (2400, int((zs.max() - z0 + 500) * scale)), 255)
    draw = ImageDraw.Draw(image)
    to_px = lambda p: ((p[0] - x0) * scale, (p[1] - z0) * scale)
    draw.line([to_px(p) for p in corridor.points], fill=190, width=5)
    for run in osm_runs:
        draw.line([to_px(p) for p in run.nodes], fill=0, width=3)
    for run in fills:
        draw.line([to_px(p) for p in run.nodes], fill=110, width=3)
    image.save(path)


def main() -> None:
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    corridor = RiverCorridor(ROOT / config["raw_dir"] / "rivers_raw.json", 10.0)
    water = WaterMask(MAP_DIR)
    osm_runs = select_osm(config, corridor)
    fills = fill_gaps(config, corridor, water, osm_runs)
    runs = osm_runs + fills
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / "cycleway.json"
    out.write_text(json.dumps({
        "version": 1,
        "note_ko": "언양~시내 태화강 자전거길. source가 osm이면 OSM 선형, gap_fill이면 OSM 공백을 강변 육지 쪽으로 메운 선형이다.",
        "asset_length_m": 12.0,
        "chains": chains_from(runs, config["scene"]),
    }, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    preview = OUT_DIR / "cycleway_preview.png"
    draw_preview(corridor, osm_runs, fills, preview)
    stats = {
        "osm_chains": len(osm_runs),
        "osm_length_m": round(sum(r.length_m for r in osm_runs)),
        "fill_chains": len(fills),
        "fill_length_m": round(sum(r.length_m for r in fills)),
        "segments": sum(len(r.nodes) - 1 for r in runs),
    }
    manifest_path = OUT_DIR / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {"assets": {}}
    manifest["cycleway"] = {"last_updated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"), "stats": stats,
                            "route_lon_range": config["route_lon_range"]}
    for name in ("cycleway.json", "cycleway_preview.png"):
        manifest["assets"][name] = {"file_path": f"res://assets/generated/riverside_trial/{name}",
                                    "sha256": hashlib.sha256((OUT_DIR / name).read_bytes()).hexdigest(),
                                    "size_bytes": (OUT_DIR / name).stat().st_size}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(json.dumps(stats, ensure_ascii=False))


if __name__ == "__main__":
    main()
