extends Control
var target := 0.5
var value := 0.0
var tolerance := 0.1

func _ready() -> void:
	custom_minimum_size.y = 42
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("142938"))
	var left := maxf(0,target-tolerance)
	var right := minf(1,target+tolerance)
	draw_rect(Rect2(Vector2(size.x*left,2),Vector2(size.x*(right-left),maxf(0,size.y-4))),Color(0.85,0.60,0.39,0.28))
	draw_line(Vector2(size.x*target,2),Vector2(size.x*target,size.y-2),Color("da9a63"),2,true)
	draw_line(Vector2(size.x*value,0),Vector2(size.x*value,size.y),Color("e4edf4"),3,true)
	draw_rect(Rect2(Vector2.ZERO,size),Color("4c6b80"),false,1)
