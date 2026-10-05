"""기존 교량 카탈로그를 보존하고 조명을 포함한 씬만 격리 재생성한다."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def main():
    with tempfile.TemporaryDirectory(prefix="bridge_light_", dir=ROOT / "previews/asset_browser") as temporary:
        stage = Path(temporary)
        for relative in ["scripts/core/asset_marker_lighting.gd", "scripts/terrain/bridge_landmark_builder.gd",
                         "scripts/terrain/bridge_geometry.gd", "scripts/terrain/bridge_asset_export.gd",
                         "assets/generated/taehwa_bridges.json"]:
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / "godot_project" / relative, target)
        (stage / "project.godot").write_text('config_version=5\n', encoding="utf-8")
        env = os.environ.copy()
        env["APPDATA"] = str(stage / "user_data")
        Path(env["APPDATA"]).mkdir()
        result = subprocess.run([str(ROOT / "tools/godot/Godot_v4.3-stable_win64_console.exe"), "--path", str(stage),
                                 "--rendering-method", "gl_compatibility", "--script", "res://scripts/terrain/bridge_asset_export.gd"],
                                env=env, capture_output=True, text=True, encoding="utf-8", timeout=30,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode or "ERROR" in result.stderr:
            raise RuntimeError(result.stdout + result.stderr)
        print(result.stdout)
        output = ROOT / "godot_project/assets/generated/bridges"
        for source in (stage / "assets/generated/bridges").glob("*.scn"):
            pending = output / (source.name + ".lighting.pending")
            shutil.copy2(source, pending)
            os.replace(pending, output / source.name)
    path = output.parent / "manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    for entry in manifest.get("taehwa_bridges", {}).get("scene_assets", []):
        file = ROOT / "godot_project" / entry["path"].removeprefix("res://")
        entry["sha256"] = hashlib.sha256(file.read_bytes()).hexdigest()
        entry["lighting"] = {"local_light_count": 1, "energy": 0.2, "fade_end_m": 100}
    pending = path.with_suffix(".lighting.pending")
    pending.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(pending, path)

if __name__ == "__main__":
    main()
