"""브이월드 영상 타일을 캠퍼스 작업 구역에 정합한다. 키는 로그에 남기지 않는다."""
import io
import json
import math
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import Request, urlopen
from PIL import Image


class CampusImageryCollector:
    def __init__(self, root: Path):
        self.root = root
        self.zoom = 17
        self.bbox = {"west": 129.246116, "east": 129.262676,
                     "north": 35.55215, "south": 35.53685}

    def pixel(self, lon, lat):
        scale = 256 * 2 ** self.zoom
        return ((lon + 180) / 360 * scale,
                (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * scale)

    def run(self):
        key = json.loads((self.root / "data/api_keys.json").read_text(encoding="utf-8"))["vworld_api_key"]
        left, top = self.pixel(self.bbox["west"], self.bbox["north"])
        right, bottom = self.pixel(self.bbox["east"], self.bbox["south"])
        x0, y0, x1, y1 = int(left // 256), int(top // 256), int(right // 256), int(bottom // 256)
        cache = self.root / "data/raw/ulsan_uc_west/imagery"
        cache.mkdir(parents=True, exist_ok=True)

        def fetch(coord):
            x, y = coord
            path = cache / f"{self.zoom}_{x}_{y}.jpeg"
            if path.exists():
                return coord, Image.open(path).convert("RGB")
            url = f"https://api.vworld.kr/req/wmts/1.0.0/{key}/Satellite/{self.zoom}/{y}/{x}.jpeg"
            try:
                with urlopen(Request(url, headers={"User-Agent": "CampusModelReference/1.0"}), timeout=20) as response:
                    content = response.read()
                tile = Image.open(io.BytesIO(content)).convert("RGB")
                tile.load()
                path.write_bytes(content)
                return coord, tile
            except Exception:
                raise RuntimeError(f"영상 타일 수집 실패: {self.zoom}/{y}/{x}") from None

        canvas = Image.new("RGB", ((x1-x0+1)*256, (y1-y0+1)*256))
        coords = [(x,y) for y in range(y0,y1+1) for x in range(x0,x1+1)]
        with ThreadPoolExecutor(max_workers=6) as executor:
            for (x,y), tile in executor.map(fetch, coords):
                canvas.paste(tile, ((x-x0)*256,(y-y0)*256))
        # 메르카토르 타일을 지도에서 사용하는 위경도 선형 축으로 재표본화한다.
        output = Image.new("RGB", (2048,2048))
        for row in range(2048):
            lat = self.bbox["north"] - row / 2047 * (self.bbox["north"]-self.bbox["south"])
            _, py = self.pixel(self.bbox["west"], lat)
            strip = canvas.crop((left-x0*256,py-y0*256,right-x0*256,py-y0*256+1))
            output.paste(strip.resize((2048,1),Image.Resampling.BILINEAR),(0,row))
        folder = self.root / "godot_project/assets/maps/ulsan_uc_west"
        output.save(folder / "campus_imagery.png")
        metadata = {"source": "VWorld Satellite WMTS", "zoom": self.zoom,
                    "tile_count": len(coords), "bbox": self.bbox, "resolution": [2048,2048],
                    "world_rect_xz": [-850,-850,1500,1700], "capture_date": "unknown",
                    "native_pixel_spacing_approx_m": 0.97,
                    "purpose": "local_modeling_reference", "attribution": "국토교통부 브이월드"}
        (folder / "campus_imagery.json").write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding="utf-8")
        print(f"CAMPUS_IMAGERY_TILES={len(coords)}")
        import sys
        sys.path.insert(0, str(self.root))
        from pipeline.indexer.campus_art_asset_indexer import CampusArtAssetIndexer
        CampusArtAssetIndexer(self.root).run()


if __name__ == "__main__":
    CampusImageryCollector(Path(__file__).resolve().parents[2]).run()
