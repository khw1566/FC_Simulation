"""원본을 임포트하지 않는 선박·교량·항적 경량 렌더."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent

with tempfile.TemporaryDirectory(prefix="marine_", dir=HERE) as temporary:
    stage = Path(temporary)
    for relative in ["scripts/core/asset_marker_lighting.gd", "scripts/water/vessel_model_factory.gd",
                     "scripts/water/vessel_wake.gd", "shaders/vessel_wake.gdshader",
                     "assets/generated/vessels/tugboat.glb",
                     "assets/generated/pedestrian_bridges/generic_pedestrian_overpass.scn"]:
        target = stage / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "godot_project" / relative, target)
    shutil.copy2(HERE / "verify.gd", stage / "verify.gd")
    (stage / "project.godot").write_text('config_version=5\n[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=720\n', encoding="utf-8")
    env = os.environ.copy()
    env["APPDATA"] = str(stage / "user_data")
    Path(env["APPDATA"]).mkdir()
    result = subprocess.run([str(ROOT / "tools/godot/Godot_v4.3-stable_win64_console.exe"),
                             "--path", str(stage), "--rendering-method", "gl_compatibility",
                             "--script", "res://verify.gd", "--quit-after", "120"],
                            env=env, capture_output=True, text=True, encoding="utf-8", timeout=30,
                            creationflags=subprocess.CREATE_NO_WINDOW)
    print(result.stdout)
    if result.returncode or "ERROR" in result.stderr:
        raise RuntimeError(result.stderr)
    (HERE / "images").mkdir(exist_ok=True)
    for source in (stage / "captures").glob("*.png"):
        shutil.copy2(source, HERE / "images" / source.name)
