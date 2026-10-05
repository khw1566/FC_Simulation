"""독립 경량 Godot 환경에서 교량을 생성하고 자산과 모듈 인덱스를 갱신한다."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


class PedestrianBridgeAssetPipeline:
    ROOT = Path(__file__).resolve().parents[2]
    MODULES = {
        "godot_project/scripts/terrain/pedestrian_bridge_geometry.gd": "교량 부재와 재질 공통 생성",
        "godot_project/scripts/terrain/gulhwa_crossing_asset.gd": "굴화리–다운동 저상 보행교 생성",
        "godot_project/scripts/terrain/seonbawi_bridge_asset.gd": "선바위교 근사 모델 생성",
        "godot_project/scripts/terrain/pedestrian_overpass_asset.gd": "범용 계단식 보행 육교 생성",
        "godot_project/scripts/core/pedestrian_bridge_preview.gd": "교량 3종 독립 선택 프리뷰",
        "godot_project/scenes/pedestrian_bridge_preview.tscn": "독립 교량 프리뷰 진입 씬",
        "pipeline/processors/export_pedestrian_bridge_assets.gd": "정적 교량 씬 저장 및 재로드 검증",
        "pipeline/processors/build_pedestrian_bridge_assets.py": "격리 생성 실행과 매니페스트 및 모듈 인덱스 갱신",
    }

    def run(self):
        root = self.ROOT
        output = root / "godot_project/assets/generated/pedestrian_bridges"
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="bridge_build_", dir=root / "results") as temporary:
            stage = Path(temporary)
            for relative in self.MODULES:
                if relative.startswith("godot_project/scripts/terrain/"):
                    target = stage / Path(relative).relative_to("godot_project")
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(root / relative, target)
            (stage / "scripts/core").mkdir(exist_ok=True)
            shutil.copy2(root / "godot_project/scripts/core/asset_marker_lighting.gd", stage / "scripts/core/asset_marker_lighting.gd")
            shutil.copy2(root / "godot_project/scripts/terrain/bridge_geometry.gd", stage / "scripts/terrain/bridge_geometry.gd")
            shutil.copy2(root / "config/pedestrian_bridge_assets.json", stage / "pedestrian_bridge_assets.json")
            shutil.copy2(root / "pipeline/processors/export_pedestrian_bridge_assets.gd", stage / "export.gd")
            (stage / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            env = os.environ.copy()
            env["APPDATA"] = str(stage / "user_data")
            Path(env["APPDATA"]).mkdir()
            result = subprocess.run([str(root / "tools/godot/Godot_v4.3-stable_win64_console.exe"),
                                     "--path", str(stage), "--rendering-method", "gl_compatibility",
                                     "--script", "res://export.gd", "--quit-after", "120"],
                                    env=env, capture_output=True, text=True, encoding="utf-8",
                                    timeout=45, creationflags=subprocess.CREATE_NO_WINDOW)
            if result.returncode or "SCRIPT ERROR" in result.stderr or "ERROR:" in result.stderr:
                raise RuntimeError(result.stdout + result.stderr)
            generated = stage / "assets/generated/pedestrian_bridges"
            manifest = json.loads((generated / "manifest.json").read_text(encoding="utf-8"))
            if len(manifest["assets"]) != 3:
                raise RuntimeError("교량 3종 생성 확인 실패")
            for source in generated.iterdir():
                pending = output / (source.name + ".pending")
                shutil.copy2(source, pending)
                os.replace(pending, output / source.name)
            print(result.stdout.strip())
        manifest_path = output.parent / "manifest.json"
        master = json.loads(manifest_path.read_text(encoding="utf-8"))
        for asset_id, entry in manifest["assets"].items():
            data = (output / (asset_id + ".scn")).read_bytes()
            if hashlib.sha256(data).hexdigest() != entry["sha256"]:
                raise RuntimeError("교량 자산 해시 불일치: " + asset_id)
            master["assets"]["pedestrian_bridge_" + asset_id] = entry
        pending = manifest_path.with_suffix(".lighting.pending")
        pending.write_text(json.dumps(master, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(pending, manifest_path)
        for relative in ["module_index.json", "godot_project/module_index.json"]:
            index_path = root / relative
            index = json.loads(index_path.read_text(encoding="utf-8"))
            index["domains"]["pedestrian_bridge_assets"] = {
                "description": "독립 도보 징검다리, 선바위교 및 범용 육교 에셋",
                "modules": [{"path": path, "responsibility": responsibility,
                             "lines": len((root / path).read_text(encoding="utf-8").splitlines())}
                            for path, responsibility in self.MODULES.items()]}
            index_path.write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    PedestrianBridgeAssetPipeline().run()
