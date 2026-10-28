# Переключение мастерской — прямое поручение владельца, 28 октября 2026

Статус: **BROWSER_ASSET_READY**. Текущий user scope: «переключи на новую мастерскую … новая по адресу res://assets/characters/mdrg_study/scenes/browser.tscn».

В ORIGINAL E:/GoDot/ero-inc точечно подключена указанная сцена. Изначально она отсутствовала; из prepared combined-merge-preview/merged перенесены 97 отсутствовавших файлов пакета assets/characters/mdrg_study (content, instances, runtime, scenes, catalog/отчёт). Существовавшие ассеты не перезаписывались. DLL/addon, общие Main/Gameplay/Shell, новые истории, пользовательские saves и Git не менялись. Никакого MDRG/raw/captures cleanup этот чат не выполнял и выполнять не будет.

Подготовлены guard/handoff и список перенесённых файлов с текущими SHA-256:
- E:/GoDot/.research/workshop-entry-2026-10-28/transfer.json
- E:/GoDot/.research/workshop-entry-2026-10-28/handoff.json

Потребители/локальные изменения:
- scripts/ui/main_menu.gd: единственная замена load-пути в _open_character_workshop на browser.tscn; прежние process_mode ALWAYS, anchors и closed→focus_workshop сохранены.
- assets/characters/mdrg_study/runtime/live2d_browser.gd: добавлены signal closed, _close, Esc и кнопка «Закрыть»; catalog_path по умолчанию указывает на реальный каталог этого пакета. Это прямое дополнение новой сцены, без wrapper/fallback старой мастерской.
- export_presets.cfg: Windows include_filter дополнен assets/characters/mdrg_study/*.json для каталога/профилей/снимков/анимационных JSON; Android exclusion не менялся.
- tests/characters/integration.gd и run.gd: ссылки/ожидания обновлены на новую мастерскую; старый UI profile round-trip удалён как проверка удалённого интерфейса.
- Удалены superseded scenes/characters/character_workshop.tscn, scripts/ui/characters/character_workshop.gd и его .uid. Не восстанавливать их при сведении. Общие Puppet/parameter_bank и conversation_actor не менялись: они остаются используемыми разговором.

Фактически выполнено: импорт новых ресурсов Godot4.7.2/Dummy без script/import ошибок; tests/characters/integration.gd — 14 pass / 0 fail. Проверяет настоящую native модель, вход из main/pause меню, сохранение pause, закрытие/освобождение и фокус, соседний разговор. Старые 63 ObjectDB/27 resources при завершении остаются; полный mechanics/export прогон не выполнялся. Лог: E:/GoDot/.research/workshop-entry-2026-10-28/integration.log.

Зависимость от root: сохранить этот caller/runtime-delta при переносе final-integration; resource prune и mapping conversation_actor ведёт root вместе с Live2D-исполнителем. После перезапуска окна по user request работа этого чата закончена, новых этапов не начинаю.

Окно основной игры запущено через tools/godot.ps1 с --character-workshop и Dummy audio: новая мастерская сразу открыта для владельца. Native renderer D3D12/Mobile, окно EroInc (DEBUG); в текущих launch-логах script/load ошибок нет. Лог проверки сохранён также в docs/coordination/verification/workshop-entry-2026-10-28/integration.log. Работа закончена; файлы освобождены.
