"""태화강 국가정원·둔치 보도와 정원 시설물 시범 배치를 placements.json 형식으로 생성한다.

출력 형식은 taehwagang_dunchi 지도의 RiversideAssetPlacer 스키마(lonlat, ground=terrain)와 같다.
실행: python -m pipeline.processors.riverside_trial.build_trial_placements [--map-dir 경로]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageDraw

from .corridor_search import CorridorSearch
from .placement_mask import PlacementMask
from .site_layouts import LAYOUTS, resolve

ROOT = Path(__file__).resolve().parents[3]
CONFIG = ROOT / "config" / "riverside_trial_sites.json"
DEFAULT_MAP_DIR = ROOT / "godot_project" / "assets" / "maps" / "taehwagang_dunchi"
OUT_DIR = ROOT / "godot_project" / "assets" / "generated" / "riverside_trial"
PREVIEW_HALF_M = 70.0
PREVIEW_PX = 420
CHAIN_KEYS = ("walk", "planter")
CHAIN_HALF_WIDTH_M = 3.0


def build(map_dir: Path) -> dict:
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    mask = PlacementMask(map_dir)
    search = CorridorSearch(mask, config["segment_length_m"], config["corridor_half_width_m"], config["yaw_sweep_degrees"])
    placements, sites, previews = [], [], []
    for site in config["sites"]:
        center = mask.lonlat_to_world(*site["center_lonlat"])
        corridor = search.find(center, config["search_radius_m"], config["search_step_m"], site["max_segments"])
        if corridor is None:
            sites.append({"id": site["id"], "name_ko": site["name_ko"], "placed": 0, "note_ko": "배치 가능 구간 없음"})
            continue
        items = LAYOUTS[site["layout"]](len(corridor.centers))
        counters: dict[str, int] = {}
        drawn = []
        for item in items:
            x, z, yaw = resolve(item, corridor)
            counters[item.key] = counters.get(item.key, 0) + 1
            lon, lat = mask.world_to_lonlat(x, z)
            entry = {
                "id": f"trial_{site['id']}_{item.key}_{counters[item.key]:02d}",
                "scene": item.scene,
                "lonlat": [round(lon, 9), round(lat, 9)],
                "ground": "terrain",
                "y_offset_m": item.y_offset,
                "yaw_degrees": round(yaw, 2),
                "scale": 1.0,
                "chain": site["id"],
                "footprint_half_m": list(item.half_extent),
            }
            if item.key in CHAIN_KEYS:
                # 보도 세그먼트와 같은 길이의 선형 부속물은 보도 높이 프로파일을 따라 기울인다
                entry["chain_index"] = item.segment
                entry["chain_role"] = "path" if item.key == "walk" else "follow"
                entry["segment_length_m"] = config["segment_length_m"]
                entry["chain_half_width_m"] = CHAIN_HALF_WIDTH_M
            placements.append(entry)
            drawn.append((item.key, x, z, math.radians(yaw), item.half_extent))
        mid = corridor.centers[len(corridor.centers) // 2]
        sites.append({
            "id": site["id"],
            "name_ko": site["name_ko"],
            "layout": site["layout"],
            "segments": len(corridor.centers),
            "length_m": len(corridor.centers) * config["segment_length_m"],
            "center_lonlat": [round(v, 7) for v in mask.world_to_lonlat(*mid)],
            "yaw_degrees": round(corridor.yaw_degrees, 2),
            "offset_from_hint_m": round(math.hypot(mid[0] - center[0], mid[1] - center[1]), 1),
            "placed": len(items),
        })
        previews.append((site["id"], mid, drawn))
    return {"placements": placements, "sites": sites, "previews": previews, "mask": mask, "config": config}


def draw_preview(result: dict, path: Path) -> None:
    mask: PlacementMask = result["mask"]
    panels = result["previews"]
    sheet = Image.new("L", (PREVIEW_PX * max(1, len(panels)), PREVIEW_PX + 24), 255)
    scale = PREVIEW_PX / (PREVIEW_HALF_M * 2)
    shades = {"walk": 70, "plaza": 110, "planter": 150, "pavilion": 0, "marquee": 0, "canopy": 0}
    for idx, (name, mid, drawn) in enumerate(panels):
        panel = Image.new("L", (PREVIEW_PX, PREVIEW_PX), 255)
        px = panel.load()
        for v in range(PREVIEW_PX):
            for u in range(PREVIEW_PX):
                wx = mid[0] + (u / scale - PREVIEW_HALF_M)
                wz = mid[1] + (v / scale - PREVIEW_HALF_M)
                px[u, v] = 225 if mask.placeable(wx, wz) else 255
        draw = ImageDraw.Draw(panel)
        for key, x, z, yaw, (hx, hz) in drawn:
            ax, az = math.cos(yaw), -math.sin(yaw)  # 로컬 X
            bx, bz = math.sin(yaw), math.cos(yaw)  # 로컬 Z
            corners = []
            for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                cx = x + ax * hx * sx + bx * hz * sz
                cz = z + az * hx * sx + bz * hz * sz
                corners.append(((cx - mid[0] + PREVIEW_HALF_M) * scale, (cz - mid[1] + PREVIEW_HALF_M) * scale))
            draw.polygon(corners, fill=shades.get(key, 30), outline=0)
        draw.rectangle([0, 0, PREVIEW_PX - 1, PREVIEW_PX - 1], outline=0)
        sheet.paste(panel, (idx * PREVIEW_PX, 24))
        ImageDraw.Draw(sheet).text((idx * PREVIEW_PX + 6, 6), f"{name} ({PREVIEW_HALF_M * 2:.0f} m, N up)", fill=0)
    sheet.save(path)


def write_outputs(result: dict, map_dir: Path) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    config = result["config"]
    catalog = {
        "version": 1,
        "map_id": config["map_id"],
        "note_ko": "보도·정원 시설물 시범 배치. taehwagang_dunchi 지도 placements.json의 placements 배열에 병합해 사용한다.",
        "placements": result["placements"],
    }
    placements_path = OUT_DIR / "placements.json"
    placements_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    preview_path = OUT_DIR / "preview.png"
    draw_preview(result, preview_path)
    manifest = {
        "last_updated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "map_id": config["map_id"],
        "source_mask_bbox": result["mask"].bbox,
        "source_map_dir": str(map_dir),
        "sites": result["sites"],
        "assets": {
            name: {
                "file_path": f"res://assets/generated/riverside_trial/{name}",
                "sha256": hashlib.sha256((OUT_DIR / name).read_bytes()).hexdigest(),
                "size_bytes": (OUT_DIR / name).stat().st_size,
            }
            for name in ("placements.json", "preview.png")
        },
    }
    (OUT_DIR / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map-dir", type=Path, default=DEFAULT_MAP_DIR, help="taehwagang_dunchi 지도 폴더")
    args = parser.parse_args()
    result = build(args.map_dir)
    write_outputs(result, args.map_dir)
    for site in result["sites"]:
        print(json.dumps(site, ensure_ascii=False))
    print(f"placements: {len(result['placements'])} -> {OUT_DIR / 'placements.json'}")


if __name__ == "__main__":
    main()
