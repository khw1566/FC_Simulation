import os
import json
import numpy as np
import cv2
from PIL import Image

class TerrainTileProcessor:
    """
    광역 고해상도 DEM 또는 국소 DEM을 타일 그리드로 분할(Tiling)하고
    타일별 16비트 정규화 높이맵 및 LOD 타일을 내보내는 엔진
    """
    def __init__(self, config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)

    def slice_dem_to_tiles(self, dem_tiff_path, output_tiles_dir, tiles_x=4, tiles_y=4, tile_res=1024):
        """
        입력 DEM TIFF를 tiles_x * tiles_y 개수의 16-bit PNG 타일로 분할하여 저장
        """
        os.makedirs(output_tiles_dir, exist_ok=True)
        print(f"[TerrainTileProcessor] Loading DEM for tiling: {dem_tiff_path}")
        
        with Image.open(dem_tiff_path) as img:
            dem_data = np.array(img, dtype=np.float32)

        # NoData 필터링
        dem_data[dem_data < -100.0] = 0.0

        min_elev = self.config["elevation_range"]["min_meters"]
        max_elev = self.config["elevation_range"]["max_meters"]

        clamped = np.clip(dem_data, min_elev, max_elev)
        normalized = (clamped - min_elev) / (max_elev - min_elev)
        u16_full = (normalized * 65535.0).astype(np.uint16)

        h, w = u16_full.shape
        tile_w = w // tiles_x
        tile_h = h // tiles_y

        manifest_tiles = []

        print(f"[TerrainTileProcessor] Splitting {w}x{h} DEM into {tiles_x}x{tiles_y} tiles (Resized to {tile_res}x{tile_res})...")

        for ty in range(tiles_y):
            for tx in range(tiles_x):
                x0 = tx * tile_w
                y0 = ty * tile_h
                x1 = (tx + 1) * tile_w if tx < tiles_x - 1 else w
                y1 = (ty + 1) * tile_h if ty < tiles_y - 1 else h

                tile_crop = u16_full[y0:y1, x0:x1]
                
                # 지정된 타일 해상도로 업스케일/리샘플링 (LANCZOS/CUBIC)
                if tile_crop.shape[0] != tile_res or tile_crop.shape[1] != tile_res:
                    tile_crop = cv2.resize(tile_crop, (tile_res, tile_res), interpolation=cv2.INTER_CUBIC)

                tile_filename = f"tile_{tx}_{ty}.png"
                tile_filepath = os.path.join(output_tiles_dir, tile_filename)

                out_img = Image.fromarray(tile_crop, mode='I;16')
                out_img.save(tile_filepath)

                manifest_tiles.append({
                    "tile_x": tx,
                    "tile_y": ty,
                    "file_name": tile_filename,
                    "width": tile_res,
                    "height": tile_res
                })

        tile_meta_path = os.path.join(output_tiles_dir, "tiles_index.json")
        with open(tile_meta_path, "w", encoding="utf-8") as f:
            json.dump({
                "tiles_x": tiles_x,
                "tiles_y": tiles_y,
                "tile_res": tile_res,
                "min_meters": min_elev,
                "max_meters": max_elev,
                "tiles": manifest_tiles
            }, f, indent=2)

        print(f"[TerrainTileProcessor] Successfully created {len(manifest_tiles)} tiles in {output_tiles_dir}")
        return tile_meta_path
