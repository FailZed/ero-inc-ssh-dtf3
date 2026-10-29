# macOS Live2D после pull — 29 октября 2026

Статус: **headless runtime подтверждён; visual pending**. Проверка относится к актуальному source после `f8ffdb2e0` и отдельному portable retained-only пакету, а не к полному запуску EroInc.

## Что выполнено

- `python3 tools/build_live2d_study.py --platform macos --destination /tmp/mac-live2d-20261029` собрал переносимую копию с 126 файлами мастерской и закреплённым Godot 4.7.2. Пакет создан вне репозитория. Имя custom user directory в тестовой копии заменено на `Live2D-study-mac-live2d-20261029`, поэтому сохранения EroInc не затронуты.
- В этой копии Godot `4.7.2.stable.official.ed1daf0bf` с `--headless --audio-driver Dummy --editor --import --quit` завершил импорт ресурсов. Лог: `.artifacts/tests/mac-live2d-20261029/import.log`.
- Узкий runtime smoke `tests/characters/macos_live2d_smoke.gd` запущен в той же копии с `--headless --audio-driver Dummy --script res://tests/macos_live2d_smoke.gd`. Браузер выбрал первый retained `shower` (`shower__714017f09d7b7c24_17054_b41a51ab64a0`). Проверены регистрация native `GDCubismUserModel`, готовность браузера, загрузка MOC через Cubism Core 5.0.0, непустые параметры и части, пять кадров, повторная загрузка той же модели, отсутствие ошибки адаптера, сигнал закрытия и освобождение сцены. **13 passed, 0 failed; process exit 0**. Лог: `.artifacts/tests/mac-live2d-20261029/smoke.log`.
- SHA-256 библиотеки в исходном дереве и пакетной копии одинаков: `38eb97344e4e48787b07b1d3e0b0d1b01710e1460360d641bc56b4bb0ce35a52`, как в `addons/gd_cubism/bin/build-macos.json`. В обоих логах нет `SCRIPT ERROR`, `Parse Error`, `FAIL` или `ERROR`.

## Предел результата и следующий шаг

Headless запуск доказывает загрузку одной retained модели и завершение её lifecycle на macOS. Он не подтверждает видимое изображение, расположение UI, работу мыши, визуальную физику или остальные пять моделей. Координатор оставил видимый слот занятой UI-песочнице. Следующий конкретный шаг после освобождения слота — открыть собранный `/tmp/mac-live2d-20261029/Запустить Live2D.command`, визуально проверить модель `shower`, управление и закрытие, сохранить один screenshot для осмотра; либо передать этот шаг владельцу UI. Фоновых процессов этой проверки не остаётся.
