"""철도 교량 5종과 안양교–울산역 연결 세트의 격리 생성 파이프라인."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


class RailwayBridgeAssetPipeline:
    ROOT = Path(__file__).resolve().parents[2]
    MODULES = {
        "godot_project/scripts/terrain/railway_bridge_geometry.gd": "철도 궤도, 가선, 부재 및 연결 기준점 생성",
        "godot_project/scripts/terrain/railway_bridge_structures.gd": "철도 교량 형식별 하부 구조 생성",
        "godot_project/scripts/terrain/railway_bridge_asset_builder.gd": "독립 철도 교량 모델 조립",
        "godot_project/scripts/terrain/ulsan_railway_bridge_set.gd": "안양교 본체와 울산역 접근부 연속 연결 세트",
        "godot_project/scripts/core/railway_bridge_preview.gd": "철도 교량 및 연결 세트 선택 프리뷰",
        "godot_project/scenes/railway_bridge_preview.tscn": "독립 철도 교량 프리뷰 진입 씬",
        "pipeline/processors/export_railway_bridge_assets.gd": "정적 씬 저장, 재로드 및 접속 규약 검증",
        "pipeline/processors/capture_railway_bridge_preview.gd": "경량 실제 렌더 프리뷰 이미지 저장",
        "pipeline/processors/build_railway_bridge_assets.py": "격리 생성, 자산 및 모듈 매니페스트 갱신",
        "pipeline/processors/railway_bridge_preview_sheet.py": "실제 철도 교량 렌더 기반 비교 미리보기 배치",
    }

    def run(self, capture=False):
        root = self.ROOT
        output = root / "godot_project/assets/generated/railway_bridges"
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="rail_bridge_build_", dir=root / "results") as temporary:
            stage = Path(temporary)
            dependencies = [p for p in self.MODULES if p.startswith("godot_project/")]
            dependencies += ["godot_project/scripts/terrain/bridge_geometry.gd",
                             "godot_project/scripts/views/custom_asset_preview.gd",
                             "godot_project/scripts/terrain/railway_night_lighting.gd",
                             "godot_project/scripts/terrain/railway_route.gd",
                                                          "godot_project/assets/generated/railway/night_lighting.json"]
            for relative in dependencies:
                target = stage / Path(relative).relative_to("godot_project")
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(root / relative, target)
            shutil.copy2(root / "config/railway_bridge_assets.json", stage / "railway_bridge_assets.json")
            for source, name in [("export_railway_bridge_assets.gd", "export.gd"),
                                 ("capture_railway_bridge_preview.gd", "capture.gd")]:
                shutil.copy2(root / "pipeline/processors" / source, stage / name)
            (stage / "project.godot").write_text(
                'config_version=5\n[display]\nwindow/size/viewport_width=1280\n'
                'window/size/viewport_height=720\n[rendering]\nanti_aliasing/quality/msaa_3d=2\n', encoding="utf-8")
            env = os.environ.copy()
            env["APPDATA"] = str(stage / "user_data")
            Path(env["APPDATA"]).mkdir()
            self._execute(stage, env, "export.gd")
            if capture:
                self._execute(stage, env, "capture.gd")
            generated = stage / "assets/generated/railway_bridges"
            manifest = json.loads((generated / "manifest.json").read_text(encoding="utf-8"))
            if len(manifest["assets"]) != 10:
                raise RuntimeError("철도 교량 10개 생성 확인 실패")
            for source in generated.iterdir():
                pending = output / (source.name + ".pending")
                shutil.copy2(source, pending)
                os.replace(pending, output / source.name)
        if capture:
            from railway_bridge_preview_sheet import create_preview_sheet
            create_preview_sheet(output)
        master_path = output.parent / "manifest.json"
        master = json.loads(master_path.read_text(encoding="utf-8"))
        for asset_id, entry in manifest["assets"].items():
            data = (output / (asset_id + ".scn")).read_bytes()
            if hashlib.sha256(data).hexdigest() != entry["sha256"]:
                raise RuntimeError("철도 교량 자산 해시 불일치: " + asset_id)
            master["assets"]["railway_bridge_" + asset_id] = entry
        self._atomic_json(master_path, master)
        for relative in ["module_index.json", "godot_project/module_index.json"]:
            path = root / relative
            index = json.loads(path.read_text(encoding="utf-8"))
            index["domains"]["railway_bridge_assets"] = {
                "description": "범용 철도 교량 및 안양교–울산역 연결 세트",
                "modules": [{"path": p, "responsibility": r,
                             "lines": len((root / p).read_text(encoding="utf-8").splitlines())}
                            for p, r in self.MODULES.items()]}
            self._atomic_json(path, index)

    @staticmethod
    def _atomic_json(path, data):
        pending = path.with_name(path.name + ".rail_bridge.pending")
        pending.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(pending, path)

    def _execute(self, stage, env, script):
        result = subprocess.run([str(self.ROOT / "tools/godot/Godot_v4.3-stable_win64_console.exe"),
                                 "--path", str(stage), "--rendering-method", "gl_compatibility",
                                 "--script", "res://" + script, "--quit-after", "300"],
                                env=env, capture_output=True, text=True, encoding="utf-8",
                                timeout=45, creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode or "SCRIPT ERROR" in result.stderr or "ERROR:" in result.stderr:
            raise RuntimeError(result.stdout + result.stderr)
        print(result.stdout.strip())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="철도 교량 에셋 생성")
    parser.add_argument("--capture-previews", action="store_true", help="실제 렌더 미리보기 저장")
    arguments = parser.parse_args()
    RailwayBridgeAssetPipeline().run(arguments.capture_previews)
