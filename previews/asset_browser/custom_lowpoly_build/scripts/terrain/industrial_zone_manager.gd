extends Node3D
class_name IndustrialZoneManager

const Factory = preload("res://scripts/terrain/industrial_asset_factory.gd")
const Placement = preload("res://scripts/terrain/industrial_placement_builder.gd")
const Roads = preload("res://scripts/terrain/industrial_road_builder.gd")
const CATALOG = "res://assets/generated/industrial_zones/ulsan_metro_80km/placements.json"

@export var terrain_manager: Node3D
@export var player_node: Node3D
@export var auto_initialize := true
var enabled := true
var load_complete := false
var _settings: Dictionary = {}
var _entries: Array = []
var _models: Dictionary = {}
var _chunks: Dictionary = {}
var _slots: Dictionary = {}
var _wanted: Dictionary = {}
var _queue: Array = []
var _content: Node3D
var _factory := Factory.new()
var _timer := 0.0

func _ready() -> void:
	set_process(false)
	if auto_initialize:
		_initialize.call_deferred()

func _initialize() -> void:
	var maps := get_node_or_null("/root/MapSelectionService")
	if maps == null or maps.selected_map == null or maps.selected_map.id!="ulsan_metro_80km":
		load_complete = true
		return
	while is_instance_valid(terrain_manager) and not terrain_manager.load_complete:
		if not terrain_manager.load_error.is_empty():
			return
		await get_tree().process_frame
		if not is_inside_tree():
			return
	var loader := get_node_or_null("/root/LoadingManagerService")
	while loader and loader.is_loading:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if catalog is Dictionary:
		var regions = JSON.parse_string(FileAccess.get_file_as_string(CATALOG.get_base_dir().path_join("regions.json")))
		if regions is Dictionary and catalog.get("regions_source_sha256","") != regions.get("source_sha256",""):
			push_warning("공단 경계가 변경되었습니다. build_sites.py로 배치 데이터를 다시 생성하세요.")
			return
		configure(catalog,get_node_or_null("/root/UserSettingsService"))

func configure(catalog: Dictionary, preferences: Node = null) -> void:
	_settings = catalog.get("settings",{})
	_entries = catalog.get("placements",[])
	_content = Node3D.new()
	_content.name = "ProceduralIndustrialSites"
	_content.visible = false
	add_child(_content)
	var road_catalog = JSON.parse_string(FileAccess.get_file_as_string(catalog.roads_path))
	_content.add_child(Roads.build(road_catalog.roads,_entries,terrain_manager))
	var size := float(_settings.get("chunk_size_m",600))
	for entry in _entries:
		var p: Array = entry.position
		var key := Vector2i(floori(float(p[0])/size),floori(float(p[2])/size))
		if not _chunks.has(key):
			_chunks[key] = {"entries":[],"center":Vector3((key.x+0.5)*size,0,(key.y+0.5)*size)}
		_chunks[key].entries.append(entry)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.58,0.58,0.55)
	for key in _chunks:
		var chunk: Dictionary = _chunks[key]
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh.material = material
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = chunk.entries.size()
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_content.add_child(node)
		chunk.node = node
		for index in chunk.entries.size():
			var entry: Dictionary = chunk.entries[index]
			_slots[entry.id] = {"node":node,"index":index}
			multi.set_instance_transform(index,_coarse_pose(entry))
	if preferences:
		if not preferences.industrial_zones_enabled_changed.is_connected(set_enabled):
			preferences.industrial_zones_enabled_changed.connect(set_enabled)
		set_enabled(preferences.industrial_zones_enabled)
	else:
		set_enabled(bool(_settings.get("enabled",true)))
	load_complete = true
	print("[IndustrialZoneManager] 공단 %d개, 설비 %d개 배치 데이터 로드" % [catalog.zones.size(),_entries.size()])

func set_enabled(value: bool) -> void:
	enabled = value
	if _content:
		_content.visible = value
	set_process(value and not _entries.is_empty())
	if not value:
		for model in _models.values():
			model.free()
		_models.clear()
		_queue.clear()
		_wanted.clear()
	else:
		_update_visibility()

func _process(delta: float) -> void:
	_timer += delta
	if _timer>=0.5:
		_timer = 0.0
		_update_visibility()
	for creation in int(_settings.get("creation_budget_per_frame",2)):
		if _queue.is_empty():
			break
		var entry: Dictionary = _queue.pop_front()
		if not _wanted.has(entry.id) or _models.has(entry.id):
			continue
		var model := _factory.instantiate(entry)
		if model:
			model.transform = Placement.pose(entry,terrain_manager)
			Placement.foundation(model,entry,terrain_manager)
			_content.add_child(model)
			_models[entry.id] = model
			var slot: Dictionary = _slots[entry.id]
			slot.node.multimesh.set_instance_transform(slot.index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))

func _update_visibility() -> void:
	_wanted.clear()
	_queue.clear()
	var viewer := player_node.global_position if is_instance_valid(player_node) else Vector3.ZERO
	var candidates: Array = []
	for entry in _entries:
		var p: Array = entry.position
		var distance := viewer.distance_to(Vector3(p[0],p[1],p[2]))
		if distance<=float(_settings.get("detail_distance_m",2600)):
			_wanted[entry.id] = true
			if not _models.has(entry.id):
				candidates.append({"entry":entry,"distance":distance})
	for id in _models.keys():
		if not _wanted.has(id):
			_models[id].free()
			_models.erase(id)
	for key in _chunks:
		var chunk: Dictionary = _chunks[key]
		chunk.node.visible = Vector2(viewer.x,viewer.z).distance_to(Vector2(chunk.center.x,chunk.center.z))<=float(_settings.get("render_distance_m",9000))
	for entry in _entries:
		var slot: Dictionary = _slots[entry.id]
		if _models.has(entry.id):
			var pose := Placement.pose(entry,terrain_manager)
			var model: Node3D = _models[entry.id]
			if absf(model.position.y-pose.origin.y)>0.05:
				model.transform = pose
				Placement.foundation(model,entry,terrain_manager)
		else:
			slot.node.multimesh.set_instance_transform(slot.index,_coarse_pose(entry))
	candidates.sort_custom(func(a,b): return a.distance<b.distance)
	for candidate in candidates:
		_queue.append(candidate.entry)

func _coarse_pose(entry: Dictionary) -> Transform3D:
	var pose := Placement.pose(entry,terrain_manager)
	var a: Array = entry.aabb_min_m
	var b: Array = entry.aabb_max_m
	var lower := Vector3(a[0],a[1],a[2])
	var upper := Vector3(b[0],b[1],b[2])
	lower.y = minf(lower.y,(float(entry.foundation_bottom_y)-pose.origin.y)/float(entry.scale))
	return Transform3D(pose.basis*Basis.from_scale(upper-lower),pose.origin+pose.basis*((lower+upper)*0.5))
