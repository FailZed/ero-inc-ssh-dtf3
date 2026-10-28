"""Package the retained Live2D browser and a pinned Godot runtime, without downloads."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import platform
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = "tools/manifests/browser_resources.json"
ENTRY = "assets/characters/mdrg_study/scenes/browser.tscn"
ASSETS = "assets/characters/mdrg_study/"
NATIVE = "addons/gd_cubism/"
WINDOWS_RENDERER = NATIVE + "bin/sdk5/libgd_cubism.windows.x86_64.dll"
WINDOWS_CORE = NATIVE + "bin/sdk5/Live2DCubismCore.dll"
MACOS_RENDERER = NATIVE + "bin/libgd_cubism.macos.universal.dylib"


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def source_file(root, relative):
    name = PurePosixPath(relative)
    if name.is_absolute() or ".." in name.parts or "\\" in relative:
        raise ValueError(f"Invalid retained path: {relative}")
    if not relative.startswith((ASSETS, NATIVE)) or "/archive/" in relative:
        raise ValueError(f"Not a retained browser dependency: {relative}")
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError(f"Missing retained file: {relative}")
    with path.open("rb") as stream:
        if stream.read(128).startswith(b"version https://git-lfs.github.com/spec/v1"):
            raise ValueError(f"LFS body is unavailable: {relative}")
    return path


def platforms_for(name):
    return ("windows", "macos") if name == "both" else (name,)


def inspect_sources(root, platforms):
    """Read-only preflight, also usable without installed engine binaries."""
    version = (root / ".godot-version").read_text(encoding="utf-8").strip()
    manifest = json.loads((root / MANIFEST).read_text(encoding="utf-8-sig"))
    if manifest.get("schema") != 1:
        raise ValueError("Unsupported retained inventory schema")
    if manifest.get("entry") != "res://" + ENTRY:
        raise ValueError("Retained inventory must use the current browser scene")
    files = dict(manifest["files"])
    if "windows" not in platforms:
        for name in (WINDOWS_RENDERER, WINDOWS_CORE, NATIVE + "bin/build-windows.json"):
            files.pop(name)
    if "macos" not in platforms:
        for name in (MACOS_RENDERER, NATIVE + "bin/build-macos.json"):
            files.pop(name)
    sources = {name: source_file(root, name) for name in files}
    browser = sources[ASSETS + "runtime/live2d_browser.gd"].read_text(encoding="utf-8-sig")
    if not re.search(r"^signal closed\s*$", browser, re.MULTILINE):
        raise ValueError("Current browser must expose its closed signal")
    if ENTRY not in sources or ASSETS + "catalog.json" not in sources:
        raise ValueError("Retained browser scene/catalog missing from inventory")
    # Native pair hashes are authoritative; ordinary source hashes are audit
    # evidence, so editing the browser later does not restore an obsolete screen.
    for target in platforms:
        binary = WINDOWS_RENDERER if target == "windows" else MACOS_RENDERER
        build = json.loads(sources[NATIVE + f"bin/build-{target}.json"].read_text(encoding="utf-8-sig"))
        if digest(sources[binary]) != build["sha256"]:
            raise ValueError(f"Renderer differs from its build metadata: {binary}")
        if target == "windows":
            if build["binary"] != "sdk5/libgd_cubism.windows.x86_64.dll":
                raise ValueError("Windows build metadata must use bin/sdk5")
            if digest(sources[WINDOWS_CORE]) != files[WINDOWS_CORE]["sha256"]:
                raise ValueError("Windows Core does not match the retained SDK5 pair")
    extension = sources[NATIVE + "gd_cubism.gdextension"].read_text(encoding="utf-8-sig")
    if '"bin/sdk5/libgd_cubism.windows.x86_64.dll"' not in extension or '"bin/sdk5/Live2DCubismCore.dll"' not in extension:
        raise ValueError("GDExtension must use the canonical SDK5 Windows pair")
    # Prove that every MOC/texture/physics/motion referenced by a retained
    # descriptor will be copied, including paths shared across instances.
    for name, path in sources.items():
        if not name.endswith(".model3.json"):
            continue
        refs = json.loads(path.read_text(encoding="utf-8-sig")).get("FileReferences", {})
        dependencies = [refs[key] for key in ("Moc", "Physics", "Pose", "UserData") if refs.get(key)]
        dependencies += refs.get("Textures", [])
        dependencies += [item["File"] for item in refs.get("Expressions", [])]
        dependencies += [item["File"] for group in refs.get("Motions", {}).values() for item in group]
        for ref in dependencies:
            target = (path.parent / ref).resolve()
            if not target.is_relative_to(root.resolve()) or target.relative_to(root.resolve()).as_posix() not in sources:
                raise ValueError(f"Descriptor dependency absent from inventory: {name}: {ref}")
    return version, sources


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        stream.write(text)


def copy_file(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def windows_launcher(console):
    return f'''@echo off
setlocal
set "STUDY_ROOT=%~dp0"
if not exist "%STUDY_ROOT%logs" mkdir "%STUDY_ROOT%logs"
"%STUDY_ROOT%runtime\\windows\\{console}" --headless --audio-driver Dummy --editor --path "%STUDY_ROOT%workshop" --import > "%STUDY_ROOT%logs\\import-windows.log" 2>&1
if errorlevel 1 goto failed
"%STUDY_ROOT%runtime\\windows\\{console}" --audio-driver Dummy --path "%STUDY_ROOT%workshop" --log-file "%STUDY_ROOT%logs\\workshop-windows.log" %*
if errorlevel 1 goto failed
exit /b 0
:failed
echo Live2D Study failed. See the logs folder.
pause
exit /b 1
'''.replace("\n", "\r\n")


MACOS_LAUNCHER = '''#!/bin/zsh
set -eu
STUDY_ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
STUDY_GODOT="$STUDY_ROOT/runtime/macos/Godot.app/Contents/MacOS/Godot"
mkdir -p "$STUDY_ROOT/logs"
if ! "$STUDY_GODOT" --headless --audio-driver Dummy --editor --path "$STUDY_ROOT/workshop" --import > "$STUDY_ROOT/logs/import-macos.log" 2>&1; then
  cat "$STUDY_ROOT/logs/import-macos.log"
  echo "Не удалось подготовить браузер моделей. См. logs."
  read -r "?Нажми Enter для закрытия."
  exit 1
fi
exec "$STUDY_GODOT" --audio-driver Dummy --path "$STUDY_ROOT/workshop" --log-file "$STUDY_ROOT/logs/workshop-macos.log" "$@"
'''


def build(root, destination, platforms, windows_runtime=None, macos_runtime=None):
    version, sources = inspect_sources(root, platforms)
    destination = destination.resolve()
    if destination.is_relative_to(root.resolve()) or root.resolve().is_relative_to(destination):
        raise ValueError("Choose a destination outside the source project")
    if destination.exists() and (not destination.is_dir() or any(destination.iterdir())):
        raise ValueError(f"Destination must be new or empty: {destination}")
    cache = root / ".cache/runtime/godot" / version
    windows_files = []
    if "windows" in platforms:
        directory = windows_runtime or cache
        for name in (f"Godot_v{version}-stable_win64.exe", f"Godot_v{version}-stable_win64_console.exe"):
            path = directory / name
            if not path.is_file():
                raise ValueError(f"Pinned Windows runtime missing: {path}. Use --windows-runtime.")
            windows_files.append(path)
    app = macos_runtime or cache / "Godot.app"
    if "macos" in platforms and not (app / "Contents/MacOS/Godot").is_file():
        raise ValueError(f"Pinned macOS runtime missing: {app}. Use --macos-runtime.")
    # All source/runtime/path checks happen before creating output. No downloads,
    # native compilation, recursive deletion, or old-workshop compatibility path.
    project = destination / "workshop"
    for name, source in sources.items():
        copy_file(source, project / name)
    copy_file(root / ".godot-version", project / ".godot-version")
    write(project / "project.godot", '''config_version=5
[application]
config/name="Live2D Study"
run/main_scene="res://main.tscn"
config/use_custom_user_dir=true
config/custom_user_dir_name="Live2D-study"
[display]
window/size/viewport_width=1440
window/size/viewport_height=960
window/size/window_width_override=1440
window/size/window_height_override=960
window/stretch/mode="canvas_items"
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
''')
    write(project / "main.gd", '''extends Node

const BROWSER = preload("res://assets/characters/mdrg_study/scenes/browser.tscn")

func _ready() -> void:
    DisplayServer.window_set_title("Live2D Study — браузер моделей")
    var browser := BROWSER.instantiate()
    browser.connect("closed", _on_closed)
    add_child(browser)

func _on_closed() -> void:
    get_tree().quit()
''')
    write(project / "main.tscn", '''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://main.gd" id="1"]
[node name="Live2DStudy" type="Node"]
script = ExtResource("1")
''')
    if "windows" in platforms:
        for source in windows_files:
            copy_file(source, destination / "runtime/windows" / source.name)
        write(destination / "Start Live2D.bat", windows_launcher(windows_files[1].name))
    if "macos" in platforms:
        shutil.copytree(app, destination / "runtime/macos/Godot.app", symlinks=True)
        launcher = destination / "Запустить Live2D.command"
        write(launcher, MACOS_LAUNCHER)
        launcher.chmod(0o755)
    packaged = {name: {"sha256": digest(path), "bytes": path.stat().st_size} for name, path in sources.items()}
    write(destination / "retained-files.json", json.dumps({"schema": 1, "engine": version,
          "browser_entry": "res://" + ENTRY, "platforms": platforms, "files": packaged}, ensure_ascii=False, indent=2) + "\n")
    write(destination / "START_HERE.txt", '''LIVE2D STUDY — БРАУЗЕР МОДЕЛЕЙ

Windows: Start Live2D.bat. macOS: Запустить Live2D.command (если платформа включена).
Первый запуск импортирует ресурсы, затем открывает браузер моделей.
Вся папка переносится целиком; Python и интернет для запуска не нужны.
Движок использует Dummy audio. Журналы находятся в logs.

Это отдельная копия текущего browser.tscn: выбор моделей, параметры, части,
физика, поза, движения и выражения берутся из сохранённого каталога.
Кнопка «Закрыть», Esc и крестик окна закрывают приложение.
Сохранения EroInc и основное меню игры не используются.
Сырой Unity archive и удалённая character_workshop в комплект не входят.
Состав и фактические хеши файлов записаны в retained-files.json.
''')
    return project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, default=Path.home() / "Downloads/live2d-study")
    parser.add_argument("--platform", choices=("windows", "macos", "both"),
                        default="macos" if platform.system() == "Darwin" else "windows")
    parser.add_argument("--windows-runtime", type=Path, help="Directory with both pinned Windows Godot executables")
    parser.add_argument("--macos-runtime", type=Path, help="Pinned Godot.app directory")
    parser.add_argument("--check", action="store_true", help="Check source composition only; no output, engine execution or download")
    args = parser.parse_args()
    try:
        selected = platforms_for(args.platform)
        if args.check:
            version, sources = inspect_sources(ROOT, selected)
            print(json.dumps({"engine": version, "platforms": selected, "files": len(sources),
                              "bytes": sum(path.stat().st_size for path in sources.values()),
                              "browser_entry": "res://" + ENTRY}, ensure_ascii=False))
        else:
            print(build(ROOT, args.destination.expanduser(), selected,
                        args.windows_runtime.expanduser().resolve() if args.windows_runtime else None,
                        args.macos_runtime.expanduser().resolve() if args.macos_runtime else None))
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Package not created: {error}\n")


if __name__ == "__main__":
    main()
