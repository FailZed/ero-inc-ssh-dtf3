shader_type canvas_item;
render_mode unshaded;
uniform vec4 tint : source_color = vec4(1.0);
varying vec4 item_modulation;
void vertex() { item_modulation = COLOR; }
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float value = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(value * tint.rgb, source.a * tint.a) * item_modulation;
}
