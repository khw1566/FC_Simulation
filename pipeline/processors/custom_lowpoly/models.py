"""패치된 복사본의 모델 함수만 호출하고 조립 씬은 보존한다."""
import importlib
import json
import sys
from glb import export, inspect


def generate(root, stage):
    sys.path.insert(0, str(stage / "python"))
    from vessels.mesh import PALETTE, VesselMesh
    from vessels.designs import SPECS, build_vessel
    from industrial import factories, equipment, pipes, structures, cranes
    from industrial_plant import towers, routing
    from wolsong.design import build_complex
    from taehwagang.geometry import StationMesh
    models = []
    config = json.loads((root / "config/industrial_assets.json").read_text(encoding="utf-8"))
    for key, label in config["assets"].items():
        builder = factories if key.startswith("factory_") else pipes if key.startswith("pipeline_") else cranes if key.endswith("_crane") else structures if key in ("transmission_tower", "cooling_tower", "cooling_fan_bank", "shipbuilding_hangar") else equipment
        models.append(("industrial", key, label, builder.build(key)))
    for key in list(towers.SPECS) + list(routing.PORTS):
        label = towers.SPECS[key][0] if key in towers.SPECS else routing.LABELS[key]
        models.append(("industrial_plant", key, label, (towers if key in towers.SPECS else routing).build(key)))
    for key, spec in SPECS.items():
        models.append(("vessels", key, spec[0], build_vessel(key)))
    config = json.loads((root / "config/taehwagang_asset.json").read_text(encoding="utf-8"))
    complete = StationMesh()
    for key in ("station", "rail_yard", "forecourt", "district"):
        mesh = importlib.import_module("taehwagang." + key).build(config)
        complete.faces.extend(mesh.faces)
        models.append(("taehwagang", key, {"station": "태화강역", "rail_yard": "역 승강장", "forecourt": "역 광장", "district": "역전 구역"}[key], mesh))
    models.append(("taehwagang", "taehwagang_complete", "태화강역 조립", complete))
    models.append(("wolsong", "wolsong_npp", "월성 발전소", build_complex()))
    metrics = []
    for family, key, label, mesh in models:
        relative = f"assets/generated/{family}/{key}.glb"
        path = stage / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        export(mesh, path, key, PALETTE)
        before = inspect(root / "godot_project" / relative)
        after = inspect(path)
        if after["triangles"] > before["triangles"]:
            raise RuntimeError("삼각형 수 증가: " + relative)
        points = [point for face in mesh.faces for point in face[:3]]
        after["aabb_min_m"] = [min(p[i] for p in points) for i in range(3)]
        after["aabb_max_m"] = [max(p[i] for p in points) for i in range(3)]
        metrics.append({"path": relative, "label_ko": label, "before": before, "after": after})
        print(f"{family}/{key}: {before['triangles']} -> {after['triangles']}", flush=True)
    # 실제 경량 기하의 소프트웨어 프리뷰. 원본 임포터를 실행하지 않는다.
    from industrial.preview import render
    selected = ("lpg_sphere", "cooling_tower", "tower_crane", "rack_elbow", "station", "wolsong_npp", "container_ship", "tugboat", "stack_concrete", "factory_gable")
    render([(key, label, mesh) for family, key, label, mesh in models if key in selected], stage / "custom_lowpoly_preview.png")
    return metrics
