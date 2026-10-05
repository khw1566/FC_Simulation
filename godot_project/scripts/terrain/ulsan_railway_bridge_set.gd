extends RefCounted
## 안양교 본체와 접근부 및 울산역 연결부의 접속된 세트 구성.

const Builder = preload("res://scripts/terrain/railway_bridge_asset_builder.gd")
const Parts = preload("res://scripts/terrain/railway_bridge_geometry.gd")

static func specs(config: Dictionary) -> Array[Dictionary]:
	var shared: Dictionary = config.defaults.duplicate(true)
	shared.merge(config.ulsan_set, true)
	var result: Array[Dictionary] = []
	for data in [
		["anyang_north_approach", "안양교 북측 접근 고가교", "viaduct", shared.north_approach_length_m],
		["anyang_main_bridge", "안양교 병렬 상로 아치 본체", "anyang", shared.main_length_m],
		["anyang_station_approach", "울산역 방향 접근 고가교", "viaduct", shared.south_approach_length_m],
		["ulsan_station_interface", "울산역 연결부", "station", shared.station_interface_length_m],
	]:
		var spec := shared.duplicate(true)
		spec.id = data[0]
		spec.name_ko = data[1]
		spec.kind = data[2]
		spec.length_m = data[3]
		spec.span_m = 32.0
		result.append(spec)
	return result

static func build(config: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(config.ulsan_set.id)
	var modules := specs(config)
	var offset := 0.0
	var connections: Array[Dictionary] = []
	var previous: Node3D
	for i in range(modules.size()):
		var spec := modules[i].duplicate(true)
		spec.include_end_support = i == modules.size() - 1
		var node := Builder.build(spec)
		node.position.z = offset
		root.add_child(node)
		if previous != null:
			var end: Vector3 = previous.position + previous.get_node("TrackEnd").position
			var start: Vector3 = node.position + node.get_node("TrackStart").position
			assert(end.distance_to(start) < 0.0001, "교량 모듈 접속점 불일치")
			for track_index in range(int(spec.track_count)):
				var track_end: Vector3 = previous.position + previous.get_node("Track%dEnd" % track_index).position
				var track_start: Vector3 = node.position + node.get_node("Track%dStart" % track_index).position
				assert(track_end.distance_to(track_start) < 0.0001, "개별 궤도 접속점 불일치")
			connections.append({"from": str(previous.name), "to": str(node.name), "z_m": offset, "gap_m": end.distance_to(start)})
		previous = node
		offset += float(spec.length_m)
	Parts.marker(root, "TrackStart", Vector3(0, float(config.defaults.rail_top_y_m), 0))
	Parts.marker(root, "TrackEnd", Vector3(0, float(config.defaults.rail_top_y_m), offset))
	Parts.marker(root, "UlsanStationSocket", Vector3(0, float(config.defaults.rail_top_y_m), offset))
	root.set_meta("length_m", offset)
	root.set_meta("track_count", 2)
	root.set_meta("gauge_m", float(config.defaults.gauge_m))
	root.set_meta("track_spacing_m", float(config.ulsan_set.track_spacing_m))
	root.set_meta("rail_top_y_m", float(config.defaults.rail_top_y_m))
	root.set_meta("connections", connections)
	root.set_meta("accuracy", config.ulsan_set.accuracy)
	root.set_meta("label_ko", config.ulsan_set.name_ko)
	root.set_meta("connection_axis", "+Z")
	return root
