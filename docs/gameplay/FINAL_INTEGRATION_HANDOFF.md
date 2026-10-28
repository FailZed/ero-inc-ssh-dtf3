# Финальная интеграция EroInc —28 октября 2026

Статус: **подключено в actual original source**, работа интегратора завершена.
Окончательная `MAIN_SCHEMA=14`;13 была промежуточным неопубликованным срезом.
Старые сохранения не мигрировали и не переписывались. Git/историю ведёт root.

## Что действительно включено

- Город: единый граф,71 место,79 рёбер, реальные входы/услуги/комнаты,
  actor access,4 варианта жилья, дом→кампус 14 минут, первая пара в выбранном N.
- Готовый per-file remote/local merge: существующие education/computer/
  antagonism/planning/companion/club_work соединены с городом и текущей UI.
  Сырой remote не копировался поверх работающих мест; source улучшения сохранены.
- Career: десять прежних вопросов двух remote работ переведены в canonical
  task banks без изменения содержания; реальные home_room_kind и typed
  Education/Residents state guards сохранены.17 троичных банков/510 задач
  не заменены этим маленьким исправлением.
- Два оригинальных события: геройское уточнение сообщения с точными instance/
  message/reply IDs и временем; NPC-only сближение/дистанция после фактических
  отмен парных визитов. Используются существующие Events/Social/Agency owners,
  одна транзакция/симуляция. Revision2 хранит fingerprint двух visitIDs против
  повторного исхода после cooldown. Phone показывает реальные решения.
- Бой: attack/defence фазы, явное подтверждение защиты, один ответ NPC за
  подтверждение, power/прогноз в существующем UI, revision guards и сохранение
  ожидающей защиты. Существующий AP4/числовой баланс сохранён; числовая
  эквивалентность School не заявляется. Второго combat runner нет.
- UI closing: book toggle/close сохраняет underlying inventory; исправлены
  focus, modal B и удалённый shortcut_style. Новая мастерская остаётся
  `res://assets/characters/mdrg_study/scenes/browser.tscn`, старый editor не
  возвращён. В её actual main_menu узко восстановлен remote last_load_error.
- Live2D data: study_catalog/conversation_reactions указывают на retained
  instances/content; optional parameter_roles читается безопасно. Ресурсный
  ASSET_READY,114 файлов/53.35 МБ, SDK5 и удаление старых builtin выполнял root.
  Загруженный старый Core не убивали; ignored копия не является runtime-путём.

## Как перенесено

Staging: `E:/GoDot/.research/agent-coordination/final-integration/project`.
Неизменяемый reviewed plan SHA256:
`3baf0e520f7fec3a0a02916867519ca511956c3d1d104de16b6d79c50898d4ab`.
Старый world candidate повторно не применялся. После явного root ASSET_READY
107 CODE/DATA/TESTS файлов перенесены с preimage/postimage guards и backup;
отдельно два узких caller/wrapper изменения. Main actual SHA256:
`b6055b6d6732c561787074f6903d2b917d4cab2303187cbec50b058b91a407a3`.

Root portable tools/config и ресурсы не подменялись старым snapshot. Events
routing наложен поверх актуального canonical test_mechanics. Рабочие source
ветви новой мастерской сохранены. Центральный READY plan не перегенерирован.
Журналы файлов/hashes: [verification/final-integration-2026-10-28](verification/final-integration-2026-10-28/).
Местный backup остаётся вне проекта в final-integration/original-code-backup-final.

## Реальная проверка и её граница

| Проверка | Факт |
| --- | --- |
| Интегрированный Main domain |89 проверок,0 ошибок |
| Events revision2 |112 проверок,0 ошибок; настоящая кнопка карточки и owner commands, reset/restore, повторы/отказ |
| School combat в Main14 |15 проверок,0 ошибок; ожидание защиты, один ответ, snapshot/RNG replay |
| Health postmerge actual source |155 проверок,0 ошибок;306 исходных hashes стабильны, выполнено владельцем здоровья |
| Main menu caller |Изолированный parser успешен;56 static dependencies, parser-only owner signatures; реальные autoloads не запускались |

Godot 4.7.2 stable, Dummy, без native окон/рабочей EXE/живых сохранений.
Финальные логи и critical-source-hashes сохранены рядом с этим документом.
Прямой --check-only без зарегистрированных autoload globals не выдан за pass;
исправленный late-load parser имеет отдельный зелёный лог. Предыдущие fixture/
compile ошибки не прибавлены к числу проверок интегрированной версии.

Не выполнялись массовые gameplay/story/mechanics suites, полный визуальный
плейтест итогового HUD/боя/Live2D, экспорт EXE и длительный autonomous soak.
Doctor/native ресурсную готовность подтвердил root отдельно; это не полная
приёмка всей игры на Windows/macOS. Внешний сценарный Google Doc не прочитан;
локальная сценарная матрица и исходные авторские TimeLine сохранены.

## Передача на завтра/другойПК

Код/данные/ресурсы уже в проекте, .research/.godot/backup не нужны для запуска.
Начать с [DEVELOPMENT_SETUP](../DEVELOPMENT_SETUP.md) и README:
`python3 tools/runtime.py setup`, `doctor`, `run -- --editor`; на Windows
`py -3` вместо python3. Движок закреплён `.godot-version`, звук Dummy;
обычный запуск не требует компилятора, локальных E:/Ai путей или raw MDRG.
Нативные библиотеки/модели входят в текущий пакет, SDK5 пути описывает root setup.

Следующий владелец действий — root: сохранить remote историю, собрать общий
NEXT_SESSION/commit/push. Исполнители сегодня свободны. Новые исправления,
исследования, генерации и проверки этим handoff не назначаются.
