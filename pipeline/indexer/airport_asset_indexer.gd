extends RefCounted

const Layout = preload("res://scripts/terrain/airfield_layout.gd")

func update(spec: Dictionary, model: Node3D) -> void:
	var meta_path := "res://assets/maps/ulsan_metro_80km/map_meta.json"
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	var triangles: int = 0
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var lamps := model.find_children("*", "MultiMeshInstance3D", true, false)
	var lamp_count: int = 0
	for node in meshes:
		triangles += node.mesh.get_faces().size() / 3
	for node in lamps:
		lamp_count += node.multimesh.instance_count
		triangles += node.multimesh.instance_count * 2
	var bounds := _bounds(spec, meta)
	var shared := {
		"bbox": bounds,
		"elevation": {"reference": "건물 바닥 기준 상대 높이. 배치 고도는 지형 샘플링으로 결정.", "min_meters": -8, "max_meters": float(spec.tower.height)},
		"resolution": {"type": "procedural_mesh", "triangles": triangles, "material_batches": meshes.size() + lamps.size(), "lamp_count": lamp_count, "units": "meters"},
		"accuracy": spec.accuracy,
		"position_uncertainty_m": spec.position_uncertainty_m
	}
	var model_entry := _entry(str(spec.scene_path), "landmark_model", shared)
	var placement_path := "res://assets/generated/airport/placement.json"
	var placement_entry := _entry(placement_path, "landmark_placement", shared)
	var map_manifest_path := "res://assets/maps/ulsan_metro_80km/manifest.json"
	var map_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(map_manifest_path))
	map_manifest.assets["airport/ulsan_airport.scn"] = model_entry
	map_manifest.assets["airport/placement.json"] = placement_entry
	map_manifest.assets["map_meta.json"] = _entry(meta_path, "metadata", {})
	map_manifest.indexed_at = Time.get_datetime_string_from_system()
	_write(map_manifest_path, map_manifest)
	var generated_path := "res://assets/generated/manifest.json"
	var generated: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(generated_path))
	generated.assets["ulsan_airport_model"] = model_entry
	generated.assets["ulsan_airport_placement"] = placement_entry
	generated.last_updated = Time.get_datetime_string_from_system()
	_write(generated_path, generated)

func _entry(path: String, category: String, metadata: Dictionary) -> Dictionary:
	var entry := metadata.duplicate(true)
	entry["file_path"] = path
	entry["file_name"] = path.get_file()
	entry["extension"] = "." + path.get_extension()
	entry["category"] = category
	entry["sha256"] = FileAccess.get_sha256(path)
	var file := FileAccess.open(path, FileAccess.READ)
	entry["size_bytes"] = file.get_length()
	return entry

func _bounds(spec: Dictionary, meta: Dictionary) -> Dictionary:
	var rotation := Basis(Vector3.UP, deg_to_rad(float(spec.rotation_y_degrees)))
	var bounds := {"south": INF, "north": -INF, "west": INF, "east": -INF}
	for building in spec.buildings:
		for sx in [-0.5, 0.5]:
			for sz in [-0.5, 0.5]:
				# 캐노피와 처마를 포함하도록 외곽에 10m 여유를 준다.
				var point := rotation * Vector3(float(building.center_xz[0]) + (float(building.size_xz[0]) + 20) * sx, 0, float(building.center_xz[1]) + (float(building.size_xz[1]) + 20) * sz)
				var lon: float = float(spec.anchor.lon) + point.x * (float(meta.bbox.east) - float(meta.bbox.west)) / float(meta.world_size_meters)
				var lat: float = float(spec.anchor.lat) - point.z * (float(meta.bbox.north) - float(meta.bbox.south)) / float(meta.world_size_meters)
				bounds.south = minf(bounds.south, lat)
				bounds.north = maxf(bounds.north, lat)
				bounds.west = minf(bounds.west, lon)
				bounds.east = maxf(bounds.east, lon)
	var frame := Layout.world_frame(spec, meta)
	for x in [-30.0, 345.0]:
		for z in [-float(spec.airfield.length_m) - float(spec.airfield.approach_18_m), float(spec.airfield.approach_36_m)]:
			var point := frame * Vector3(x, 0, z)
			var lon: float = float(meta.bbox.west) + (point.x / float(meta.world_size_meters) + 0.5) * (float(meta.bbox.east) - float(meta.bbox.west))
			var lat: float = float(meta.bbox.north) - (point.z / float(meta.world_size_meters) + 0.5) * (float(meta.bbox.north) - float(meta.bbox.south))
			bounds.south = minf(bounds.south, lat)
			bounds.north = maxf(bounds.north, lat)
			bounds.west = minf(bounds.west, lon)
			bounds.east = maxf(bounds.east, lon)
	return bounds

func _write(path: String, content: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(content, "  "))
	file.close()


