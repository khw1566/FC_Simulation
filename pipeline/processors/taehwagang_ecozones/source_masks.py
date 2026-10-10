"""둔치 지형 생성기의 산출물(높이맵·수면·평탄 둔치 마스크)을 읽기 전용으로 불러온다."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None


class DunchiSourceMasks:
    FILES = {
        "heightmap": "dunchi_heightmap_16bit.png",
        "watermask": "dunchi_watermask_8bit.png",
        "placement_mask": "dunchi_placement_mask_8bit.png",
    }

    def __init__(self, root, folders):
        self.root = Path(root)
        self.folder = self._find(folders)
        self.meta = json.loads((self.folder / "map_meta.json").read_text(encoding="utf-8"))
        self.bbox = self.meta["bbox"]
        self.world_size_m = float(self.meta["world_size_meters"])
        self.low = float(self.meta["min_elevation"])
        self.high = float(self.meta["max_elevation"])

    def _find(self, folders):
        for folder in folders:
            path = (self.root / folder).resolve()
            if all((path / name).exists() for name in self.FILES.values()):
                return path
        raise FileNotFoundError("둔치 지형 산출물이 없습니다. taehwagang_terrain 생성기를 먼저 실행하세요: " + ", ".join(folders))

    def provenance(self):
        result = {"folder": str(self.folder)}
        for key, name in self.FILES.items():
            path = self.folder / name
            result[key] = {"file": name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "size_bytes": path.stat().st_size}
        return result

    def _load(self, key):
        return np.array(Image.open(self.folder / self.FILES[key]))

    def masks(self, size):
        """작업 해상도로 줄인 수면(any)·둔치(과반) 마스크."""
        water = self._load("watermask") > 127
        placeable = self._load("placement_mask") > 127
        return self._reduce(water, size, any_mode=True), self._reduce(placeable, size, any_mode=False)

    @staticmethod
    def _reduce(mask, size, any_mode):
        factor = mask.shape[0] // size
        if factor <= 1:
            return mask
        blocks = mask[: size * factor, : size * factor].reshape(size, factor, size, factor)
        return blocks.any(axis=(1, 3)) if any_mode else blocks.mean(axis=(1, 3)) >= 0.5

    def heights(self):
        raw = self._load("heightmap").astype(np.float32)
        return self.low + raw / 65535.0 * (self.high - self.low)
