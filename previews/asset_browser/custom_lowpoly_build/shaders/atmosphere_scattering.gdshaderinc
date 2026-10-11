uniform float observer_altitude_m = 0.0;
uniform float air_density_ratio = 1.0;
uniform float density_scale_height_m = 8000.0;
const float EARTH_RADIUS = 6371000.0;
const float ATMOSPHERE_TOP = 100000.0;

float atmospheric_column(float elevation) {
	float r = EARTH_RADIUS + max(observer_altitude_m, 0.0);
	float outer = EARTH_RADIUS + ATMOSPHERE_TOP;
	float projection = r * elevation;
	float distance = max(0.0, -projection + sqrt(max(0.0, projection*projection + outer*outer-r*r)));
	float ground_discriminant = projection*projection + EARTH_RADIUS*EARTH_RADIUS-r*r;
	if (elevation < 0.0 && ground_discriminant >= 0.0) {
		distance = min(distance, max(0.0, -projection-sqrt(ground_discriminant)));
	}
	float column = 0.0;
	for (int i=0; i<16; i++) {
		float a = float(i)/16.0;
		float b = float(i+1)/16.0;
		float start = distance*a*a;
		float finish = distance*b*b;
		float t = (start+finish)*0.5;
		float h = sqrt(r*r+t*t+2.0*t*projection)-EARTH_RADIUS;
		column += exp(-max(h, 0.0)/density_scale_height_m)*(finish-start);
	}
	return column;
}

vec3 altitude_scattered_color(vec3 base, vec3 ray, vec3 sun) {
	// RGB 레일리 소광계수와 태양-시선 위상함수의 경량 근사.
	vec3 beta = vec3(0.0000058, 0.0000135, 0.0000331);
	float column = atmospheric_column(ray.y);
	vec3 scattering = vec3(1.0)-exp(-beta*column);
	vec3 reference = vec3(1.0)-exp(-beta*density_scale_height_m);
	float mu = dot(ray, normalize(sun));
	float phase = 0.75*(1.0+mu*mu);
	vec3 color = base*clamp(scattering/reference, vec3(0.0), vec3(1.35))*phase;
	float halo = pow(max(mu, 0.0), 32.0)*exp(-max(observer_altitude_m, 0.0)/1200.0);
	return color + vec3(0.12, 0.10, 0.075)*halo;
}
