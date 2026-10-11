extends Node3D
var data: Dictionary = {}

func get_terrain_elevation(x: float, z: float) -> float:
	if data.is_empty():
		return 65.0
	var fx := clampf((x-float(data.min))/float(data.step),0,47.99999)
	var fz := clampf((z-float(data.min))/float(data.step),0,47.99999)
	var ix := floori(fx)
	var iz := floori(fz)
	var a := lerpf(float(data.values[iz][ix]),float(data.values[iz][ix+1]),fx-ix)
	var b := lerpf(float(data.values[iz+1][ix]),float(data.values[iz+1][ix+1]),fx-ix)
	return lerpf(a,b,fz-iz)
