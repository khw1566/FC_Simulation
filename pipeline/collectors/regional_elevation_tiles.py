"""공개 Terrarium 고도 타일을 제한된 동시 요청과 재사용 캐시로 수집."""
import io
import math
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from PIL import Image
import numpy as np


class RegionalElevationTiles:
    URL = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'

    def __init__(self, root, zoom=8):
        self.zoom = zoom
        self.cache = Path(root) / 'data/raw/horizon_terrarium' / str(zoom)
        self.cache.mkdir(parents=True, exist_ok=True)
        self.requests = 0

    def tile(self, lon, lat):
        n = 2 ** self.zoom
        return ((lon + 180) / 360 * n,
                (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)

    def fetch(self, coordinate):
        x, y = coordinate
        path = self.cache / f'{x}_{y}.png'
        if not path.exists():
            url = self.URL.format(z=self.zoom, x=x, y=y)
            for attempt in range(3):
                try:
                    request = urllib.request.Request(url, headers={'User-Agent': 'FC-Simulation-Horizon/2'})
                    with urllib.request.urlopen(request, timeout=45) as response:
                        payload = response.read()
                    with Image.open(io.BytesIO(payload)) as image:
                        image.verify()
                    temporary = path.with_suffix('.tmp')
                    temporary.write_bytes(payload)
                    temporary.replace(path)
                    break
                except Exception:
                    if attempt == 2:
                        raise
                    time.sleep(2 ** attempt)
        with Image.open(path) as image:
            rgb = np.asarray(image.convert('RGB'), dtype=np.float32)
        return x, y, rgb[:, :, 0] * 256 + rgb[:, :, 1] + rgb[:, :, 2] / 256 - 32768

    def collect(self, bbox):
        left, top = self.tile(bbox['west'], bbox['north'])
        right, bottom = self.tile(bbox['east'], bbox['south'])
        x0, y0, x1, y1 = math.floor(left), math.floor(top), math.floor(right), math.floor(bottom)
        coordinates = [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]
        self.requests = sum(not (self.cache / f'{x}_{y}.png').exists() for x, y in coordinates)
        mosaic = np.empty(((y1-y0+1)*256, (x1-x0+1)*256), dtype=np.float32)
        with ThreadPoolExecutor(max_workers=4) as pool:
            for i, (x, y, heights) in enumerate(pool.map(self.fetch, coordinates)):
                mosaic[(y-y0)*256:(y-y0+1)*256, (x-x0)*256:(x-x0+1)*256] = heights
                if i % 40 == 0:
                    print(f'고도 타일 {i+1}/{len(coordinates)}', flush=True)
        n = 2 ** self.zoom
        latitude = lambda y: math.degrees(math.atan(math.sinh(math.pi*(1-2*y/n))))
        return mosaic, {'west': x0/n*360-180, 'east': (x1+1)/n*360-180,
                        'north': latitude(y0), 'south': latitude(y1+1)}, len(coordinates)
