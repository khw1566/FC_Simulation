extends Node3D
class_name RailwayTunnelWorldManager

const Route = preload("res://scripts/terrain/railway_route.gd")
const Fitter = preload("res://scripts/terrain/railway_asset_path_fitter.gd")
var _modules: Array[Dictionary] = []
var _active: Dictionary = {}
var _player: Node3D
var _settings: Dictionary
var _timer: float = 0.0
var _fitter := Fitter.new()

func configure(catalog: RefCounted,player: Node3D) -> void:
	_player = player
	_settings = catalog.data.settings
	for tunnel in catalog.data.tunnels:
		var route := Route.new()
		route.configure(catalog.projected(tunnel),[])
		var profile: String = "hsr" if tunnel.service=="ktx" else "donghae"
		var mouth := minf(8.0 if profile=="hsr" else 6.0,route.length*0.25)
		_append(tunnel,route,profile,"entry",0.0,mouth)
		var length := maxf(0,route.length-2.0*mouth)
		var count := maxi(1,ceili(length/(24.0 if profile=="hsr" else 20.0)))
		for i in range(count):
			_append(tunnel,route,profile,"body",mouth+length*i/count,mouth+length*(i+1)/count)
		_append(tunnel,route,profile,"exit",route.length-mouth,route.length)
	_update_visible()

func _append(tunnel: Dictionary,route: RefCounted,profile: String,part: String,start: float,finish: float) -> void:
	if finish-start<0.1:
		return
	_modules.append({"id":_modules.size(),"route":route,"start":start,"finish":finish,"center":route.sample((start+finish)*0.5).origin,"path":"res://assets/generated/railway_tunnels/%s_tunnel_%s.scn" % [profile,part],"part":part,"width_scale":float(tunnel.width_scale)})

func _process(delta: float) -> void:
	_timer += delta
	if _timer>=0.5:
		_timer = 0.0
		_update_visible()

func _update_visible() -> void:
	if not _player:
		return
	var near: Array[Dictionary] = []
	for module in _modules:
		var distance: float = _player.global_position.distance_to(module.center)
		var radius: float = _settings.tunnel_body_view_distance_m if module.part=="body" else _settings.tunnel_portal_view_distance_m
		if distance<radius:
			near.append({"module":module,"distance":distance})
	near.sort_custom(func(a,b): return a.distance<b.distance)
	var desired: Dictionary = {}
	for i in range(mini(near.size(),int(_settings.maximum_active_tunnel_modules))):
		var module: Dictionary = near[i].module
		desired[module.id] = module
	for id in _active.keys():
		if not desired.has(id):
			_active[id].free()
			_active.erase(id)
	var created := 0
	for id in desired:
		if _active.has(id):
			continue
		var module: Dictionary = desired[id]
		var points := PackedVector3Array([module.route.sample(module.start).origin])
		for index in range(module.route.points.size()):
			if module.route.distances[index]>module.start and module.route.distances[index]<module.finish:
				points.append(module.route.points[index])
		points.append(module.route.sample(module.finish).origin)
		var node := Node3D.new()
		node.name = "TunnelModule_%s" % id
		add_child(node)
		_fitter.place(node,module.path,points,null,0.0,module.width_scale,{"tunnel":true})
		_active[id] = node
		created += 1
		if created>=6:
			break
