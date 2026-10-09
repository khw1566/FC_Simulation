"""독립 조립 예제. 실제 항구 좌표나 배치 데이터를 만들지 않는다."""
import math
from .terrain_fit import connected,world_port


def specs():
    return {
      "fishing_harbor_demo": {"label_ko":"소형 어항 조립 예제","placements":[
        ("quay_12x12_sea_edge",(0,0,0),0),("quay_foundation_4m",(-3,0,0),0),("quay_foundation_4m",(3,0,0),0),
        ("fishing_crane_post",(3,0,0),0),("mooring_bollard",(5,0,-4),0),("mooring_bollard",(5,0,4),0),
        ("fender_block",(6.2,-1,-3),0),("fender_tire",(6.2,-1,3),0),
        ("fishing_shed",(-3,0,-13),0),("shore_power_water",(4,0,4),0),
        ("breakwater_straight_12m",(-9,0,0),0),("breakwater_head",(-9,0,9),0),("lighthouse_red",(-9,0,9),0),
        ("tetrapod_2.5m",(-6.5,-1,9),.3),("tetrapod_2.5m",(-6.5,-1,6),1.1)],
        "connections":[(("breakwater_straight_12m",0,"End"),("breakwater_head",0,"Start"))],
        "external_instances":[{"scene":"res://assets/generated/vessels/fishing_boat.tscn","position_m":[11,-2,0],"rotation_y_rad":0,"anchor":"waterline"}],"assumed_water_y_m":-2},
      "container_terminal_demo": {"label_ko":"컨테이너 부두 조립 예제","placements":[
        ("quay_12x12_sea_edge",(0,0,0),0),("quay_12x12_sea_edge",(0,0,12),0),
        ("crane_rails_12m",(0,0,0),0),("crane_rails_12m",(0,0,12),0),
        ("container_crane_feeder",(0,0,0),0),("container_stack_2x2x2",(-15,0,0),0),
        ("container_stack_3x2x3",(-25,0,12),0),("harbor_warehouse",(-18,0,-20),0)],
        "connections":[(("quay_12x12_sea_edge",0,"End"),("quay_12x12_sea_edge",1,"Start")),
                        (("crane_rails_12m",0,"End"),("crane_rails_12m",1,"Start"))]},
      "terrain_height_demo": {"label_ko":"수평 상판·지형 높이 전환 예제","placements":[
        ("quay_6x12",(0,0,0),0),("quay_ramp_rise2m",(0,0,12),0),("quay_6x12",(0,2,24),0),
        ("pier_pile_4m",(-2,0,-4),0),("pier_pile_8m",(2,0,4),0),
        ("pier_pile_8m",(-2,2,20),0),("pier_pile_12m",(2,2,28),0),
        ("quay_walk_adapter_3m",(0,2,33),0)],
        "connections":[(("quay_6x12",0,"End"),("quay_ramp_rise2m",0,"Start")),
                        (("quay_ramp_rise2m",0,"End"),("quay_6x12",1,"Start")),
                        (("quay_6x12",1,"End"),("quay_walk_adapter_3m",0,"Start"))]}}


def validate(models,example):
    def locate(key,index,name):
        matching=[item for item in example["placements"] if item[0]==key]
        _,position,yaw=matching[index]
        port=next(port for port in models[key].ports if port["name"]==name)
        return world_port(port,position,yaw)
    for left,right in example["connections"]:
        if not connected(locate(*left),locate(*right)):
            raise ValueError(f"접속 불일치: {left} / {right}")
    return len(example["connections"])


def combined(models,example):
    from .mesh import HarborMesh
    from .terrain_fit import rotate
    mesh=HarborMesh()
    for key,position,yaw in example["placements"]:
        for face in models[key].mesh.faces:
            vertices=[tuple(v+position[i] for i,v in enumerate(rotate(point,yaw))) for point in face[:3]]
            mesh.faces.append((*vertices,tuple(rotate(face[3],yaw)),face[4]))
    return mesh


def bounds(models,example,project):
    """조립과 외부 참조 모델의 로컬 범위를 카탈로그에 기록한다."""
    import json
    from pathlib import Path
    from .terrain_fit import rotate
    points=[]; triangles=0
    instances=[(models[key].metadata(),position,yaw) for key,position,yaw in example["placements"]]
    for external in example.get("external_instances",[]):
        uri=external["scene"].replace(".tscn",".glb")
        source=Path(project)/uri.removeprefix("res://")
        manifest=json.loads((source.parent/"manifest.json").read_text(encoding="utf-8"))
        entry=next(item for item in manifest["assets"].values() if item.get("file_path")==uri)
        instances.append((entry["metadata"],external["position_m"],external["rotation_y_rad"]))
    for metadata,position,yaw in instances:
        triangles+=metadata["triangles"]
        lo,hi=metadata["aabb_min_m"],metadata["aabb_max_m"]
        corners=[(x,y,z) for x in (lo[0],hi[0]) for y in (lo[1],hi[1]) for z in (lo[2],hi[2])]
        points.extend([[v+position[i] for i,v in enumerate(rotate(point,yaw))] for point in corners])
    return {"aabb_min_m":[min(p[i] for p in points) for i in range(3)],"aabb_max_m":[max(p[i] for p in points) for i in range(3)],"triangles":triangles}
