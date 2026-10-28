> Статус завершения 28 октября 2026: городской граф реально подключён в original, финальная Main schema 14. Ниже сохранён исторический подготовительный план; актуальная передача и проверенные границы — [FINAL_INTEGRATION_HANDOFF](../gameplay/FINAL_INTEGRATION_HANDOFF.md).

# Единый город: контракт интеграции

28 октября2026. Это документ из изолированного runtime-кандидата
`E:/GoDot/.research/world-integration-2026-10-28/project`.
Оригинал автоматически не менялся. Полный handoff: `ISOLATED_INTEGRATION.md`.

## Географический источник

`data/world/city-graph.json` содержит нынешний город:71 место,79 двусторонних
рёбер,17 зданий/контейнеров и26 услуг. `CityGraph` только читает/проверяет данные
и actor-access; поиска пути, команд и второго игрового цикла в нём нет.
`CityLayout` устанавливает этот граф в основной каталог. `CityWorld` сохраняет
существующий Dijkstra/World-команды/транзакцию. NPC продолжают использовать
существующий agency._route и planner. Старая карта не служит fallback.

Публичные улицы, подходы, парки и мосты связны без прохода через частное жильё,
кафе или лабораторию. Наружные frontage не закрываются с услугой. Все71 место —
адреса, а не71 предметно наполненная сцена:16 объектов подготовлены в4 сценах.
Позиции UV и минуты пути — честная проектная схема, не топографическая съёмка.
Новые рисунки улиц не генерировались; карта показывает схему, фон сцены берёт
существующие иллюстрации. Работающий standalone mechanics/parity runtime
сохраняет собственные явно заданные роли и данные; его ID не являются
запасной веткой основной игры.

## Первый район и реальные входы

| ID | Смысл |
| --- | --- |
| student_home | Публичная сторона калитки одноэтажного дома героя |
| residential_district | Улица/жилые дворы |
| pharmacy_house | Публичный фасад дома с аптекой; сама аптека не зарегистрирована как новая услуга |
| south_trade_street | Торговая улица |
| south_market | Внутренний адрес действующего южного магазина |
| riverside_cafe_front | Круглосуточный наружный подход/проход у кафе |
| riverside_cafe | Отдельный зал и рабочее место,08–23 |
| city_resident_home_selina | Частный дом resident_cafe_shift_lead |
| city_resident_home_dana | Частный дом resident_south_grocer |

Начальные bedroom/apartment_hall/bathroom/kitchen сохранены как реальные
комнаты пролога. У detached_house/penthouse/social_housing свои room IDs.

## API и доверенный actor-контекст

`CityGraph.load_graph()` возвращает `{ok,data:graph}` либо `{ok:false,error,...}`.
`activation_errors()` проверяет схему, референсы и технические зависимости.
`ready_for_main_world=true` относится только к этому изолированному кандидату;
внешняя `author_scenario_review` явно pending, а не ложно resolved.

`CityGraph.can_enter(graph,id,actor,minute_of_day,weekday,check_hours=true)`
проверяет публичность, владельца/проживание, приглашение, занятие, duty и urgent.
Контекст берётся только из симуляции. UI не передаёт себе права через args.

Основные запросы симуляции:

- `player_home_room(kind)`: hall/bedroom/bathroom/kitchen текущего property.
- `player_home()`: нынешняя спальня; пустая строка при отсутствии жилья.
- `room_kind(id)` и `is_player_home_location(id)`.
- `actor_home(actor_id='player')`, `is_actor_home_location(actor_id,id)`.
- `world.actor_availability(id,actor_id,absolute_minute,ignore_hours=false,invited_destination='')`.
- `world.is_open_at(catalog.locations[id],absolute_minute)`: часы именно услуги.
- `world.route_from(start,destination,departure,check_open=true)`: player forecast.
- `npc_agency._route(npc,start,destination,minute=-1,urgent_destination=false,invited_destination='')`: существующий NPC поиск.

`invited_destination` — внутренний trusted query-параметр для уже принятого
частного приглашения, не поле команд игрока. Действующие private sessions,
проживание tenant и допустимые домашние appointment учитываются отдельно.
Доступ игрока не используется вместо доступа NPC. Поэтому запрет войти
к Селине не блокирует её путь домой. Срочная клиника определяется медицинским
статусом/принятой задачей; ordinary visit ночью не получает этот пропуск.

`site_open` кандидата проверяет actor на arrival/finish−1. Это не заявление
о проверке каждой минуты сложного интервала. Source H01 медицинского владельца
должен быть сохранён root при3-way merge и использовать тот же actor API.

## Каталог, население, сохранение

Main применяет graph/job/lesson/shop bindings до создания NPC, пересобирает
npc_jobs, добавляет южный south_grocer без изменения зарплатной математики,
затем применяет CityResidents/CityPlaceContent. Неизвестный обязательный адрес
не подменяется старой картой.

Чистая фабрика `resident_home_records()` регистрируется до generate_from_template.
Каждый случайный житель получает отдельное частное жильё без новой map-метки.
Раннее полное N сохраняет исходную сюжетную толпу; пара Селина/Дана входит
в тот же бюджет и исключена из story_crowd. Agency/личные арки активируются
только существующим открытием города. Восстановленный snapshot не дополняется.

Один Population.generate_batch использует исходный RNG/цикл. Внутренний N−K=0
пропускается, публичный count остаётся1..200. Один внешний command, один batch
и один population_generated с полным N. Исходные settings не подменяются.
При отказе откатываются state/RNG и добавленные записи каталога. Main schema11
хранит список владельцев динамических домов в порядке регистрации, чтобы
восстановить тот же catalog hash; старые main-сейвы не мигрируют автоматически.

## Сценарная граница

`story_bindings` покрывает спальню, прихожую, зеркало/ванную, кухню, фото,
выход у дома, фасад аптеки/двери Асуки и Оливера, парк и двор кампуса,
холл/актовый зал, коридор левого крыла,213, мужской туалет, cosplay_clubroom,
учительскую и пустую аудитории, вечерний возврат. Дом→двор кампуса14 минут.
Авторские TimeLine и событие open_character_creator не переименованы.
Спорное название института не исправлялось; UI использует «Университет».

Склад рамочной сцены и детская Праксия/море/этажи4 и8 имеют
outside_present_graph и не открываются прогулкой из нынешней Эллизии.
Google Doc не прочитан: интеграция соответствует локальным источникам,
не утверждает окончательную авторскую сверку.

## UI-предметы и подтверждение

Компактная scene_actions предлагает «Осмотреть предметы рядом». Inspector
открывается в видимом objects panel, отдельно от кнопок выходов/людей.
Осмотр только читает. PlaceObjects передаёт captured descriptor; Shell создаёт
один ConfirmationDialog и отправляет одну обычную команду после подтверждения.
После успеха и отказа/rollback заново строится context с актуальным sim.state.
Выбранный объект сохраняется в _screen_state. Navigation_changed связан
с существующим _wire_scene_focus без тестового injection.

## Граница принятия

Фактический кандидат и hashes перечислены в соседнем handoff/manifest.
Root переносит через immutable baseline, сохраняя новые source A04, H01/H02,
семейный уход и диалоговые правки. Нет разрешения копировать candidate целиком
поверх original, запускать массовый набор, экспортировать рабочую EXE,
трогать сохранения или делать Git исполнителем географии.

Санитарный контракт перед переносом: `catalog.locations[id].toilet=true`
синхронен реальной facility toilet. Он установлен ванным, clinic,
campus_mens_washroom и санитарным агрегированным private residence units,
включая новые generated homes. Это capability, не разрешение входа;
owner_actor_id и actor availability сохраняются.
