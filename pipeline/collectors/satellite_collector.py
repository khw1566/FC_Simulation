import os
import json
import math
import time
import requests
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

class SatelliteCollector:
    """
    일본 국토지리원(GSI Seamlessphoto) 항공/위성 영상 타일을 일괄 수집하여
    지리 정합(Geo-referenced) 4096x4096 크기의 광역 고해상도 RGB 정사 영상을 합성하는 수집기
    """
    BASE_URL = "https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/{z}/{x}/{y}.jpg"

    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)
        self.bbox = self.config["bbox"]
        self.region_name = self.config.get("region_name", "kanmon_straits")

    @staticmethod
    def _deg2num(lat_deg, lon_deg, zoom):
        lat_rad = math.radians(lat_deg)
        n = 2.0 ** zoom
        xtile = int((lon_deg + 180.0) / 360.0 * n)
        ytile = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
        return xtile, ytile

    @staticmethod
    def _num2deg(xtile, ytile, zoom):
        n = 2.0 ** zoom
        lon_deg = xtile / n * 360.0 - 180.0
        lat_rad = math.atan(math.sinh(math.pi * (1.0 - 2.0 * ytile / n)))
        lat_deg = math.degrees(lat_rad)
        return lat_deg, lon_deg

    def fetch_satellite_mosaic(self, output_dir, zoom=13, target_res=(4096, 4096)):
        os.makedirs(output_dir, exist_ok=True)
        mosaic_path = os.path.join(output_dir, f"{self.region_name}_satellite_rgb.png")

        if os.path.exists(mosaic_path) and os.path.getsize(mosaic_path) > 100000:
            print(f"[SatelliteCollector] Existing satellite mosaic found: {mosaic_path}")
            return mosaic_path

        # BBox에 해당하는 타일 x, y 범위 계산
        x_min, y_min = self._deg2num(self.bbox["north"], self.bbox["west"], zoom)
        x_max, y_max = self._deg2num(self.bbox["south"], self.bbox["east"], zoom)

        if x_min > x_max:
            x_min, x_max = x_max, x_min
        if y_min > y_max:
            y_min, y_max = y_max, y_min

        x_count = x_max - x_min + 1
        y_count = y_max - y_min + 1
        print(f"[SatelliteCollector] Fetching {x_count}x{y_count} ({x_count * y_count} tiles) at Zoom {zoom}...")

        tile_cache_dir = os.path.join(output_dir, f"tiles_z{zoom}")
        os.makedirs(tile_cache_dir, exist_ok=True)

        tiles_tasks = []
        for ty in range(y_min, y_max + 1):
            for tx in range(x_min, x_max + 1):
                tiles_tasks.append((tx, ty))

        def download_tile(coord):
            tx, ty = coord
            t_file = os.path.join(tile_cache_dir, f"{tx}_{ty}.jpg")
            if os.path.exists(t_file) and os.path.getsize(t_file) > 500:
                return coord, t_file

            url = self.BASE_URL.format(z=zoom, x=tx, y=ty)
            for attempt in range(3):
                try:
                    res = requests.get(url, timeout=15)
                    if res.status_code == 200:
                        with open(t_file, "wb") as f:
                            f.write(res.content)
                        return coord, t_file
                except Exception:
                    time.sleep(0.5)
            return coord, None

        downloaded = {}
        with ThreadPoolExecutor(max_workers=8) as executor:
            results = executor.map(download_tile, tiles_tasks)
            for coord, t_file in results:
                if t_file:
                    downloaded[coord] = t_file

        print(f"[SatelliteCollector] Downloaded {len(downloaded)} / {len(tiles_tasks)} tiles. Stitching mosaic...")

        # 256x256 타일 합성
        full_w = x_count * 256
        full_h = y_count * 256
        canvas = Image.new("RGB", (full_w, full_h), (30, 40, 50))

        for (tx, ty), t_file in downloaded.items():
            px = (tx - x_min) * 256
            py = (ty - y_min) * 256
            try:
                with Image.open(t_file) as tile_img:
                    canvas.paste(tile_img, (px, py))
            except Exception as e:
                print(f"[SatelliteCollector] Failed to paste tile {tx}_{ty}: {e}")

        # 전체 타일 캔버스 영역의 위경도 범위
        top_lat, left_lon = self._num2deg(x_min, y_min, zoom)
        bot_lat, right_lon = self._num2deg(x_max + 1, y_max + 1, zoom)

        # 프로젝트 BBox에 맞게 정확히 크롭
        frac_left = (self.bbox["west"] - left_lon) / (right_lon - left_lon)
        frac_right = (self.bbox["east"] - left_lon) / (right_lon - left_lon)
        frac_top = (top_lat - self.bbox["north"]) / (top_lat - bot_lat)
        frac_bot = (top_lat - self.bbox["south"]) / (top_lat - bot_lat)

        crop_x0 = int(np_clip(frac_left * full_w, 0, full_w - 1))
        crop_x1 = int(np_clip(frac_right * full_w, crop_x0 + 1, full_w))
        crop_y0 = int(np_clip(frac_top * full_h, 0, full_h - 1))
        crop_y1 = int(np_clip(frac_bot * full_h, crop_y0 + 1, full_h))

        cropped_img = canvas.crop((crop_x0, crop_y0, crop_x1, crop_y1))
        final_img = cropped_img.resize(target_res, Image.Resampling.LANCZOS)
        final_img.save(mosaic_path, format="PNG")
        print(f"[SatelliteCollector] Saved cropped satellite mosaic: {mosaic_path} ({target_res[0]}x{target_res[1]})")
        return mosaic_path

def np_clip(val, v_min, v_max):
    return max(v_min, min(v_max, val))
