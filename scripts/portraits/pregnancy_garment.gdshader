shader_type canvas_item;
render_mode unshaded;
// The painted abdomen supplies the silhouette and broad cloth shading.
// Identity layers retain their original UVs and pixels.
uniform sampler2D abdomen_texture : source_color, filter_linear;
uniform float stage_strength : hint_range(0.0,1.0) = 1.0;
uniform int garment_role = 1;
uniform float dirt : hint_range(0.0,1.0) = 0.0;
uniform float fatigue : hint_range(0.0,1.0) = 0.0;
varying vec4 item_modulation;
void vertex() { item_modulation = COLOR; }
void fragment() {
	vec4 source = texture(TEXTURE,UV);
	vec4 abdomen = texture(abdomen_texture,UV);
	if (garment_role == 1) {
		// Cloth receives broad volume lighting, never the skin's navel or outline.
		vec2 local = (UV-vec2(0.5167,0.454))/vec2(0.111,0.090);
		float roundness = sqrt(max(0.0,1.0-dot(local,local)));
		float shade = clamp(0.91+0.13*roundness-0.035*local.x-0.045*local.y,0.78,1.05);
		vec3 fabric = vec3(shade);
		source.rgb = mix(source.a > 0.01 ? source.rgb : vec3(0.95),fabric,abdomen.a*mix(0.25,0.88,stage_strength));
		source.a = max(source.a,abdomen.a);
	} else {
		source.a *= 1.0-abdomen.a*smoothstep(0.04,0.25,stage_strength);
	}
	float patch = (1.0-smoothstep(0.035,0.10,distance(UV,vec2(0.44,0.39))))+(1.0-smoothstep(0.02,0.06,distance(UV,vec2(0.57,0.60))));
	source.rgb = mix(source.rgb,source.rgb*vec3(0.70,0.65,0.56),clamp(patch*dirt*0.45,0.0,0.5));
	source.rgb = mix(source.rgb,source.rgb*vec3(0.92,0.94,1.0),fatigue*0.3);
	COLOR = source*item_modulation;
}
