"""울산 전체 지상 도로의 노반 평면을 공간 타일에 저장하고 원본 벡터·DEM을 보존한다."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from profiles import profiles

ROOT = Path(__file__).resolve().parents[3]
CELL = 512


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix+".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    temp.replace(path)


def build():
    meta = read(ROOT/"godot_project/assets/maps/ulsan_metro_80km/map_meta.json")
    vector = ROOT/"godot_project"/meta["assets"]["buildings_roads"].removeprefix("res://")
    height = ROOT/"godot_project/assets/generated/railway/graded_heightmap_16bit.png"
    if not height.exists():
        height = ROOT/"godot_project"/meta["assets"]["heightmap"].removeprefix("res://")
    water = ROOT/"godot_project"/meta["assets"]["watermask"].removeprefix("res://")
    inputs = {p: (p.stat().st_size, p.stat().st_mtime_ns, digest(p)) for p in (vector, height, water)}
    with Image.open(height) as image:
        heights = np.asarray(image, dtype=np.float32)/65535*(meta["max_elevation"]-meta["min_elevation"])+meta["min_elevation"]
    with Image.open(water) as image:
        water_pixels = np.asarray(image.convert("L"), dtype=np.float32)/255
    roads = read(vector)["roads"]
    rows, counts = profiles(roads, heights, water_pixels, meta["world_size_meters"])
    print(f"도로 {len(roads):,}, 노반 선분 {len(rows):,}", flush=True)
    tiles = {}
    for i, row in enumerate(rows):
        margin = row[6]+row[7]+1
        lo = np.floor((np.minimum(row[:2], row[3:5])-margin)/CELL).astype(int)
        hi = np.floor((np.maximum(row[:2], row[3:5])+margin)/CELL).astype(int)
        for z in range(lo[1], hi[1]+1):
            for x in range(lo[0], hi[0]+1):
                tiles.setdefault((x,z), []).append(i)
    revision = hashlib.sha256((inputs[vector][2]+inputs[height][2]+inputs[water][2]+"formation_v1").encode()).hexdigest()[:16]
    base = vector.parent/"road_formation"
    folder = base/revision
    folder.mkdir(parents=True, exist_ok=True)
    entries = {}
    for (x,z), indices in tiles.items():
        path = folder/f"{x}_{z}.f32"
        data = rows[indices].tobytes()
        if path.exists() and path.read_bytes()!=data:
            raise RuntimeError("기존 노반 리비전 충돌")
        path.write_bytes(data)
        entries[f"{x},{z}"] = {"file": f"{revision}/{path.name}", "count": len(indices), "sha256": digest(path)}
    for path, state in inputs.items():
        assert (path.stat().st_size, path.stat().st_mtime_ns, digest(path)) == state, "원본 동시 변경"
    index = {"version": 1, "revision": revision, "cell_m": CELL, "record_floats": 9,
             "columns": ["ax","az","ay","bx","bz","by","half_width","shoulder","segment_id"],
             "source_path": "res://"+vector.relative_to(ROOT/"godot_project").as_posix(),
             "source_size": inputs[vector][0], "source_modified": int(vector.stat().st_mtime), "source_sha256": inputs[vector][2],
             "height_source": "res://"+height.relative_to(ROOT/"godot_project").as_posix(), "height_sha256": inputs[height][2],
             "height_size": height.stat().st_size, "height_modified": int(height.stat().st_mtime),
             "water_source": "res://"+water.relative_to(ROOT/"godot_project").as_posix(), "water_sha256": inputs[water][2],
             "water_size": water.stat().st_size, "water_modified": int(water.stat().st_mtime),
             "bbox": meta["bbox"], "world_size_meters": meta["world_size_meters"], "resolution": None,
             "elevation_min": float(rows[:,[2,5]].min()), "elevation_max": float(rows[:,[2,5]].max()),
             "sampling_step_m": 24, "counts": counts, "segments": len(rows), "tiles": entries,
             "status": "generated_roadbed_estimate", "cross_slope": 0, "longitudinal_grade": "source DEM", "source_preserved": True}
    save(base/"index.json", index)
    asset = {"type": "road_formation_planes", "file_path": "res://"+(base/"index.json").relative_to(ROOT/"godot_project").as_posix(),
             "sha256": digest(base/"index.json"), "bbox": meta["bbox"], "resolution": None,
             "elevation_min": index["elevation_min"], "elevation_max": index["elevation_max"],
             "metadata": {"revision": revision, "segments": len(rows), "sampling_step_m": 24, "source_sha256": inputs[vector][2],
                          "height_sha256":inputs[height][2],"water_sha256":inputs[water][2]}}
    save(base/"manifest.json", {"assets": {"index.json": asset}})
    common_path = ROOT/"godot_project/assets/generated/manifest.json"
    before = common_path.read_bytes()
    common = json.loads(before)
    common.setdefault("assets", {})["ulsan_road_formation"] = asset
    assert common_path.read_bytes()==before, "공통 매니페스트 동시 변경"
    save(common_path, common)
    save(ROOT/"results/road_formation/build.json", {k:v for k,v in index.items() if k!="tiles"} | {"tile_count": len(entries), "bytes": sum((base/e["file"]).stat().st_size for e in entries.values())})
    print(f"노반 타일 {len(entries):,}개 저장, 리비전 {revision}", flush=True)


if __name__ == "__main__":
    build()
