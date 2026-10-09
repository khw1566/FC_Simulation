"""도로·보행로 유형과 연결 규격 정의."""
import math

LENGTH = 12.0
LANE_WIDTH = 3.25
WALK_HEIGHT = .15
ROAD_TYPES = {
    "urban": ("도시 아스팔트", "asphalt", list(range(1, 9)), .5),
    "rural": ("일반 지방도로", "asphalt_worn", [1, 2, 4], .5),
    "highway": ("고속도로", "asphalt", [2, 4, 6, 8], 1.25),
    "industrial": ("공단 도로", "concrete", [1, 2, 4, 6], .5),
    "residential": ("주거 공유도로", "paver_gray", [1, 2], .5),
    "gravel": ("비포장 차량도로", "gravel", [1, 2], .5),
    "concrete": ("콘크리트 차도", "concrete", [2, 4], .5),
}
WALK_TYPES = {
    "concrete": ("일반 콘크리트 보도", "concrete", "slabs"),
    "concrete_worn": ("노후 콘크리트 보도", "concrete_worn", "slabs"),
    "asphalt": ("아스팔트 보행로", "asphalt_worn", "plain"),
    "paver_gray": ("회색 인터로킹 보도", "paver_gray", "pavers"),
    "paver_sand": ("모래색 인터로킹 보도", "paver_sand", "pavers"),
    "paver_red": ("적갈색 인터로킹 보도", "brick_red", "pavers"),
    "brick_running": ("줄눈 벽돌 보도", "brick_red", "bricks"),
    "brick_herringbone": ("엇갈린 사선 벽돌 보도", "brick_red", "diagonal"),
    "stone_large": ("대형 석판 보도", "stone", "large_slabs"),
    "stone_small": ("소형 석재 보도", "stone", "pavers"),
    "cobblestone": ("불규칙 돌포장 보도", "stone_dark", "cobbles"),
    "granite": ("밝은 화강석 보도", "granite", "slabs"),
    "permeable": ("투수블록 보도", "paver_gray", "permeable"),
    "wood_long": ("종방향 목재 데크", "wood", "wood_long"),
    "wood_cross": ("횡방향 목재 데크", "wood", "wood_cross"),
    "boardwalk": ("해안 목재 산책로", "wood_weathered", "wood_cross"),
    "gravel": ("자갈 산책로", "gravel", "gravel"),
    "sand": ("모래 산책로", "sand", "gravel"),
    "earth": ("다진 흙길", "earth", "earth"),
    "forest": ("숲속 오솔길", "earth_dark", "earth"),
    "rubber": ("탄성포장 보행로", "rubber", "plain"),
    "shared_cycle": ("보행·자전거 공유길", "asphalt_worn", "shared"),
    "tactile_guided": ("점자 유도블록 보도", "concrete", "tactile"),
    "waterside": ("수변 석판 산책로", "stone", "large_slabs"),
}


def profile(kind, width, lanes=0, height=0):
    return {"id": f"{kind}_w{width:.2f}_h{height:.2f}", "kind": kind,
            "width_m": width, "surface_y_m": height, "lane_count": lanes,
            "lane_width_m": LANE_WIDTH if lanes else None}


def port(name, position, direction, cross_section):
    return {"name": name, "position_m": list(position),
            "outward_direction": list(direction), "profile": cross_section}


def route(shape, width):
    if shape == "straight":
        return [(0, -LENGTH/2, 0), (0, LENGTH/2, 0)]
    angle = math.pi/4 if shape == "curve45" else math.pi/2
    radius = max(LENGTH, math.floor(width/LANE_WIDTH)*LANE_WIDTH+4)
    count = max(12, math.ceil(radius*angle/.6))
    return [(radius*(1-math.cos(angle*i/count)),
             -LENGTH/2+radius*math.sin(angle*i/count), angle*i/count)
            for i in range(count+1)]


def route_ports(points, cross_section):
    x,z,a = points[0]; u,v,b = points[-1]
    y = cross_section["surface_y_m"]
    return [port("Start", (x,y,z), (-math.sin(a),0,-math.cos(a)), cross_section),
            port("End", (u,y,v), (math.sin(b),0,math.cos(b)), cross_section)]


def specs():
    result=[]
    for style,(label,material,lanes,shoulder) in ROAD_TYPES.items():
        for count in lanes:
            for shape in ("straight", "curve45", "curve90"):
                result.append({"key":f"road_{style}_{count}l_{shape}",
                    "label_ko":f"{label} {count}차선 / {shape}", "kind":"road",
                    "style":style,"material":material,"lanes":count,
                    "width":count*LANE_WIDTH+2*shoulder,"shape":shape})
    for style,(label,material,pattern) in WALK_TYPES.items():
        for width in (1.5,3.0,4.5):
            result.append({"key":f"walk_{style}_w{width:g}_straight",
                "label_ko":f"{label} / 폭 {width:g}m", "kind":"walk",
                "style":style,"material":material,"pattern":pattern,
                "width":width,"shape":"straight"})
        result.append({"key":f"walk_{style}_w3_curve90",
            "label_ko":f"{label} / 90도 곡선", "kind":"walk",
            "style":style,"material":material,"pattern":pattern,
            "width":3.0,"shape":"curve90"})
    return result
