"""공유 재질과 독립 조립 예제를 작성한다."""
import json
import shutil
from pathlib import Path

BASE="res://assets/generated/park_vegetation/"


def write_support(out):
    (out/"module_index.json").write_text(json.dumps({"batch_factory.gd":"32m MultiMesh 및 거리 LOD",
        "composition.gd":"독립 조립 예제","surface.gdshader":"정점색 및 바람·거리 전환",
        "ground.gdshader":"범용 바닥 표현"},ensure_ascii=False,indent=2),encoding="utf-8")
    for name in ("batch_factory.gd","composition.gd","surface.gdshader","ground.gdshader"):
        shutil.copyfile(Path(__file__).with_name(name),out/name)
    for key,color in {"lawn":(.22,.34,.14),"meadow":(.32,.37,.17),"soil":(.32,.25,.17),
                      "gravel":(.47,.46,.40),"bamboo_litter":(.38,.33,.20)}.items():
        (out/f"ground_{key}.tres").write_text('[gd_resource type="ShaderMaterial" load_steps=2 format=3]\n'
            f'[ext_resource type="Shader" path="{BASE}ground.gdshader" id="1"]\n'
            '[resource]\nshader = ExtResource("1")\n'
            f'shader_parameter/base_color = Color({color[0]}, {color[1]}, {color[2]}, 1)\n',encoding="utf-8")
    (out/"README.md").write_text('''# 공원·정원 공용 에셋 첫 묶음
범용 절차 모델이며 태화강 국가정원의 실제 종·품종·배치를 재현했다고 주장하지 않는다. 1단위=1m, Y=0 지표 기준이다.

- 16종, 46 LOD 모델. 불투명 정점색, 모델당 표면 1개, 외부 텍스처 없음.
- batch_factory.gd의 add_batches(parent, key, transforms)는 32m 청크 MultiMesh를 생성한다. 개별 LOD 거리와 소거는 catalog.json을 참조한다.
- 풀은 60m 이후 소거한다. 넓은 바닥은 ground_*.tres 5종으로 표현하고 풀 메시로 채우지 않는다.
- 작은 잎의 바람은 surface.gdshader의 wind_strength로 조정한다. 기본값 0이며 조립 예제는 0.04다. 바닥과 조경석은 움직이지 않는다.
- 생울타리 접속점은 catalog.json의 connection_ports에 기록한다. 모서리는 L자, 끝단에는 한 개의 접속점이 있다.
- compositions/의 5개 씬은 독립 배치 예제다. 기존 수목·대나무·벤치·보행로를 읽기 전용으로 참조한다. 실제 좌표는 없다.
- 생성: 명시적 Python으로 pipeline/processors/park_vegetation/generate.py 실행.
- 검증은 previews/asset_browser/park_vegetation_check에서만 수행한다. 게임에 자동 연결하지 않는다.
''',encoding="utf-8")


def write_compositions(root,out,models):
    presetdir=out/"compositions"; presetdir.mkdir(exist_ok=True)
    generated=root/"godot_project/assets/generated"
    roadfiles=sorted((generated/"road_assets").rglob("walk_concrete_w3_straight.tscn"))
    road="res://"+roadfiles[0].relative_to(root/"godot_project").as_posix() if roadfiles else None
    refs={"shrub":"res://assets/generated/trees/shrub_lod0.scn",
          "tree":"res://assets/generated/trees/broadleaf_lod0.scn",
          "bamboo":"res://assets/generated/bamboo/bamboo_clump_lod0.scn",
          "bench":"res://assets/generated/garden_furniture/near/park_bench.tscn","path":road}
    presets={
        "lawn_plaza":("잔디 광장","lawn",["grass_sparse","grass_dense","hedge_2m","rock_small"],["tree","bench"]),
        "flower_path":("꽃길","lawn",["flower_low_round","flower_low_edge","hedge_1m"],["shrub","path"]),
        "naturalist_bed":("자연형 화단","meadow",["perennial_upright","perennial_dry","ornamental_seedhead","rock_cluster"],["shrub"]),
        "bamboo_edge":("대숲 가장자리","bamboo_litter",["ornamental_fine","rock_medium","grass_sparse"],["bamboo","path"]),
        "shaded_rest":("그늘 쉼터","soil",["flower_low_edge","hedge_corner","hedge_end","rock_small"],["tree","bench","path"])}
    for key,(label,ground,plants,reuse) in presets.items():
        reused=[{"path":refs[r],"position":[-5+i*4,0,-5],"role":r} for i,r in enumerate(reuse) if refs[r]]
        data={"id":key,"label":label,"ground":ground,"plants":plants,"reused":reused,"seed":170+len(label)}
        (presetdir/f"{key}.json").write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf-8")
        (presetdir/f"{key}.tscn").write_text('[gd_scene load_steps=2 format=3]\n'
            f'[ext_resource type="Script" path="{BASE}composition.gd" id="1"]\n'
            f'[node name="{key}" type="Node3D"]\nscript = ExtResource("1")\n'
            f'preset_path = "{BASE}compositions/{key}.json"\n',encoding="utf-8")
