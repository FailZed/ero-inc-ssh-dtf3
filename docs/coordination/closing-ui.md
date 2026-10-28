# Closing UI — книга и окно спутника

28 октября 2026. Статус: ограниченный этап закончен, файлы освобождены. Новые задачи не беру. Исполнитель UI:01a17e31-e4e5-7082-9035-1cc15ff87fdc.

## Граница результата

Это **проверенная компонентная дельта для подготовленного combined candidate**, ещё не применённая в original или central. Полную работу мира не заявляю. Исходный согласованный компактный HUD/Actions–People–Places, Tab-hook, сумка и15мин wait сохранены; старые world_hotspots/альтернативный HUD не возвращались. Нового оформления или механизма нет.

Базовый READY-срез: E:/GoDot/.research/agent-coordination/combined-merge-preview/resolved-plan.json, SHA256 `3BAF0E520F7FEC3A0A02916867519CA511956C3D1D104DE16B6D79C50898D4AB`. Собственный стенд: E:/GoDot/.research/agent-coordination/closing-ui/project. Сборка использовала resolution→resolved/path, auto_merged/remote_apply→merged/path, resolved_delete удалён, local_only/identical сохранены. Все файлы/caches скопированы независимо, без ссылок и записи обратно в original. Четыре выбранных prepared preimage повторно сверены при упаковке и не изменились.

## Подтверждённые дефекты и дельта

| Файл и строка в исправленном файле | Воспроизведение / причина | Исправление |
| --- | --- | --- |
| scripts/ui/gameplay/book_overlay.gd:105 | Class-load Shell останавливался: удалённый `HUD.shortcut_style()` не существует в утверждённом hud_widgets. | Использован существующий `HUD.button_style`; старый helper не возвращён. |
| scripts/ui/gameplay/book_overlay.gd:98,128,139 | Tab/Shift+Tab выходили из книги в нижние Controls; Esc/B не закрывали отдельный компонент и не возвращали фокус. | Текущий UI.focus_loop ограничивает книгу и обновляется после смены главы/resize; WeakRef сохраняет предыдущий Control; Esc/B закрывают, остальные горячие клавиши не уходят в Shell. |
| scripts/ui/gameplay/companion_window.gd:71,80 | После принятого предложения кнопки пересозданы: focus owner терялся, Tab вызывал `Next focus node path is invalid`. Первое открытие тоже оставляло фокус под окном. | После обоих вариантов сборки `_choices` вызывается существующий GameWindow._restore, который пересчитывает фокус и выбирает живой Control. |
| scripts/ui/gameplay/game_window.gd:113 | B проходила сквозь окно спутника к существующей горячей клавише книги Shell. | B добавлена в существующий список блокируемых под модальным окном клавиш. |
| scripts/ui/gameplay/gameplay_shell.gd:243,1102 | Открытие книги из сумки принудительно вызывало open_panel(place), очищая историю; закрытие полностью перестраивало underlying Controls. | Книга открывается над текущим экраном; закрытие обновляет только HUD. Существующий sections-button остаётся fallback фокуса, а книга восстанавливает ещё живой предыдущий Control. |

Изначальный компонентный проход после исправления единственного parser blocker:16проверок/10отказов (`before-focus.log`). Ошибки самого первого fixture (недостающее synthetic npc.location) исправлены отдельно в harness и не включаются в production delta.

## Фактические проверки и пределы

- `classload.log`: штатный launcher, headless class-load/создание4UI-классов без добавления в дерево мира —4/0, exit0, ошибок parser/compile нет. Прямой CLI `--check-only` в parser.log не является успешной проверкой: он не регистрирует autoload Gameplay и останавливается на Identifier not found; заменён проверкой с объявленными fixture-autoloads, без изменения production кода.
- `after.log`:18компонентных проверок,0отказов, headless. `native-component.log`:18/0, Compatibility1366×768. Новых script/focus ошибок в обоих проходах нет.
- Использованы настоящие InputEventKey/Viewport GUI: Tab/Shift+Tab внутри книги, смена главы, Esc/B, повторное открытие; открытие спутника, принятие/завершение, Tab по пересозданным кнопкам, блокировка B, закрытие и возврат фокуса.
- Для двух проверок контекста вызван настоящий наследуемый Shell._toggle_book с изолированными дочерними Controls и override open_panel, без построения игрового мира. Проверены сохранение current_panel=inventory и прежнего _panel_history. Закрывающий callback Shell дополнительно проверен по source-flow и parser, полноценный игровой маршрут не запускался.
- Gameplay fixture синтетический: заменены каталог/выбор ответа/время/отношения, Gameplay._ready не создаёт мир. Эти18проверок подтверждают UI, **не** механику companion, RNG, совместимость сохранения, world runtime или numeric parity.
- В synthetic startup присутствует ожидаемое предупреждение QuestWeaver SimpleInventoryAdapter: inventory_controller не создаётся, потому что Gameplay._ready заменён fixture. Это не проверка инвентарных сценариев QuestWeaver; соответствующий production код не менялся.
- Полный candidate runtime до этого останавливался на известном `superseded_work_task_field`; DATA-дельту ведёт карьерный исполнитель. Изменений каталога/симуляции в этом пакете нет. Общие216проверок, экспорт и School-клики не запускались. Физический геймпад/Live2D-жесты этим этапом не проверялись.
- Два native кадра компонентов были получены и осмотрены до последнего steering об очистке: own closing-ui/captures. Это синтетический фон и тестовый взрослый NPC, не снимки прохождения. Для handoff не обязательны, новых снимков не делаю. В original достаточно compact-1920/1366/ultrawide и docs/ui/references; прежние focus-long-name/*before можно удалить решением root. Textlogs/JSON evidence сохраняются.

## Пакет для root

Каталог E:/GoDot/.research/agent-coordination/closing-ui:

- `files/scripts/ui/gameplay/{book_overlay,companion_window,game_window,gameplay_shell}.gd` — ровно4изменённых production файла.
- `preimage/` и `preimage-hashes.json` — точные prepared исходники/SHA256.
- `manifest.json` — pre/post hashes, происхождение preimage, scope18/0 и явное full_world_runtime_verified=false.
- `closing-ui.patch` — unified diff к prepared-срезу; SHA256 `01fd57ad92b11fd459afaab28d30631b43ffbb8a89d463eb3a1e563b77bb2eb8`.
- `harness/tests/closing_ui/` —5тестовых скриптов. В standalone smoke project только autoload Gameplay переопределён на gameplay_fixture.gd; настоящий world не инициализируется. Эти fixture-файлы **не** заменять в production autoload.
- `classload.log`, `after.log`, `native-component.log`, `before.log`, `before-focus.log`, `import.log`, `parser.log` (неуспешный прямой CLI) — локальные доказательства.

Original/central, game_screens, MainSimulation, данные мира, существующие сохранения и Git этим этапом не менялись. Единственная запись в рабочем repo — этот согласованный отчёт.

## Передача на другой компьютер / следующий шаг

1. Root сверяет preimage hashes и применяет4production файла к combined candidate; не копирует весь project с synthetic autoload. Эта дельта требует remote book_blank.png, companion_interactions.gd и остальных зависимостей prepared plan; это не автономный перенос4файлов прямо в старый original.
2. После DATA-исправления каталога root проверяет один настоящий маршрут: сумка→B→Esc→сумка с прежним выбором, книга→экран→закрытие, спутник→предложение→закрытие. До такого прогона компонентные18/0 не называть полной игрой.
3. Перед переносом на другой компьютер root включает применённые файлы, patch/manifest и textlogs в общий handoff; вся папка project, caches и диагностические PNG не нужны. Зависимость для повторения — установленный Godot4.7.2 через tools/godot.ps1 и ресурсы prepared plan. В E:/Ai и Temp внешних зависимостей этого closing-патча нет.
