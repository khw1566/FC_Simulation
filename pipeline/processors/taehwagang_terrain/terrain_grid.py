"""지도 bbox와 Godot 높이맵 픽셀 사이의 좌표 변환 및 고도 모자이크 재표본."""
import cv2
import numpy as np


class TerrainGrid:
    def __init__(self, config):
        self.bbox = config["bbox"]
        self.width = int(config["resolution"]["target_width"])
        self.height = int(config["resolution"]["target_height"])
        self.world_size = float(config["world_size_meters"])
        self.pixel_m = self.world_size / (self.width - 1)

    def lonlat_to_pixel(self, lon, lat):
        """Godot의 uv = 픽셀/(크기-1) 규약과 같은 점 정합 좌표를 반환한다."""
        b = self.bbox
        x = (np.asarray(lon) - b["west"]) / (b["east"] - b["west"]) * (self.width - 1)
        y = (b["north"] - np.asarray(lat)) / (b["north"] - b["south"]) * (self.height - 1)
        return x, y

    def column_lons(self):
        b = self.bbox
        return np.linspace(b["west"], b["east"], self.width)

    def resample(self, mosaic, extent):
        """행 0이 북쪽인 위경도 등간격 모자이크를 지도 격자로 쌍선형 재표본한다."""
        b = self.bbox
        lons = np.linspace(b["west"], b["east"], self.width, dtype=np.float64)
        lats = np.linspace(b["north"], b["south"], self.height, dtype=np.float64)
        cols = (lons - extent["west"]) / (extent["east"] - extent["west"]) * (mosaic.shape[1] - 1)
        rows = (extent["north"] - lats) / (extent["north"] - extent["south"]) * (mosaic.shape[0] - 1)
        map_x = np.broadcast_to(cols[None, :], (self.height, self.width)).astype(np.float32)
        map_y = np.broadcast_to(rows[:, None], (self.height, self.width)).astype(np.float32)
        return cv2.remap(mosaic.astype(np.float32), map_x, map_y, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
