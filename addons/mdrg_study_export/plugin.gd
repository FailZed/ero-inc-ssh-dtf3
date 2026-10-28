@tool
extends EditorPlugin

var _exporter: EditorExportPlugin

func _enter_tree() -> void:
    _exporter = preload("raw_export.gd").new()
    add_export_plugin(_exporter)

func _exit_tree() -> void:
    if _exporter != null:
        remove_export_plugin(_exporter)
        _exporter = null
