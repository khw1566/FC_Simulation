extends SceneTree
const Manager = preload("res://scripts/terrain/landmark_manager.gd")
const Selection = preload("res://selection_stub.gd")
func _initialize() -> void:
 call_deferred("_run")
func _run() -> void:
 var service := Selection.new()
 service.name = "MapSelectionService"
 service.selected_map = {"landmarks_path":"", "bbox_south":35.0,"bbox_north":36.0,"bbox_west":129.0,"bbox_east":130.0,"world_size_meters":80000.0}
 root.add_child(service)
 var manager := Manager.new()
 root.add_child(manager)
 assert(manager.beacons.is_empty(), "울산 빈 자료에서 칸몬 태그 유출")
 service.selected_map.landmarks_path = "res://missing.json"
 manager.load_and_spawn_landmarks()
 assert(manager.beacons.is_empty(), "울산 누락 자료에서 칸몬 태그 유출")
 service.selected_map.landmarks_path = "res://assets/maps/kanmon_straits/landmarks.json"
 manager.load_and_spawn_landmarks()
 assert(manager.beacons.is_empty(), "맵 밖 태그 유출")
 service.selected_map = {"landmarks_path":"res://assets/maps/kanmon_straits/landmarks.json", "bbox_south":33.8,"bbox_north":34.05,"bbox_west":130.8,"bbox_east":131.1,"world_size_meters":28000.0}
 manager.load_and_spawn_landmarks()
 assert(manager.beacons.size() > 0, "칸몬 정상 태그 누락")
 var count := manager.beacons.size()
 manager.load_and_spawn_landmarks()
 assert(manager.beacons.size() == count, "재로드 중복")
 service.selected_map.landmarks_path = ""
 manager.load_and_spawn_landmarks()
 assert(manager.beacons.is_empty(), "기존 태그 잔존")
 print("MAP TAG PASS: empty, missing, bounds, kanmon, reload, clear")
 quit(0)
