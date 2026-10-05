"""광역 고도 자료를 원경 전용 부동소수 래스터와 GPU 해안 표본으로 변환."""
import hashlib
from pathlib import Path
import sys
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'collectors'))
from regional_elevation_tiles import RegionalElevationTiles


class RegionalHorizonAtlas:
    def build(self, root, settings):
        collector = RegionalElevationTiles(root, settings['regional_zoom'])
        values, bbox, tiles = collector.collect(settings['regional_bbox'])
        n = settings['regional_resolution']
        # 원본 Web Mercator 격자를 유지한다. 위경도 선형 격자로 잘못 해석하지 않는다.
        heights = np.asarray(Image.fromarray(values).resize((n, n), Image.Resampling.BILINEAR), dtype='<f4')
        folder = root / 'godot_project/assets/generated/horizon'
        folder.mkdir(parents=True, exist_ok=True)
        binary = folder / 'regional_height.f32'
        temporary = binary.with_suffix('.tmp')
        temporary.write_bytes(heights.tobytes())
        temporary.replace(binary)
        encoded = np.clip(np.rint(heights + 32768), 0, 65535).astype(np.uint16)
        texture = np.zeros((n, n, 3), dtype=np.uint8)
        texture[:, :, 0] = encoded >> 8
        texture[:, :, 1] = encoded & 255
        Image.fromarray(texture).save(folder / 'regional_height_rgb.png')
        return {'bbox': bbox, 'projection': 'EPSG:3857', 'resolution': n,
                'height_file': 'res://assets/generated/horizon/regional_height.f32',
                'height_texture': 'res://assets/generated/horizon/regional_height_rgb.png',
                'encoding': 'little-endian float32 meters, row-major',
                'texture_encoding': 'R*65280+G*255-32768 meters',
                'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                'elevation_min': float(heights.min()), 'elevation_max': float(heights.max()),
                'source_zoom': collector.zoom, 'tile_count': tiles, 'new_requests': collector.requests,
                'attribution': 'Terrain Tiles: Mapzen/Tilezen; SRTM and GMTED2010 (USGS), ETOPO1 (NOAA).',
                'attribution_url': 'https://github.com/tilezen/joerd/blob/master/docs/attribution.md'}
