"""OSM 도로 유형·포장 태그를 보행로 에셋 씬으로 대응시킨다."""
from __future__ import annotations

ROAD = "res://assets/generated/road_assets/"
BENCH_SCENE = "res://assets/generated/garden_furniture/near/park_bench.tscn"

SURFACE_STYLES = {
    "asphalt": "walk_asphalt",
    "concrete": "walk_concrete",
    "paving_stones": "walk_paver_gray",
    "sett": "walk_stone_small",
    "bricks": "walk_brick_running",
    "wood": "walk_boardwalk",
    "gravel": "walk_gravel",
    "fine_gravel": "walk_gravel",
    "compacted": "walk_gravel",
    "dirt": "walk_earth",
    "ground": "walk_earth",
    "earth": "walk_earth",
    "unpaved": "walk_earth",
    "grass": "walk_forest",
    "rubber": "walk_rubber",
}

HIGHWAY_STYLES = {
    "cycleway": "walk_shared_cycle",
    "footway": "walk_paver_gray",
    "path": "walk_earth",
    "pedestrian": "walk_granite",
}


def style_for(highway: str, surface: str | None, lon: float, garden_lon_range: list[float]) -> str:
    """보행로 씬 경로. 포장 태그가 우선이고, 없으면 유형별 기본값, 국가정원 구간 보도는 적갈색 블록이다."""
    style = SURFACE_STYLES.get(surface or "")
    if style is None:
        style = HIGHWAY_STYLES.get(highway, "walk_paver_gray")
        if highway == "footway" and garden_lon_range[0] <= lon <= garden_lon_range[1]:
            style = "walk_paver_red"
    return f"{ROAD}{style}_w3_straight.tscn"
