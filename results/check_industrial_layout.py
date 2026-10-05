"""생성된 JSON만을 읽어 공단 경계·시설 보존·도로 연결·모델 점유 형상을 재검사."""
import json
import math
import sys
from pathlib import Path

from shapely.geometry import Polygon, LineString, Point, shape, box
from shapely.affinity import rotate, scale, translate
from shapely.ops import unary_union

root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/"pipeline/processors"))
from industrial_zones.site_inputs import IndustrialSiteInputs

config=IndustrialSiteInputs.read(root/"config/industrial_zones.json")
inputs=IndustrialSiteInputs(root,config)
folder=root/f"godot_project/assets/generated/industrial_zones/{config['map_id']}"
data=IndustrialSiteInputs.read(folder/"placements.json")
roads=IndustrialSiteInputs.read(folder/"roads.json")["roads"]
failures=[]
checked=0
for zone in data["zones"]:
    boundary=shape(zone["world_polygon"])
    safe=inputs.safe_geometry(boundary,include_roads=True)
    road_safe=inputs.safe_geometry(boundary)
    owned=[p for p in data["placements"] if p["zone_id"]==zone["zone_id"]]
    new_roads=[r for r in roads if r["zone_id"]==zone["zone_id"]]
    footprints=[]
    for placement in owned:
        footprint=Polygon(placement["footprint_xz"])
        if not safe.buffer(0.02).covers(footprint):
            failures.append(placement["id"]+": 제외 영역 침범")
        lo,hi=placement["aabb_min_m"],placement["aabb_max_m"]
        expected=translate(rotate(scale(box(lo[0],lo[2],hi[0],hi[2]),xfact=placement["scale"],yfact=placement["scale"],origin=(0,0)),
                                  -placement["yaw_degrees"],origin=(0,0)),placement["position"][0],placement["position"][2])
        if expected.hausdorff_distance(footprint)>0.01:
            failures.append(placement["id"]+": 모델 전체 점유 범위 불일치")
        if any(footprint.intersects(previous) for previous in footprints):
            failures.append(placement["id"]+": 설비 간 중복")
        for attachment in placement.get("attachments",[]):
            port=[a+b for a,b in zip(attachment["position_m"],attachment["port_attachment_m"])]
            if math.dist(port,attachment["port_parent_m"])>0.001:
                failures.append(placement["id"]+": 배관 포트 불일치")
        for road in new_roads:
            if footprint.intersects(LineString(road["points_xz"]).buffer(road["width_m"]/2)):
                failures.append(placement["id"]+": 생성 도로와 중복")
        footprints.append(footprint)
        checked+=1
    source_roads=[inputs.roads[int(i)] for i in inputs.road_tree.query(boundary)]
    connected=unary_union([r["line"].buffer(r["width"]/2) for r in source_roads]+[LineString(r["points_xz"]).buffer(r["width_m"]/2) for r in new_roads])
    pieces=[connected] if connected.geom_type=="Polygon" else list(connected.geoms)
    join=Point(zone["connection"]["point_xz"])
    entry=next((polygon for polygon in pieces if polygon.covers(join)),None)
    for road in new_roads:
        line=LineString(road["points_xz"])
        if not road_safe.buffer(0.02).covers(line.buffer(road["width_m"]/2,cap_style=2)):
            failures.append(road["id"]+": 도로의 제외 영역 침범")
        if entry is None or not entry.covers(line.interpolate(0.5,normalized=True)):
            failures.append(road["id"]+": 기존 도로 연결 단절")
report={"zones":len(data["zones"]),"checked_assets":checked,"checked_roads":len(roads),"failures":failures}
(root/"results/261004_IndustrialLayoutValidation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps(report,ensure_ascii=False))
raise SystemExit(1 if failures else 0)
