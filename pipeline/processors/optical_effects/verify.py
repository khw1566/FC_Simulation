"""원본 임포터 없이 광학 셰이더와 건물 그림자를 작은 격리 프로젝트에서 확인한다."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT / "previews/asset_browser/optical_effects_check/project"


def copy_sources():
    pending = ["scripts/weather/procedural_cloud_manager.gd", "scripts/terrain/building_mesh_builder.gd"]
    copied = set()
    while pending:
        relative = pending.pop()
        if relative in copied:
            continue
        source = ROOT / "godot_project" / relative
        target = PROJECT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        before = source.stat()
        shutil.copy2(source, target)
        after = source.stat()
        if (before.st_mtime_ns, before.st_size) != (after.st_mtime_ns, after.st_size):
            raise RuntimeError(f"복사 중 변경: {source}")
        copied.add(relative)
        text = source.read_text(encoding="utf-8")
        pending.extend(re.findall(r'res://([^"\s]+\.(?:gdshaderinc|gdshader|gd))(?=")', text))
        for include in re.findall(r'#include "([^"]+)"', text):
            pending.append((Path(relative).parent / include).as_posix())
    for name in ("preview.gd", "preview_weather.gd", "preview_cycle.gd"):
        shutil.copy2(Path(__file__).parent / name, PROJECT / name)
    (PROJECT / "project.godot").write_text('''config_version=5
[application]
config/name="광학 효과 독립 확인"
config/use_custom_user_dir=true
config/custom_user_dir_name="optics"
[display]
window/size/viewport_width=960
window/size/viewport_height=540
[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding="utf-8")
    return sorted(copied)


def verify(render=False, method="gl_compatibility"):
    copied = copy_sources()
    env = os.environ.copy()
    env["APPDATA"] = str(ROOT / "previews/optics_check/environment/roaming")
    env["LOCALAPPDATA"] = str(ROOT / "previews/optics_check/environment/local")
    for key in ("APPDATA", "LOCALAPPDATA"):
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    godot = ROOT / "tools/godot/Godot_v4.3-stable_win64_console.exe"
    command = [str(godot), "--path", str(PROJECT), "--rendering-method", method]
    # 전역 클래스 캐시는 이 격리 프로젝트에서만 생성한다.
    imported = subprocess.run(command + ["--headless", "--editor", "--quit"], env=env,
                              capture_output=True, encoding="utf-8", errors="replace", timeout=90)
    (PROJECT.parent / "import.log").write_text(imported.stdout + imported.stderr, encoding="utf-8")
    if imported.returncode or "SCRIPT ERROR" in imported.stderr:
        raise RuntimeError("격리 프로젝트 임포트 실패: import.log 확인")
    args = [] if render else ["--headless"]
    result = subprocess.run(command + args + ["--script", "res://preview.gd", "--quit-after", "180"],
                            env=env, capture_output=True, encoding="utf-8", errors="replace", timeout=150)
    log = result.stdout + result.stderr
    (PROJECT.parent / (method + ".log")).write_text(log, encoding="utf-8")
    # 엔진의 전체 GLSL 덤프는 파일에 보존하고 콘솔에는 결과와 오류만 출력한다.
    print("\n".join(line for line in log.splitlines() if not re.match(r'^\d+: ', line)))
    if result.returncode or "OPTICS_CHECK_OK" not in log or "SCRIPT ERROR" in log or "Shader compilation failed" in log or (render and "ERROR:" in log):
        raise RuntimeError("격리 검증 실패: 로그 확인")
    evidence = json.loads((PROJECT / "verification.json").read_text(encoding="utf-8"))
    evidence.update(copied_sources=copied, rendered=render, method=method)
    output = ROOT / "results/optical_effects"
    output.mkdir(parents=True, exist_ok=True)
    evidence["source_sha256"] = {p: hashlib.sha256((PROJECT / p).read_bytes()).hexdigest() for p in copied}
    if render:
        for name in ("baseline", "optics", "rays_only", "clear_baseline", "clear_flare", "occluded", "occluded_baseline"):
            image = PROJECT / "images" / (name + ".png")
            shutil.copy2(image, output / (method + "_" + image.name))
        from image_metrics import measure
        evidence["image_metrics"] = measure(output, method)
        print(json.dumps(evidence["image_metrics"], indent=2))
    for relative, digest in evidence["source_sha256"].items():
        if hashlib.sha256((ROOT / "godot_project" / relative).read_bytes()).hexdigest() != digest:
            raise RuntimeError(f"확인 중 원본 변경: {relative}")
    (output / (method + ".json")).write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--method", default="gl_compatibility")
    args = parser.parse_args()
    verify(args.render, args.method)
