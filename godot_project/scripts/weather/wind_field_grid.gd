extends RefCounted
class_name WindFieldGrid

## 3차원 바람 벡터 격자의 색인·좌표·삼선형 보간·3D 텍스처 변환.
## 지도 원점 중심 수평 160km(2.5km 간격) × 고도 0~37.5km(2.5km 간격)를 덮고, 밖은 가장자리 값으로 고정한다.
## 메모리 배치는 고도 층 → z 행 → x 열 순서이며 3D 텍스처(너비 x, 높이 z, 깊이 고도)와 같다.

const NX := 64
const NY := 16
const NZ := 64
const HALF_EXTENT := 80000.0
const TOP := 37500.0
const ORIGIN := Vector3(-HALF_EXTENT, 0.0, -HALF_EXTENT)
const CELL := Vector3(2.0 * HALF_EXTENT / float(NX - 1), TOP / float(NY - 1), 2.0 * HALF_EXTENT / float(NZ - 1))

static func count() -> int:
	return NX * NY * NZ

static func index(ix: int, iy: int, iz: int) -> int:
	return (iy * NZ + iz) * NX + ix

static func cell_position(ix: int, iy: int, iz: int) -> Vector3:
	return ORIGIN + Vector3(float(ix), float(iy), float(iz)) * CELL

static func level_altitude(iy: int) -> float:
	return float(iy) * CELL.y

## 셰이더 텍스처 차원(너비 x, 높이 z, 깊이 고도)
static func texture_dims() -> Vector3:
	return Vector3(NX, NZ, NY)

static func sample(data: PackedVector3Array, pos: Vector3) -> Vector3:
	if data.size() != count():
		return Vector3.ZERO
	var g := (pos - ORIGIN) / CELL
	var fx := clampf(g.x, 0.0, float(NX - 1) - 0.0001)
	var fy := clampf(g.y, 0.0, float(NY - 1) - 0.0001)
	var fz := clampf(g.z, 0.0, float(NZ - 1) - 0.0001)
	var ix := int(fx)
	var iy := int(fy)
	var iz := int(fz)
	var tx := fx - float(ix)
	var ty := fy - float(iy)
	var tz := fz - float(iz)
	var c00 := data[index(ix, iy, iz)].lerp(data[index(ix + 1, iy, iz)], tx)
	var c10 := data[index(ix, iy, iz + 1)].lerp(data[index(ix + 1, iy, iz + 1)], tx)
	var c01 := data[index(ix, iy + 1, iz)].lerp(data[index(ix + 1, iy + 1, iz)], tx)
	var c11 := data[index(ix, iy + 1, iz + 1)].lerp(data[index(ix + 1, iy + 1, iz + 1)], tx)
	return c00.lerp(c10, tz).lerp(c01.lerp(c11, tz), ty)

## 고도 층마다 RGBA 반정밀 이미지 한 장(rgb = 바람 벡터 m/s)
static func to_images(data: PackedVector3Array) -> Array[Image]:
	var images: Array[Image] = []
	var floats := PackedFloat32Array()
	floats.resize(NX * NZ * 4)
	for iy in range(NY):
		var base := iy * NZ * NX
		for j in range(NX * NZ):
			var v := data[base + j]
			floats[j * 4] = v.x
			floats[j * 4 + 1] = v.y
			floats[j * 4 + 2] = v.z
			floats[j * 4 + 3] = 1.0
		var image := Image.create_from_data(NX, NZ, false, Image.FORMAT_RGBAF, floats.to_byte_array())
		image.convert(Image.FORMAT_RGBAH)
		images.append(image)
	return images
