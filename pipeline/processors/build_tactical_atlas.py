"""울산 M 지도용 등고선·수계·주요도로 합성 자산 생성."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


class TacticalAtlasBuilder:
    ROOT = Path(__file__).resolve().parents[2]
    SIZE = 3072

    @staticmethod
    def read(path):
        return json.loads(path.read_text(encoding="utf-8-sig"))

    @staticmethod
    def write(path, data):
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    def resolve(self, uri):
        return self.ROOT / "godot_project" / uri.removeprefix("res://")

    def build(self, map_id):
        folder = self.ROOT / "godot_project/assets/maps" / map_id
        meta = self.read(folder / "map_meta.json")
        n = self.SIZE
        height = np.asarray(Image.open(self.resolve(meta["assets"]["heightmap"])).convert("F").resize((n, n), Image.Resampling.BILINEAR)) / 65535
        height = meta["min_elevation"] + height * (meta["max_elevation"] - meta["min_elevation"])
        water = np.asarray(Image.open(self.resolve(meta["assets"]["watermask"])).convert("L").resize((n, n), Image.Resampling.BILINEAR)) / 255
        dy, dx = np.gradient(height)
        shade = np.clip(231 - dx * 0.9 - dy * 0.7 - height * 0.015, 197, 245)
        bands = np.floor(height / 50)
        contours = np.zeros((n, n), dtype=bool)
        contours[1:] |= bands[1:] != bands[:-1]
        contours[:, 1:] |= bands[:, 1:] != bands[:, :-1]
        shade[contours & (water < 0.35) & (height > 5)] = 173
        # 얇은 하천도 마스크의 부분 피복을 유지한다.
        shade = shade * (1 - water) + 105 * water
        pixels = Image.fromarray(shade.astype(np.uint8)).convert("RGB")
        draw = ImageDraw.Draw(pixels)
        roads = self.read(self.resolve(meta["assets"]["buildings_roads"]))["roads"]
        widths = {"motorway": 5, "trunk": 4, "primary": 3, "secondary": 2}
        selected = [road for road in roads if road.get("type", "").removesuffix("_link") in widths]
        for casing in (True, False):
            for road in selected:
                points = [((p[0] / meta["world_size_meters"] + 0.5) * (n - 1), (p[2] / meta["world_size_meters"] + 0.5) * (n - 1)) for p in road["points"]]
                if len(points) > 1:
                    width = widths[road["type"].removesuffix("_link")]
                    draw.line(points, fill=(248, 248, 248) if casing else (44, 44, 44), width=width + 2 if casing else width, joint="curve")
        output = folder / "tactical_atlas.png"
        pixels.save(output)
        uri = f"res://assets/maps/{map_id}/tactical_atlas.png"
        meta["assets"]["tactical_map"] = uri
        meta["tactical_atlas"] = {"contour_interval_m": 50, "road_count": len(selected), "water_source": meta["assets"]["watermask"], "detail_note": "도로는 기존 수집 범위에 한함"}
        self.write(folder / "map_meta.json", meta)
        entry = {"file_path": uri, "sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "size_bytes": output.stat().st_size, "bbox": meta["bbox"], "elevation": {"min_meters": meta["min_elevation"], "max_meters": meta["max_elevation"]}, "resolution": {"width": n, "height": n}, "metadata": meta["tactical_atlas"]}
        for manifest_path in (folder / "manifest.json", self.ROOT / "godot_project/assets/generated/manifest.json"):
            manifest = self.read(manifest_path)
            key = "tactical_atlas.png" if manifest_path.parent == folder else f"{map_id}/tactical_atlas.png"
            manifest["assets"][key] = entry
            for item in manifest["assets"].values():
                if item.get("file_path") == f"res://assets/maps/{map_id}/map_meta.json":
                    item["sha256"] = hashlib.sha256((folder / "map_meta.json").read_bytes()).hexdigest()
                    item["size_bytes"] = (folder / "map_meta.json").stat().st_size
            self.write(manifest_path, manifest)
        print(f"{map_id}: {len(selected)} roads", flush=True)


if __name__ == "__main__":
    builder = TacticalAtlasBuilder()
    for name in ("ulsan_metro_80km"):
        builder.build(name)

