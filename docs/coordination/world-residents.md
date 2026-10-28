# Состояние: жители и районные истории

- Исполнитель: `/root/world_residents`.
- Этап: завершён ограниченный кодовый candidate первой пары и адресных home-leaf компонентов.
- Статус: изолированная интеграция проверена bounded in-memory smoke: **102 checks, 0 failures, exit0**. Перенос в основной проект выполняет root; этот этап не менял original runtime.
- Копия: `E:/GoDot/.research/world-integration-2026-10-28/project`.
- Все shellcalls выполнялись с полным workdir копии. Base/manifest не менялись. В original меняется только этот файл.

## Изменённые файлы candidate

- Новый `scripts/gameplay/city_residents.gd`: apply_catalog, чистый population_plan, preflight всех выбранных записей, seed внутри внешней команды population.generate, state_error.
- Новый `data/world/city-residents.json`: ровно Селина Вейл29 и Дана Керн41; одна арка rear_door_notice, строгие employment-планы, строки RU/EN, флаг cafe_notice_resolution, чистый revisit.
- `scripts/mechanics/npc_stories.gd`: явное назначение/пустая арка, city-closed до автономии, проверка реальной доступности/календаря, разрешение строк, однократный эффект концовки, целостность флага/снимка и повторный визит после нового посещения на следующий день. C1: world/journey с пустым result.data.path не увеличивает count и не выдаёт unique-token. Запасных movement-полей нет.
- Только строки/revisit `scripts/ui/gameplay/personal_story_window.gd`: locale в view, refresh по смене языка, короткая строка повторного посещения. Компоновка и стиль сохранены.
- `scripts/gameplay/city_housing.gd`: move_in всех4home_units через реальный frontage, Base сохраняет правильный hall. Продажа/прекращение аренды/выселение выводит из бывшего жилья на его frontage, не в starter bedroom. При переезде/потере жилья очищается city_story_home. Финансы и социальные условия прежние.
- `scripts/gameplay/player_needs.gd`: сон только в спальне текущего жилья; досуг использует semantic trade. Вода/туалет проверяют catalog.facilities и текущую world.availability; чужие home-комнаты не допускаются. Разрешены доступные публичные санитарные помещения кампуса/клиники, но закрытый вход не обходится. Числа и эффекты прежние.
- `scripts/gameplay/player_character.gd`: продавец тоника через location_role supply_shop, без изменений цены/обучения/здоровья.
- `scripts/gameplay/action_policy.gd`: удалён starter HOME, ограничения сна/душа/плиты/рабочего места и контекст переезда используют актуальное жильё/семантические места. Математика сил/работы/боя прежняя.
- `docs/world/STORY_INTEGRATION.md`: узкое уточнение actual-arrival контракта и результата проверки.

`player_careers.gd` перечитан и проверен, но **не изменён**: _shift уже делегирует Base, общий адресный helper профессии принадлежит geography. MainSimulation/Gameplay/Shell/Population/World/общие механики редактировал только geography; мои hooks переданы ему.

## Население и расписания

Пара занимает слоты ВНУТРИ выбранного N, а не добавляется поверх него. Чистый план соблюдает возраст, женскую квоту, морфологии, activity_mode, диапазон статов и разброс черт. Study-only/несовместимые возраст/пол не навязывают этих жителей. Public count остаётся1..200; внутренний остаток0 пропускается без generate/configure0. Исходные settings сохраняются.

Полный N создаётся одной ранней командой и одним batch/event, поскольку story_crowd использует население. Пара исключается из студенческой толпы по biography.city_cast_id=first_trade_loop. Автономия/личная арка включаются существующим стартом свободного города. На restore нет досоздания людей. Seed не вызывает reentrant sim.command и не увеличивает batches.

Используется реальный social.generate_from_template и проверка employment={job,skill_level,workplace}; employment_plan и mind не подменяются вручную. Селина: cafe_orders/cooking/riverside_cafe, 10–16будни. Дана: согласованный geography south_grocer/sales/south_market, 10–18будни. У обеих отдельные actor-owned private homes. Новых обязательных recreation окон и нового planner/runner нет. Встречи возможны на рабочем месте после смены или при фактическом свободном пересечении.

## Фактическая проверка

Godot4.7.2 stable/Dummy, только минимальный no-autoload project `.godot/world-geography-smoke`, APPDATA=`E:/GoDot/.research/world-integration-2026-10-28/world-userdata`. Мой отдельный `resident_leaf_smoke.gd` прошёл **102 checks / 0 failures, exit0**. Общий geography/run.gd не менял.

Проверены: все4вида жилья, реальный move_in/hall/ванная/nap/home-workspace/end_lease; выселение через настоящую billing tick; запрет starter bathroom после переезда; публичные sink/toilet и отказ закрытойclinic/места безfacility. Первая пара, запрет истории до открытия города, обычный contact, чистый локализованный view и пустая арка Даны. Все3концовки через реальные команды, journey туда/обратно, C1пустойpath безтокена/прогресса, 0XPотказ, один флаг/одна память, повторная команда безstate/RNG-изменений. Чистый следующий-day revisit и snapshot equality безreseeding. Invalidworkplace отклоняется атомарно безчастичногоspawn.

Первый smoke выявил alias rollback общего catalog; geography исправил finish_command, после чего проверка прошла. Начальный fixture ошибочно переводил часы с1427назад1020 и получил invalid_adult_health_time; исправлен fixture через initial settings.start_minutes, runtime ради него не менялся.

Отдельные --headless --check-only прошли для city_residents, npc_stories и всех5делегированных leaf-файлов. Standalone parser UI остановился на недоступном autoload Gameplay; успешной UI-проверкой это не считается. Нативных окон, пользовательских saves, массовых игровых прогонов, экспорта/EXE и Git не запускал. Следующий-day revisit проверен контролируемым in-memory fixture времени/числа посещений; вероятность естественной встречи/визуальная компоновка не проверены.

## Дизайн и границы

Исходный отдельный дизайн: docs/world/RESIDENTS_AND_STORIES.md, data/world/design/neighborhood_stories.json, docs/world/STORY_INTEGRATION.md, data/world/design/story_bindings.json. Там7взрослых оригинальных жителей/3цепочки; текущий кодовый пакет ограничен первыми2людьми и одной историей. Остальные5жителей/2арки не подключались. Имя Мира исключено из-за одноимённой героини chapter_one. Детский парк/море не смешиваются с нынешним городом, квартиры сюжетных соседей не присваиваются.

Предыдущие узкие original fix0XP/explicit binding/UI-callers уже приняты root; профильные sandbox сценарии в original tests/gameplay/run_sandbox.gd добавлены, но **не запускались**.

Внешний Google Doc не прочитан, его содержание не объявлено каноном. Новая биография пары остаётся авторским предложением. Обычное знакомство и trust≥5 остаются реальной границей, бесплатный просмотр ничего не начисляет. UI неизвестных ошибок требует обычной согласованной локализации presentation, не fallback подстановок.

## Передача

Пакет готов к ревью/переносу root вместе с единым графом/hook-пакетом geography. Пока перенос не выполнен, это работающий изолированный candidate, не опубликованная игра. Новое направление/новые жители этим этапом не добавляются. Корректность общей UI/автосохранения/root-caller интеграции вне no-autoload smoke остаётся за общей интеграцией.
