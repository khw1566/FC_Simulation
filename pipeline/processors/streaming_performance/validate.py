"""분리 프로젝트에서 LOD 교체·분할·건물 동시 업로드와 기존 노반을 확인한다."""
import json
import os
import shutil
import subprocess
from pathlib import Path

from run import ROOT, fixture, verify


def validate():
    project = ROOT/"previews/asset_browser/streaming_check/validation/project"
    copied = fixture(project)
    for name in ("state_check.gd","state_host.gd","detail_field.gd"):
        shutil.copy2(Path(__file__).parent/name,project/name)
    env = os.environ.copy()
    for key in ("APPDATA","LOCALAPPDATA"):
        env[key] = str(ROOT/f"previews/sp_env/{key.lower()}")
    godot = ROOT/"tools/godot/Godot_v4.3-stable_win64_console.exe"
    commands = (("import",["--headless","--editor","--quit"]),
                ("state",["--rendering-method","forward_plus","--script","res://state_check.gd"]),
                ("formation",["--rendering-method","forward_plus","--script","res://check.gd"]))
    for name,args in commands:
        result = subprocess.run([str(godot),"--path",str(project),*args],env=env,capture_output=True,encoding="utf-8",errors="replace",timeout=60)
        log = result.stdout+result.stderr
        (project.parent/f"{name}.log").write_text(log,encoding="utf-8")
        print(log[-4000:],flush=True)
        assert result.returncode==0 and "SCRIPT ERROR" not in log and "ERROR:" not in log
        if name!="import":
            assert ("STREAMING_STATE_OK" if name=="state" else "ROAD_FORMATION_CHECK_OK") in log
    report = {"state":json.loads((project/"state_verification.json").read_text(encoding="utf-8")),
              "formation":json.loads((project/"verification.json").read_text(encoding="utf-8")),
              "full_world_run":False,"assets_changed":False,
              "source_sha256":{p:verify.digest(project/p) for p in sorted(copied)}}
    assert all(verify.digest(ROOT/"godot_project"/p)==h for p,h in report["source_sha256"].items())
    verify.save(ROOT/"results/streaming_performance/validation.json",report)


if __name__=="__main__":
    validate()
