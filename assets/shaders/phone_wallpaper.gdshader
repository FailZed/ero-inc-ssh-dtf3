shader_type canvas_item;
uniform vec2 surface_size = vec2(456.0,884.0);
uniform float corner_radius = 24.0;
uniform float dimming = 0.22;
varying vec2 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
	vec2 q = abs(local_position - surface_size * 0.5) - (surface_size * 0.5 - vec2(corner_radius));
	float edge = length(max(q, vec2(0.0))) + min(max(q.x,q.y),0.0) - corner_radius;
	vec4 paint = texture(TEXTURE,UV);
	paint.rgb *= 1.0 - dimming;
	paint.a *= 1.0 - smoothstep(-1.0,1.0,edge);
	COLOR = paint;
}
