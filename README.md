# EroInc

Godot **4.7.2 stable**, Windows x86_64 и macOS universal.

Инструкции для следующего рабочего дня: [NEXT_SESSION.md](NEXT_SESSION.md).
Установка: [docs/DEVELOPMENT_SETUP.md](docs/DEVELOPMENT_SETUP.md).

```sh
python3 tools/runtime.py setup
python3 tools/runtime.py doctor
python3 tools/runtime.py run -- --editor
```

На Windows используйте `py -3` вместо `python3`. Запускатели используют Dummy audio.
Нативные библиотеки Live2D уже включены; обычный запуск не требует компилятора.

Мастерская: `res://assets/characters/mdrg_study/scenes/browser.tscn`.
Сырой MDRG-архив и старые скриншоты удалены из текущей версии по поручению
владельца. Текущая мастерская использует сохранённые модели, атласы, физику,
профили и снимки параметров; скачивать архив через Git LFS для неё не требуется.
Старая история Git сохранена и может иметь недоступные архивные LFS-объекты.

Сохранения игрока, окружения, кэши и локальные сборки в репозиторий не входят.
Наличие исходников и workflow не означает полную приёмку игры на обеих ОС.
