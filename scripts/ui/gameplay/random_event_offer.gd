extends VBoxContainer
## Small in-thread event card; all mutations belong to the existing gameplay callback.

func setup(offer: Dictionary, choose: Callable) -> void:
	add_theme_constant_override("separation",6)
	var title := Label.new()
	title.text = str(offer.title)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title)
	var description := Label.new()
	description.text = str(offer.text)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(description)
	for choice: Dictionary in offer.choices:
		var button := Button.new()
		button.text = str(choice.text)+(" · %d мин" % int(choice.minutes) if int(choice.minutes)>0 else "")
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 38
		button.set_meta("phone_focus","event:"+str(offer.id)+":"+str(choice.id))
		button.pressed.connect(choose.bind(str(offer.id),str(choice.id)))
		add_child(button)
