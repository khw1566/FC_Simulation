extends RefCounted
class_name RenderOrder

## 반투명 그리기 순서(render_priority) 단일 정의.
## 화면 전체 구름층은 깊이를 쓰지 않으므로, 그보다 뒤에 그려지는 반투명은 거리와 무관하게 구름 위에 덮인다.
## 그래서 앞뒤 관계를 우선순위로 정한다.
## - 지면·수면에 붙은 반투명(수면, 항적)은 구름보다 먼저 그린다. 구름 적분은 불투명 깊이(수면 아래 하상)에서
##   멈추므로, 이 순서면 수면 앞의 구름만 수면을 덮는다(구름 뒤 강이 비쳐 보이지 않는다).
## - 구름층은 핵폭발 볼륨을 사이에 두고 뒤쪽 구간과 앞쪽 구간 두 패스로 나눈다. 버섯구름보다 먼 구름은 먼저,
##   가까운 구름은 나중에 그려서 항상 가까운 쪽이 앞에 보인다.
## 순서: 수면 → 항적 → 구름 그림자 → 뒤쪽 구름 → 폭발 볼륨·응결 껍질(폭발 4건 × 2칸) → 앞쪽 구름 → 빛줄기 → 기타(0)

const WATER_SURFACE := Material.RENDER_PRIORITY_MIN
const WATER_DETAIL := Material.RENDER_PRIORITY_MIN + 1
const CLOUD_SHADOW := Material.RENDER_PRIORITY_MIN + 2
const CLOUD_BEHIND := Material.RENDER_PRIORITY_MIN + 3
const NUCLEAR_FIRST := Material.RENDER_PRIORITY_MIN + 4
const NUCLEAR_SLOTS := 4
const CLOUD_FRONT := NUCLEAR_FIRST + NUCLEAR_SLOTS * 2
const LIGHT_RAYS := CLOUD_FRONT + 1

## 폭발 그리기 칸(0 = 가장 먼 폭발)의 [볼륨, 응결 껍질] 우선순위
static func nuclear_slot(slot: int) -> Vector2i:
	var base := NUCLEAR_FIRST + clampi(slot, 0, NUCLEAR_SLOTS - 1) * 2
	return Vector2i(base, base + 1)
