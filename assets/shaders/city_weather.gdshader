shader_type canvas_item;
uniform int precipitation = 0;
uniform float overcast = 0.0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
	vec2 uv = UV;
	float cloud = sin(uv.x*9.0 + TIME*0.035) * sin(uv.y*7.0 - TIME*0.02);
	vec4 result = vec4(0.39,0.48,0.57,overcast*(0.06+cloud*0.025));
	if (precipitation == 1) {
		vec2 p = vec2(uv.x*95.0+uv.y*25.0,uv.y*22.0+TIME*15.0);
		vec2 cell = floor(p);
		vec2 f = fract(p);
		float rain = (1.0-smoothstep(0.018,0.065,abs(f.x-0.5))) * smoothstep(0.1,0.3,f.y) * (1.0-smoothstep(0.55,0.95,f.y)) * step(0.48,hash(cell));
		result = mix(result,vec4(0.70,0.84,0.94,0.48),rain);
	} else if (precipitation == 2) {
		float snow = 0.0;
		for (int i=0;i<3;i++) {
			float layer = float(i)+1.0;
			vec2 p = vec2(uv.x*35.0+sin(TIME*0.4+uv.y*8.0)*0.5,uv.y*22.0+TIME*(0.5+layer*0.35))/layer;
			vec2 cell = floor(p);
			vec2 center = vec2(hash(cell),hash(cell+8.1))*0.7+0.15;
			snow += (1.0-smoothstep(0.01,0.055,length(fract(p)-center)))*0.65;
		}
		result = mix(result,vec4(0.91,0.96,1.0,0.88),clamp(snow,0.0,1.0));
	}
	COLOR = result;
}
