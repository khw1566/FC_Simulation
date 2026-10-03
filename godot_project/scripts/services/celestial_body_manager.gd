extends Node3D
class_name CelestialBodyManager

## 별 목록과 달·금성 천구 방향을 계산해 하늘 셰이더에 전달한다.
@export var player_camera: Camera3D
@export var cycle_service: Node

const STAR_CATALOG := [
	{"name": "Sirius", "ra": 101.287, "dec": -16.716, "mag": -1.46},
	{"name": "Canopus", "ra": 95.988, "dec": -52.696, "mag": -0.74},
	{"name": "Arcturus", "ra": 213.915, "dec": 19.182, "mag": -0.05},
	{"name": "Vega", "ra": 279.234, "dec": 38.784, "mag": 0.03},
	{"name": "Capella", "ra": 79.172, "dec": 45.998, "mag": 0.08},
	{"name": "Rigel", "ra": 78.634, "dec": -8.202, "mag": 0.13},
	{"name": "Procyon", "ra": 114.825, "dec": 5.225, "mag": 0.34},
	{"name": "Betelgeuse", "ra": 88.793, "dec": 7.407, "mag": 0.42},
	{"name": "Altair", "ra": 297.696, "dec": 8.868, "mag": 0.77},
	{"name": "Aldebaran", "ra": 68.980, "dec": 16.509, "mag": 0.85},
	{"name": "Spica", "ra": 201.298, "dec": -11.161, "mag": 0.97},
	{"name": "Antares", "ra": 247.352, "dec": -26.432, "mag": 1.06},
	{"name": "Pollux", "ra": 116.329, "dec": 28.026, "mag": 1.14},
	{"name": "Fomalhaut", "ra": 344.413, "dec": -29.622, "mag": 1.16},
	{"name": "Deneb", "ra": 310.358, "dec": 45.280, "mag": 1.25},
	{"name": "Regulus", "ra": 152.093, "dec": 11.967, "mag": 1.35},
	{"name": "Castor", "ra": 113.650, "dec": 31.888, "mag": 1.58},
	{"name": "Bellatrix", "ra": 81.283, "dec": 6.350, "mag": 1.64},
	{"name": "Elnath", "ra": 81.573, "dec": 28.608, "mag": 1.65},
	{"name": "Alnilam", "ra": 84.053, "dec": -1.202, "mag": 1.69},
	{"name": "Alnitak", "ra": 85.190, "dec": -1.943, "mag": 1.74},
	{"name": "Alioth", "ra": 193.507, "dec": 55.960, "mag": 1.77},
	{"name": "Dubhe", "ra": 165.932, "dec": 61.751, "mag": 1.79},
	{"name": "Mirfak", "ra": 51.081, "dec": 49.861, "mag": 1.80},
	{"name": "Wezen", "ra": 107.098, "dec": -26.393, "mag": 1.84},
	{"name": "Kaus Australis", "ra": 276.043, "dec": -34.385, "mag": 1.85},
	{"name": "Alkaid", "ra": 206.885, "dec": 49.313, "mag": 1.86},
	{"name": "Sadr", "ra": 305.557, "dec": 40.257, "mag": 2.20},
	{"name": "Polaris", "ra": 37.954, "dec": 89.264, "mag": 1.98},
	{"name": "Menkalinan", "ra": 89.882, "dec": 44.948, "mag": 1.90},
	{"name": "Alphard", "ra": 141.897, "dec": -8.659, "mag": 2.00},
	{"name": "Mizar", "ra": 200.981, "dec": 54.925, "mag": 2.23},
	{"name": "Algol", "ra": 47.042, "dec": 40.956, "mag": 2.12},
	{"name": "Acrux", "ra": 186.650, "dec": -63.099, "mag": 0.76},
	{"name": "Shaula", "ra": 263.402, "dec": -37.104, "mag": 1.63},
	{"name": "Rasalhague", "ra": 263.734, "dec": 12.560, "mag": 2.08},
	{"name": "Alphecca", "ra": 233.672, "dec": 26.715, "mag": 2.23},
	{"name": "Hamal", "ra": 31.793, "dec": 23.462, "mag": 2.00},
	{"name": "Dschubba", "ra": 240.083, "dec": -22.622, "mag": 2.32},
	{"name": "Eltanin", "ra": 269.152, "dec": 51.489, "mag": 2.23},
	{"name": "Algenib", "ra": 3.309, "dec": 15.184, "mag": 2.83},
	{"name": "Mirach", "ra": 17.433, "dec": 35.621, "mag": 2.06},
	{"name": "Schedar", "ra": 10.127, "dec": 56.537, "mag": 2.24},
	{"name": "Caph", "ra": 2.295, "dec": 59.150, "mag": 2.27},
	{"name": "Ruchbah", "ra": 21.454, "dec": 60.235, "mag": 2.68},
	{"name": "Enif", "ra": 326.046, "dec": 9.875, "mag": 2.39},
	{"name": "Markab", "ra": 346.190, "dec": 15.205, "mag": 2.49},
	{"name": "Algenubi", "ra": 154.173, "dec": 23.417, "mag": 2.97},
	{"name": "Zosma", "ra": 168.527, "dec": 20.524, "mag": 2.56},
	{"name": "Vindemiatrix", "ra": 195.545, "dec": 10.959, "mag": 2.83},
	{"name": "Kochab", "ra": 222.676, "dec": 74.155, "mag": 2.08},
	{"name": "Phecda", "ra": 178.458, "dec": 53.695, "mag": 2.44},
	{"name": "Merak", "ra": 165.460, "dec": 56.383, "mag": 2.37},
	{"name": "Menkent", "ra": 211.671, "dec": -36.370, "mag": 2.06},
	{"name": "Nunki", "ra": 283.816, "dec": -26.297, "mag": 2.05},
	{"name": "Almach", "ra": 30.975, "dec": 42.330, "mag": 2.10},
	{"name": "Kraz", "ra": 188.597, "dec": -23.397, "mag": 2.65},
	{"name": "Gienah", "ra": 183.951, "dec": -17.542, "mag": 2.59},
	{"name": "Aludra", "ra": 111.024, "dec": -29.303, "mag": 2.45},
	{"name": "Saiph", "ra": 86.939, "dec": -9.670, "mag": 2.07},
	{"name": "Mintaka", "ra": 83.002, "dec": -0.299, "mag": 2.23},
	{"name": "Alhena", "ra": 99.428, "dec": 16.399, "mag": 1.93},
	{"name": "Wasat", "ra": 110.030, "dec": 21.983, "mag": 3.53},
	{"name": "Mebsuta", "ra": 95.740, "dec": 25.131, "mag": 3.06},
	{"name": "Zubeneschamali", "ra": 229.252, "dec": -9.383, "mag": 2.61},
	{"name": "Zubenelgenubi", "ra": 222.720, "dec": -16.042, "mag": 2.75},
	{"name": "Sabik", "ra": 257.595, "dec": -15.725, "mag": 2.43},
	{"name": "Izar", "ra": 221.247, "dec": 27.074, "mag": 2.37},
	{"name": "Nashira", "ra": 325.023, "dec": -16.662, "mag": 3.68},
	{"name": "Dabih", "ra": 305.253, "dec": -14.781, "mag": 3.08},
	{"name": "Gacrux", "ra": 187.791, "dec": -57.113, "mag": 1.63}
]

const STAR_MAGNITUDE_LIMIT := 3.8
const STAR_RADIUS_RADIANS := 0.0017
const MOON_RADIUS_RADIANS := 0.0048
const VENUS_RADIUS_RADIANS := 0.0016

var _sky_material: ShaderMaterial
var _night_weight := 0.0
var _observer_latitude := 35.54
var _observer_longitude := 129.32
var _last_update_minute := -1

func _ready() -> void:
	_cache_observer_location()
	_cache_sky_material()
	if cycle_service and cycle_service.has_signal("time_changed"):
		cycle_service.connect("time_changed", _on_time_changed)
	_update_celestial_state(true)

func _process(_delta: float) -> void:
	var minute := int(floor(_simulation_hour() * 60.0))
	if minute != _last_update_minute:
		_update_celestial_state(false)

func set_night_weight(weight: float) -> void:
	_night_weight = clampf(weight, 0.0, 1.0)
	if is_instance_valid(_sky_material):
		_sky_material.set_shader_parameter("night_weight", _night_weight)

func _on_time_changed(_time_hours: float, _time_string: String) -> void:
	_update_celestial_state(true)

func _cache_observer_location() -> void:
	var selection := get_node_or_null("/root/MapSelectionService")
	var model = selection.get("selected_map") if selection else null
	if model == null:
		return
	var south := float(model.get("bbox_south"))
	var north := float(model.get("bbox_north"))
	var west := float(model.get("bbox_west"))
	var east := float(model.get("bbox_east"))
	if north > south:
		_observer_latitude = (south + north) * 0.5
	if east > west:
		_observer_longitude = (west + east) * 0.5

func _cache_sky_material() -> void:
	var env_node := get_node_or_null("../WorldEnvironment") as WorldEnvironment
	if env_node and env_node.environment and env_node.environment.sky:
		_sky_material = env_node.environment.sky.sky_material as ShaderMaterial
	if not is_instance_valid(_sky_material):
		push_error("CelestialBodyManager: night sky shader material was not assigned.")
		return
	var directions := PackedVector3Array()
	var colors := PackedColorArray()
	var sizes := PackedFloat32Array()
	for star in STAR_CATALOG:
		if float(star.mag) > STAR_MAGNITUDE_LIMIT:
			continue
		directions.append(Vector3.ZERO)
		var brightness := clampf(1.18 - float(star.mag) * 0.18, 0.38, 1.38)
		var warm := clampf((float(star.mag) + 0.8) * 0.14, 0.0, 0.55)
		colors.append(Color(0.70 + warm, 0.82, 1.0 - warm * 0.28, brightness))
		sizes.append(STAR_RADIUS_RADIANS * lerpf(1.0, 2.0, clampf((1.0 - float(star.mag)) / 3.0, 0.0, 1.0)))
	directions.resize(72)
	colors.resize(72)
	sizes.resize(72)
	_sky_material.set_shader_parameter("star_directions", directions)
	_sky_material.set_shader_parameter("star_colors", colors)
	_sky_material.set_shader_parameter("star_radii", sizes)

func _update_celestial_state(force: bool) -> void:
	if not is_instance_valid(_sky_material):
		return
	var hour := _simulation_hour()
	var minute := int(floor(hour * 60.0))
	if not force and minute == _last_update_minute:
		return
	_last_update_minute = minute
	var julian_day := _julian_day_now(hour)
	var sidereal_degrees := _local_sidereal_degrees(julian_day, _observer_longitude)
	var directions := PackedVector3Array()
	for star in STAR_CATALOG:
		if float(star.mag) <= STAR_MAGNITUDE_LIMIT:
			directions.append(_equatorial_to_world(float(star.ra), float(star.dec), sidereal_degrees, _observer_latitude))
	directions.resize(72)
	_sky_material.set_shader_parameter("star_directions", directions)
	var moon_direction := _moon_direction(julian_day, sidereal_degrees)
	var sun_direction := _sun_direction(julian_day, sidereal_degrees)
	_sky_material.set_shader_parameter("moon_direction", moon_direction)
	_sky_material.set_shader_parameter("sun_direction", sun_direction)
	_sky_material.set_shader_parameter("venus_direction", _venus_direction(julian_day, sidereal_degrees))
	_sky_material.set_shader_parameter("moon_radius", MOON_RADIUS_RADIANS)
	_sky_material.set_shader_parameter("venus_radius", VENUS_RADIUS_RADIANS)
	_sky_material.set_shader_parameter("night_weight", _night_weight)

func _simulation_hour() -> float:
	if cycle_service and "current_time_hours" in cycle_service:
		return fposmod(float(cycle_service.current_time_hours), 24.0)
	var now := Time.get_datetime_dict_from_system()
	return float(now.hour) + float(now.minute) / 60.0 + float(now.second) / 3600.0

func get_sun_world_direction() -> Vector3:
	_cache_observer_location()
	var julian_day := _julian_day_now(_simulation_hour())
	return _sun_direction(julian_day, _local_sidereal_degrees(julian_day, _observer_longitude))

func get_moon_world_direction() -> Vector3:
	var julian_day := _julian_day_now(_simulation_hour())
	return _moon_direction(julian_day, _local_sidereal_degrees(julian_day, _observer_longitude))

func _julian_day_now(hour: float) -> float:
	var date := Time.get_date_dict_from_system(false)
	var year := int(date.year)
	var month := int(date.month)
	var day := int(date.day)
	if month <= 2:
		year -= 1
		month += 12
	var a := int(floor(float(year) / 100.0))
	var b := 2 - a + int(floor(float(a) / 4.0))
	return floor(365.25 * float(year + 4716)) + floor(30.6001 * float(month + 1)) + float(day) + float(b) - 1524.5 + (hour - 9.0) / 24.0

func _sun_direction(julian_day: float, sidereal_degrees: float) -> Vector3:
	var days := julian_day - 2451545.0
	var centuries := days / 36525.0
	var mean_longitude := deg_to_rad(fposmod(280.46646 + 36000.76983 * centuries, 360.0))
	var mean_anomaly := deg_to_rad(fposmod(357.52911 + 35999.05029 * centuries, 360.0))
	var ecliptic_longitude := mean_longitude + deg_to_rad(1.914602) * sin(mean_anomaly) + deg_to_rad(0.019993) * sin(2.0 * mean_anomaly) + deg_to_rad(0.000289) * sin(3.0 * mean_anomaly)
	var obliquity := deg_to_rad(23.4393 - 0.0000004 * days)
	var right_ascension := atan2(cos(obliquity) * sin(ecliptic_longitude), cos(ecliptic_longitude))
	var declination := asin(sin(obliquity) * sin(ecliptic_longitude))
	return _equatorial_to_world(rad_to_deg(right_ascension), rad_to_deg(declination), sidereal_degrees, _observer_latitude)

func _local_sidereal_degrees(julian_day: float, longitude: float) -> float:
	var days := julian_day - 2451545.0
	var gmst := 280.46061837 + 360.98564736629 * days
	return fposmod(gmst + longitude, 360.0)

func _moon_direction(julian_day: float, sidereal_degrees: float) -> Vector3:
	var days := julian_day - 2451545.0
	var mean_longitude := fposmod(218.316 + 13.176396 * days, 360.0)
	var mean_anomaly := deg_to_rad(fposmod(134.963 + 13.064993 * days, 360.0))
	var mean_elongation := deg_to_rad(fposmod(297.850 + 12.190749 * days, 360.0))
	var longitude := mean_longitude + 6.289 * sin(mean_anomaly)
	var latitude := 5.128 * sin(deg_to_rad(fposmod(93.272 + 13.229350 * days, 360.0)))
	longitude += 1.274 * sin(2.0 * mean_elongation - mean_anomaly)
	longitude -= 0.658 * sin(2.0 * mean_elongation)
	var obliquity := deg_to_rad(23.4393 - 0.0000004 * days)
	var ecliptic_lon := deg_to_rad(longitude)
	var ecliptic_lat := deg_to_rad(latitude)
	var right_ascension := atan2(sin(ecliptic_lon) * cos(obliquity) - tan(ecliptic_lat) * sin(obliquity), cos(ecliptic_lon))
	var declination := asin(sin(ecliptic_lat) * cos(obliquity) + cos(ecliptic_lat) * sin(obliquity) * sin(ecliptic_lon))
	return _equatorial_to_world(rad_to_deg(right_ascension), rad_to_deg(declination), sidereal_degrees, _observer_latitude)

func _venus_direction(julian_day: float, sidereal_degrees: float) -> Vector3:
	var days := julian_day - 2451545.0
	var centuries := days / 36525.0
	var mean_longitude := deg_to_rad(fposmod(181.979801 + 58517.815676 * centuries, 360.0))
	var mean_anomaly := deg_to_rad(fposmod(50.115 + 58517.803875 * centuries, 360.0))
	var longitude := mean_longitude + deg_to_rad(0.7758) * sin(mean_anomaly) + deg_to_rad(0.0033) * sin(2.0 * mean_anomaly)
	var obliquity := deg_to_rad(23.4393 - 0.0000004 * days)
	var right_ascension := atan2(sin(longitude) * cos(obliquity), cos(longitude))
	var declination := asin(sin(longitude) * sin(obliquity))
	return _equatorial_to_world(rad_to_deg(right_ascension), rad_to_deg(declination), sidereal_degrees, _observer_latitude)

func _equatorial_to_world(ra_degrees: float, dec_degrees: float, sidereal_degrees: float, latitude_degrees: float) -> Vector3:
	var hour_angle := deg_to_rad(fposmod(sidereal_degrees - ra_degrees + 180.0, 360.0) - 180.0)
	var declination := deg_to_rad(dec_degrees)
	var latitude := deg_to_rad(latitude_degrees)
	var east := -cos(declination) * sin(hour_angle)
	var north := sin(declination) * cos(latitude) - cos(declination) * cos(hour_angle) * sin(latitude)
	var up := sin(declination) * sin(latitude) + cos(declination) * cos(hour_angle) * cos(latitude)
	return Vector3(east, up, -north).normalized()
