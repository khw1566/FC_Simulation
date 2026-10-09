"""안정된 16bit 보정 높이맵에서 경량 파생 자산을 수동 생성한다."""
import argparse
from array import array
import hashlib
import json
import math
import os
import struct
import sys
import zlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def atomic_json(path, value, expected=None):
    if expected is not None and path.read_bytes() != expected:
        raise RuntimeError(f"동시 변경으로 갱신 보류: {path}")
    temp = path.with_name(path.name + f".{os.getpid()}.tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if expected is not None and path.read_bytes() != expected:
        temp.unlink()
        raise RuntimeError(f"동시 변경으로 갱신 보류: {path}")
    os.replace(temp, path)


def build_void_buckets(output, meta):
    """실제 마스크의 모든 유효 픽셀을 포함하는 충돌 검사 공간 인덱스."""
    source = ROOT / "godot_project/assets/generated/railway/tunnel_void.png"
    before = source.stat()
    with Image.open(source) as image:
        blue = image.getchannel("B").point(lambda value: 255 if value > 63 else 0)
        width, height = blue.size
        buckets = []
        for by in range(-79, 79):
            for bx in range(-79, 79):
                x0 = max(0, math.floor((bx * 512 / 80000 + 0.5) * (width - 1)) - 2)
                y0 = max(0, math.floor((by * 512 / 80000 + 0.5) * (height - 1)) - 2)
                x1 = min(width, math.ceil(((bx + 1) * 512 / 80000 + 0.5) * (width - 1)) + 3)
                y1 = min(height, math.ceil(((by + 1) * 512 / 80000 + 0.5) * (height - 1)) + 3)
                if x1 > x0 and y1 > y0 and blue.crop((x0, y0, x1, y1)).getbbox():
                    buckets.append([bx, by])
    source_hash = digest(source)
    after = source.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise RuntimeError("터널 마스크 변경으로 공간 인덱스 생성 보류")
    path = output.parent / f"tunnel_buckets_{source_hash[:16]}.json"
    atomic_json(path, {"bucket_size": 512, "source_size": before.st_size,
                      "source_modified": int(before.st_mtime), "source_sha256": source_hash, "buckets": buckets})
    return {"file_path": "res://" + path.relative_to(ROOT / "godot_project").as_posix(),
            "type": "terrain_collision_spatial_index", "sha256": digest(path),
            "size_bytes": path.stat().st_size, "bbox": meta["bbox"],
            "elevation_min": meta["min_elevation"], "elevation_max": meta["max_elevation"],
            "resolution": [width, height], "metadata": {"source_sha256": source_hash, "bucket_size_m": 512}}


def build(map_id="ulsan_metro_80km"):
    meta_path = ROOT / "godot_project/assets/maps" / map_id / "map_meta.json"
    meta_before = meta_path.read_bytes()
    meta = json.loads(meta_before)
    source = ROOT / "godot_project" / meta["assets"]["heightmap"][6:]
    railway = ROOT / "godot_project/assets/generated/railway/graded_heightmap_16bit.png"
    if map_id == "ulsan_metro_80km" and railway.exists():
        source = railway
    before = source.stat()
    source_hash = digest(source)
    output = ROOT / "godot_project/assets/generated/terrain_quality" / map_id / "light"
    output.mkdir(parents=True, exist_ok=True)
    lock = output / "build.lock"
    descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    try:
        # 해시별 파일을 사용하여 기존 정상 파생 자산을 덮어쓰지 않는다.
        path = output / f"heightmap_{source_hash[:16]}_2816.png"
        with Image.open(source) as image:
            size = (min(2816, image.width), round(image.height * min(2816, image.width) / image.width))
            resized = image.convert("I").resize(size, Image.Resampling.BILINEAR).convert("I;16")
            temp = path.with_name(path.name + f".{os.getpid()}.tmp")
            resized.save(temp, format="PNG")
            os.replace(temp, path)
            preview_path = path
            # Godot의 PNG 로더는 16bit 회색조를 8bit로 읽으므로 RF 데이터를 직접 전달한다.
            pixels = resized.get_flattened_data() if hasattr(resized, "get_flattened_data") else resized.getdata()
            values = array("f", (value / 65535.0 for value in pixels))
            if sys.byteorder != "little":
                values.byteswap()
            path = output / f"heightmap_{source_hash[:16]}_2816.rf32z"
            temp = path.with_name(path.name + f".{os.getpid()}.tmp")
            temp.write_bytes(struct.pack("<II", *size) + zlib.compress(values.tobytes(), 6))
            os.replace(temp, path)
        after = source.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns) or meta_path.read_bytes() != meta_before:
            raise RuntimeError("원본 변경으로 파생 자산 공개를 보류합니다.")
        record = {
            "file_path": "res://" + path.relative_to(ROOT / "godot_project").as_posix(),
            "type": "terrain_quality_heightmap", "quality": "light", "sha256": digest(path),
            "size_bytes": path.stat().st_size, "bbox": meta["bbox"],
            "elevation_min": meta["min_elevation"], "elevation_max": meta["max_elevation"],
            "resolution": list(size),
            "metadata": {"source_path": "res://" + source.relative_to(ROOT / "godot_project").as_posix(),
                         "source_sha256": source_hash, "source_size": before.st_size,
                         "source_modified": int(before.st_mtime), "encoding": "float32_le_normalized_zlib",
                         "resampling": "bilinear", "correction_policy": "원본 보정 유지, 공항은 런타임 재평탄화, 터널 마스크 원본 유지"}
        }
        shared = ROOT / "godot_project/assets/generated/manifest.json"
        shared_before = shared.read_bytes()
        manifest = json.loads(shared_before)
        manifest.setdefault("assets", {})[f"{map_id}_light_heightmap"] = record
        local_assets = {path.name: record}
        preview_record = dict(record, type="terrain_quality_preview", file_path="res://" + preview_path.relative_to(ROOT / "godot_project").as_posix(), sha256=digest(preview_path), size_bytes=preview_path.stat().st_size)
        preview_record["metadata"] = dict(record["metadata"], encoding="uint16_normalized_png")
        manifest["assets"][f"{map_id}_light_heightmap_preview"] = preview_record
        local_assets[preview_path.name] = preview_record
        if map_id == "ulsan_metro_80km":
            buckets = build_void_buckets(output, meta)
            manifest["assets"][f"{map_id}_tunnel_buckets"] = buckets
            local_assets["tunnel_buckets"] = buckets
        atomic_json(shared, manifest, shared_before)
        atomic_json(output / "manifest.json", {"assets": local_assets})
        print(json.dumps({"file": record["file_path"], "size_bytes": record["size_bytes"], "resolution": record["resolution"]}))
    finally:
        os.close(descriptor)
        lock.unlink()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--map-id", default="ulsan_metro_80km")
    build(parser.parse_args().map_id)
