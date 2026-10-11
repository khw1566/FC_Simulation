extends RefCounted
class_name RailwayAlignmentCatalog

const PATH = "res://assets/generated/railway/alignment.json"
var data: Dictionary = {}
var tracks: Dictionary = {}

func _init() -> void:
	if FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			data = parsed
			for track in data.get("tracks",[]):
				tracks[int(track.osm_id)] = track

func projected(track: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array()
	for p in track.get("points",[]):
		points.append(Vector3(float(p[0]),float(p[1]),float(p[2])))
	return points
