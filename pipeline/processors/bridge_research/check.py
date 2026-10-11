"""6개 GLB만 격리된 Godot 프로젝트에서 읽는 경량 구조 확인."""
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    root=Path(__file__).resolve().parents[3]
    stage=root/"previews/asset_browser/bridge_research_check"
    source=root/"godot_project/assets/generated/bridges/research_20261009"
    stage.mkdir(parents=True,exist_ok=True)
    manifest=json.loads((source/"manifest.json").read_text(encoding="utf-8"))
    metrics=[]
    for key,item in manifest["assets"].items():
        shutil.copy2(source/(key+".glb"),stage/(key+".glb"))
        metrics.append({"path":key+".glb","after":{"triangles":item["metadata"]["triangles"]}})
    (stage/"glb_metrics.json").write_text(json.dumps(metrics),encoding="utf-8")
    (stage/"project.godot").write_text('config_version=5\n[application]\nconfig/name="Bridge research fixture"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding="utf-8")
    shutil.copy2(root/"pipeline/processors/custom_lowpoly/verify_glb.gd",stage/"verify_glb.gd")
    env=os.environ.copy()
    env["APPDATA"]=str(stage/"user_data")
    env["LOCALAPPDATA"]=str(stage/"local_data")
    result=subprocess.run([str(root/"tools/godot/Godot_v4.3-stable_win64_console.exe"),
                           "--headless","--path",str(stage),"--script","res://verify_glb.gd"],
                          env=env,capture_output=True,text=True,encoding="utf-8",timeout=30,
                          creationflags=subprocess.CREATE_NO_WINDOW)
    log=result.stdout+result.stderr
    (root/"results/261009_bridge_research/godot_glb_check.log").write_text(log,encoding="utf-8")
    print(log)
    if result.returncode or f"GLB READ OK: {len(metrics)}" not in log or "ERROR" in log:
        raise RuntimeError("격리 GLB 확인 실패")


if __name__=="__main__":
    main()
