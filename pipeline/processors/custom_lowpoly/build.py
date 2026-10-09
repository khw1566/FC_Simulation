"""커스텀 에셋 생성기의 격리 복사·경량화·검증·게시 진입점."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from presets import PYTHON, GODOT, patch
from models import generate
from publish import publish

ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT / "godot_project"
STAGE = ROOT / "previews/asset_browser/custom_lowpoly_build"
PACKAGES = ("vessels", "industrial", "industrial_plant", "taehwagang", "wolsong")
SCN_FAMILIES = ("heritage", "airport", "japan_airports")


def execute(script):
    env = os.environ.copy()
    env["APPDATA"] = str(STAGE / "user_data")
    Path(env["APPDATA"]).mkdir(exist_ok=True)
    result = subprocess.run([str(ROOT / "tools/godot/Godot_v4.3-stable_win64_console.exe"),
        "--rendering-method", "gl_compatibility", "--resolution", "64x64", "--position", "-32000,-32000",
        "--path", str(STAGE), "--script", "res://" + script], capture_output=True, text=True,
        encoding="utf-8", env=env, timeout=90, creationflags=subprocess.CREATE_NO_WINDOW)
    (STAGE / (Path(script).stem + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
    print(result.stdout.strip(), flush=True)
    if result.returncode or "SCRIPT ERROR" in result.stderr or "ERROR:" in result.stderr:
        raise RuntimeError(result.stdout + result.stderr)


def build_assets():
    protected = {}
    for package in PACKAGES:
        target = STAGE / "python" / package
        target.mkdir(parents=True, exist_ok=True)
        for source in (ROOT / "pipeline/processors" / package).glob("*.py"):
            shutil.copy2(source, target / source.name)
    for folder in ("scripts", "shaders"):
        for source in (PROJECT / folder).rglob("*"):
            if not source.is_file() or source.suffix not in (".gd", ".gdshader", ".gdshaderinc"):
                continue
            target = STAGE / source.relative_to(PROJECT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    paths = []
    for family in (*PACKAGES, *SCN_FAMILIES):
        for source in (PROJECT / "assets/generated" / family).glob("*"):
            if source.suffix not in (".glb", ".scn", ".tscn"):
                continue
            relative = source.relative_to(PROJECT).as_posix()
            target = STAGE / "originals" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            protected[relative] = hashlib.sha256(source.read_bytes()).hexdigest()
            if hashlib.sha256(target.read_bytes()).hexdigest() != protected[relative]:
                raise RuntimeError("복사 중 원본 변경: " + relative)
            if source.suffix == ".scn" and family in SCN_FAMILIES:
                paths.append(relative)
    for name in ("ulsan_heritage_models", "ulsan_airport_model", "japan_airports"):
        shutil.copy2(ROOT / "config" / (name + ".json"), STAGE / (name + ".json"))
    for name in ("export.gd", "audit.gd", "verify_glb.gd"):
        shutil.copy2(Path(__file__).parent / name, STAGE / name)
    (STAGE / "project.godot").write_text('config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    (STAGE / "paths.json").write_text(json.dumps(paths), encoding="utf-8")
    (STAGE / "protected.json").write_text(json.dumps(protected), encoding="utf-8")
    patch(STAGE / "python", PYTHON)
    shutil.copy2(Path(__file__).parent / "runway_label.gd", STAGE / "scripts/terrain/lowpoly_runway_label.gd")
    patch(STAGE / "scripts/terrain", GODOT)
    metrics = generate(ROOT, STAGE)
    (STAGE / "glb_metrics.json").write_text(json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8")
    execute("verify_glb.gd")
    execute("export.gd")
    execute("audit.gd")
    metrics += json.loads((STAGE / "metrics.json").read_text(encoding="utf-8"))
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
