shader_type canvas_item;
render_mode unshaded;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool tint_enabled = false;
uniform float dirt : hint_range(0.0, 1.0) = 0.0;
uniform float fatigue : hint_range(0.0, 1.0) = 0.0;
varying vec4 item_modulation;
void vertex() { item_modulation = COLOR; }
void fragment() {
	vec2 uv = UV;
	vec4 source = texture(TEXTURE,uv);
	if (tint_enabled) {
		float value = dot(source.rgb,vec3(0.299,0.587,0.114));
		source.rgb = value*tint.rgb;
		source.a *= tint.a;
	}
	float patch = (1.0-smoothstep(0.035,0.10,distance(uv,vec2(0.44,0.39)))) + (1.0-smoothstep(0.02,0.06,distance(uv,vec2(0.57,0.60))));
	source.rgb = mix(source.rgb, source.rgb*vec3(0.70,0.65,0.56),clamp(patch*dirt*0.45,0.0,0.5));
	source.rgb = mix(source.rgb,source.rgb*vec3(0.92,0.94,1.0),fatigue*0.3);
	COLOR = source*item_modulation;
}
