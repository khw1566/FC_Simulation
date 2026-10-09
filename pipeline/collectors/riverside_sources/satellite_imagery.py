"""VWorld 위성 영상 WMTS 타일을 지도 격자(위경도 선형)로 정합한다. 키는 로그에 남기지 않는다."""
import io
import math
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import cv2
import numpy as np
import requests
from PIL import Image


class SatelliteImagerySource:
    def __init__(self, root, settings, api_key):
        self.settings = settings
        self.api_key = api_key
        self.zoom = int(settings.get("zoom", 17))
        self.cache = Path(root) / "data/raw/taehwagang_dunchi/satellite" / str(self.zoom)
        self.cache.mkdir(parents=True, exist_ok=True)
        self.requests = 0

    def _pixel(self, lon, lat):
        scale = 256 * 2 ** self.zoom
        return ((lon + 180) / 360 * scale,
                (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * scale)

    def _fetch(self, coord):
        x, y = coord
        path = self.cache / f"{x}_{y}.jpeg"
        if not path.exists():
            url = self.settings["url_template"].format(key=self.api_key, z=self.zoom, x=x, y=y)
            for attempt in range(3):
                try:
                    response = requests.get(url, timeout=30, headers={"User-Agent": "FC-Simulation-Riverside/1"})
                    response.raise_for_status()
                    Image.open(io.BytesIO(response.content)).verify()
                    temporary = path.with_suffix(".tmp")
                    temporary.write_bytes(response.content)
                    temporary.replace(path)
                    self.requests += 1
                    break
                except Exception:
                    if attempt == 2:
                        raise RuntimeError(f"위성 타일 수집 실패: {self.zoom}/{y}/{x}") from None
                    time.sleep(2 ** attempt)
        with Image.open(path) as tile:
            return coord, np.asarray(tile.convert("RGB"))

    def collect(self, bbox, width, height):
        """bbox를 width x height 위경도 선형 RGB 배열로 반환한다. 행 0이 북쪽이다."""
        left, top = self._pixel(bbox["west"], bbox["north"])
        right, bottom = self._pixel(bbox["east"], bbox["south"])
        x0, y0, x1, y1 = int(left // 256), int(top // 256), int(right // 256), int(bottom // 256)
        coords = [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]
        canvas = np.zeros(((y1 - y0 + 1) * 256, (x1 - x0 + 1) * 256, 3), np.uint8)
        with ThreadPoolExecutor(max_workers=int(self.settings.get("max_workers", 6))) as pool:
            for i, ((x, y), tile) in enumerate(pool.map(self._fetch, coords)):
                canvas[(y - y0) * 256:(y - y0 + 1) * 256, (x - x0) * 256:(x - x0 + 1) * 256] = tile
                if i % 200 == 0:
                    print(f"[SatelliteImagerySource] {i + 1}/{len(coords)} 타일", flush=True)
        scale = min(1.0, width / max(right - left, 1.0))
        if scale < 1.0:
            canvas = cv2.resize(canvas, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
        lons = np.linspace(bbox["west"], bbox["east"], width)
        lats = np.linspace(bbox["north"], bbox["south"], height)
        cols = (np.array([self._pixel(lon, bbox["north"])[0] for lon in lons]) - x0 * 256) * scale
        rows = (np.array([self._pixel(bbox["west"], lat)[1] for lat in lats]) - y0 * 256) * scale
        map_x = np.broadcast_to(cols[None, :], (height, width)).astype(np.float32)
        map_y = np.broadcast_to(rows[:, None], (height, width)).astype(np.float32)
        return cv2.remap(canvas, map_x, map_y, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)

    def meta(self):
        return {"source": "vworld_wmts_satellite", "zoom": self.zoom, "new_requests": self.requests}
