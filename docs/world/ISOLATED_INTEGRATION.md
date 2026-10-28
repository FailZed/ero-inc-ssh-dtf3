# Handoff: единый городской runtime-кандидат

## Передача root в основной исходник

28 октября, 21:28 МСК: root перенёс76 согласованных дельт через immutable
baseline, hash-guard preimages и резервные копии. Это включение в source,
не публикация в Git и не доказательство полной приёмки объединённой игры.
Source H01/H02/H05, семейный handoff, A04 и Tab-hook сохранены. NPC-calendar
соединяет полный интервал услуги с actor-aware доступом; строгая owner-проверка
домашнего API взята из source без дублирования методов. Приведённый ниже
отчёт исполнителей относится к isolated candidate до этого сведения.
Удалённый commit468aa32 ещё требуется отдельно объединить; он содержит
дополнительные runtime-сервисы и portable desktop tooling.

Ниже сохранён исторический handoff исполнителя.

28 октября2026. Исполнитель `/root/world_geography` закончил ограниченный этап.
Рабочая копия: `E:/GoDot/.research/world-integration-2026-10-28/project`.
Baseline: `../base`, исходный `../source-manifest.json` не менялись.
В original runtime ничего автоматически не перенесено. Git/EXE/сохранения
исполнителем не затронуты. Новых этапов до завтрашнего решения не назначать.

## Результат

Единый graph/CityLayout заменяет main-каталог:71 место,79 рёбер,17 зданий,
26 услуг; реальные входы кампуса/магазинов/клиники/работ и4 варианта жилья.
Сценарные частные, frame и flashback места не становятся свободной прогулкой.
Обновлены player/NPC access, текущие комнаты, пути обязанностей, начальное
население и snapshot каталога. Старые scene-change пути удалены; LocationManager
теперь только отражает единственный Gameplay/World, а не содержит свою карту.
Полный API и сценарная граница — `GRAPH_INTEGRATION.md`.

Существующая компактная панель сохранена. Через неё доступны4 объектные сцены,
осмотр и2 малых действия с единым центральным подтверждением. Селина/Дана
создаются внутри выбранного N и имеют реальные private homes/workplaces;
личная жизнь открывается после пролога, не при загрузке snapshot.

## Владение и соседние пакеты

Все common MainSimulation/Gameplay/Shell/Population/World изменения сделаны
географией в копии. Places закрыл city_place_content/place_objects и
city_view/weather_matrix/presentation. Residents закрыл city_residents,
данные/arc/UI личной истории и5 адресных leaf-файлов. Leases завершены;
новая самостоятельная работа исполнителям сегодня не назначается.

Точный машинный список: `E:/GoDot/.research/world-integration-2026-10-28/world-candidate-manifest.json`.
Он содержит action, baseline/candidate/current-original SHA256 и merge-sensitive
пометки. Это список для3-way переноса, не команда перезаписи original.
Новые переносимые domain-smoke файлы: `tools/test_city_graph.ps1` и
`tests/gameplay/city_graph_runtime_smoke.gd`.

## Реальные проверки

| Проверка | Факт | Граница |
| --- | --- | --- |
| Main domain smoke |89checks,0failures; exit0; Godot 4.7.2/Dummy | Без autoloads/окон/сейвов; N36/N2/K0, квоты, batch, homes, snapshot/rollback, все fixed job routes, реальные buy/shift/lesson/urgent clinic, mandatory story IDs |
| Residents leaf smoke |102checks,0failures; exit0 |4 жилья, комнаты/переезд/выселение, санитарные входы,3 концовки/C1/память/revisit/restore; контролируемые fixture contacts/time |
| City map UI smoke |128passed,0failed | Синтетическая сцена1280×720/125%, подписи/маршруты/16weather previews; без команды перехода/визуального плейтеста |
| UI parser |7 из7 файлов | Shell/Phone/GameScreens/InventoryView/LivelihoodWindow/Gameplay/LocationManager;4 малых parser-only autoload stubs |
| Shell confirmation |12checks,0failures | Headless shell subclass + реальные Main/PlaceObjects и Gameplay test-double; popup/cancel/doublepress/success/reject/новый context после state replacement; полный _ready/HUD не запускался |

Логи находятся рядом с копией: `world-runtime-smoke.log`,
`residents-smoke-evidence.json`, `city-map-ui-smoke.log`,
`world-ui-parser-final.log`, `world-ui-confirmation-smoke.log`.
Последний переносимый `tools/test_city_graph.ps1` реально выполнен:89/0,
лог `.godot/city-graph-smoke.log`. Он создаёт только минимальный isolated
проект, использует pinned wrapper, отдельный APPDATA и восстанавливает env.
Массовые gameplay/story/mechanics suites, обычный project.godot, визуальная
приёмка, export/PCK/рабочая EXE и долгий autonomous soak не запускались.

Исправлены подтверждённые интеграционные ошибки: home-only practice validator,
неверная адресная строка Livelihood, catalog alias при rollback, старые room
списки в inventory/work/needs, frontend confirmation и stale context после
отказа. Ошибки закрытых часов/неверного дня в smoke-fixture исправлялись как
fixture; они не выданы за defects игровой логики.

## Что root обязан сохранить при3-way переносе

1. `livelihood_window.gd` в candidate намеренно возвращён к immutable baseline
   с ТОЛЬКО spatial-query дельтой. Source обновлённое окно/A04/work_task_banks
   не откатывать. Это прямое решение root; candidate preload отсутствующей
   business-зависимости закрыт таким способом. Остальной A04 source-пакет
   сюда не импортирован.
2. Source H01/H02 и семейный уход/переезд медицинского владельца идут дальше
   снимка: сохранять его поведение. Candidate `site_open` endpoint-only;
   полный visit window принадлежит H01. Наши health/family изменения — адресные
   queries, не замена врачебных/семейных правил. Аналогично source-only
   npc_dialogue initiative/боевые изменения; adopted новый npc_dialogue был
   взят только при candidate==baseline, его нельзя использовать как blanket
   overwrite будущих source правок.
3. Source UI/Inventory/SceneInteraction изменения после snapshot сохранять.
   Candidate содержит navigation_changed→_wire_scene_focus. Смена основной
   схемы11 намеренная; старые main-сейвы не мигрируются. Source includes
   data/world/*.json уже подходят новым данным; export фильтры не менялись.

## Ограничения и следующий конечный шаг

- Google Doc недоступен и не прочитан. Университет назван нейтрально; авторские
  тексты/зеркало и разные эпохи сохранены. Сценарная сверка с внешним авторским
  документом остаётся внешней зависимостью.
- Новая карта — схема с приблизительными UV, не утверждённая иллюстрация.
  Предметная глубина есть у4 сцен, остальной backbone содержит функции/адреса.
- Завтра: root сводит candidate с актуальным original через baseline; закрывает
  только конфликты source A04/H01/H02/UI, затем минимально проверяет реально
  объединённую версию. Полный UI/сюжетный визуальный проход остаётся отдельным
  разрешённым этапом. Не расширять районы/арт/системы ради количества.

Для другогоПК: сам проект и JSON/шрифты/изображения из репозитория,
Godot 4.7.2stable по `.godot-version`, PowerShell и `tools/godot.ps1`.
Существующий wrapper ожидает движок в пользовательском LOCALAPPDATA/Programs/Godot.
Новые Python/npm/сетевые сервисы, токены и локальные пути E: для запуска игры
не требуются. Тестовые `.godot` caches/userdata и `.research` — не runtime
зависимости и не должны попадать в публикацию.


## Последняя санитарная коррекция перед переносом

По конечному поручению root изменён только runtime-файл `scripts/gameplay/city_layout.gd`:
у мест с фактической facility toilet теперь есть и `catalog.locations[id].toilet=true`.
Это четыре ванные player-property, clinic, campus_mens_washroom и агрегированные
private residence units, уже имевшие санитарную capability; генератор нового
частного жилья ставит тот же признак. Спальня/кухня/фасады/улицы его не получили.
Удалены мёртвые ветви записи adult_health_rules/pregnancy_wellbeing_rules.
Actor policies, availability и privacy не менялись. Private residence содержит
точный `owner_actor_id`; property ID не даёт права входить в другую owner-квартиру.
Headless Godot 4.7.2/Dummy sanitary-contract smoke:21 checks, 0 failures, exit 0;
лог `../world-sanitary-contract-smoke.log`. Это узкая проверка capability/owner-access,
не повторный общий прогон и не проверка новых source H01/H02.
Окончательный manifest SHA256 пересоздан после правки. Работа окончательно остановлена.
