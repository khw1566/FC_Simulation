"""VWorld 3D 지형(DEM) 타일 수집기.

XDServer `Layer=dem` 노드는 레벨 0 타일 폭 36도에서 레벨마다 절반으로 나뉘며,
각 노드는 65x65 little-endian float32 표고(미터)를 담는다. 행 순서는 문서화가
부족하므로 수집 결과를 공개 고도와 비교해 방향을 확정한다(`orientation_check`).
"""
import math
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import requests


class VworldDemSource:
    name = "vworld_dem"

    def __init__(self, root, settings, api_key):
        self.settings = settings
        self.api_key = api_key
        self.level = int(settings.get("level", 14))
        self.samples = int(settings.get("samples_per_tile", 65))
        self.unit = 36.0 / (2 ** self.level)
        self.cache = Path(root) / "data/raw/taehwagang_dunchi/vworld_dem" / str(self.level)
        self.cache.mkdir(parents=True, exist_ok=True)
        self.requests = 0

    def _index(self, lon, lat):
        return math.floor((lon + 180.0) / self.unit), math.floor((lat + 90.0) / self.unit)

    def _fetch(self, key):
        idx, idy = key
        path = self.cache / f"{idx}_{idy}.bil"
        expected = self.samples * self.samples * 4
        if not path.exists() or path.stat().st_size != expected:
            url = self.settings["url_template"].format(key=self.api_key, level=self.level, idx=idx, idy=idy)
            for attempt in range(3):
                try:
                    response = requests.get(url, timeout=45, headers={"User-Agent": "FC-Simulation-Riverside/1"})
                    response.raise_for_status()
                    if len(response.content) != expected:
                        raise ValueError(f"DEM 노드 크기 불일치 {idx},{idy}: {len(response.content)} bytes")
                    temporary = path.with_suffix(".tmp")
                    temporary.write_bytes(response.content)
                    temporary.replace(path)
                    break
                except (requests.RequestException, ValueError):
                    if attempt == 2:
                        raise
                    time.sleep(2 ** attempt)
        data = np.frombuffer(path.read_bytes(), dtype="<f4").reshape(self.samples, self.samples)
        return key, data

    def plan(self, bbox):
        x0, y0 = self._index(bbox["west"], bbox["south"])
        x1, y1 = self._index(bbox["east"], bbox["north"])
        keys = [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]
        missing = sum(not (self.cache / f"{x}_{y}.bil").exists() for x, y in keys)
        return keys, missing

    def collect(self, bbox, north_first=True):
        """bbox를 덮는 표고 모자이크와 경위도 범위를 반환한다. 행 0이 북쪽이다."""
        keys, missing = self.plan(bbox)
        limit = int(self.settings.get("daily_request_limit", 2500))
        if missing > limit:
            raise RuntimeError(f"VWorld DEM 신규 요청 {missing}건이 일일 한도 설정 {limit}건을 넘습니다. level을 낮추거나 나눠 수집하세요.")
        self.requests = missing
        xs = sorted({k[0] for k in keys})
        ys = sorted({k[1] for k in keys})
        step = self.samples - 1
        mosaic = np.zeros((len(ys) * step + 1, len(xs) * step + 1), dtype=np.float32)
        with ThreadPoolExecutor(max_workers=int(self.settings.get("max_workers", 4))) as pool:
            for i, ((idx, idy), data) in enumerate(pool.map(self._fetch, keys)):
                tile = data if north_first else data[::-1]
                row = (ys[-1] - idy) * step
                col = (idx - xs[0]) * step
                mosaic[row:row + self.samples, col:col + self.samples] = tile
                if i % 100 == 0:
                    print(f"[VworldDemSource] {i + 1}/{len(keys)} 노드", flush=True)
        extent = {
            "west": xs[0] * self.unit - 180.0,
            "east": (xs[-1] + 1) * self.unit - 180.0,
            "south": ys[0] * self.unit - 90.0,
            "north": (ys[-1] + 1) * self.unit - 90.0,
        }
        return mosaic, extent

    def meta(self):
        return {"source": self.name, "level": self.level, "node_degrees": self.unit,
                "sample_spacing_degrees": self.unit / (self.samples - 1), "new_requests": self.requests}
