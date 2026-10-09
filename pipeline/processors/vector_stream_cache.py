"""큰 벡터 JSON을 제한된 메모리로 읽어 게임용 공간 배치 캐시를 만든다."""
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path


class VectorStreamCache:
    def __init__(self, source, optimizer=None):
        self.source = Path(source)
        # 건물 최적화기를 주면 출력 폴더와 인덱스에 최적화 판을 기록한다.
        self.optimizer = optimizer

    def items(self):
        decoder = json.JSONDecoder()
        with self.source.open(encoding="utf-8-sig") as stream:
            buffer, position, eof = "", 0, False

            def fill():
                nonlocal buffer, position, eof
                buffer = buffer[position:]
                position = 0
                chunk = stream.read(65536)
                eof = not chunk
                buffer += chunk

            def peek():
                nonlocal position
                while True:
                    while position < len(buffer) and buffer[position].isspace():
                        position += 1
                    if position < len(buffer):
                        return buffer[position]
                    if eof:
                        raise ValueError("JSON이 완료되기 전에 파일이 끝났습니다")
                    fill()

            def value():
                nonlocal position
                peek()
                while True:
                    try:
                        result, position = decoder.raw_decode(buffer, position)
                        return result
                    except json.JSONDecodeError:
                        if eof:
                            raise
                        fill()

            assert peek() == "{"
            position += 1
            while peek() != "}":
                key = value()
                assert peek() == ":"
                position += 1
                if peek() == "[":
                    position += 1
                    while peek() != "]":
                        item = value()
                        if key in ("buildings", "roads", "breakwaters"):
                            yield key, item
                        if peek() == ",":
                            position += 1
                        elif peek() != "]":
                            raise ValueError("잘못된 배열 구분자")
                    position += 1
                else:
                    value()
                if peek() == ",":
                    position += 1
                elif peek() != "}":
                    raise ValueError("잘못된 객체 구분자")

    def build(self):
        with self.source.open("rb") as source_file:
            digest = hashlib.file_digest(source_file, "sha256").hexdigest()
        folder_name = digest[:16] if self.optimizer is None else f"{digest[:16]}_b{self.optimizer.VERSION}"
        folder = self.source.parent / "vector_stream" / folder_name
        folder.mkdir(parents=True, exist_ok=True)
        batches, buckets, counts = [], defaultdict(list), defaultdict(int)
        pending = 0

        def flush(key):
            nonlocal pending
            items = buckets.pop(key)
            kind, x, z = key
            name = f"{len(batches):06d}.json"
            raw = json.dumps({kind: items}, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            (folder / name).write_bytes(raw)
            center = [(x + .5) * 1500, (z + .5) * 1500]
            radius = 1100
            if kind == "roads":
                radius = max([math.hypot(p[0] - center[0], p[2] - center[1]) for item in items for p in item.get("points", [])] or [1100])
            batches.append({"kind": kind, "file": f"{folder_name}/{name}", "count": len(items), "center": center, "radius": radius, "sha256": hashlib.sha256(raw).hexdigest()})
            pending -= len(items)

        for kind, item in self.items():
            if kind == "buildings" and self.optimizer is not None:
                item = self.optimizer.optimize(item)
                if item is None:
                    continue
            counts[kind] += 1
            x = z = 0
            if kind == "buildings":
                poly = item.get("polygon", [])
                center = item.get("center", [0, 0, 0])
                px = sum(p[0] for p in poly) / len(poly) if poly else center[0]
                pz = sum(p[1] for p in poly) / len(poly) if poly else center[2]
                x, z = math.floor(px / 1500), math.floor(pz / 1500)
            elif kind == "roads" and item.get("points"):
                points = item["points"]
                x = math.floor(sum(p[0] for p in points) / len(points) / 1500)
                z = math.floor(sum(p[2] for p in points) / len(points) / 1500)
            key = kind, x, z
            buckets[key].append(item)
            pending += 1
            if len(buckets[key]) >= (64 if kind == "buildings" else 8):
                flush(key)
            if pending >= 4096:
                flush(max(buckets, key=lambda k: len(buckets[k])))
        for key in list(buckets):
            flush(key)
        index = {"version": 1, "source_size": self.source.stat().st_size, "source_modified": int(self.source.stat().st_mtime), "source_sha256": digest, "counts": counts, "batches": batches}
        if self.optimizer is not None:
            index["building_optimization"] = {"parameters": self.optimizer.parameters(), "stats": dict(self.optimizer.stats)}
        index_path = folder.parent / "index.json"
        temporary = index_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(index, ensure_ascii=False), encoding="utf-8")
        temporary.replace(index_path)
        self.index_asset(index_path, index)
        print(self.source.parent.name, dict(counts), "batches", len(batches), flush=True)
        return index_path

    def index_asset(self, index_path, index):
        root = Path(__file__).resolve().parents[2]
        meta_path = self.source.parent / "map_meta.json"
        if not meta_path.exists():
            return
        meta = json.loads(meta_path.read_text(encoding="utf-8-sig"))
        entry = {"file_path": "res://" + index_path.relative_to(root / "godot_project").as_posix(), "sha256": hashlib.sha256(index_path.read_bytes()).hexdigest(), "bbox": meta["bbox"], "elevation": {"min_meters": meta["min_elevation"], "max_meters": meta["max_elevation"]}, "resolution": {"type": "spatial_vector_batches", "batches": len(index["batches"]), "counts": index["counts"]}, "metadata": {"source_sha256": index["source_sha256"], "batch_hashes": "각 배치의 SHA-256은 인덱스에 기록"}}
        if "building_optimization" in index:
            entry["metadata"]["building_optimization"] = index["building_optimization"]
        for path in [self.source.parent / "manifest.json", root / "godot_project/assets/generated/manifest.json"]:
            before = path.read_bytes() if path.exists() else None
            document = json.loads(before.decode("utf-8-sig")) if before is not None else {"assets": {}}
            document.setdefault("assets", {})[meta["id"] + "_vector_stream"] = entry
            temp = path.with_suffix(".tmp")
            temp.write_text(json.dumps(document, ensure_ascii=False, indent=2), encoding="utf-8")
            # 다른 작업이 같은 매니페스트를 고친 경우 덮어쓰지 않는다.
            if (path.read_bytes() if path.exists() else None) != before:
                temp.unlink()
                raise RuntimeError(f"동시 변경으로 매니페스트 갱신 보류: {path}")
            temp.replace(path)


if __name__ == "__main__":
    import sys
    root = Path(__file__).resolve().parents[2]
    from building_optimizer import BuildingOptimizer
    for name in sys.argv[1:] or ["ulsan_metro_80km", "southeast_mega_140km"]:
        VectorStreamCache(root / "godot_project/assets/maps" / name / "buildings_and_roads.json", BuildingOptimizer()).build()

