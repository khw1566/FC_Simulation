"""고도 원천 선택: VWorld 키가 있으면 VWorld DEM, 없거나 검증 실패 시 공개 Terrarium.

VWorld 노드 행 방향은 Terrarium 격자와의 상관계수로 확정하고, 결측 표고는 Terrarium으로 채운다.
"""
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "collectors"))
from riverside_sources import ApiKeyResolver, TerrariumDemSource, VworldDemSource  # noqa: E402


class HeightSourceSelector:
    MIN_CORRELATION = 0.6

    def __init__(self, root, config, grid):
        self.root = root
        self.settings = config["height_source"]
        self.bbox = config["bbox"]
        self.grid = grid
        self.report = {}

    @staticmethod
    def _correlation(a, b):
        small_a = cv2.resize(a, (256, 256), interpolation=cv2.INTER_AREA).ravel()
        small_b = cv2.resize(b, (256, 256), interpolation=cv2.INTER_AREA).ravel()
        return float(np.corrcoef(small_a, small_b)[0, 1])

    def _terrarium(self):
        source = TerrariumDemSource(self.root, self.settings.get("terrarium", {}))
        mosaic, extent = source.collect(self.bbox)
        return self.grid.resample(mosaic, extent), source.meta()

    def _vworld(self, key, reference):
        source = VworldDemSource(self.root, self.settings["vworld"], key)
        best = None
        for north_first in (True, False):
            mosaic, extent = source.collect(self.bbox, north_first=north_first)
            heights = self.grid.resample(mosaic, extent)
            invalid = (heights < -100.0) | ~np.isfinite(heights)
            filled = np.where(invalid, reference, heights)
            score = self._correlation(filled, reference)
            if best is None or score > best[0]:
                best = (score, filled, north_first, float(invalid.mean()))
        score, heights, north_first, invalid_ratio = best
        meta = dict(source.meta(), north_first_rows=north_first, terrarium_correlation=round(score, 4),
                    filled_from_terrarium_ratio=round(invalid_ratio, 6))
        return heights, meta, score

    def select(self, preferred=None, dry_run=False):
        preferred = preferred or self.settings.get("preferred", "auto")
        key, key_origin = ApiKeyResolver(self.root, self.settings["api_key_env"], self.settings["api_key_file_field"]).resolve()
        self.report["api_key_origin"] = key_origin
        if dry_run:
            plan = None
            if key:
                keys, missing = VworldDemSource(self.root, self.settings["vworld"], key).plan(self.bbox)
                plan = {"nodes": len(keys), "new_requests": missing}
            return None, {"source": "dry_run", "vworld_plan": plan, **self.report}
        reference, terrarium_meta = self._terrarium()
        if preferred == "terrarium" or (preferred == "auto" and not key):
            return reference, {**terrarium_meta, **self.report}
        if not key:
            raise RuntimeError(f"VWorld 키가 없습니다. 환경변수 {self.settings['api_key_env']}를 설정하세요.")
        try:
            heights, meta, score = self._vworld(key, reference)
        except Exception as error:
            if preferred == "vworld":
                raise
            print(f"[HeightSourceSelector] VWorld 수집 실패, Terrarium 사용: {error}", flush=True)
            return reference, {**terrarium_meta, "vworld_error": str(error), **self.report}
        if score < self.MIN_CORRELATION and preferred == "auto":
            print(f"[HeightSourceSelector] VWorld 상관계수 {score:.3f} 미달, Terrarium 사용", flush=True)
            return reference, {**terrarium_meta, "vworld_rejected": meta, **self.report}
        return heights, {**meta, **self.report}
