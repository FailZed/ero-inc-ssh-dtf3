"""Create a separate, offline Live2D workshop beside an imported study model."""
from pathlib import Path
import argparse
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def copy_file(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def build(destination, model_directory, include_windows):
    version = (ROOT / ".godot-version").read_text().strip()
    godot = ROOT / ".cache/runtime/godot" / version / "Godot.app"
    if not godot.is_dir():
        raise ValueError("Сначала установи Godot для Mac через tools/runtime.py setup.")
    model = model_directory / "interaction_model.model3.json"
    if not model.is_file():
        raise ValueError(f"Сначала импортируй учебную модель: {model}")
    project = destination / "workshop"
    runtime = destination / "runtime"
    launcher = destination / "Запустить Live2D.command"
    windows_launcher = destination / "Start Live2D.bat"
    readme = destination / "START_HERE.txt"
    for path in (project, runtime, launcher, windows_launcher, readme):
        if path.exists():
            raise ValueError(f"Путь уже существует; выбери другую --destination: {path}")
    windows = ROOT / ".cache/runtime/godot-windows" / version
    executables = sorted(windows.glob("*.exe")) if include_windows else []
    if include_windows and not executables:
        raise ValueError("Windows runtime не установлен. Запусти без --windows.")
    destination.mkdir(parents=True, exist_ok=True)
    for relative in [
        "scripts/characters/puppet_view.gd", "scripts/characters/parameter_bank.gd",
        "scripts/characters/interaction_memory.gd", "scripts/characters/motion_clip.gd",
        "scripts/ui/characters/character_workshop.gd", "scripts/ui/gameplay/ui_factory.gd",
        "assets/textures/ui/windows-v2/window_surface.png", "data/characters/interaction_profile.json",
    ]:
        copy_file(ROOT / relative, project / relative)
    model_target = project / "models/interaction_model"
    model_target.mkdir(parents=True)
    manifest = json.loads(model.read_text(encoding="utf-8"))
    references = manifest["FileReferences"]
    resources = [model.name, "model.info.json", references["Moc"], references["Physics"], *references["Textures"]]
    for relative in resources:
        source = (model_directory / relative).resolve()
        if not source.is_relative_to(model_directory.resolve()):
            raise ValueError("Ресурс модели находится за пределами её папки.")
        copy_file(source, model_target / relative)
    catalog = {"schema": 1, "models": [{"id": "interaction_model", "title": "Повседневная учебная модель",
        "model": "res://models/interaction_model/interaction_model.model3.json", "study_asset": True}]}
    write(project / "data/characters/study_catalog.json", json.dumps(catalog, ensure_ascii=False, indent=2))
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
textures/default_filters/use_nearest_mipmap_filter=false
''')
    write(project / "main.gd", '''extends "res://scripts/ui/characters/character_workshop.gd"

func _ready() -> void:
    super._ready()
    DisplayServer.window_set_title("Live2D Study — отдельная мастерская")
    status.text = "Live2D Study · отдельная мастерская · свои профили и записи"
''')
    write(project / "main.tscn", '''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://main.gd" id="1"]
[node name="Live2DStudy" type="Control"]
layout_mode=3
anchors_preset=15
anchor_right=1.0
anchor_bottom=1.0
grow_horizontal=2
grow_vertical=2
script=ExtResource("1")
''')
    extension = ROOT / "addons/gd_cubism"
    shutil.copytree(extension / "res", project / "addons/gd_cubism/res")
    copy_file(extension / "gd_cubism.gdextension", project / "addons/gd_cubism/gd_cubism.gdextension")
    copy_file(extension / "bin/libgd_cubism.macos.universal.dylib", project / "addons/gd_cubism/bin/libgd_cubism.macos.universal.dylib")
    if include_windows:
        for name in ["libgd_cubism.windows.x86_64.dll", "Live2DCubismCore.dll"]:
            copy_file(extension / "bin" / name, project / "addons/gd_cubism/bin" / name)
        for executable in executables:
            copy_file(executable, runtime / "windows" / executable.name)
        console = next((exe.name for exe in executables if "console" in exe.name), executables[0].name)
        write(windows_launcher, f'''@echo off
setlocal
set "STUDY_ROOT=%~dp0"
if not exist "%STUDY_ROOT%logs" mkdir "%STUDY_ROOT%logs"
"%STUDY_ROOT%runtime\\windows\\{console}" --headless --editor --path "%STUDY_ROOT%workshop" --import > "%STUDY_ROOT%logs\\import-windows.log" 2>&1
if errorlevel 1 goto failed
"%STUDY_ROOT%runtime\\windows\\{console}" --path "%STUDY_ROOT%workshop" --log-file "%STUDY_ROOT%logs\\workshop-windows.log" %*
if errorlevel 1 goto failed
exit /b 0
:failed
echo Live2D Study failed. See the logs folder.
pause
exit /b 1
'''.replace("\n", "\r\n"))
    shutil.copytree(godot, runtime / "macos/Godot.app", symlinks=True)
    write(launcher, '''#!/bin/zsh
set -eu
STUDY_ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
STUDY_GODOT="$STUDY_ROOT/runtime/macos/Godot.app/Contents/MacOS/Godot"
mkdir -p "$STUDY_ROOT/logs"
echo "Live2D Study — подготовка мастерской…"
if ! "$STUDY_GODOT" --headless --editor --path "$STUDY_ROOT/workshop" --import > "$STUDY_ROOT/logs/import-macos.log" 2>&1; then
  cat "$STUDY_ROOT/logs/import-macos.log"
  echo "Не удалось подготовить мастерскую. Журнал находится в папке logs."
  read -r "?Нажми Enter для закрытия."
  exit 1
fi
exec "$STUDY_GODOT" --path "$STUDY_ROOT/workshop" --log-file "$STUDY_ROOT/logs/workshop-macos.log" "$@"
''')
    launcher.chmod(0o755)
    write(readme, '''LIVE2D STUDY — ОТДЕЛЬНАЯ МАСТЕРСКАЯ

macOS: двойной щелчок по «Запустить Live2D.command».
Первый запуск подготавливает ресурсы, затем сразу открывает модель.
''' + ("Windows x64: открой «Start Live2D.bat».\n" if include_windows else "") + '''
Работает отдельно от EroInc, без меню, истории и сохранений игры.
Движок и модель находятся внутри этой папки. Интернет и Python для запуска не нужны.
Можно переносить всю папку live2d-study целиком.

Параметры: двигай ползунки, используй поиск.
Настройки: физика, моргание, взгляд, зоны захвата, чувствительность.
Запись: нажми «Запись», двигай модель, нажми квадрат и воспроизведение.
Сохранение профиля и движения — во вкладке «Настройки».
Диалог сохранения открывается в отдельной пользовательской папке Live2D-study.
Закрыть мастерскую: «Закрыть» или крестик окна.

Журналы запуска: logs.
В комплекте одна повседневная учебная модель. Привязки взаимодействий — из EroInc.
Это отдельный экземпляр мастерской: изменения исходного проекта автоматически сюда не попадают.
''')
    print(launcher)
    return project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, default=Path.home() / "Downloads/live2d-study")
    parser.add_argument("--model", type=Path, default=Path.home() / "Downloads/live2d-study/mac-interaction")
    parser.add_argument("--windows", action="store_true", help="Добавить установленный Windows runtime и .bat")
    args = parser.parse_args()
    try:
        build(args.destination.expanduser().resolve(), args.model.expanduser().resolve(), args.windows)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"Сборка не выполнена: {error}\n")


if __name__ == "__main__":
    main()
