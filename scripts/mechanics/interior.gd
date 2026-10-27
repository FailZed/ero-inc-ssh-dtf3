extends "res://scripts/mechanics/core/module.gd"
## Grid placement model + render plan, independent from a final art/UI scene.

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	if not sim.state.housing.properties.has(id): return Rules.fail("property_not_acquired")
	var property: Dictionary = sim.state.housing.properties[id]
	var spec := definition("properties", id)
	if not property.has("layout"): property.layout = {}
	var item := str(args.get("item", ""))
	match operation:
		"place", "move":
			if not property.equipment.has(item): return Rules.fail("furniture_not_owned")
			var furniture := definition("furniture", item)
			if furniture.is_empty(): return Rules.fail("not_placeable_furniture")
			var x := int(args.get("x", 0))
			var y := int(args.get("y", 0))
			var rotated := bool(args.get("rotated", false))
			var size: Array = furniture.get("size", [1, 1])
			var width := int(size[1] if rotated else size[0])
			var height := int(size[0] if rotated else size[1])
			var room: Array = spec.get("room_size", [8, 6])
			if x < 0 or y < 0 or x + width > int(room[0]) or y + height > int(room[1]): return Rules.fail("furniture_out_of_bounds")
			for other in property.layout:
				if other == item: continue
				var placed: Dictionary = property.layout[other]
				if x < int(placed.x) + int(placed.width) and x + width > int(placed.x) and y < int(placed.y) + int(placed.height) and y + height > int(placed.y): return Rules.fail("furniture_collision")
			property.layout[item] = {"x": x, "y": y, "width": width, "height": height, "rotated": rotated, "layer": int(furniture.get("layer", 0))}
		"unplace": property.layout.erase(item)
		"remove":
			if not property.equipment.has(item): return Rules.fail("furniture_not_owned")
			var result: Dictionary = sim.services.inventory.change(item, 1)
			if not result.ok: return result
			property.equipment.erase(item)
			property.layout.erase(item)
			if sim.state.housing.residence == id: sim.services.housing._refresh_equipment(property)
		_: return Rules.fail("unknown_operation")
	return Rules.ok({"render_plan": render_plan(id)})

func render_plan(id: String) -> Array:
	var result: Array = []
	var property: Dictionary = sim.state.housing.properties.get(id, {})
	for item in property.get("layout", {}):
		var placed: Dictionary = property.layout[item].duplicate(true)
		placed.item = item
		placed.visual = definition("furniture", item).get("visual", "")
		result.append(placed)
	result.sort_custom(func(a, b): return str(a.item) < str(b.item) if a.layer == b.layer else int(a.layer) < int(b.layer))
	return result
