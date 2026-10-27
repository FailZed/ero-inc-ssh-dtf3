extends RefCounted
## Original ImageGen-painted inventory objects; shared by bag, shop and room.
static var _cache: Dictionary = {}
const ROOT := "res://assets/textures/ui/raster-v1/"
const ITEMS := ["meal","book","jacket","backpack","computer","stove","vegetable","grain","desk","lockpick"]

static func texture(id: String, item: Dictionary = {}) -> Texture2D:
	var key := id if id in ITEMS else "jacket" if item.has("slot") else "computer" if item.has("equipment") else "book"
	if not _cache.has(key):
		var path := ROOT+key+".png"
		_cache[key] = load(path) if ResourceLoader.exists(path,"Texture2D") else null
	return _cache[key]
