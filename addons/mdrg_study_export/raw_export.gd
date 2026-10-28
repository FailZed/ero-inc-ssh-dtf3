@tool
extends EditorExportPlugin

func _get_name() -> String:
    return "Live2DResources_assets/characters/mdrg_study"

func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
    var manifest_path: String = "res://assets/characters/mdrg_study/pack_files.json"
    if not FileAccess.file_exists(manifest_path):
        push_error("Live2D packaging manifest is missing: " + manifest_path)
        return
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
    if not data is Dictionary:
        push_error("Invalid Live2D packaging manifest")
        return
    for item: Variant in data.get("files", []):
        var file_path: String = str(item)
        if not file_path.begins_with("res://assets/characters/mdrg_study/") or "/archive/" in file_path:
            push_error("Rejected Live2D export path: " + file_path)
            continue
        if not FileAccess.file_exists(file_path):
            push_error("Missing Live2D export file: " + file_path)
            continue
        add_file(file_path, FileAccess.get_file_as_bytes(file_path), false)
