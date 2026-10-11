extends Node3D
class_name RailwayLandmarkManager

const Fitter = preload("res://scripts/terrain/railway_asset_path_fitter.gd")
const Route = preload("res://scripts/terrain/railway_route.gd")
const CATALOG = "res://assets/generated/railway/landmark_placements.json"
var data: Dictionary = {}
var _station_transform := Transform3D.IDENTITY
var _station_placed: bool = false
var _anyang_tracks: Array[PackedVector3Array] = []

func setup(map_config, terrain: Node3D) -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if not map_config.id in data.maps:
		data = {}
		return
	var spec: Dictionary = data.station
	var location := project(spec.coordinate,map_config,terrain)
	var yaw := deg_to_rad(float(spec.yaw_degrees))
	_station_transform = Transform3D(Basis(Vector3.UP,yaw),location)
	# 높은 지형 모서리를 기준으로 배치하고 기존 역사 건물의 중복을 제거한다.
	var ground_min := location.y
	for corner in [Vector3(-59,0,-40),Vector3(59,0,-40),Vector3(-59,0,34),Vector3(59,0,34)]:
		var world: Vector3 = _station_transform*corner
		location.y = maxf(location.y,terrain.get_terrain_elevation(world.x,world.z))
		ground_min = minf(ground_min,terrain.get_terrain_elevation(world.x,world.z))
	_station_transform.origin = location
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(spec.glb_path,state)!=OK:
		return
	var station := document.generate_scene(state)
	if not station:
		return
	station.transform = _station_transform
	station.name = "TaehwagangStation"
	add_child(station)
	_station_placed = true
	var label := Label3D.new()
	label.text = "태화강역"
	label.position = Vector3(0,16.5,21.5)
	label.font_size = 96
	label.pixel_size = 0.012
	station.add_child(label)
	var foundation := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(118,maxf(0.5,location.y-ground_min+0.5),74)
	foundation.mesh = box
	foundation.position = Vector3(0,-box.size.y*0.5,-3)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.48,0.48,0.46)
	foundation.material_override = material
	station.add_child(foundation)

func replaces_building(x: float,z: float) -> bool:
	if not _station_placed:
		return false
	var local := _station_transform.affine_inverse()*Vector3(x,_station_transform.origin.y,z)
	return absf(local.x)<61.0 and local.z>-42.0 and local.z<36.0

func custom_bridge(osm_id: int) -> bool:
	for bridge in data.get("bridges",[]):
		if int(bridge.osm_id)==osm_id:
			return true
	return false

func place_bridge(track: Dictionary, points: PackedVector3Array, terrain: Node3D) -> void:
	if not custom_bridge(int(track.osm_id)):
		return
	var route := Route.new()
	route.configure(points,[])
	var fitter := Fitter.new()
	if int(track.osm_id) in [128255609,407197573]:
		var ordered := points.duplicate()
		if float(track.points[0][1])<float(track.points[-1][1]):
			ordered.reverse()
		_anyang_tracks.append(ordered)
		if _anyang_tracks.size()<2:
			return
		var other := Route.new()
		route.configure(_anyang_tracks[0],[])
		other.configure(_anyang_tracks[1],[])
		var center := PackedVector3Array()
		for i in range(65):
			var fraction := float(i)/64.0
			center.append((route.sample(route.length*fraction).origin+other.sample(other.length*fraction).origin)*0.5)
		var spacing := _anyang_tracks[0][0].distance_to(_anyang_tracks[1][0])
		route.configure(center,[])
		var middle := (route.length-231.8)*0.5
		for part in [["anyang_north_approach",0.0,middle],["anyang_main_bridge",middle,middle+231.8],["anyang_station_approach",middle+231.8,route.length]]:
			fitter.place(self,"res://assets/generated/railway_bridges/%s.scn" % part[0],slice(route,part[1],part[2]),terrain,0.0,clampf(spacing/5.4,0.7,1.3))
	else:
		var count := maxi(1,ceili(route.length/32.0))
		for i in range(count):
			fitter.place(self,"res://assets/generated/railway_bridges/rail_plate_girder.scn",slice(route,route.length*i/count,route.length*(i+1)/count),terrain)

func place_ulsan_interface(points: PackedVector3Array, terrain: Node3D) -> void:
	if data.is_empty():
		return
	Fitter.new().place(self,"res://assets/generated/railway_bridges/ulsan_station_interface.scn",points,terrain,-1.35,0.5)

func slice(route: RefCounted,start: float,finish: float) -> PackedVector3Array:
	var result := PackedVector3Array([route.sample(start).origin])
	for i in range(route.points.size()):
		if route.distances[i]>start and route.distances[i]<finish:
			result.append(route.points[i])
	result.append(route.sample(finish).origin)
	return result

func project(coordinate: Array,map_config,terrain: Node3D) -> Vector3:
	var x: float = ((float(coordinate[0])-map_config.bbox_west)/(map_config.bbox_east-map_config.bbox_west)-0.5)*map_config.world_size_meters
	var z: float = ((map_config.bbox_north-float(coordinate[1]))/(map_config.bbox_north-map_config.bbox_south)-0.5)*map_config.world_size_meters
	return Vector3(x,terrain.get_terrain_elevation(x,z),z)
