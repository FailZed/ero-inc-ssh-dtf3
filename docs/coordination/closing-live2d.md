# Closing Live2D — завершено, payload применён интегратором

28 октября 2026. Собственный staging:
`E:/GoDot/.research/agent-coordination/closing-live2d`.
Исполнитель не менял runtime original или central preview. В original записаны
только этот отчёт и `closing-live2d-manifest.json`. Новая очередь не начинается.

## Новый standalone packager — применён интегратором

Интегратор проверил и применил payload в actual
`tools/build_live2d_study.py` с after SHA256, указанным ниже, и guard переносимого
repo manifest. Применение подтверждено интегратором; новых прогонов после
применения не было. Упаковщик открывает настоящий
`res://assets/characters/mdrg_study/scenes/browser.tscn`, читает переносимый
**repo** manifest `tools/manifests/browser_resources.json`. Нет зависимости от
внешнего research, удалённой `character_workshop.gd`, её UI/helpers или старых
builtin моделей. `closed` браузера завершает отдельное приложение; сохранены
caller-owned Close/Esc и текущий catalog_path. Основной проект не запускается.

Точный guard — `packager-patch-manifest.json` в staging:

- prepared preimage SHA256:
  `5faa18278ac4060a99146ad23e974923ea577042f085160953e86c2ed271337b`;
- payload after SHA256:
  `7c351a0e8ce4182c7ba55c6d37a942ba5f78f91873254c3ca2133d73d2fcb7f9`;
- `tools/build_live2d_study.py` добавлен в original интегратором как выбранная
  замена удалённого упаковщика старого editor;
- unified patch: `payload/build_live2d_study.py.patch`;
- canonical resource manifest SHA256:
  `aac8fbb1e22347ace00506c733bc7b5b9fbbaf387e614323e6c209e1e905c246`.

CLI заменён без старого пути совместимости: `--platform windows|macos|both`,
`--windows-runtime DIRECTORY`, `--macos-runtime Godot.app`, `--check`.
Убраны старые `--model`/`--windows`. По умолчанию выбирается текущая платформа.
Движок берётся из pinned `.cache/runtime/godot/<version>` или явно заданной
папки; проверяются оба Windows exe и структура Mac app. Загрузок/компиляции нет.
Вывод — новая/пустая папка вне исходного проекта, ничего не удаляется.
Создаётся копия raw Godot project с браузером, runtime, лицензиями и фактическими
хешами `retained-files.json`, без autoloads/сохранений EroInc.

Синтаксис Python и read-only состав проверены, **не build**:

| Состав | Файлов | Байт исходных ресурсов |
|---|---:|---:|
| Windows | 127 | 55 957 969 |
| macOS | 126 | 54 975 435 |
| Обе платформы | 129 | 57 564 101 |

Все 129 SHA текущих ресурсов совпали с repo manifest. Все относительные
MOC/texture/physics/motion зависимости model3 попали в план. Во всех вариантах
нет archive и старой мастерской. Проверены **4 команды** лаунчеров: импорт и
видимый запуск Windows/macOS содержат `--audio-driver Dummy`. Это статическая
проверка строк, сами лаунчеры не запускались. Доступный режим `--check`:
`python tools/build_live2d_study.py --check --platform both`.
После применения этот режим повторно не запускался. Полные результаты ранее
принятой проверки: staging `packager-composition.json`; также сохранены в
repo `closing-live2d-manifest.json`.

## Native SDK5 — подтверждено чистым headless smoke

**13 passed / 0 failed**, Godot **4.7.2 stable**, Dummy audio. В чистом
`sdk5-project` Windows-пара лежит **только** в `addons/gd_cubism/bin/sdk5/`.
Нет archive, старой builtin папки или root-bin Core DLL. Загружен реальный
обычный одетый conversation actor: **106 параметров, 257 meshes**, Core 5.0,
MOC v5. Проверены speech/skip как в parameter bank, так и настоящие native
parameter values; narrated-результат не включает рот. После освобождения actor
WeakRef исчез. `load_errors=[]`. Журнал `smoke-sdk5.log`, marker и hashes
перенесены в repo audit JSON. Нативная библиотека не пересобиралась.

Канонические Windows файлы:

- `addons/gd_cubism/bin/sdk5/libgd_cubism.windows.x86_64.dll`, 2 349 056 байт,
  SHA `a3550d51d04926e443c55b39a2759e266be8c4102cddafc5d15dfef81ddf485f`;
- `addons/gd_cubism/bin/sdk5/Live2DCubismCore.dll`, 239 240 байт,
  SHA `ba94f85875baa408d85e0deafc0e6c3dd5ba1792842f608738a127c35c7f157b`.

Windows PE: AMD64; renderer использует Windows/UCRT + Core, дополнительных
MinGW runtime imports нет; у Core import KERNEL32. Проверены только headers/imports.
Mac dylib SHA
`38eb97344e4e48787b07b1d3e0b0d1b01710e1460360d641bc56b4bb0ce35a52`,
Fat Mach-O x86_64 + arm64; **на macOS не выполнялся**.
Root уже переключил actual `.gdextension`, build metadata и `.gitignore` на SDK5.
Старый locked Core не выбирается runtime и не входит в manifest/новый пакет.

## Что необходимо сохранить и что не нужно runtime

Browser+shader graph: **114 файлов с .import/.uid**, 53 350 267 байт после
сохранения текущего пользовательского варианта browser. Старое число 93 не
включало 21 sidecar. Канонический root inventory вместе с native/license:
**129 файлов / 57 564 101 байт**. Нельзя удалять sidecars, shader tree,
content/instances/runtime/scenes/catalog/import_report/interaction_profile.

Repo `closing-live2d-manifest.json` хранит audit/removal evidence и точные
хеши; он не является вторым runtime inventory. Интегратор исключил устаревший
raw-export plugin при cleanup. Его **6 prepared export-support файлов**
(pack_files.json и addon mdrg_study_export) теперь отмечены в audit JSON только
как исторические данные frozen snapshot и не входят в текущие 129 файлов.
Все **63** записи прежнего pack_files.json были проверены статически: они уже
входят в browser graph, archive там нет. Возвращать этот plugin не требуется.
Project сохранён интегратором на **GL Compatibility**. Экспорт не запускался.

Сырой `archive/` не нужен текущему browser и разговорному actor. Конкретный LFS:
`assets/characters/mdrg_study/archive/unity/objects/0d211999bfd2a8d5_1259.json`,
114 485 752 байта, oid
`7a451797109a400e857aac9ac569cabcaa1a05d2907cbe58df72073913e98c80`.
Он не упомянут в доступных runtime/catalog/scene/snapshot или export manifest.
Тело **не доступно и не изучалось**, fetch не повторялся. Его конкретный Unity
тип не выдумывается. Импортированные MOC/texture/physics/snapshot/motion3 дают
рабочую компактную замену **для runtime**, без заявления о полной/побайтовой
эквивалентности исследовательскому архиву. Удаление/история Git — работа root.

## Три ранее согласованных узких патча

Полные after-файлы и diff — staging `patches/`, точные preimage/after hashes —
`patch-manifest.json` и repo audit JSON. Уже применены интегратором:

1. `data/characters/study_catalog.json`: 6 builtin model/info путей → retained instances.
2. `data/characters/conversation_reactions.json`: только model URI → retained instance;
   прежний одетый interaction_profile сохранён, Unity snapshot не добавлен.
3. Selected remote `scripts/characters/puppet_view.gd`: безопасное чтение
   `settings.get("parameter_roles", {}).get("output_ids", [])`.
   В prepared варианте отсутствующий optional key вызывал SCRIPT ERROR.

У всех шести old/retained MOC совпали SHA256. Интегратор применил JSON-rebind
и удалил obsolete builtin/raw archive; source references на них исключены по
его проверке. Все три after SHA подтверждены в original при ранее выполненной
финальной read-only сверке. Данный исполнитель source не менял.
Особенно нельзя класть prepared Puppet поверх иного текущего файла без guard.

## Область утверждений и завершение

Это локальная Windows native dependency/portability проверка одного clothed
actor и статическая проверка packager. Она не подтверждает весь merged gameplay,
UI-раскладку или численный паритет School. Полная игра/EXE/PCK/новый native build,
загрузки, пользовательские окна, CUA/мышь, School, saves, Git и cleanup не запускались.
Удаление character_workshop и дрейф main_menu выполнялись другим владельцем,
не этим исполнителем. Запущенных source writers у меня нет.
Итоговый repo-отчёт обновлён после подтверждения интегратора. Новых запусков,
проверок, сборок, загрузок или изменений runtime не выполнялось. Работа закрыта;
исполнитель idle, новые задачи самостоятельно не начинаются.
