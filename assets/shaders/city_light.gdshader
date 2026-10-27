shader_type canvas_item;
uniform float brightness = 1.0;
uniform float saturation = 1.0;
uniform vec4 light_tint : source_color = vec4(1.0);
void fragment() {
	vec4 color = texture(TEXTURE,UV);
	float grey = dot(color.rgb,vec3(0.2126,0.7152,0.0722));
	COLOR = vec4(mix(vec3(grey),color.rgb,saturation)*brightness*light_tint.rgb,color.a)*COLOR;
}
