"""지도 실행 없이 DEM 표본을 입력받아 지지대 길이와 배치 높이를 제안한다."""
import math


def rotate(point,yaw):
    x,y,z=point
    return [x*math.cos(yaw)+z*math.sin(yaw),y,-x*math.sin(yaw)+z*math.cos(yaw)]


def reanchor_rotated_points(points,ground_y):
    """회전이 끝난 테트라포드 정점의 최저점이 지표에 닿도록 이동량을 반환한다."""
    return ground_y-min(p[1] for p in points)


def support_plan(samples,deck_world_y,top_local_y=None,embed_m=.25,available=None,family="quay_foundation"):
    """상판을 수평으로 유지하고 각 지지 위치의 바닥 높이를 별도로 처리한다."""
    defaults={"quay_foundation":(1,2,4,8),"pier_pile":(4,8,12),"seawall":(2,4,8)}
    if family not in defaults: raise ValueError("지원하지 않는 기초 계열: "+family)
    if available is None: available=defaults[family]
    if top_local_y is None: top_local_y=0 if family=="seawall" else -.6
    result=[]
    for x,z,ground in samples:
        if ground is None or not math.isfinite(ground):
            result.append({"position_xz_m":[x,z],"status":"missing_terrain_sample"})
            continue
        required=deck_world_y+top_local_y-ground+embed_m
        if required<=0:
            result.append({"position_xz_m":[x,z],"status":"terrain_above_support_top","required_depth_m":required})
            continue
        depth=next((n for n in available if n>=required),None)
        asset=None if depth is None else (f"seawall_12m_depth{depth}m" if family=="seawall" else f"{family}_{depth}m")
        result.append({"position_xz_m":[x,z],"required_depth_m":required,"selected_depth_m":depth,"asset_key":asset,
                       "status":"ready" if depth else "needs_custom_depth","root_world_y_m":deck_world_y})
    return result


def connected(left,right,tolerance=.001):
    same=left["profile"]==right["profile"] and abs(left.get("width_m",0)-right.get("width_m",0))<tolerance
    distance=math.sqrt(sum((left["position_m"][i]-right["position_m"][i])**2 for i in range(3)))
    dot=sum(left["outward_direction"][i]*right["outward_direction"][i] for i in range(3))
    return same and distance<tolerance and dot<-1+tolerance


def world_port(port,position,yaw):
    return {**port,"position_m":[v+position[i] for i,v in enumerate(rotate(port["position_m"],yaw))],
            "outward_direction":rotate(port["outward_direction"],yaw)}
