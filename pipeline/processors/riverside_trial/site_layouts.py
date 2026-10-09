"""보도 직선 구간을 따라 보행로·부속물·정원 시설물을 배열하는 레이아웃."""
from __future__ import annotations

from dataclasses import dataclass

from .corridor_search import Corridor

ROAD = "res://assets/generated/road_assets/"
GARDEN = "res://assets/generated/garden_furniture/near/"
WALK_HALF_WIDTH_M = 1.5
WALK_SURFACE_Y_M = 0.15


@dataclass
class Item:
    """세그먼트 기준 상대 배치. along은 진행 방향, lateral은 진행 방향 오른손 법선 방향이다."""

    key: str
    scene: str
    segment: int
    along: float
    lateral: float
    yaw_rel: float
    y_offset: float
    half_extent: tuple[float, float]  # (로컬 X, 로컬 Z) 반폭, 미리보기용


def _walk(scene: str, count: int) -> list[Item]:
    return [Item("walk", ROAD + scene, i, 0.0, 0.0, 0.0, 0.0, (1.5, 6.0)) for i in range(count)]


def _bench(scene: str, i: int, side: float) -> Item:
    # 벤치 길이축(X)을 보도와 나란히 둔다
    return Item("bench", GARDEN + scene, i, 0.0, side * (WALK_HALF_WIDTH_M + 0.5), 90.0 * side, 0.0, (0.9, 0.26))


def garden_promenade(count: int) -> list[Item]:
    """국가정원: 적갈색 블록 보도, 한쪽 녹지 띠, 맞은편 벤치와 석재 광장 위 정자."""
    mid = count // 2
    items = _walk("walk_paver_red_w3_straight.tscn", count)
    for i in range(count):
        items.append(Item("planter", ROAD + "addon_planter_strip.tscn", i, 0.0, -(WALK_HALF_WIDTH_M + 0.75), 0.0, 0.0, (0.75, 6.0)))
        if i != mid and i % 2 == 0:
            items.append(_bench("park_bench.tscn", i, 1.0))
    plaza_lateral = WALK_HALF_WIDTH_M + 3.0
    items.append(Item("plaza", ROAD + "deck_stone_plaza_6m.tscn", mid, 0.0, plaza_lateral, 0.0, 0.0, (3.0, 3.0)))
    items.append(Item("pavilion", GARDEN + "korean_pavilion.tscn", mid, 0.0, plaza_lateral, 0.0, WALK_SURFACE_Y_M, (2.95, 2.6)))
    return items


def cycle_path(count: int) -> list[Item]:
    """중류 둔치: 보행·자전거 공유길, 평벤치, 소형 천막 쉼터."""
    mid = count // 2
    items = _walk("walk_shared_cycle_w3_straight.tscn", count)
    for i in range(1, count, 2):
        items.append(_bench("backless_bench.tscn", i, 1.0))
    items.append(Item("canopy", GARDEN + "square_canopy.tscn", mid, 0.0, -(WALK_HALF_WIDTH_M + 2.1), 0.0, 0.0, (1.6, 1.6)))
    items.append(Item("picnic", GARDEN + "picnic_table.tscn", mid, 0.0, -(WALK_HALF_WIDTH_M + 2.1), 0.0, 0.0, (0.9, 0.81)))
    return items


def waterside_picnic(count: int) -> list[Item]:
    """명촌 둔치: 수변 석판 보도, 피크닉 테이블, 벤치, 행사 천막."""
    mid = count // 2
    items = _walk("walk_waterside_w3_straight.tscn", count)
    for i in range(count):
        if i == mid:
            continue
        if i % 2 == 0:
            items.append(Item("picnic", GARDEN + "picnic_table.tscn", i, 0.0, WALK_HALF_WIDTH_M + 1.6, 0.0, 0.0, (0.9, 0.81)))
        else:
            items.append(_bench("park_bench.tscn", i, 1.0))
    items.append(Item("marquee", GARDEN + "festival_marquee.tscn", mid, 0.0, -(WALK_HALF_WIDTH_M + 4.1), 0.0, 0.0, (3.1, 6.1)))
    return items


LAYOUTS = {
    "garden_promenade": garden_promenade,
    "cycle_path": cycle_path,
    "waterside_picnic": waterside_picnic,
}


def resolve(item: Item, corridor: Corridor) -> tuple[float, float, float]:
    """상대 배치를 월드 (x, z, yaw)로 바꾼다."""
    c = corridor.centers[item.segment]
    d, n = corridor.direction, corridor.normal
    x = c[0] + d[0] * item.along + n[0] * item.lateral
    z = c[1] + d[1] * item.along + n[1] * item.lateral
    return x, z, corridor.yaw_degrees + item.yaw_rel
