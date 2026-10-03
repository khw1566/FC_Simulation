"""칸몬 범위의 GSI 최대 상세도 건물 폴리곤을 수집한다."""
import gzip
import json
import math
from functools import lru_cache
from pathlib import Path
import mapbox_vector_tile
from pmtiles.reader import Reader
from pmtiles.tile import zxy_to_tileid, deserialize_directory, find_tile
from pmtiles_range_source import PMTilesRangeSource


class GsiBuildingCollector:
    ROOT = Path(__file__).resolve().parents[2]
    URL = "https://cyberjapandata.gsi.go.jp/xyz/optimal_bvmap-v1/optimal_bvmap-v1.pmtiles"

    def __init__(self):
        self.source = PMTilesRangeSource(self.URL, self.ROOT / "data/raw/buildings/gsi_range_cache")
        self.reader = Reader(self.source)
        self.header = self.reader.header()

    @lru_cache(maxsize=64)
    def directory(self, offset, length):
        return deserialize_directory(self.source(offset, length))

    def tile(self, z, x, y):
        tile_id = zxy_to_tileid(z, x, y)
        offset, length = self.header["root_offset"], self.header["root_length"]
        for _ in range(4):
            entry = find_tile(self.directory(offset, length), tile_id)
            if entry is None:
                return None
            if entry.run_length:
                data = self.source(self.header["tile_data_offset"] + entry.offset, entry.length)
                return gzip.decompress(data) if data[:2] == b"\x1f\x8b" else data
            offset = self.header["leaf_directory_offset"] + entry.offset
            length = entry.length
        raise RuntimeError("PMTiles 인덱스 깊이 오류")

    @staticmethod
    def tile_xy(lon, lat, z):
        n = 2 ** z
        return int((lon + 180) / 360 * n), int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)

    @staticmethod
    def geo(point, x, y, z, extent):
        n = 2 ** z
        lon = (x + point[0] / extent) / n * 360 - 180
        lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + point[1] / extent) / n))))
        return [lon, lat]

    def run(self, probe=False):
        config = json.loads((self.ROOT / "config/kanmon_region.json").read_text(encoding="utf-8-sig"))
        bbox = config["bbox"]
        z = 16
        west, north = self.tile_xy(bbox["west"], bbox["north"], z)
        east, south = self.tile_xy(bbox["east"], bbox["south"], z)
        tiles = [(x, y) for x in range(west, east+1) for y in range(north, south+1)]
        if probe:
            tiles = [self.tile_xy(130.88, 33.885, z)]
        records = []
        total = len(tiles)
        for index, (x, y) in enumerate(tiles):
            data = self.tile(z, x, y)
            if not data:
                continue
            layers = mapbox_vector_tile.decode(data, default_options={"y_coord_down": True})
            if probe:
                print({name: {"count": len(layer["features"]), "sample": layer["features"][:1]} for name, layer in layers.items() if name == "BldA"}, flush=True)
                print("layers", list(layers), "tiles_required", (east-west+1)*(south-north+1), flush=True)
                continue
            for name, layer in layers.items():
                if name != "BldA":
                    continue
                for feature in layer["features"]:
                    geometry = feature["geometry"]
                    if geometry["type"] not in ("Polygon", "MultiPolygon"):
                        continue
                    polygons = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
                    for polygon in polygons:
                        rings = [[self.geo(p, x, y, z, layer["extent"]) for p in ring] for ring in polygon]
                        records.append({"tile": [z, x, y], "properties": feature["properties"], "rings": rings})
            if index % 100 == 0:
                print(f"GSI {index+1}/{total}, polygons={len(records)}, HTTP={self.source.calls}", flush=True)
        if not probe:
            output = self.ROOT / "data/raw/buildings/kanmon_gsi_buildings_20261003.json"
            output.write_text(json.dumps({"source": self.URL, "zoom": z, "bbox": bbox, "tiles": total, "buildings": records}, separators=(",", ":")), encoding="utf-8")
            print(f"GSI 완료: {len(records)}개 폴리곤 / {total}타일", flush=True)
        self.source.save_metrics(self.ROOT / "results/261003_gsi_building_http_metrics.json")


if __name__ == "__main__":
    import sys
    GsiBuildingCollector().run("--probe" in sys.argv)

