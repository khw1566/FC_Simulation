"""수계 렌더링 전용 부호 거리장(water_sdf.png) 생성 진입점.

기존 이진 마스크(water/river/lake/sea_mask.png)는 도로·건물·물리 계산이 그대로 쓰므로 바꾸지 않는다.
이 텍스처는 지형·바다 셰이더가 수면 경계를 화소 계단 없이 그리는 데만 쓴다.

- 하천·호수: OSM 벡터를 4배 해상도로 그린 부호 거리. 선형 수로는 최소 폭 16m로 그려 끊김을 막는다.
- 바다: 해양 마스크의 부호 거리를 1화소 가우시안으로 다듬는다(해안선은 지형 높이 판정이 정한다).
- 수면 보정(hydro_leveling)이 지운 비탈 수면과 급류는 현재 수계 마스크를 2화소 넓힌 허용 영역으로 계속 제외한다.

인코딩: 8bit, 값 = 128 + 부호거리(m) / clamp * 127, 수면 안쪽이 음수(128 미만).
실행: <python> pipeline/processors/water_sdf/build_water_sdf.py [--root <프로젝트 루트>] [--map ulsan_metro_80km] [--dry-run]
"""
import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from vector_tile_rasterizer import VectorTileRasterizer  # noqa: E402

CLAMP_M = 40.0
MIN_LINE_WIDTH_M = 16.0
ALLOW_DILATE_PX = 2


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def mask(path):
    return np.asarray(Image.open(path).convert("L")) > 127


def mask_signed_distance(binary, meters):
    outside = cv2.distanceTransform((~binary).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    inside = cv2.distanceTransform(binary.astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    return ((outside - inside) * meters).astype(np.float32)


def encode(signed):
    return np.clip(np.rint(128.0 + np.clip(signed, -CLAMP_M, CLAMP_M) / CLAMP_M * 127.0), 0, 255).astype(np.uint8)


def components(binary):
    return cv2.connectedComponents(binary.astype(np.uint8), connectivity=4)[0] - 1


def main():
    parser = argparse.ArgumentParser(description="수계 렌더링용 부호 거리장 생성")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[3]))
    parser.add_argument("--map", default="ulsan_metro_80km")
    parser.add_argument("--dry-run", action="store_true", help="통계와 미리보기만 만든다")
    args = parser.parse_args()
    root = Path(args.root)
    folder = root / "godot_project/assets/maps" / args.map
    hydro = folder / "hydro"
    meta = read_json(folder / "map_meta.json")
    current_water = mask(hydro / "water_mask.png")
    sea = mask(hydro / "sea_mask.png")
    n = current_water.shape[0]
    meters = float(meta["world_size_meters"]) / (n - 1)

    rasterizer = VectorTileRasterizer(meta["bbox"], n, meters, clamp_m=CLAMP_M, min_line_width_m=MIN_LINE_WIDTH_M)
    for kind in ("river", "lake"):
        for feature in read_json(hydro / f"{kind}.geojson")["features"]:
            rasterizer.add_feature(feature)
    started = time.time()
    vector = rasterizer.signed_distance(lambda i, total: print(f"[water_sdf] 타일 {i}/{total}", flush=True))

    # 수면 보정이 지운 비탈·급류 구간은 다시 살리지 않는다.
    allowed = cv2.dilate(current_water.astype(np.uint8), np.ones((3, 3), np.uint8), iterations=ALLOW_DILATE_PX) > 0
    vector = np.where(allowed, vector, CLAMP_M)
    sea_field = cv2.GaussianBlur(mask_signed_distance(sea, meters), (0, 0), 1.0)
    signed = np.minimum(vector, sea_field)

    inland_new = (vector < 0) & ~sea
    inland_old = current_water & ~sea
    report = {
        "generated": time.strftime("%Y-%m-%d %H:%M:%S"),
        "map": args.map,
        "resolution": n,
        "meters_per_pixel": round(meters, 3),
        "encoding": {"center": 128, "clamp_m": CLAMP_M, "inside": "negative"},
        "min_line_width_m": MIN_LINE_WIDTH_M,
        "supersample": rasterizer.ss,
        "features": len(rasterizer.items),
        "inland_water_components_before": int(components(inland_old)),
        "inland_water_components_after": int(components(inland_new)),
        "inland_water_pixels_before": int(inland_old.sum()),
        "inland_water_pixels_after": int(inland_new.sum()),
        "seconds": round(time.time() - started, 1),
    }
    print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)
    preview(root / "results/261010_WaterSdfPreview.jpg", current_water, signed, meta, n)
    if args.dry_run:
        return
    path = hydro / "water_sdf.png"
    temporary = path.with_name("water_sdf.partial.png")
    Image.fromarray(encode(signed)).save(temporary)
    temporary.replace(path)
    report["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    (hydro / "water_sdf_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    manifest_path = folder / "manifest.json"
    manifest = read_json(manifest_path)
    manifest.setdefault("assets", {})[f"{args.map}/hydro/water_sdf.png"] = {
        "file_path": f"res://assets/maps/{args.map}/hydro/water_sdf.png", "sha256": report["sha256"],
        "size_bytes": path.stat().st_size, "bbox": meta["bbox"], "resolution": {"width": n, "height": n},
        "encoding": report["encoding"], "role": "render_only_water_signed_distance"}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[water_sdf] 저장: {path}", flush=True)


def preview(path, current_water, signed, meta, n):
    """태화강 상류 지류 부근: 왼쪽 기존 마스크 이중선형 0.5 경계, 오른쪽 거리장 0m 경계(4배 확대)."""
    b = meta["bbox"]
    cx = int((129.20 - b["west"]) / (b["east"] - b["west"]) * (n - 1))
    cy = int((b["north"] - 35.60) / (b["north"] - b["south"]) * (n - 1))
    window = np.s_[cy - 160:cy + 160, cx - 240:cx + 240]
    old = cv2.resize(current_water[window].astype(np.float32), None, fx=4, fy=4, interpolation=cv2.INTER_LINEAR) > 0.5
    new = cv2.resize(signed[window], None, fx=4, fy=4, interpolation=cv2.INTER_LINEAR) < 0
    panels = [np.where(m, 60, 225).astype(np.uint8) for m in (old, new)]
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(path), np.concatenate([panels[0], np.full((panels[0].shape[0], 8), 0, np.uint8), panels[1]], axis=1),
                [cv2.IMWRITE_JPEG_QUALITY, 88])


if __name__ == "__main__":
    main()
