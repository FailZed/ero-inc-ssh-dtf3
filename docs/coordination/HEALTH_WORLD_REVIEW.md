# Статическая сверка здоровья и опеки с новым городом

28 октября 2026, чтение 20:39:17–20:48:17 МСК (UTC+03:00).
Кандидат: `E:/GoDot/.research/world-integration-2026-10-28/project`.
Отчёт записан в original. **Игра, тесты, окна, Godot/игровые EXE, пользовательские
сохранения и Git не запускались. Это разбор кода, не зелёный runtime.**
Код кандидата и original не редактировался; A07 здесь не разрабатывался.

## Итог и статус среза

По прочитанным путям выделены **5 конкретных расхождений** H01–H05
и **3 незавершённые точки переключения** I01–I03. Подтверждение здесь означает
наличие/отсутствие проверки в указанной цепочке вызовов; воспроизведение в движке
не проводилось. Исправления должен распределить координатор.

Граф правильно разделяет `clinic_forecourt` и `clinic`, публичный порог
и чужую квартиру, часы услуги и адрес помещения. У `clinic_service` часы
08:00–20:00 ежедневно и отдельный `urgent_entry`; `clinic_access` предусматривает
отдельные проверенные допуски дежурного и срочного пациента. Само наличие этих
полей ещё не подключает их к маршрутам и медицинским действиям.

Срез менялся прямо во время чтения. В 20:40 `city_layout.gd` ещё читал v2,
а в 20:42 уже получил новую реализацию на city-graph. В 20:45
`main_simulation.gd` получил переключение каталога и candidate-схему 11.
В прочитанном `city-graph.json` остаются `ready_for_main_world=false` и
`consumer_switch_complete=false`; это перепроверено хешем в 20:46:56.
Нельзя описывать этот промежуточный кандидат как полностью переключённый город
или принимать прежние проверки старой карты за его runtime-проверку.

## Конкретные расхождения по цепочкам вызовов

### H01 · P1 · Обычный приём игрока может закончиться после закрытия

Файлы/функции: [adult_health_care.gd:19](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/adult_health_care.gd:19)
`blocked`, [adult_health_care.gd:91](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/adult_health_care.gd:91)
`perform`, [action_policy.gd:141](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/action_policy.gd:141)
`check`.

У обычной клинической операции проверяется открытие только перед
`sim.advance(minutes)`. После истечения времени результат и оплата применяются
без проверки полного интервала услуги. Общая action policy такой проверки
не добавляет. Например, при закрытии в 20:00 консультация на 30 минут,
начатая в 19:55, проходит ветку результата после 20:00. Это отличается
от принятого NPC-контракта, где submit проверяет прибытие и завершение.

Ожидается: до принятия обычной операции проверить весь необходимый интервал
по часам именно услуги и отказать без времени, оплаты и результата, если
визит в него не помещается. Допуск дежурного/срочного пациента не должен
разрешать произвольную обычную процедуру после закрытия.

### H02 · P1 · Дородовый осмотр через health обходит присутствие и часы клиники

Файлы/функции: [health.gd:46](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/health.gd:46)
`execute`, [health.gd:82](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/health.gd:82)
`prenatal_care`, [pregnancy_selfcare.gd:72](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/pregnancy_selfcare.gd:72)
`execute(checkup)`, [npc_reproductive_jobs.gd:125](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/npc_reproductive_jobs.gd:125)
`_complete(prenatal_care)`.

Прямая команда `health/prenatal_care` передаёт target в общий метод. Он
проверяет беременность, интервал и деньги, но не место пациента, место
плательщика или часы услуги. Поэтому улучшение care логически доступно
без физического посещения клиники, включая target NPC. Вход через
pregnancy_wellbeing/checkup проверяет только местоположение игрока,
не часы. У автономного NPC путь обычно защищён планировщиком, но это
не закрывает прямой командный вход.

Ожидается: единый медицинский контракт присутствия пациента, применимого
плательщика и полного окна услуги; NPC-путь должен использовать тот же
допуск после реальной дороги. При недоступности — без care, оплаты и
продления next_care. Не исправлять только видимостью UI-кнопки.

### H03 · P1 · Срочный игрок снаружи не получает ночной маршрут

Файлы/функции: [city_world.gd:17](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/city_world.gd:17)
`availability`, [city_world.gd:68](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/city_world.gd:68)
`_travel`, [world.gd:17](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/world.gd:17)
`availability`, `adult_health_care.blocked`.

Медицинское emergency разрешено при подтверждённом urgent, но требует
уже находиться в clinic. Прочитанный маршрут игрока закрывает вход в
неработающее помещение общей availability и не передаёт медицинский
срочный контекст. Поэтому льгота emergency внутри кабинета не решает
доступ игрока снаружи ночью. Принятая ночная цепочка для NPC использует
отдельное исключение конечной точки в _route и не является доказательством
работы маршрута игрока.

Ожидается: проверенное текущее urgent конкретного пациента позволяет
пройти настоящий маршрут через публичный порог на срочную помощь.
При этом clinic_service остаётся закрытой для обычного посещения,
чужого сопровождающего без основания и остальных услуг. Не делать
здание публично открытым круглосуточно.

### H04 · P1 · Два соседних пути напрямую переставляют NPC

Файлы/функции: [social.gd:53](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/social.gd:53)
`execute(invite)`, [social_rules.gd:78](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/social_rules.gd:78)
`availability`, [player_social_rules.gd:4](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/player_social_rules.gd:4)
`availability`, [housing.gd:45](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/housing.gd:45)
`execute(remove_tenant)`.

Invite после доверия и общей готовности сразу пишет npc.location в
место игрока и pin — без маршрута, длительности дороги или проверки
прибытия перед следующей сменой. Семейный исполнитель защищает уже
занятого family task опекуна, но доступного удалённого опекуна это
не заставляет физически добраться до ребёнка; общий медицинский
personal_travel/personal_errand также не исключён базовой availability.
При remove_tenant NPC, находящийся в прежнем доме, сразу переносится
в original_home.

Ожидается: принятие приглашения/прекращение проживания не означает
уже совершённую дорогу. Фактическое перемещение использует прежний
планировщик, деньги/время маршрута, медицинские приоритеты и обязательства.
Снять право проживания и создать дальнейшее намерение допустимо;
получить доступного «дома» опекуна без поездки — нет.

### H05 · P1 · Новая санитарная привязка пишет не в источник медицинских правил

Файлы/функции: [city_layout.gd:155](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/city_layout.gd:155)
`apply_catalog`, [adult_health.gd:16](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/adult_health.gd:16)
`config`, [pregnancy_wellbeing.gd:8](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/pregnancy_wellbeing.gd:8)
`config`, `adult_health_care.private_facility`, `pregnancy_selfcare.toilet_available`.

Новая CityLayout собирает санитарные комнаты и пишет
catalog.adult_health_rules/private_locations и
catalog.pregnancy_wellbeing_rules/toilet_locations при наличии таких групп.
Фактические медицинские исполнители читают static config() из своих JSON,
а не эти группы каталога. Поэтому даже выполнение записи не подключает
новые bathroom ID к действующим проверкам. Аналогично не меняется
фактический supply_locations. В старом списке остаются удаляемые
global_map и общие названия помещений.

Ожидается: реальные действия получают санитарную возможность/место
покупки из действующего города и реального адреса актёра. Не мутировать
общий static cache для одной симуляции и не создавать запасной список
старой карты. Отдельный независимый механический runtime должен сохранять
свои собственные действующие правила.

## Незавершённые точки интеграции

### I01 · Взаимные API и активация нового каталога пока не сведены

`city_layout.gd` в последнем чтении объявляет home(catalog,state) и
семантические home_room/is_home_room; прочитанные city_world/city_housing
ещё вызывают home(state), используют отсутствующий City.ROOMS и общий
apartment_hall. Новый main._load_catalog уже вызывает City.apply_catalog;
при неготовом графе он очищает locations. В то же время
[reproductive_simulation.gd:26](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/reproductive_simulation.gd:26)
`_init` ещё обращается к bedroom/global_map после родительской инициализации.

Это подтверждённое несовпадение прочитанных интерфейсов в незавершённом
переключении, а не заявленный новый runtime-сбой из запуска. Ожидается
один согласованный источник города и вызывающие пути без старых
location ID/резервной карты; активация только после закрытия зависимостей.

### I02 · Actor-aware доступ и часы услуги ещё не дошли до потребителей

Файлы/функции: `city_graph.can_enter/service_open/catalog_locations`,
`city_world.availability/route_from`, `npc_agency._location_open/_route`,
`npc_calendar.site_open/conflict`, `npc_planner.submit/_dispatch`.

Graph.can_enter корректно различает публичный порог, владельца,
подтверждённое приглашение, дежурного и срочного пациента. Но прочитанные
потребители используют location.hours/requirements, а graph.locations
намеренно не содержат hours: часы находятся в graph.services.
Подстановка нового каталога при сохранении этих проверок дала бы
значение [0,0] по умолчанию и не проверяла бы access_policy_id.

Ожидается один доверенный actor-контекст из состояния: действительное
проживание/приглашение, текущая дежурная обязанность и подтверждённый urgent.
Проверять доступ и услугу в прогнозе пути, при прибытии и до результата.
Не принимать urgent/duty/invited_location_ids из произвольных UI-аргументов.
Публичный clinic_forecourt не даёт права на весь clinic или квартиру.

Дорога после визита уже учитывается npc_calendar.conflict через _route
к следующему обязательству. Этот принятый контракт нужно сохранить,
заменив источник часов/доступа; не выбрасывать прогноз возвращения ради
нового графа.

Врач в прочитанных медицинских действиях представлен услугой, а не отдельным
перемещаемым NPC. Строка staff_entry в JSON не доказывает фактическое
присутствие врача. Если используется врач-NPC, его duty_location_ids
должны следовать настоящей профессии/смене и текущему месту. Подтверждённого
телепорта отдельного врача в этих путях не обнаружено; это предел проверки,
а не основание добавлять новую симуляцию медицинского персонала.

### I03 · Адрес семьи и уход после переезда ещё привязаны к старым комнатам

Файлы/функции: `family._sync_births/_at_home/_autonomy/start_care`,
`family_handoff.blocked`, `adult_health_care.blocked/consider`,
`city_housing.execute(move_in)`, `housing.execute(tenant)`.

Для семьи с игроком member.home при рождении принудительно равен bedroom;
_at_home распознаёт четыре общих старых ID. Для NPC дом запоминается
из npc.home при рождении. Handoff честно требует location==member.home,
но семейный адрес не получает новое конкретное помещение при переезде.
Медицинский care_step допускает home либо литералы bedroom/bathroom/clinic.

У нового графа есть разные detached_house_bedroom,
penthouse_bathroom и другие room_ids. Старый city_housing после move_in
пишет общий apartment_hall; это не помещение нового жилья. Поэтому
семантическая замена адресов должна дойти и до семьи/самоухода.

Ожидается: действительный семейный переезд опекуна, с которым живёт ребёнок,
фиксирует фактический дом семьи после выполненного перемещения; уход
проверяет комнаты этого дома и нужную возможность. Переезд отдельно
живущего второго родителя сам по себе не переносит ребёнка. До окончания
переезда нет нового домашнего ухода. Опекун из другого адреса не считается
присутствующим из-за общего имени bedroom и не получает право на чужую квартиру.

## Что сохраняется по чтению принятых контрактов

- NPC-медицинская задача хранит origin, arrival, due и pin; место меняется
  после истечения рассчитанного маршрута, а не при выборе назначения.
  Проверяется ожидаемое место/резервация; cancel очищает задачу.
- Family handoff повторно проверяет опеку, присутствие, силы, medical owner
  и календарь; запрос без фактического старта не расходует средства.
  Старт использует прежний family task, сохраняет assignments, оплачивает
  один раз. Результат и связь возникают при завершении; прерывание их не даёт.
- NPC-репродуктивные jobs при неуспешном вложенном завершении откатывают
  его изменения и RNG; сама задача затем закрывается. Нельзя повторно
  оплачивать ту же завершённую задачу при новой проверке доступа.
- care_reminder сохраняет target; Presentation.event_text отбрасывает чужое
  медицинское напоминание, а Gameplay._on_domain_event не публикует пустой текст.
  Личный health UI читает view() игрока. В этих путях нового раскрытия
  чужих медицинских напоминаний не обнаружено.
- Приватные дома не имеют map.marker, Graph.can_enter требует владельца или
  действительного приглашения. Это хорошее описание политики, однако его
  реальное применение маршрутом относится к I02, а не считается проверенным.

## Передача координатору

| Область исправления | Пункты для распределения |
| --- | --- |
| Медицинские команды и принятые клинические границы | H01, H02; срочный контекст пациента из H03 |
| Город, маршруты и actor-aware доступ | H03, I01, I02 |
| Социальное приглашение и жильё | H04, согласование I03 |
| Семейный/медицинский потребитель фактического адреса | H05, I03 после утверждения городских запросов |

Не менял ни один из перечисленных файлов. Не запускал старые профильные
наборы в candidate; прежние зелёные результаты health/family относятся
к прежнему принятому этапу. Список конечен; актуальность после дальнейших
правок проверяется по хешам ниже.

## Отпечатки прочитанного среза

Все пути в таблице — относительно candidate, время чтения МСК 28.10.2026.
SHA-256 вычислен из тех же байтов, из которых читался текст/JSON.
Это пофайловый срез, не атомарный снимок всего проекта. Контроль ключевых
city_graph JSON/city_world/city_housing/city_layout/main_simulation в 20:46:56
не обнаружил отличий от последних прочитанных версий; позднее дочитаны
только UI/журнал и их отдельные отпечатки.

| Файл | Чтение МСК | SHA-256 |
| --- | --- | --- |
| `data/mechanics/adult_health.json` | 20:45:10 | `415272b86cc6f4c27f23add523ce957a7ea516ca93429510cb66c97c41ae9365` |
| `data/mechanics/pregnancy_wellbeing.json` | 20:45:10 | `c391bd8beefef5a4f421df4b19a165fac572e3af26bb99b476e1a3fe7b43983c` |
| `data/world/city-graph.json` | 20:40:22 | `5b3d0bcb728187b312726b0e20d040a29b4901f4084c94d6d326c56cbe2ebfe3` |
| `scripts/gameplay/action_policy.gd` | 20:40:57 | `f6e8a7d6ac723285f83bed9684f8f39fe82506341a46103e31d9c9363ffa80b9` |
| `scripts/gameplay/city_agency.gd` | 20:41:57 | `b930e0cf6305b96039b7da4261d07a702d60b01529dc41e3a6ee787c0cfc49ec` |
| `scripts/gameplay/city_graph.gd` | 20:39:17 | `7b84229f520214a7f26955fb0788d93c854e4f842ab5283a13b01ab12a49e2af` |
| `scripts/gameplay/city_housing.gd` | 20:39:17 | `36fd60ecce0fbde845a74159edd057102a867a51e15cb7c0501c856ba7737393` |
| `scripts/gameplay/city_layout.gd` | 20:42:20 | `4cec3284d5aba6925d7451af0289c1ab9b8a6a09a635998411e8e310088ed648` |
| `scripts/gameplay/city_world.gd` | 20:42:20 | `e7d209975f81de8e0f901f8ef3dc31888e51fc11d19ef39575b3986c6d133d32` |
| `scripts/gameplay/gameplay.gd` | 20:48:17 | `84aa9676e996308b4a25104829d0cb6ad006e349256eadaaf4c237699a652e4a` |
| `scripts/gameplay/main_simulation.gd` | 20:45:10 | `e69d671e8bbc680e38afbf9773c6ddc3d3a6f34b726ec4ee24011815432f883e` |
| `scripts/gameplay/player_social_rules.gd` | 20:41:57 | `e40df92f3cb5cb378e24ac6b3fd798edf320d7cacc9001fe123020e037933c69` |
| `scripts/gameplay/presentation.gd` | 20:44:03 | `a931dc7d40942aaed13298dee000298c98684e5112a43551cae60736f61c93ec` |
| `scripts/mechanics/adult_health_care.gd` | 20:40:39 | `8b10194c0aca6091385f7d456b8a02c96768f1c9631306adcc63ac6609a5d888` |
| `scripts/mechanics/adult_health.gd` | 20:45:24 | `5e6bcac003424bba8ef8e2aac7b1c8a11683267f65e68aa65e4e9cf1a3d8a3d4` |
| `scripts/mechanics/autonomous_reproductive_simulation.gd` | 20:45:24 | `f7fb559d7af4863feb60d3dc1399d1c98819d1951ead7e4096224846600fe228` |
| `scripts/mechanics/family_handoff.gd` | 20:41:26 | `79d70a3a281c072bb40bc2acb61bd6c4337b90fb739e56afd1addccc44eda90f` |
| `scripts/mechanics/family.gd` | 20:41:26 | `e06dcac3bd0e25ef813129c10a251276ed4c8fc5ffa54c0f9edfe4bcaa8f79f8` |
| `scripts/mechanics/health_care_plans.gd` | 20:44:03 | `7a41d9e169d5cf4af745faae8aadd66992a7c6f9bfc2003a714ce40371988430` |
| `scripts/mechanics/health.gd` | 20:44:03 | `d1bc3500534fbb2f79e2341907e31a8ff6975122c46a14ba1a85bbd7da6804b7` |
| `scripts/mechanics/housing.gd` | 20:41:26 | `d01d745812d704540bce7b1138738e28dfd53a5cadc146fdd9129ab7202eb2ed` |
| `scripts/mechanics/human_social_rules.gd` | 20:42:20 | `02abe7ed726c12d1f1ab657faf1624203060f857a50a3da9b40eef3a4f496db4` |
| `scripts/mechanics/npc_agency.gd` | 20:40:00 | `ac8347f10a41cd259bf15c30f3fae371a790826188ff7b27de9d1641051afd66` |
| `scripts/mechanics/npc_calendar.gd` | 20:40:57 | `55897216d7e9f8fc9e98d7e6c4dc8ed8b94a1f46e9f279442e09486cba8e4e82` |
| `scripts/mechanics/npc_planner.gd` | 20:40:57 | `98465842111882461f2a4e38127cc5a1dc024da8786dc3a3a72c1fc8f6bb885e` |
| `scripts/mechanics/npc_reproductive_jobs.gd` | 20:41:57 | `d1d0745a8e46ddd3899180429c28f8fa9919740faff5b12457786313040dd21b` |
| `scripts/mechanics/pregnancy_selfcare.gd` | 20:44:03 | `77e08627cbcb1fd6590aad22b95e17aedce5c919a1d35b1d9695efce48ca3380` |
| `scripts/mechanics/pregnancy_wellbeing.gd` | 20:45:24 | `d46c4ea184b3740c434d5cddd874bec09d60c1fbfecf93ed06904235989589d8` |
| `scripts/mechanics/reproductive_simulation.gd` | 20:45:24 | `b51255f33ca29a247ff6a2fb9620a65b6baa032a0ff320d9a19f7454bcf8c273` |
| `scripts/mechanics/simulation.gd` | 20:44:03 | `612727e726192071565a2e73da69a5b5f658f6b0dc0880ed4bcd16b81bd3aa7f` |
| `scripts/mechanics/social_rules.gd` | 20:45:10 | `3f5aa31095393fef33c9d12ff7edd51fcffe080d87472a8483426e26666084d4` |
| `scripts/mechanics/social.gd` | 20:42:20 | `dc47902ac5f92f49ae6d36607fea980209b1dab3f60a4de0be7ee769bfa6a36f` |
| `scripts/mechanics/world.gd` | 20:40:57 | `0b572aa2791f0583af8988b046ebf31dbe80bd5f6bbd548d93e659597d263c57` |
| `scripts/ui/gameplay/adult_health_panel.gd` | 20:48:17 | `4546268698622bb779c08bb7cc350e7d98ead9e60eac2a18abb3d3b6943168d7` |
| `scripts/ui/gameplay/health_care_plan_panel.gd` | 20:48:17 | `c16b70aadde1c895e231492e5cef76119e2c571f5a1686fa55ee0c283174dc8f` |

Наблюдённые изменения в ходе чтения:
- city_layout: 20:40:00 `5d6e11a9480f5f0b2824bd1a335bc9e1a93748ab09fe1c245adedc520baf9563`
  → 20:42:20 `4cec3284d5aba6925d7451af0289c1ab9b8a6a09a635998411e8e310088ed648`.
- main_simulation: 20:40:00 `3357e3d9f3a03dfec5d74235c01e783f4d089d3415e6188e222a49882da0c708`
  → 20:45:10 `e69d671e8bbc680e38afbf9773c6ddc3d3a6f34b726ec4ee24011815432f883e`.

В 20:44:59 сопоставлены SHA-256 26 уже отобранных путей candidate/original,
в том числе семейного ухода, медицинского исполнителя, маршрутов и жилья.
Тогда отличались main_simulation, city_layout, social и simulation; остальные
22 пары совпадали. Остальные пути таблицы дочитаны позднее и этим сравнением
не охватываются. Это не сверка пользовательских сохранений и не перенос
candidate обратно в original.



## Исправление собственного блока после статического аудита

По прямому запросу пользователя H01/H02 и домашние потребители H05/I03
реализованы в original. Подробности и границы доказательства:
[CLINICAL_ACCESS_AND_HOME_CARE.md](../mechanics/CLINICAL_ACCESS_AND_HOME_CARE.md).
Новый город после этих проверок объединяет координатор; старые хеши выше
остаются историческим срезом. H04 этим медицинским патчем не исправлялся,
actor-aware часть npc_calendar объединяется root отдельно.
