# EroInc

Godot 4.7.2 · macOS (Apple Silicon/Intel) · Windows x86_64.

Для получения полного архива ресурсов нужен [Git LFS](https://git-lfs.com/).
После его установки в папке клонированного проекта выполните:

```sh
git lfs install --local
git lfs pull
```

На macOS из папки проекта:

```sh
python3 tools/runtime.py setup
python3 tools/runtime.py run -- --editor
```

На Windows используйте `py -3` вместо `python3`. В редакторе нажмите **F5**. Live2D-библиотеки включены в проект.

[Запуск Live2D, проверки, сборки и настройка среды](docs/DEVELOPMENT_SETUP.md).

[Что изменилось и как проверено](docs/gameplay/COMPANION_AND_DESKTOP.md).
