# EroInc: macOS и Windows

Проект использует Godot **4.7.2 stable** из `.godot-version`, GL Compatibility и Python 3.9+. Python нужен для инструментов разработки; готовая игра запускается без Python и установленного Godot. Сборки: macOS Apple Silicon/Intel и Windows x86_64.

## Первый запуск

В терминале откройте папку проекта. На macOS:

```sh
python3 tools/runtime.py setup
python3 tools/runtime.py doctor
python3 tools/runtime.py run -- --editor
```

На Windows в PowerShell замените `python3` на `py -3`:

```powershell
py -3 tools/runtime.py setup
py -3 tools/runtime.py doctor
py -3 tools/runtime.py run -- --editor
```

`setup` скачивает закреплённый Godot с официального GitHub и проверяет SHA-512. Движок хранится в `.cache/runtime`; системный Godot не заменяется. Дождитесь первого импорта. **F5** запускает игру. Без редактора: `python3 tools/runtime.py run -- --path .`. Для существующего движка задайте `EROINC_GODOT`; версия всё равно проверяется.

Запускатели и тесты сохраняют прежнюю настройку проекта: звук отключён драйвером Dummy.

Обёртки: `./tools/godot.sh --editor` на Mac, `./tools/godot.ps1 --editor` в PowerShell. Настройки VS Code больше не содержат путей к дискам и старой версии движка; Godot Tools можно указать путь из `doctor`.

## Live2D

Готовые библиотеки включены в `addons/gd_cubism/bin`: универсальная macOS `.dylib`, Windows `.dll` и `Live2DCubismCore.dll`. Компилятор для обычного запуска не требуется.

1. В боковом меню игры откройте **МАСТЕРСКАЯ** — экран с шестью учебными моделями, параметрами, физикой и зонами взаимодействия.
2. Для встречи с игровым NPC начните новое прохождение, выберите песочницу, завершите создание персонажа и откройте профиль знакомого NPC в текущей локации.
3. В разделе **Время вместе** нажмите **Прикосновения и время вместе**. Жесты учитывают доверие, близость, настроение, границы и занятость собеседника. После принятого предложения удерживайте соответствующую область модели и отпустите либо используйте кнопку завершения. Esc/«Остановиться» отменяет встречу без ухудшения отношений.

Встреча тратит игровое время, влияет на отношения и остаётся в памяти NPC. Между повторами есть пауза; длительное удерживание не увеличивает награду. Сохранённую принятую встречу можно продолжить после загрузки. Во время встречи посторонние команды времени заблокированы; отмена и изменение границ доступны.

Live2D-образ **учебный и временный**, для женского человеческого/получеловеческого тела. Другие NPC используют свой обычный портрет с теми же действиями. Индивидуальные авторские Live2D-модели ещё предстоит сделать. Происхождение моделей: `assets/characters/mdrg_study/provenance.json`.

## Проверки

```sh
python3 tools/test.py all
python3 tools/test.py mechanics --isolated --pack
python3 tools/test.py characters --isolated --pack
python3 tools/test.py companion --native
```

На Windows замените `python3` на `py -3`. Старые `tools/test_*.ps1` вызывают общий runner. `--native` сохраняет графические снимки встречи; `--visible` запускает обычную проверку с окном. Результаты: `.artifacts/tests`. Тесты работают в копиях `.cache/tests` и отдельных каталогах пользовательских данных, не затрагивая сохранения игрока. Не запускайте два runner одновременно для одной тестовой копии.

Основная схема сохранения теперь **9**. Старые слоты не мигрируются. Несовместимое сохранение получает ошибку; ручная и автоматическая перезапись такого состояния запрещена. Для новых механик начните новое прохождение. Установка не удаляет файлы сохранений.

## Сборки

```sh
python3 tools/runtime.py setup --templates
python3 tools/export.py --platform all
```

Можно выбрать `macos` или `windows`. Результат: `dist/macos/EroInc.zip` и `dist/windows/EroInc.exe` с `.pck`, DLL и лицензиями. Переносите **всю папку Windows**, а не один EXE. На Mac распакуйте ZIP и запустите EroInc.app. Это отладочные сборки без публичной подписи/нотаризации; для распространения подпись настраивается отдельно. Android не входит в эту проверку; его preset сохранён.

CI `.github/workflows/desktop.yml` выполняет проверки и экспорт на macOS и Windows при push/PR. Наличие workflow само по себе не означает выполненный удалённый прогон.

## Пересборка Live2D

Требуется только при изменении C++ или восстановлении библиотек:

```sh
python3 tools/runtime.py setup --live2d
```

Нужны Git и компилятор: Xcode Command Line Tools на Mac; Visual Studio Build Tools с C++ и Windows SDK на Windows (Developer PowerShell). SCons 4.7.0 устанавливается в `.cache/runtime/build-venv`. Скрипт получает официальный Cubism Native SDK 5-r.1 с проверкой SHA-256 и закреплённые gd_cubism/godot-cpp. DLL другой игры не используется. Локальный SDK: `python3 tools/build_cubism_runtime.py --sdk /path/to/CubismSdkForNative-5-r.1`.

Кросс-сборка Windows на Mac: установите MinGW-w64 и выполните `python3 tools/build_cubism_runtime.py --platform windows`. Хеши библиотек записываются в `bin/build-*.json`. Условия и уведомления Cubism сохранены в `addons/gd_cubism/*LICENSE*` и `*NOTICE*`.

## Сценарные утилиты

Для DOCX: `python3 -m pip install -r requirements-dev.txt`. Справка: `python3 tools/build_prologue_dialogic.py --help`. Генератор перезаписывает таймлайны, поэтому запускайте его только при намеренной пересборке сценария. Существующие диалоги редактируются в Dialogic без исходного DOCX.
