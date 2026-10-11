"""식생을 놓으면 안 되는 곳(차도·건물·수면)을 작업 격자 제외 마스크로 만든다.

- 게임 지도 자료: 표시 지도(울산 80km)의 buildings_and_roads.json 건물 다각형·도로 중심선(폭 포함)과
  수면 마스크를 위경도로 바꿔 그린다. 게임에 실제로 그려지는 도로·건물·강과 겹치지 않게 하기 위함이다.
- OSM 차도: 게임 자료에 없는 생활도로까지 막기 위해 차량 통행 도로를 등급별 폭으로 더한다.
- 원천 둔치 지도의 수면 마스크도 함께 막는다.
게임 자료 원본(수백 MB)은 대상 bbox만 잘라 캐시한다.
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

Image.MAX_IMAGE_PIXELS = None

# OSM 차도 등급별 기본 전체 폭(m). 차선 정보가 있으면 차선당 3.3m로 대체한다.
OSM_ROAD_WIDTH_M = {
    "motorway": 22.0, "trunk": 18.0, "primary": 16.0, "secondary": 13.0, "tertiary": 10.0,
    "unclassified": 7.0, "residential": 7.0, "living_street": 5.0, "service": 5.0,
    "motorway_link": 8.0, "trunk_link": 8.0, "primary_link": 8.0, "secondary_link": 7.0, "tertiary_link": 7.0,
}


class ObstacleMask:
    def __init__(self, root, raster, settings):
        self.root = Path(root)
        self.raster = raster
        self.settings = settings
        self.scale = 2  # 2배 해상도로 그린 뒤 any로 줄여 가는 도로를 놓치지 않는다.
        self.stats = {}

    def build(self, source_water, osm_roads):
        size = self.raster.size * self.scale
        image = Image.new("L", (size, size), 0)
        draw = ImageDraw.Draw(image)
        margin = float(self.settings.get("margin_m", 2.0))
        for game in self.settings.get("game_maps", []):
            self._draw_game_map(draw, game, margin)
        self._draw_osm_roads(draw, osm_roads, margin)
        drawn = np.array(image) > 0
        blocked = drawn.reshape(self.raster.size, self.scale, self.raster.size, self.scale).any(axis=(1, 3))
        for game in self.settings.get("game_maps", []):
            blocked |= self._game_water(game)
        blocked |= source_water
        self.stats["blocked_area_m2"] = round(float(blocked.sum()) * self.raster.cell_m ** 2, 1)
        return blocked

    # --- 좌표 변환 ---
    def _px(self, lat, lon):
        u, v = self.raster.to_pixel(lat, lon)
        return u * self.scale + (self.scale - 1) / 2.0, v * self.scale + (self.scale - 1) / 2.0

    def _game_to_px(self, meta, x, z):
        b = meta["bbox"]
        size = float(meta["world_size_meters"])
        lon = b["west"] + (x / size + 0.5) * (b["east"] - b["west"])
        lat = b["north"] - (z / size + 0.5) * (b["north"] - b["south"])
        return self._px(lat, lon)

    def _width_px(self, width_m):
        return max(1, int(round(width_m / self.raster.cell_m * self.scale)))

    # --- 게임 지도 도로·건물 ---
    def _draw_game_map(self, draw, game, margin):
        folder = self.root / game["folder"]
        meta = json.loads((folder / "map_meta.json").read_text(encoding="utf-8"))
        data = self._game_cache(game, folder, meta)
        for road in data["roads"]:
            points = [self._game_to_px(meta, p[0], p[1]) for p in road["points"]]
            if len(points) >= 2:
                draw.line(points, fill=255, width=self._width_px(float(road["width"]) + 2 * margin), joint="curve")
        for polygon in data["buildings"]:
            points = [self._game_to_px(meta, p[0], p[1]) for p in polygon]
            if len(points) >= 3:
                draw.polygon(points, fill=255, outline=255, width=self._width_px(2 * margin))
        self.stats[game["folder"]] = {"roads": len(data["roads"]), "buildings": len(data["buildings"])}

    def _game_cache(self, game, folder, meta):
        cache = self.root / "data/raw/taehwagang_ecozones" / f"game_obstacles_{meta['id']}.json"
        source = folder / game.get("obstacles_file", "buildings_and_roads.json")
        stamp = {"size": source.stat().st_size, "mtime": int(source.stat().st_mtime), "bbox": self.raster.bbox}
        if cache.exists():
            cached = json.loads(cache.read_text(encoding="utf-8"))
            if cached.get("source") == stamp:
                return cached
        full = json.loads(source.read_text(encoding="utf-8"))
        x0, x1, z0, z1 = self._game_window(meta)
        inside = lambda x, z: x0 <= x <= x1 and z0 <= z <= z1
        roads = [{"width": r.get("width", 8.0), "points": [[p[0], p[2]] for p in r["points"]]}
                 for r in full.get("roads", []) if not r.get("tunnel") and any(inside(p[0], p[2]) for p in r["points"])]
        buildings = [b["polygon"] for b in full.get("buildings", []) if b.get("polygon") and inside(b["center"][0], b["center"][2])]
        data = {"source": stamp, "roads": roads, "buildings": buildings}
        cache.parent.mkdir(parents=True, exist_ok=True)
        temporary = cache.with_suffix(".tmp")
        temporary.write_text(json.dumps(data), encoding="utf-8")
        temporary.replace(cache)
        return data

    def _game_window(self, meta):
        b, s = meta["bbox"], self.raster.bbox
        size = float(meta["world_size_meters"])
        to_x = lambda lon: ((lon - b["west"]) / (b["east"] - b["west"]) - 0.5) * size
        to_z = lambda lat: ((b["north"] - lat) / (b["north"] - b["south"]) - 0.5) * size
        pad = 100.0
        return to_x(s["west"]) - pad, to_x(s["east"]) + pad, to_z(s["north"]) - pad, to_z(s["south"]) + pad

    def _game_water(self, game):
        folder = self.root / game["folder"]
        meta = json.loads((folder / "map_meta.json").read_text(encoding="utf-8"))
        path = meta.get("assets", {}).get("watermask", "")
        local = self.root / "godot_project" / path.replace("res://", "") if path else None
        if local is None or not local.exists():
            return np.zeros((self.raster.size, self.raster.size), dtype=bool)
        mask = np.array(Image.open(local).convert("L")) > int(self.settings.get("water_threshold", 96))
        b, s = meta["bbox"], self.raster.bbox
        n = self.raster.size
        lon = s["west"] + np.arange(n) / (n - 1) * (s["east"] - s["west"])
        lat = s["north"] - np.arange(n) / (n - 1) * (s["north"] - s["south"])
        u = np.clip(np.rint((lon - b["west"]) / (b["east"] - b["west"]) * (mask.shape[1] - 1)).astype(int), 0, mask.shape[1] - 1)
        v = np.clip(np.rint((b["north"] - lat) / (b["north"] - b["south"]) * (mask.shape[0] - 1)).astype(int), 0, mask.shape[0] - 1)
        water = mask[v[:, None], u[None, :]]
        self.stats[game["folder"] + "_water_m2"] = round(float(water.sum()) * self.raster.cell_m ** 2, 1)
        return water

    # --- OSM 차도 ---
    def _draw_osm_roads(self, draw, osm_roads, margin):
        count = 0
        for element in osm_roads.get("elements", []):
            tags = element.get("tags", {})
            kind = tags.get("highway")
            if kind not in OSM_ROAD_WIDTH_M or tags.get("tunnel") in ("yes", "building_passage"):
                continue
            width = OSM_ROAD_WIDTH_M[kind]
            try:
                width = max(width * 0.6, float(tags.get("lanes", 0)) * 3.3) if tags.get("lanes") else width
            except ValueError:
                pass
            points = [self._px(p["lat"], p["lon"]) for p in element.get("geometry", [])]
            if len(points) >= 2:
                draw.line(points, fill=255, width=self._width_px(width + 2 * margin), joint="curve")
                count += 1
        self.stats["osm_roads"] = count
