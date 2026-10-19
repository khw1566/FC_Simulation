extends RefCounted
class_name NuclearYieldCatalog

## 핵폭발 위력 5종 프리셋과 위력별 규모 환산식을 제공한다.
## 화구 반경·열복사 극대 시각은 Glasstone & Dolan(1977) 근사식, 구름 높이·갓 반경·안정화 시각은 공개 시험 관측 범위의 시각화용 추정이다.
## 실제 피해 산정에 사용하지 않는다.

const PRESETS := [
	{"id": "10kt", "label": "10 kt", "kilotons": 10.0, "cloud_top": 9000.0, "cloud_bottom": 5500.0, "cap_radius": 2500.0, "stabilize": 240.0, "standoff": 6000.0},
	{"id": "50kt", "label": "50 kt", "kilotons": 50.0, "cloud_top": 12500.0, "cloud_bottom": 7800.0, "cap_radius": 4500.0, "stabilize": 300.0, "standoff": 9000.0},
	{"id": "500kt", "label": "500 kt", "kilotons": 500.0, "cloud_top": 18500.0, "cloud_bottom": 11000.0, "cap_radius": 10000.0, "stabilize": 420.0, "standoff": 16000.0},
	{"id": "1mt", "label": "1 Mt", "kilotons": 1000.0, "cloud_top": 21500.0, "cloud_bottom": 12500.0, "cap_radius": 13000.0, "stabilize": 480.0, "standoff": 22000.0},
	{"id": "10mt", "label": "10 Mt", "kilotons": 10000.0, "cloud_top": 37000.0, "cloud_bottom": 18000.0, "cap_radius": 32000.0, "stabilize": 600.0, "standoff": 45000.0},
]

static func count() -> int:
	return PRESETS.size()

static func get_preset(index: int) -> Dictionary:
	return (PRESETS[clampi(index, 0, PRESETS.size() - 1)] as Dictionary).duplicate()

## 화구 최대 반경(m): R = 55 W^0.4 (W: kt)
static func fireball_max_radius(kilotons: float) -> float:
	return 55.0 * pow(kilotons, 0.4)

## 열복사 2차 극대 시각(s): t = 0.0417 W^0.44
static func thermal_peak_time(kilotons: float) -> float:
	return 0.0417 * pow(kilotons, 0.44)

## 화구가 지면에 거의 닿는 저고도 공중폭발 높이(m). 먼지 기둥이 바로 빨려 올라간다.
static func burst_height(kilotons: float) -> float:
	return fireball_max_radius(kilotons) * 0.95

## 섬광이 주변 구름·지형을 태양광 수준 이상으로 비추는 거리(m).
static func flash_light_radius(kilotons: float) -> float:
	return 2500.0 * pow(kilotons, 0.33)

## 지면 먼지 파도(기저 서지)의 최대 높이(m).
static func surge_height(kilotons: float) -> float:
	return 100.0 + 90.0 * pow(kilotons, 1.0 / 3.0)

## 윌슨 응결운이 보였다가 사라지는 시간(s).
static func wilson_lifetime(kilotons: float) -> float:
	return 0.8 + 0.25 * pow(kilotons, 1.0 / 3.0)
