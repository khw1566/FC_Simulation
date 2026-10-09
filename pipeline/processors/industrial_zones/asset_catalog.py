"""공단 배치용 산업 설비 카탈로그를 읽고 footprint·배관 부착 정보를 보강한다."""
import json
from pathlib import Path

# 연결 포트 (-12,5,0) 하나를 가진 공정 설비에는 랙 오른쪽 포트 (12,5,0)를 접속한다.
RACK_FED = ("stack_steel", "stack_concrete", "stack_triple", "flare_lattice", "process_column", "scrubber_tower")


def _read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def load_catalog(root):
    catalog = dict(_read(root / "godot_project/assets/generated/industrial/catalog.json")["assets"])
    plant = _read(root / "godot_project/assets/generated/industrial_plant/catalog.json")["assets"]
    rack = plant["rack_straight"]
    for key, source in plant.items():
        spec = dict(source)
        lo, hi = list(spec["aabb_min_m"]), list(spec["aabb_max_m"])
        if key in RACK_FED:
            lo[0] = -36.0
            spec["attachments"] = [{"asset_type": "rack_straight", "position_m": [-24, 0, 0],
                                    "glb_path": rack["scene_path"].replace(".tscn", ".glb"),
                                    "night_lighting": rack.get("night_lighting", {}),
                                    "port_parent_m": [-12, 5, 0], "port_attachment_m": [12, 5, 0]}]
        spec["aabb_min_m"], spec["aabb_max_m"] = lo, hi
        spec["footprint_xz_m"] = [lo[0], lo[2], hi[0], hi[2]]
        spec["scale_range"] = [1.0, 1.0]
        catalog[key] = spec
    return catalog
