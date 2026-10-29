extends SceneTree

const BROWSER := preload("res://assets/characters/mdrg_study/scenes/browser.tscn")
var passed := 0
var failed := 0
var closed_count := 0

func check(condition: bool, label: String) -> void:
    if condition:
        passed += 1
    else:
        failed += 1
        push_error("FAIL: " + label)

func _initialize() -> void:
    _run.call_deferred()

func _on_closed() -> void:
    closed_count += 1

func _run() -> void:
    await process_frame
    check(ClassDB.class_exists("GDCubismUserModel"), "macOS native GDCubismUserModel registered")
    var browser := BROWSER.instantiate()
    browser.connect("closed", _on_closed)
    root.add_child(browser)
    await process_frame
    var current: Dictionary = browser.get("_current")
    check(str(current.get("name", "")) == "shower", "retained browser selected first shower model")
    check(bool(browser.get("_model_ready")), "retained browser completed model load")
    var actor: Node2D = browser.get("_actor")
    check(is_instance_valid(actor) and bool(actor.call("is_model_loaded")), "actor holds loaded native model")
    if is_instance_valid(actor) and bool(actor.call("is_model_loaded")):
        var backend: Node2D = actor.get("_model")
        check(is_instance_valid(backend), "native backend exists")
        if is_instance_valid(backend):
            check(int(backend.call("csm_get_moc_version")) > 0, "Cubism Core parsed MOC")
        check((actor.call("get_parameter_descriptors") as Array).size() > 0, "native parameters available")
        check((actor.call("get_part_descriptors") as Array).size() > 0, "native parts available")
        for i in range(5):
            await process_frame
        check(bool(actor.call("load_model", current)), "same model reload succeeds")
        check(bool(actor.call("is_model_loaded")), "native model remains loaded after reload")
        check(str(actor.get("last_error")).is_empty(), "no actor error after reload")
    browser.call("_close")
    await process_frame
    check(closed_count == 1, "browser emits closed once")
    check(not is_instance_valid(browser), "browser and native child freed on close")
    print("MACOS_LIVE2D_SMOKE_RESULT ", JSON.stringify({"passed": passed, "failed": failed, "model": str(current.get("name", ""))}))
    quit(1 if failed > 0 else 0)
