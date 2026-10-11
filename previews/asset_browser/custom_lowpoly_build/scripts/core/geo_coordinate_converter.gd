extends RefCounted
class_name GeoCoordinateConverter

# 기본 시모노세키-고쿠라 BBOX
static var bbox_south: float = 33.8000
static var bbox_north: float = 34.0500
static var bbox_west: float = 130.8000
static var bbox_east: float = 131.1000
static var world_size_meters: float = 28000.0

static func configure_bounds(south: float, north: float, west: float, east: float, size_meters: float) -> void:
	bbox_south = south
	bbox_north = north
	bbox_west = west
	bbox_east = east
	world_size_meters = size_meters

# WGS84 위경도 -> Godot 3D 월드 좌표(미터 단위) 변환
# X: 서(-size/2) ~ 동(+size/2)
# Z: 북(-size/2) ~ 남(+size/2) (Godot 좌표계 규격: -Z가 북쪽)
static func geo_to_world(lat: float, lon: float, altitude_meters: float = 0.0) -> Vector3:
	var span_x: float = bbox_east - bbox_west
	var span_z: float = bbox_north - bbox_south
	if span_x <= 0.0:
		span_x = 0.0001
	if span_z <= 0.0:
		span_z = 0.0001

	var frac_x: float = (lon - bbox_west) / span_x
	var frac_z: float = (bbox_north - lat) / span_z

	var world_x: float = (frac_x - 0.5) * world_size_meters
	var world_z: float = (frac_z - 0.5) * world_size_meters
	return Vector3(world_x, altitude_meters, world_z)

# Godot 3D 월드 좌표(미터) -> WGS84 위경도 역변환
static func world_to_geo(pos: Vector3) -> Dictionary:
	var span_x: float = bbox_east - bbox_west
	var span_z: float = bbox_north - bbox_south

	var frac_x: float = (pos.x / world_size_meters) + 0.5
	var frac_z: float = (pos.z / world_size_meters) + 0.5

	var lon: float = bbox_west + frac_x * span_x
	var lat: float = bbox_north - frac_z * span_z
	return {
		"lat": lat,
		"lon": lon,
		"altitude": pos.y
	}
