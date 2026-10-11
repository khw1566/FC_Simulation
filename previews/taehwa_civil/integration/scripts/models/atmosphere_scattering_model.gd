extends RefCounted
class_name AtmosphereScatteringModel

## 광학용 지수 밀도와 곡면 대기 광학 경로. 비행 역학 ISA 모델과 분리한다.
static func density(altitude: float, scale_height: float = 8000.0) -> float:
	return exp(-maxf(altitude, 0.0) / maxf(scale_height, 1.0))

static func column(altitude: float, elevation: float, scale_height: float = 8000.0) -> float:
	var radius := 6371000.0
	var observer := radius + maxf(altitude, 0.0)
	var atmosphere := radius + 100000.0
	var projection := observer * elevation
	var distance := -projection + sqrt(maxf(0.0, projection*projection + atmosphere*atmosphere - observer*observer))
	var ground_discriminant := projection*projection + radius*radius - observer*observer
	if elevation < 0.0 and ground_discriminant >= 0.0:
		distance = minf(distance, -projection - sqrt(ground_discriminant))
	var total := 0.0
	for i in range(16):
		var start := distance * pow(float(i) / 16.0, 2.0)
		var finish := distance * pow(float(i+1) / 16.0, 2.0)
		var t := (start + finish) * 0.5
		var h := sqrt(observer*observer + t*t + 2.0*t*projection) - radius
		total += density(h, scale_height) * (finish-start)
	return total
