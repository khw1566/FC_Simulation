"""프리뷰 전용 고유 작업 공간에서 터널을 생성하고 원본에는 완성된 자산만 기록한다."""

import argparse
import json
import os
import runpy
from pathlib import Path
import shutil
import subprocess
import tempfile


class RailwayTunnelAssetPipeline:
    ROOT = Path(__file__).resolve().parents[2]
    MODULES = {
        "godot_project/scripts/terrain/railway_tunnel_geometry.gd": "중공 라이닝 메시와 재질별 터널 부재 생성",
        "godot_project/scripts/terrain/railway_tunnel_details.gd": "궤도, 보행로, 가선, 배수로와 입구 설비 생성",
        "godot_project/scripts/terrain/railway_tunnel_asset_builder.gd": "입구·내부·출구 및 연결 완료 터널 조립",
        "pipeline/indexer/export_railway_tunnel_assets.gd": "터널 씬 및 해시·경계·연결 메타데이터 저장",
        "pipeline/processors/build_railway_tunnel_assets.py": "독립 터널 생성 실행과 자산·모듈 색인 갱신",
    }

    def run(self, capture=False):
        root = self.ROOT
        output = root / "godot_project/assets/generated/railway_tunnels"
        output.mkdir(parents=True, exist_ok=True)
        browser = root / "previews/asset_browser"
        browser.mkdir(parents=True, exist_ok=True)
        # 고유 공간만 쓰므로 실행 중인 전체 에셋 프리뷰의 작성자와 캐시를 공유하지 않는다.
        with tempfile.TemporaryDirectory(prefix="tunnel_build_", dir=browser) as temporary:
            stage = Path(temporary)
            dependencies = [p for p in self.MODULES if p.startswith("godot_project/")]
            dependencies.append("godot_project/scripts/terrain/bridge_geometry.gd")
            dependencies += ["godot_project/scripts/terrain/railway_night_lighting.gd",
                             "godot_project/scripts/terrain/railway_route.gd",
                                                          "godot_project/assets/generated/railway/night_lighting.json"]
            for relative in dependencies:
                target = stage / Path(relative).relative_to("godot_project")
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(root / relative, target)
            shutil.copy2(root / "config/railway_tunnel_assets.json", stage / "railway_tunnel_assets.json")
            shutil.copy2(root / "pipeline/indexer/export_railway_tunnel_assets.gd", stage / "export.gd")
            (stage / "project.godot").write_text(
                'config_version=5\n[display]\nwindow/size/viewport_width=1100\n'
                'window/size/viewport_height=700\n[rendering]\nanti_aliasing/quality/msaa_3d=2\n', encoding="utf-8")
            env = os.environ.copy()
            env["APPDATA"] = str(stage / "user_data")
            Path(env["APPDATA"]).mkdir()
            self._execute(stage, env, "export.gd")
            if capture:
                shutil.copy2(browser / "railway_tunnel_capture/capture.gd", stage / "capture.gd")
                self._execute(stage, env, "capture.gd")
                screenshots = browser / "railway_tunnel_capture/images"
                screenshots.mkdir(parents=True, exist_ok=True)
                for image in (stage / "captures").glob("*.png"):
                    shutil.copy2(image, screenshots / image.name)
                sheet = runpy.run_path(str(browser / "railway_tunnel_capture/make_sheet.py"))
                sheet["make_sheet"]()
            generated = stage / "assets/generated/railway_tunnels"
            manifest = json.loads((generated / "manifest.json").read_text(encoding="utf-8"))
            if len(manifest["assets"]) != 10:
                raise RuntimeError("터널 자산 생성 미완료")
            # 안정된 최종 파일을 원자적으로 공개해 실행 중인 프리뷰의 읽기와 공존한다.
            for source in generated.iterdir():
                temporary_output = output / (source.name + ".pending")
                shutil.copy2(source, temporary_output)
                os.replace(temporary_output, output / source.name)
        master_path = output.parent / "manifest.json"
        master = json.loads(master_path.read_text(encoding="utf-8"))
        for asset_id, entry in manifest["assets"].items():
            master["assets"]["railway_tunnel_" + asset_id] = entry
        self._atomic_json(master_path, master)
        for relative in ["module_index.json", "godot_project/module_index.json"]:
            path = root / relative
            index = json.loads(path.read_text(encoding="utf-8"))
            index["domains"]["railway_tunnel_assets"] = {
                "description": "고속철도용·동해선용 독립 범용 터널 에셋",
                "modules": [{"path": p, "responsibility": r,
                             "lines": len((root / p).read_text(encoding="utf-8").splitlines())}
                            for p, r in self.MODULES.items()]}
            self._atomic_json(path, index)

    @staticmethod
    def _atomic_json(path, data):
        pending = path.with_name(path.name + ".tunnel.pending")
        pending.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(pending, path)

    def _execute(self, stage, env, script):
        result = subprocess.run([str(self.ROOT / "tools/godot/Godot_v4.3-stable_win64_console.exe"),
                                 "--path", str(stage), "--rendering-method", "gl_compatibility",
                                 "--script", "res://" + script, "--quit-after", "150"],
                                env=env, capture_output=True, text=True, encoding="utf-8",
                                timeout=35, creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode or "SCRIPT ERROR" in result.stderr or "ERROR:" in result.stderr:
            raise RuntimeError(result.stdout + result.stderr)
        print(result.stdout.strip())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="범용 철로 터널 에셋 생성")
    parser.add_argument("--capture-previews", action="store_true")
    RailwayTunnelAssetPipeline().run(parser.parse_args().capture_previews)
