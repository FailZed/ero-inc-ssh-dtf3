"""Export the everyday Live2D study model from the user-supplied macOS build.

Reads Unity assets without starting the donor game. Does not export scene models,
game scripts, dialogue or animation controllers. Existing output is never replaced.
Shared Cubism conversion helpers live in import_mdrg_study_models.py.
"""
from pathlib import Path
import argparse
import ctypes as C
import hashlib
import json
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MODEL_NAME = "interaction_model"


def canonical_path(path):
    """Preserve actual directory spelling on macOS's case-insensitive volumes."""
    path = path.expanduser().resolve()
    current = Path(path.anchor)
    for part in path.parts[1:]:
        requested = current / part
        if requested.exists():
            candidates = [entry for entry in current.iterdir()
                          if entry.name.casefold() == part.casefold() and entry.samefile(requested)]
            current = candidates[0] if candidates else requested
        else:
            current = requested
    return current


def find_app(source):
    source = canonical_path(source)
    if source.suffix.lower() == ".app" and source.is_dir():
        return source
    candidates = sorted(source.glob("*.app")) if source.is_dir() else []
    if len(candidates) != 1:
        raise ValueError("Укажи путь к .app или папке, содержащей ровно одно приложение.")
    return candidates[0]


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def texture_slots(core, raw):
    """Use native texture slot indices, never guess atlas order from filenames."""
    buffer = C.create_string_buffer(len(raw) + 64)
    pointer = (C.addressof(buffer) + 63) & ~63
    C.memmove(pointer, raw, len(raw))
    moc = core.dll.csmReviveMocInPlace(pointer, len(raw))
    if not moc:
        raise ValueError("Cubism Core отклонил модель.")
    size = core.dll.csmGetSizeofModel(moc)
    model_buffer = C.create_string_buffer(size + 16)
    model = core.dll.csmInitializeModelInPlace(moc, (C.addressof(model_buffer) + 15) & ~15, size)
    if not model:
        raise ValueError("Не удалось создать модель Cubism.")
    function = core.dll.csmGetDrawableTextureIndices
    function.argtypes = [C.c_void_p]
    function.restype = C.POINTER(C.c_int)
    slots = function(model)
    ids = core.dll.csmGetDrawableIds(model)
    return {ids[i].decode(): slots[i] for i in range(core.dll.csmGetDrawableCount(model))}


def read_model(app, library):
    import UnityPy
    from UnityPy.helpers.TypeTreeGenerator import TypeTreeGenerator
    from import_mdrg_study_models import Core, physics

    data = app / "Contents/Resources/Data"
    resources = data / "resources.assets"
    managed = data / "Managed"
    for path in [resources, managed, library]:
        if not path.exists():
            raise ValueError(f"В этой сборке отсутствует ожидаемый ресурс: {path}")
    env = UnityPy.load(str(resources))
    resource_file = next(f for f in env.files.values() if hasattr(f, "unity_version"))
    version = resource_file.unity_version
    generator = TypeTreeGenerator(version)
    generator.load_local_dll_folder(str(managed))
    env.typetree_generator = generator
    objects = {obj.path_id: obj for obj in resource_file.objects.values()}
    names, transforms, by_go, components = {}, {}, {}, []
    for obj in objects.values():
        if obj.type.name == "GameObject":
            names[obj.path_id] = obj.read().m_Name
        elif obj.type.name in ("Transform", "RectTransform"):
            value = obj.read()
            transforms[obj.path_id] = (value.m_GameObject.m_PathID, [p.m_PathID for p in value.m_Children])
            by_go[value.m_GameObject.m_PathID] = obj.path_id
        elif obj.type.name == "MonoBehaviour":
            head = obj.parse_monobehaviour_head()
            if head.m_GameObject.m_PathID:
                components.append((obj, head))
    roots = [go for go, name in names.items() if name == MODEL_NAME]
    if len(roots) != 1:
        raise ValueError(f"Ожидалась одна повседневная модель {MODEL_NAME}; найдено {len(roots)}.")
    pending, descendants = [by_go[roots[0]]], set()
    while pending:
        go, children = transforms[pending.pop()]
        if go in descendants:
            continue
        descendants.add(go)
        pending.extend(children)
    wanted = {"CubismModel", "CubismRenderer", "CubismPhysicsController", "CubismEyeBlinkParameter", "CubismMouthParameter"}
    records = []
    for obj, head in components:
        if head.m_GameObject.m_PathID not in descendants:
            continue
        cls = head.m_Script.deref_parse_as_object().m_ClassName
        if cls in wanted:
            records.append((cls, head.m_GameObject.m_PathID, obj, obj.read_typetree()))
    models = [record for record in records if record[0] == "CubismModel"]
    if len(models) != 1:
        raise ValueError("Не найдена единственная CubismModel внутри повседневной модели.")
    reference = models[0][3]["_moc"]
    if reference["m_FileID"]:
        raise ValueError("Внешняя ссылка на moc не поддерживается этой версией импортера.")
    raw = bytes(objects[reference["m_PathID"]].read_typetree()["_bytes"])
    core = Core(library)
    parameters, drawables, parts = core.inspect(raw)
    slots = texture_slots(core, raw)
    textures = {}
    for cls, go, obj, value in records:
        if cls != "CubismRenderer":
            continue
        drawable = names[go]
        if drawable not in slots:
            raise ValueError(f"Сетка {drawable} не найдена в moc.")
        pointer = value["_mainTexture"]
        if pointer["m_FileID"]:
            raise ValueError("Внешняя ссылка на текстуру не поддерживается этой версией импортера.")
        slot, texture_id = slots[drawable], pointer["m_PathID"]
        if slot in textures and textures[slot] != texture_id:
            raise ValueError(f"Конфликт текстур для слота {slot}.")
        textures[slot] = texture_id
    expected = set(slots.values())
    if set(textures) != expected or expected != set(range(len(expected))):
        raise ValueError("Не удалось восстановить все слоты атласа текстур.")
    rigs = [value["_rig"] for cls, _, _, value in records if cls == "CubismPhysicsController"]
    if len(rigs) != 1:
        raise ValueError("Не найден единственный набор физики повседневной модели.")
    groups = []
    for cls, name in [("CubismEyeBlinkParameter", "EyeBlink"), ("CubismMouthParameter", "LipSync")]:
        ids = [names[go] for kind, go, _, _ in records if kind == cls]
        if ids:
            groups.append({"Target": "Parameter", "Name": name, "Ids": ids})
    return dict(raw=raw, parameters=parameters, drawables=drawables, parts=parts,
                images=[objects[textures[i]].read() for i in sorted(textures)],
                physics=physics(rigs[0]), groups=groups, unity_version=version,
                source_resources_sha256=sha256(resources))


def export_model(model, app, target):
    from import_mdrg_study_models import write

    if target.exists():
        raise ValueError(f"Папка уже существует: {target}. Укажи новый --target.")
    target.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".live2d-import-", dir=target.parent))
    try:
        (staging / f"{MODEL_NAME}.moc3").write_bytes(model["raw"])
        textures = []
        for index, texture in enumerate(model["images"]):
            filename = f"texture_{index:02}.png"
            texture.image.save(staging / filename)
            textures.append(filename)
        write(staging / f"{MODEL_NAME}.physics3.json", model["physics"])
        write(staging / f"{MODEL_NAME}.model3.json", {
            "Version": 3, "FileReferences": {"Moc": f"{MODEL_NAME}.moc3", "Textures": textures,
            "Physics": f"{MODEL_NAME}.physics3.json"}, "Groups": model["groups"], "HitAreas": []})
        provenance = {"source_app": str(app), "purpose": "Local technical Live2D study",
                      "unity_version": model["unity_version"], "source_resources_sha256": model["source_resources_sha256"],
                      "moc_sha256": hashlib.sha256(model["raw"]).hexdigest()}
        write(staging / "model.info.json", {"id": MODEL_NAME, "parameters": model["parameters"],
              "drawables": model["drawables"], "parts": model["parts"], "provenance": provenance})
        bindings = json.loads((ROOT / "data/characters/interaction_profile.json").read_text(encoding="utf-8"))
        values = {p["id"]: p["default"] for p in model["parameters"]}
        for parameter, value in bindings["initial"].items():
            if parameter not in values:
                raise ValueError(f"Профиль EroInc несовместим с моделью: отсутствует {parameter}.")
            values[parameter] = value
        write(staging / "workshop.profile.json", {"schema": 1,
              "model": {"id": MODEL_NAME, "title": "Повседневная модель · Mac study", "study_asset": True,
                        "model": str(target / f"{MODEL_NAME}.model3.json")},
              "bindings": bindings, "values": values, "parts": {},
              "settings": {"physics_enabled": True, "gaze_enabled": True, "blink_enabled": True}})
        (staging / "README.txt").write_text(
            "EroInc: Мастерская → Настройки → Загрузить профиль… → workshop.profile.json\n"
            "Профиль содержит абсолютный путь к модели. При переносе папки измени model.model в профиле.\n"
            "Модель и физика извлечены из Unity. Привязки взаимодействий взяты из EroInc.\n"
            "Код исходной игры, сцены, анимационные контроллеры и исходник Cubism .cmo3 не перенесены.\n",
            encoding="utf-8")
        if target.exists():
            raise ValueError(f"Папка появилась во время экспорта: {target}")
        staging.rename(target)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path.home() / "Downloads/factorial-omega-mac-64")
    parser.add_argument("--target", type=Path, default=Path.home() / "Downloads/live2d-study/mac-interaction")
    parser.add_argument("--core", type=Path, default=ROOT / "addons/gd_cubism/bin/libgd_cubism.macos.universal.dylib",
                        help="Совместимая библиотека Cubism Core; по умолчанию модуль нашего проекта")
    parser.add_argument("--inspect", action="store_true", help="Проверить модель без сохранения файлов")
    args = parser.parse_args()
    try:
        app = find_app(args.source)
        target = canonical_path(args.target)
        if not args.inspect and target.exists():
            raise ValueError(f"Папка уже существует: {target}. Укажи новый --target.")
        if target == app or app in target.parents:
            raise ValueError("Нельзя сохранять экспорт внутрь исходного приложения.")
        print(f"Читаю: {app}", flush=True)
        model = read_model(app, args.core.expanduser().resolve())
        print(json.dumps({"model": MODEL_NAME, "unity": model["unity_version"],
              "parameters": len(model["parameters"]), "drawables": len(model["drawables"]),
              "textures": len(model["images"]), "physics_chains": len(model["physics"]["PhysicsSettings"])}, ensure_ascii=False), flush=True)
        if not args.inspect:
            export_model(model, app, target)
            print(f"Готово: {target / 'workshop.profile.json'}")
        return 0
    except ImportError as error:
        print(f"Не установлены зависимости: {error}\nУстанови tools/requirements-live2d-import.txt в venv.", file=sys.stderr)
    except (OSError, ValueError, KeyError, StopIteration) as error:
        print(f"Импорт не выполнен: {error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
