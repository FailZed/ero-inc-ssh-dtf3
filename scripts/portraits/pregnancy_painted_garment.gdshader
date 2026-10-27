shader_type canvas_item;
render_mode unshaded;
// Registered art replacement; original neck, straps and upper chest stay exact.
// No deformation of the body, arms, face, hair or garment source UVs.
uniform sampler2D painted_texture : source_color, filter_linear;
uniform vec4 registration = vec4(264.0,41.0,1422.5456,2184.084);
uniform float dirt : hint_range(0.0,1.0) = 0.0;
uniform float fatigue : hint_range(0.0,1.0) = 0.0;
varying vec4 item_modulation;
void vertex() { item_modulation = COLOR; }
void fragment() {
	vec4 source = texture(TEXTURE,UV);
	vec2 canvas_position = UV*vec2(1920.0,2596.0);
	vec2 painted_uv = (canvas_position-registration.xy)/registration.zw;
	vec4 painted = texture(painted_texture,clamp(painted_uv,vec2(0.0),vec2(1.0)));
	painted.a = smoothstep(0.15,0.85,painted.a);
	// Ignore generated low-opacity outliers outside the registered garment slot.
	painted.a *= step(650.0,canvas_position.x)*step(canvas_position.x,1320.0)*step(canvas_position.y,1790.0);
	float replace = smoothstep(910.0,1040.0,canvas_position.y);
	vec4 combined = mix(vec4(source.rgb*source.a,source.a),vec4(painted.rgb*painted.a,painted.a),replace);
	source = vec4(combined.rgb/max(combined.a,0.001),combined.a);
	float patch = (1.0-smoothstep(0.035,0.10,distance(UV,vec2(0.44,0.39))))+(1.0-smoothstep(0.02,0.06,distance(UV,vec2(0.57,0.60))));
	source.rgb = mix(source.rgb,source.rgb*vec3(0.70,0.65,0.56),clamp(patch*dirt*0.45,0.0,0.5));
	source.rgb = mix(source.rgb,source.rgb*vec3(0.92,0.94,1.0),fatigue*0.3);
	COLOR = source*item_modulation;
}
