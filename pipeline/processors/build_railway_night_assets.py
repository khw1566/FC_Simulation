"""철로·열차 야간 에셋을 프리뷰 전용 고유 공간에서 생성한다."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


class RailwayNightAssetPipeline:
    ROOT = Path(__file__).resolve().parents[2]

    def run(self):
        root = self.ROOT
        browser = root / "previews/asset_browser"
        with tempfile.TemporaryDirectory(prefix="rail_night_", dir=browser) as temporary:
            stage = Path(temporary)
            for path in ["scripts/terrain/railway_train_builder.gd", "scripts/terrain/railway_track_builder.gd",
                         "scripts/terrain/railway_night_lighting.gd", "scripts/terrain/railway_route.gd",
                         "assets/generated/railway/night_lighting.json",
                         "assets/generated/railway/services.json"]:
                target = stage / path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(root / "godot_project" / path, target)
            shutil.copy2(root / "pipeline/indexer/export_railway_night_assets.gd", stage / "export.gd")
            shutil.copy2(browser / "railway_night_capture/verify.gd", stage / "verify.gd")
            (stage / "project.godot").write_text('config_version=5\n[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=720\n[rendering]\nanti_aliasing/quality/msaa_3d=2\n', encoding="utf-8")
            env = os.environ.copy()
            env["APPDATA"] = str(stage / "user_data")
            Path(env["APPDATA"]).mkdir()
            for script in ["export.gd", "verify.gd"]:
                result = subprocess.run([str(root / "tools/godot/Godot_v4.3-stable_win64_console.exe"),
                                         "--path", str(stage), "--rendering-method", "gl_compatibility",
                                         "--script", "res://" + script, "--quit-after", "120"],
                                        env=env, capture_output=True, text=True, encoding="utf-8", timeout=35,
                                        creationflags=subprocess.CREATE_NO_WINDOW)
                if result.returncode or "ERROR" in result.stderr:
                    raise RuntimeError(result.stdout + result.stderr)
                print(result.stdout.strip())
            source = stage / "assets/generated/railway/night_assets"
            output = root / "godot_project/assets/generated/railway/night_assets"
            output.mkdir(parents=True, exist_ok=True)
            for file in source.iterdir():
                pending = output / (file.name + ".pending")
                shutil.copy2(file, pending)
                os.replace(pending, output / file.name)
            images = browser / "railway_night_capture/images"
            images.mkdir(parents=True, exist_ok=True)
            for file in (stage / "captures").glob("*.png"):
                shutil.copy2(file, images / file.name)
        manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
        catalog = {"version": 1, "family": "railway", "assets": [
            {"id": key, "scene": entry["file_path"], **entry["metadata"]}
            for key, entry in manifest["assets"].items()]}
        (output / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
        master_path = root / "godot_project/assets/generated/manifest.json"
        master = json.loads(master_path.read_text(encoding="utf-8"))
        for key, entry in manifest["assets"].items():
            master["assets"]["railway_night_" + key] = entry
        settings = root / "godot_project/assets/generated/railway/night_lighting.json"
        data = settings.read_bytes()
        master["assets"]["railway_night_lighting"] = {"file_path": "res://assets/generated/railway/night_lighting.json",
            "format": "JSON", "type": "railway_lighting_settings", "sha256": hashlib.sha256(data).hexdigest(),
            "size_bytes": len(data), "metadata": {"bbox": None, "resolution": None, "elevation_min": None, "elevation_max": None}}
        pending = master_path.with_name("manifest.json.night.pending")
        pending.write_text(json.dumps(master, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(pending, master_path)


if __name__ == "__main__":
    RailwayNightAssetPipeline().run()
