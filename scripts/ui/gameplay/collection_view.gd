extends VBoxContainer
signal entry_selected(id: String)
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
var selected_id := ""

func _ready() -> void:
	set_meta("collection_view", true)
	theme = UI.skin()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not selected_id.is_empty() and selected_id in Gameplay.simulation.state.collection.unlocked:
		_present_entry(Gameplay.simulation.catalog.gallery_entries[selected_id])
	else: _show_list()

func _show_list() -> void:
	selected_id = ""
	entry_selected.emit("")
	UI.clear(self)
	var grid := W.grid(self,3)
	for entry in Gameplay.simulation.services.collections.entries():
		var card := W.panel(grid,14,Color("253a47") if entry.unlocked else Color("10212b"))
		if entry.unlocked and ResourceLoader.exists(str(entry.image)):
			var photo := TextureRect.new()
			photo.texture = load(str(entry.image))
			photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			photo.custom_minimum_size = Vector2(240,150)
			card.add_child(photo)
		else:
			W.icon(card,"eye",64,UI.MUTED)
		UI.label(card, str(entry.label) if entry.unlocked else "Будущее воспоминание", 23, UI.INK if entry.unlocked else UI.MUTED)
		if not entry.unlocked:
			UI.label(card,"Ещё не открыто",16,UI.MUTED)
			continue
		UI.button(card, "ПОСМОТРЕТЬ", func(): _show_entry(entry))

func _show_entry(entry: Dictionary) -> void:
	var result: Dictionary = Gameplay.execute("collections", "view", {"id":entry.id})
	if not result.ok: return
	selected_id = str(entry.id)
	entry_selected.emit(selected_id)
	_present_entry(entry)

func _present_entry(entry: Dictionary) -> void:
	UI.clear(self)
	UI.label(self, str(entry.label), 28, UI.BLUE)
	if ResourceLoader.exists(str(entry.image)):
		var picture := TextureRect.new()
		picture.texture = load(str(entry.image))
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size = Vector2(320, 240)
		add_child(picture)
	UI.label(self, str(entry.text), 22)
	UI.button(self, "К КОЛЛЕКЦИИ", _show_list)
