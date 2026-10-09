"""원본 프로젝트를 실행하지 않고 철로·교량 경량 에셋을 생성한다."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
if __package__:
    from .presets import apply
    from .publish import publish
else:
    from presets import apply
    from publish import publish

ROOT = Path(__file__).resolve().parents[3]
STAGE = ROOT / "previews/asset_browser/rail_bridge_lowpoly_build"
PROJECT = ROOT / "godot_project"
FAMILIES = ("railway_bridges", "bridges", "pedestrian_bridges", "railway/night_assets")


def copy_dependency(relative, seen):
    if relative in seen:
        return
    seen.add(relative)
    source = PROJECT / relative
    target = STAGE / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    if source.suffix == ".gd":
        for dependency in re.findall(r'res://([^"\s]+\.gd)', source.read_text(encoding="utf-8")):
            copy_dependency(dependency, seen)


def execute(script):
    env = os.environ.copy()
    env["APPDATA"] = str(STAGE / "user_data")
    Path(env["APPDATA"]).mkdir(exist_ok=True)
    result = subprocess.run([str(ROOT / "tools/godot/Godot_v4.3-stable_win64_console.exe"),
                             "--rendering-method", "gl_compatibility", "--resolution", "64x64",
                             "--position", "-32000,-32000", "--path", str(STAGE), "--script", "res://" + script],
                            capture_output=True, text=True, encoding="utf-8", env=env,
                            timeout=90, creationflags=subprocess.CREATE_NO_WINDOW)
    (STAGE / (Path(script).stem + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
    print(result.stdout.strip(), flush=True)
    if result.returncode or "SCRIPT ERROR" in result.stderr or "ERROR:" in result.stderr:
        raise RuntimeError(result.stdout + result.stderr)


def build_assets():
    STAGE.mkdir(parents=True, exist_ok=True)
    seen = set()
    for relative in ("scripts/terrain/bridge_asset_export.gd", "scripts/terrain/railway_bridge_asset_builder.gd",
                     "scripts/terrain/ulsan_railway_bridge_set.gd", "scripts/terrain/gulhwa_crossing_asset.gd",
                     "scripts/terrain/seonbawi_bridge_asset.gd", "scripts/terrain/pedestrian_overpass_asset.gd",
                     "scripts/terrain/railway_track_builder.gd"):
        copy_dependency(relative, seen)
    for relative in ("assets/generated/taehwa_bridges.json", "assets/generated/railway/night_lighting.json",
                     "assets/generated/railway/services.json"):
        copy_dependency(relative, seen)
    for name in ("railway_bridge_assets", "pedestrian_bridge_assets"):
        shutil.copy2(ROOT / "config" / (name + ".json"), STAGE / (name + ".json"))
        shutil.copy2(ROOT / "pipeline/processors" / ("export_" + name + ".gd"), STAGE / ("export_" + name + ".gd"))
    for name in ("tracks.gd", "audit.gd"):
        shutil.copy2(Path(__file__).parent / name, STAGE / name)
    paths = []
    protected = {}
    for family in FAMILIES:
        for source in sorted((PROJECT / "assets/generated" / family).glob("*.scn")):
            if family == "railway/night_assets" and source.stem.endswith("_train"):
                continue
            relative = source.relative_to(PROJECT).as_posix()
            target = STAGE / "originals" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            paths.append(relative)
            protected[relative] = hashlib.sha256(source.read_bytes()).hexdigest()
            if hashlib.sha256(target.read_bytes()).hexdigest() != protected[relative]:
                raise RuntimeError(f"원본이 복사 중 변경되었습니다: {relative}")
    (STAGE / "paths.json").write_text(json.dumps(paths), encoding="utf-8")
    (STAGE / "project.godot").write_text('config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    apply(STAGE)
    for script in ("export_railway_bridge_assets.gd", "export_pedestrian_bridge_assets.gd",
                   "scripts/terrain/bridge_asset_export.gd", "tracks.gd", "audit.gd"):
        execute(script)
    metrics = json.loads((STAGE / "metrics.json").read_text(encoding="utf-8"))
    publish(ROOT, STAGE, metrics, protected)


def main():
    STAGE.mkdir(parents=True, exist_ok=True)
    lock = STAGE / "writer.lock"
    fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    try:
        build_assets()
    finally:
        os.close(fd)
        lock.unlink()


if __name__ == "__main__":
    main()
