"""울산 80km 지도의 하천·호수 수면 평탄화 보정을 적용한다.

기존 수계 단계(rebuild_hydro_terrain.py)는 해안만 정형하고 하천·호수 마스크는 원 DEM 위에
그대로 칠해 수면 질감이 산비탈을 타고 오르는 문제가 있었다. 이 단계는
1) 호수마다 단일 수위로 평탄화하고, 2) 하천은 하곡 바닥 기준 매끄러운 수면 아래로 하도를 정지하며,
3) 산비탈로 번진 수계 마스크와 경사가 과도한 산지 계류는 수면 표시에서 뺀다. 지형은 낮추기만 한다.
실행 높이맵(railway/graded_heightmap_16bit.png)과 수계 높이맵(hydro/coastal_heightmap_16bit.png)에
같은 보정량을 적용하며, 철도 정지가 바꾼 화소는 철도 값을 유지한다.
원본은 data/archives/hydro_leveling_backup_<시각>/ 에 먼저 복사한다.

실행: python pipeline/processors/hydro_leveling/apply.py [--root <프로젝트 루트>] [--dry-run]
"""
import argparse
import hashlib
import json
import shutil
import sys
import time
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from hydro_leveling import LakeLeveler, RiverLeveler  # noqa: E402

Image.MAX_IMAGE_PIXELS = None
MAP_ID = "ulsan_metro_80km"
SETTINGS = {
    "lake": {"level_percentile": 10.0, "keep_above_m": 4.0, "depth_m": 1.0, "shore_rise_m": 0.6, "shore_blend_m": 30.0, "shore_max_cut_m": 3.0, "report_range_m": 5.0},
    "river": {"floor_radius_m": 30.0, "smooth_m": 45.0, "carve_max_m": 6.0, "channel_depth_m": 0.6, "bank_rise_m": 0.8,
              "bank_blend_m": 45.0, "max_visible_grade": 0.08},
    "rail_edit_threshold_m": 0.25,
}


def load_heights(path, low, high):
    return low + np.asarray(Image.open(path), dtype=np.float32) / 65535.0 * (high - low)


def save_heights(path, heights, low, high):
    encoded = np.rint(np.clip((heights - low) / (high - low), 0, 1) * 65535).astype(np.uint16)
    temporary = path.with_name(path.stem + ".partial.png")
    Image.fromarray(encoded).save(temporary)
    temporary.replace(path)


def save_mask(path, mask):
    temporary = path.with_name(path.stem + ".partial.png")
    Image.fromarray(np.where(mask, 255, 0).astype(np.uint8)).save(temporary)
    temporary.replace(path)


def preview(path, before, after, water_before, water_after):
    def shade(h):
        gy, gx = np.gradient(h)
        return np.clip(150 - 6 * gx + 6 * gy, 0, 255).astype(np.uint8)
    panels = []
    for heights, water in ((before, water_before), (after, water_after)):
        image = np.repeat(shade(heights)[:, :, None], 3, axis=2)
        image[water] = (image[water] * 0.4 + np.array([230, 140, 40]) * 0.6).astype(np.uint8)
        panels.append(cv2.resize(image, (1400, 1400), interpolation=cv2.INTER_AREA))
    cv2.imwrite(str(path), np.concatenate(panels, axis=1), [cv2.IMWRITE_JPEG_QUALITY, 85])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[3]))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root = Path(args.root)
    folder = root / "godot_project/assets/maps" / MAP_ID
    hydro = folder / "hydro"
    graded_path = root / "godot_project/assets/generated/railway/graded_heightmap_16bit.png"
    meta = json.loads((folder / "map_meta.json").read_text(encoding="utf-8-sig"))
    low, high = float(meta["min_elevation"]), float(meta["max_elevation"])
    pixel_m = float(meta["world_size_meters"]) / 5631.0

    coastal = load_heights(hydro / "coastal_heightmap_16bit.png", low, high)
    graded = load_heights(graded_path, low, high) if graded_path.exists() else None
    sea = np.asarray(Image.open(hydro / "sea_mask.png")) > 127
    lake = (np.asarray(Image.open(hydro / "lake_mask.png")) > 127) & ~sea
    river = (np.asarray(Image.open(hydro / "river_mask.png")) > 127) & ~sea & ~lake
    water_before = sea | lake | river

    heights, lake_kept, lake_stats = LakeLeveler(pixel_m, SETTINGS["lake"]).apply(coastal, lake)
    heights, visible, river_stats = RiverLeveler(pixel_m, SETTINGS["river"]).apply(heights, river)
    heights[sea] = coastal[sea]
    heights = np.minimum(heights, coastal)
    delta = heights - coastal
    water_after = sea | lake_kept | visible

    report = {"generated": time.strftime("%Y-%m-%d %H:%M:%S"), "settings": SETTINGS, "lakes": lake_stats,
              "rivers": river_stats, "max_lowered_m": round(float(-delta.min()), 2),
              "max_raised_m": round(float(delta.max()), 2), "changed_pixels_over_0_5m": int((np.abs(delta) > 0.5).sum())}
    summary = {k: v for k, v in report.items() if k != "settings"}
    summary["lakes"] = {k: v for k, v in lake_stats.items() if k != "worst"}
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    results = root / "results"
    preview(results / "261009_HydroLevelingPreview.jpg", coastal, heights, water_before, water_after)
    if args.dry_run:
        return

    backup = root / "data/archives" / f"hydro_leveling_backup_{time.strftime('%Y%m%d_%H%M%S')}"
    backup.mkdir(parents=True, exist_ok=True)
    targets = [hydro / "coastal_heightmap_16bit.png", hydro / "river_mask.png", hydro / "lake_mask.png", hydro / "water_mask.png"]
    if graded is not None:
        targets.append(graded_path)
    for path in targets + [folder / "manifest.json"]:
        shutil.copy2(path, backup / path.name)

    save_heights(hydro / "coastal_heightmap_16bit.png", heights, low, high)
    if graded is not None:
        rail_edited = np.abs(graded - coastal) > SETTINGS["rail_edit_threshold_m"]
        graded_new = np.where(rail_edited, graded, graded + delta)
        report["rail_edited_pixels_kept"] = int((rail_edited & (np.abs(delta) > 0.01)).sum())
        save_heights(graded_path, graded_new, low, high)
    save_mask(hydro / "river_mask.png", visible)
    save_mask(hydro / "lake_mask.png", lake_kept)
    save_mask(hydro / "water_mask.png", water_after)
    report["backup"] = backup.relative_to(root).as_posix()
    (hydro / "hydro_leveling_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    manifest_path = folder / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    for path in [p for p in targets if p.parent == hydro] + [hydro / "hydro_leveling_report.json"]:
        key = f"{MAP_ID}/hydro/{path.name}"
        entry = manifest["assets"].get(key, {"file_path": f"res://assets/maps/{MAP_ID}/hydro/{path.name}"})
        entry.update(sha256=hashlib.sha256(path.read_bytes()).hexdigest(), size_bytes=path.stat().st_size,
                     bbox=meta["bbox"], elevation={"min_meters": low, "max_meters": high})
        manifest["assets"][key] = entry
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"백업: {backup}", flush=True)


if __name__ == "__main__":
    main()
