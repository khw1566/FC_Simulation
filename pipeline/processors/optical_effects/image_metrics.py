"""정지된 독립 장면에서 각 효과의 화면 기여와 태양 가림을 수치로 기록한다."""
import json
from pathlib import Path

import numpy as np
from PIL import Image


def measure(folder: Path, method: str):
    pairs = {"combined": ("baseline", "optics"), "rays": ("baseline", "rays_only"),
             "flare": ("clear_baseline", "clear_flare"), "occluded_flare": ("occluded_baseline", "occluded")}
    metrics = {}
    for name, (before, after) in pairs.items():
        a = np.asarray(Image.open(folder / f"{method}_{before}.png"), dtype=np.float32)[..., :3]
        b = np.asarray(Image.open(folder / f"{method}_{after}.png"), dtype=np.float32)[..., :3]
        difference = np.abs(a-b)
        metrics[name] = {"mean_rgb_difference_255": float(difference.mean()),
                         "max_rgb_difference_255": float(difference.max()),
                         "changed_pixels": int(np.any(difference > 0, axis=2).sum())}
    assert metrics["rays"]["changed_pixels"] > 1000
    assert metrics["flare"]["changed_pixels"] > 100
    assert metrics["occluded_flare"]["max_rgb_difference_255"] == 0
    (folder / f"{method}_image_metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    return metrics
