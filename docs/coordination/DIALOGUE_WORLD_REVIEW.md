# Статическая сверка диалогов и городского кандидата

28 октября 2026. Основной срез чтения: **20:39–20:48 МСК**, заключительное точечное перечитывание — **20:52–20:53 МСК**. Назначение координатора: только чтение candidate/original и этот отчёт. Код, данные и immutable `base` не редактировались. Godot, тесты, окна, EXE, нативное управление, пользовательские сохранения и Git **не запускались**. Предыдущие 836/19 относятся к отдельному этапу диалогов и не являются результатами проверки этого города.

Candidate: `E:/GoDot/.research/world-integration-2026-10-28/project`; original: `E:/GoDot/ero-inc`; baseline: `E:/GoDot/.research/world-integration-2026-10-28/base`. Авторы продолжают менять candidate. Это сверка конкретных хешей ниже, **не атомарная приёмка всего изменяющегося дерева**.

В прочитанных новых helper/UI не найдено прямого продвижения часов или RNG при выборе предмета и осмотре. Существующая транзакция и ограничения действий обеспечивают откат и защиту от повторных эффектов при условии правильного подключения. Остаются обязательные зависимости потребителей/подтверждения/обновления контекста и один перенос уже готовой source-правки. Ниже они отделены от дефектов, которые можно приписать готовому к запуску пути.

## Важное изменение кандидата во время чтения

Первое чтение `main_simulation.gd` в 20:39:46, SHA `3357e3d9f3a03dfec5d74235c01e783f4d089d3415e6188e222a49882da0c708`, ещё не имело новых импортов/каталогов. В 20:46:23 файл перечитан целиком: SHA `e69d671e8bbc680e38afbf9773c6ddc3d3a6f34b726ec4ee24011815432f883e`, уже есть `PlaceContent`, `Residents`, `MAIN_SCHEMA=11`, транзакционный seed и откат динамического каталога. Поэтому **отсутствие этих hooks в первом чтении не выдано за текущий баг**.

`npc_stories.gd` и `city_residents.gd` также менялись; выводы о наградах/seed ниже относятся к последним прочитанным версиям `bc5e…` и `34e3…`. Старые комментарии про `CityPopulation/complete_initial` не означают необходимость создавать такой сервис: фактическая новая цепочка уже использует обычный `population.generate`.

## M1 — требуется перенос готовой правки открытого stale offer

**Ожидается:** при потере контекста или начале боя уже открытое предложение тоже переходит из `initiative` в `end`, а не только теряет token.

**Наблюдается:** candidate `npc_dialogue.gd` SHA `131514…` совпадает с `base`; `interrupt_conflict():421–425` очищает только `pending`, а `tick():487–495` при неактуальности тоже лишь присваивает `{}`. Original SHA `36c0…` содержит `_invalidate_offer():427` и вызывает его из обоих мест: он завершает `initiative` и обнуляет `expires`.

Это **source-fix после снимка, а не регрессия авторов географии**. При переносе нужны именно эти небольшие изменения и соответствующий `post_conflict_dialogue.gd`, без замены всего original файлом кандидата. Большая часть прошлого исправления уже есть в candidate: проверка памяти/канала, минутная очистка pending, дистанция после насилия, свежий token и запрет принятия устаревшей инициативы.

## D1 — единое переключение географии ещё должно закончиться

**Ожидается:** личная беседа запускается только при реальном совместном присутствии, а попасть в частный дом или закрытое помещение можно только через текущие actor-aware правила. Часы, duty/story/invitation/urgent-права строятся из состояния симуляции, а не из UI-аргументов.

**Наблюдается:** `CityGraph.can_enter():384–421` сам по себе чистый и различает public, residence/private_home и service. В данных четыре предметные сцены публичные; частные входы не имеют выданных helper-команд. Дома Селины/Даны имеют owner/invitation policy. Но на срезе:

- новый `city_layout.gd` SHA `4cec…`: `home(catalog,state):36`, `point(catalog,id):19`;
- `city_world.gd` SHA `e7d2…` ещё вызывает старый `City.home(sim.state):6`, использует `City.ROOMS`, а `route_from():24–54` / `_travel():68–87` не вызывают новый `Graph.can_enter` для каждого промежуточного места;
- `city_dialogue.gd` SHA `82e5…`, `local_initiative():4–5`, ещё вызывает старый `City.point(location)`;
- в `gameplay.gd` SHA `84aa…`, `gameplay_shell.gd` SHA `8047…` сохраняются прежние адресные потребители; предметный `action_requested` ещё не соединён с новым подтверждением.

Это **незаконченная согласованная замена потребителей**, не утверждение о новом рабочем обходе доступа. `city-graph.json` SHA `5b3d…` по состоянию 20:48:22 всё ещё имеет `ready_for_main_world=false`, `consumer_switch_complete=false`. До завершения этого этапа нельзя объявить новый маршрут или приватность runtime-проверенными. Gate не следует обходить старой картой.

После переключения нужные границы повторно сверить в `CityWorld.availability/route_from/_travel`, формировании actor и `CityDialogue.local_initiative`. Одна UI-проверка `context.access` не заменяет backend-проверку доступа к каждому узлу пути.

## D2 — метаданные подтверждения ещё не являются подтверждением

**Ожидается:** выбор/осмотр бесплатен; только подтверждение один раз вызывает `Gameplay.execute("actions","perform",args)`.

**Наблюдается:** `place_objects.gd` SHA `66cc…`, `_render_inspection():102–133`, создаёт две допустимые action-кнопки и ставит metadata `confirmation_required=true`. `_request_action():135–149` повторно получает descriptor и лишь испускает сигнал. Это правильно сохраняет компонент без игрового runner.

Но прочитанный `GameplayShell._context_action():618–623` только ставит действие в очередь либо вызывает callback; `_act():550–579` сразу вызывает `Gameplay.execute`. Ни один из них сам по себе не создаёт общего подтверждения. Следовательно, будущая прямая связь `action_requested → _act` **не выполнит** условие подтверждения. Сейчас связь ещё не добавлена, поэтому это **явная зависимость hook**, а не заявление, что игрок уже может обойти несуществующее окно.

При подключении callback должен захватить конкретные module/operation/args/descriptor, а не перечитывать изменяемый `selected_choice_descriptor()` после подтверждения. Не подключать один сигнал одновременно к непосредственному исполнению и к подтверждению. После успеха показывать `Content.result_text`, не запускать ещё `events.fire`, второй `advance` или отдельное начисление флага.

## D3 — свежий UI-контекст нужен и после отказа/отката

**Ожидается:** подтверждение, не прошедшее backend-проверку, оставляет мир/RNG прежними; следующий осмотр читает именно восстановленное состояние, а не старую ссылку.

**Наблюдается:** `place_objects.update():36–62` сохраняет `_context = context`, а context передаёт `sim.state`. `Simulation.command():131–135` при отказе заменяет `state` снимком. После частичного изменения откатившаяся команда может оставить прежнюю ссылку UI на отброшенный Dictionary. `Gameplay.execute():149–150` при ошибке выдаёт notification, без `changed`; `_act():577–579` не делает обычный refresh после ошибки.

Новый компонент пока не подключён, поэтому **готового пользовательского сценария с этим дефектом не заявлено**. Требование к интеграции: после завершения подтверждения, включая отказ/откат и загрузку, заново собрать authority/access/state и выполнить `update`. Не полагаться исключительно на `Gameplay.changed`. Программный `select_object()` также не очищает `_last_choice`, в отличие от `_on_selected`/`update`; безопаснее захватывать descriptor при нажатии, а не использовать его как общий mutable execution context.

## C1 — уточнить смысл нулевого journey для авторской цели

**Ожидаемая граница:** если цель требует реального перехода, бесплатное подтверждение уже текущего места не должно засчитывать посещение.

**Наблюдается в прочитанном старом пути:** `CityWorld.route_from():27` возвращает `{path:[], minutes:0}` для текущего места, `execute("journey"):58–64` возвращает успех. `NpcStories.observe():147–162` считает module/operation и текущую локацию, но не проверяет ненулевой путь/прирост visits. Новая `rear_door_notice.walk_check` требует два уникальных `world.journey` к `south_trade_street` и `riverside_cafe_front`; intro разрешён и у кафе. Поэтому при сохранении этой семантики подтверждённый journey в уже текущий `riverside_cafe_front` может дать первую единицу цели без движения.

Это **статическое условное замечание для согласования semantics**, не запущенный exploit и не утверждение, что новый незаконченный route-hook уже оставлен таким. `unique` не даст второй раз засчитать тот же token; повторной награды здесь не доказано. Если осмотр текущего входа по замыслу допустим, надо назвать это отдельным подтверждённым наблюдением/проверенным присутствием. Если требуется переход — зачитывать только фактическое прибытие. Preview не следует превращать в `Gameplay.execute` ради выполнения цели.

## Сопоставление остальных контрактов

| Контракт | Наблюдение в прочитанном коде | Граница вывода |
| --- | --- | --- |
| Бесплатные выбор/осмотр | `PlaceObjects.select_object/_on_selected/_render_inspection` меняют только локальный UI. `Content.describe/inspect/choice` создают результаты/копии, читают `Rules.check`; нет `sim.advance`, `sim.command`, RNG, world.write | Статически соответствует; построение внешнего authority ещё зависит от D1/D2 |
| Preview маршрута | старый `CityWorld.route/route_from` использует локальную очередь, `calendar.snapshot` и проверки, без RNG/advance. `ActionPolicy.duration(world.journey)` лишь читает route | Чистота прочитанного preview подтверждена чтением; новый actor-aware runtime-путь ещё нужен |
| Действие и откат | `Actions.availability():3–16` проверяет requirements/location/hours/tags/daily limit/resources. `execute():18–33` увеличивает один дневной counter, применяет effects и один `advance`. `Simulation.command():102–144` откатывает state/RNG/events, запрещает reentry, публикует только success | Не вызывать `services.actions.execute` напрямую из UI. Отказ после частичного эффекта остаётся внутри внешней транзакции; D3 про UI-ссылку, не про потерю backend rollback |
| Городская афиша | `wp_rain_margin`: 2 минуты, rain + точное место + отрицание `city_cafe_notice_sheltered`; один флаговый effect. Повтор блокируется и в тот же день, и после смены суток. `wp_last_crate`: 2 минуты, daily_limit=1, effects=[] | У этих двух действий нет отдельной денежной/XP-награды. Бесплатное чтение после них не дублирует effects |
| Присутствие / бой | `NpcDialogue.availability():281–293` проверяет active combat, contact/distance и совместную локацию для face. Верхняя `Simulation.command` запрещает прочие команды во время боя | Переписка — явный отдельный канал, а не личная беседа с телепортацией. Приватность маршрута — D1 |
| Работа NPC | face вызывает `PlayerSocialRules.availability` → базовый `SocialRules.availability(long_visit=true)`: activity work/study + committed запрещает разговор. Personal story дополнительно проверяет active_owner и календарный conflict перед длительным choice | Это не доказательство, что любая обычная тема проверяет всё будущее окно смены: в `_advance_talk` нет такого calendar-conflict. Нужен отдельный согласованный сценарий на границе смены, если требуется этот более сильный контракт; неверный planner state не объявлен здесь воспроизведённым багом |
| Stale offer / уход | большая часть guard уже в candidate; `ConversationOptions._depart` зовёт `interrupt_contact`, начало боя — `interrupt_conflict`; принятие/отказ проверяют token и контекст | Для закрытия открытого initiative нужен M1; не добавлять вторую социальную систему |
| Страх / согласие | `NpcRelationships.blocked(court/invite_relationship)` при fear≥15 возвращает unresolved_harm; проверяет взаимное влечение, grievance/comfort и consent thresholds. `ConversationOptions` запрещает романтику при fear и на враждебном исходе ставит consent=false | Городские effects содержат флаги и небольшие trust/respect/comfort, но не consent. Рост страха в агрессии не является согласием |
| Пустой story_arc | `CityResidents.seed` назначает Дане явное `""`; `NpcStories.arc_for` возвращает его сразу, `blocked` даёт personal_story_unassigned, `present` — `{}`. Window выводит отсутствие истории, game_screens скрывает кнопку/пустые карточки | Hash-арка остаётся только для обычного NPC без явного поля; к Дане с явным пустым полем не применяется |
| Концовка / XP / флаг | `NpcStories.execute`: status active и node из запроса; после ending — completed, rewarded=true, один apply_effects, bond, XP только если >0, одна память/событие. `state_error` проверяет outcome ↔ owner/ending и терминальный rewarded | При повторном choose/start после загрузки тот же terminal state отклоняет награду. Это вывод по хранению и guard, не результат запуска загрузки |
| Revisit | `NpcStories.revisit` только возвращает текст: completed + место + visits больше зафиксированного при окончании + минимум день + актуальное присутствие/занятость актёра. Ни counters, ни XP, ни flags не пишет | Повторный refresh/загрузка может показать ту же ambient-строку; это не новая награда/append-событие. Одноразовое «потребление» revisit отдельно не реализовано и не следует придумывать без требования |
| Seed первой пары | актуальная цепочка `Population.execute(generate):60–63` → `MainSimulation.generate_population():193–207` → `Residents.seed():160–177`. Маркер ставится после обеих генераций; preflight отсекает collision; повторный seed с валидным marker возвращает already_seeded | Комментарий complete_initial устарел относительно фактического имени команды. Прямой вызов seed вне внешней команды не обладает самостоятельной транзакцией и не нужен |
| Динамический каталог / загрузка | новый `MainSimulation.before_command` сохраняет catalog для generate; `rollback_command():209–210` восстанавливает его. Core command зовёт этот hook. Export содержит state/RNG и owners; restore сначала строит candidate catalog и проверяет hash, при отказе возвращает прошлый catalog | Схема кандидата уже 11; приёмка старых пользовательских слотов/миграция не проверялись и этим обзором не разрешены |

## Что передать координатору

1. M1 перенести из original малым diff; сохранить параллельные изменения original MainSimulation/Shell. Их хеши уже отличаются от immutable base.
2. D1 закончить в рамках единого переключения: сигнатуры, actor-aware route/access и gate. Не чинить по одному вызову, оставляя вторую старую карту.
3. D2/D3 включить в точные обязанности будущего Shell-hook: одно подтверждение, одна команда, новый контекст после любого результата и загрузки.
4. C1 согласовать с владельцем истории и географии до runtime-проверки, если переход/осмотр должны отличаться.
5. Повторно читать только изменившиеся хеши после конца интеграции. Текущий документ не даёт разрешение на новые кодовые правки/прогоны; их назначает координатор.

## Заключительное перечитывание изменившихся файлов — 20:52–20:53 МСК

Это дополнение имеет приоритет над наблюдениями прежних версий D1/D3; обзор не продлевается бесконечно вслед за активными авторами.

- **D1 частично закрывается новой версией:** `city_world.gd` SHA `b3180e2dd4c2c1a5140f9c6edc3521d88364dca4a488b14270769a779e57efcc` теперь имеет `actor_context():16–57`, `actor_availability():59–69`, route проверяет каждый next через него (`:93`), а `_travel():112–132` проверяет доступ на расчётное прибытие и после advance. Старые вызовы City.home/City.ROOMS из этого файла удалены. Ни одного запуска не было; этот текстовый факт не объявлен end-to-end приёмкой. `city_dialogue.gd` в основном срезе всё ещё старый; полный перечень новых потребителей/gate требует конечного хеша после сборки.
- **C2, уточнить источник полномочия:** в новом `CityWorld.actor_context(player):23–31` activity-места выводятся из definitions уроков/навыков, а duty-места — из определения вакансии, min_skill и времени; фактическая назначенная профессия/принятая рабочая сессия здесь не проверяется. `Graph.can_enter():411–412` допускает duty до публичных часов. Это ещё не доказательство доступного игроку обхода в текущих данных (например, часы публичного кафе уже покрывают его вакансии), но смысл «проверенного duty/activity» нужно согласовать с владельцем geography перед приёмкой. Квалификация для вакансии и действующее назначение — разные исходные факты. Код `CityGraph` SHA `0cf89ca379aee3e0a48a3d2335c8032130b32f1453182db3a5aa55f878f57a77` прочитан в 20:53:29.
- **D3, локальная часть уже исправлена владельцем:** `place_objects.gd` SHA `a90bafba44e3f312dea079494187d20afe0dff343186455bb87992099144e953`, `select_object():78–85` теперь очищает `_last_choice`; кнопка захватывает source_location/source_object, а `_request_action():163–179` отбрасывает старую невидимую/чужую кнопку. Замечание о неочищенном descriptor относится только к прежнему `66cc…` и больше не открыто. D2 (настоящее подтверждение в Shell) и D3 (свежая ссылка на backend state после отказа/rollback) всё ещё отдельные зависимости общего hook.
- **C1 остаётся применимым наблюдением для согласования:** новая `CityWorld.route_from():79` по-прежнему возвращает успешный нулевой путь к текущему месту; `execute(journey):102–108` передаёт успех observer. Это не эффект чистого preview, но может быть бесплатным зачётом одной авторской goal-location, если таков ожидаемый смысл данного действия.
- `CityResidents.seed` в заключительном чтении SHA `ca459f65b4af2574cfcffd77e3ba5b4538ca29234d958c03cb9dbc5a4e7d5b46`, `:164–180` сохраняет already_seeded guard, генерацию обеих записей и финальный marker. Остальные новые изменения этого файла/данных после основного чтения не выдаются за полностью проверенные.

Ни один пункт этого перечитывания не сопровождался правкой чужого кода. Дальнейшие изменения авторами после указанных хешей требуют новой назначенной сверки, а не автоматического переноса оценки.

## Отпечатки прочитанных версий

Время ниже — чтение в МСК 28 октября 2026. Номера строк в замечаниях относятся к этим версиям. Таблица не обещает, что авторы не изменили файл после чтения. Дополнительная завершающая сверка хешей отмечает такие изменения отдельно.

C = candidate; O = original; B = immutable baseline.

| Корень / файл | Чтение МСК | SHA256 прочитанной версии | Сверка перед записью отчёта |
| --- | --- | --- | --- |
| C: [scripts/ui/world/place_objects.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/ui/world/place_objects.gd) | 20:39:09 | `66ccb7a3f6ca2eff8c1f8e8a7c65b9f18f272e491a698c677dcf6f9d2e5d15a3` | ИЗМЕНИЛСЯ: `a90bafba44e3f312dea079494187d20afe0dff343186455bb87992099144e953` |
| C: [scripts/gameplay/city_place_content.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/city_place_content.gd) | 20:39:09 | `921180bf22bc850b34f5598e131ce6a9aa12c1842eaa7d57f0d57d3d94e98a46` | совпадает |
| C: [scripts/gameplay/city_residents.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/city_residents.gd) | 20:46:08 | `34e3ebba5e195d6607794ea3a2c442b7e022598cecc7e7f7efb3d6cba7f5fd30` | ИЗМЕНИЛСЯ: `ca459f65b4af2574cfcffd77e3ba5b4538ca29234d958c03cb9dbc5a4e7d5b46` |
| C: [scripts/gameplay/city_graph.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/city_graph.gd) | 20:40:19 | `7b84229f520214a7f26955fb0788d93c854e4f842ab5283a13b01ab12a49e2af` | ИЗМЕНИЛСЯ: `0cf89ca379aee3e0a48a3d2335c8032130b32f1453182db3a5aa55f878f57a77` |
| C: [scripts/gameplay/city_layout.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/city_layout.gd) | 20:47:11 | `4cec3284d5aba6925d7451af0289c1ab9b8a6a09a635998411e8e310088ed648` | ИЗМЕНИЛСЯ: `2908b25c7797dd6a6ca4dd68917a24666cab791f472ac8260a6556243f9c331a` |
| C: [scripts/gameplay/city_world.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/city_world.gd) | 20:39:46 | `e7d209975f81de8e0f901f8ef3dc31888e51fc11d19ef39575b3986c6d133d32` | ИЗМЕНИЛСЯ: `b3180e2dd4c2c1a5140f9c6edc3521d88364dca4a488b14270769a779e57efcc` |
| C: [scripts/gameplay/city_dialogue.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/city_dialogue.gd) | 20:39:46 | `82e5cfac9440dd911f84fb7c74c19e202f4f3227219071bb5c668efc22cb23a7` | совпадает |
| C: [scripts/gameplay/main_simulation.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/main_simulation.gd) | 20:46:23 | `e69d671e8bbc680e38afbf9773c6ddc3d3a6f34b726ec4ee24011815432f883e` | совпадает |
| C: [scripts/gameplay/gameplay.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/gameplay.gd) | 20:41:36 | `84aa9676e996308b4a25104829d0cb6ad006e349256eadaaf4c237699a652e4a` | совпадает |
| C: [scripts/gameplay/action_policy.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/action_policy.gd) | 20:41:36 | `f6e8a7d6ac723285f83bed9684f8f39fe82506341a46103e31d9c9363ffa80b9` | совпадает |
| C: [scripts/gameplay/player_social_rules.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/gameplay/player_social_rules.gd) | 20:39:46 | `e40df92f3cb5cb378e24ac6b3fd798edf320d7cacc9001fe123020e037933c69` | совпадает |
| C: [scripts/ui/gameplay/gameplay_shell.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/ui/gameplay/gameplay_shell.gd) | 20:46:23 | `8047495ce30df3037a8a63ae4a72dfa8cdc2df734d7795d219e00cfd6d15907a` | совпадает |
| C: [scripts/ui/gameplay/game_screens.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/ui/gameplay/game_screens.gd) | 20:44:04 | `d2798eb35047d5e0ae8c146252b102444c7a65abb22ceb747ac44890589a8004` | совпадает |
| C: [scripts/ui/gameplay/personal_story_window.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/ui/gameplay/personal_story_window.gd) | 20:41:07 | `e34ead0e3eb56f7c2b4ddceceb0b197bfea492895f250aa8b85347c91e85dfcb` | совпадает |
| C: [scripts/mechanics/actions.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/actions.gd) | 20:39:21 | `f8d7bd9ee671ff402de2969932b045b2427dba66ad8606ab3f9b4663426b8d8b` | совпадает |
| C: [scripts/mechanics/simulation.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/simulation.gd) | 20:46:08 | `612727e726192071565a2e73da69a5b5f658f6b0dc0880ed4bcd16b81bd3aa7f` | ИЗМЕНИЛСЯ: `a36ead6aba38a93499d2d37a19d1d96ff438dc04cbdebf43176165c5301a64dd` |
| C: [scripts/mechanics/population.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/population.gd) | 20:47:11 | `e9931685c1e837622fd3a1740f26ff123bbff6dc25e87f35d4b16be98b24ebf6` | совпадает |
| C: [scripts/mechanics/social.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/social.gd) | 20:47:11 | `dc47902ac5f92f49ae6d36607fea980209b1dab3f60a4de0be7ee769bfa6a36f` | совпадает |
| C: [scripts/mechanics/npc_dialogue.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/npc_dialogue.gd) | 20:44:04 | `1315148db7258c3a191757524fd6ccb393c3286e0c5145432afc5057775cf4be` | совпадает |
| C: [scripts/mechanics/npc_relationships.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/npc_relationships.gd) | 20:42:12 | `6a2e10f82e9ade53d3c4bc9677886c7620e555c56aff3c446be05a1f5d4883ca` | совпадает |
| C: [scripts/mechanics/conversation_options.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/conversation_options.gd) | 20:42:12 | `c6b0a1cde63dd6147d8e51118ba4aabc334ee4624b1c62fc042408d531ae1047` | совпадает |
| C: [scripts/mechanics/combat.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/combat.gd) | 20:44:04 | `99bc8fbe71d75f48879ff81ed4b1e50cc0e093f32ace0a6316da7c0192c87995` | совпадает |
| C: [scripts/mechanics/social_rules.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/social_rules.gd) | 20:41:07 | `3f5aa31095393fef33c9d12ff7edd51fcffe080d87472a8483426e26666084d4` | совпадает |
| C: [scripts/mechanics/human_social_rules.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/human_social_rules.gd) | 20:42:12 | `02abe7ed726c12d1f1ab657faf1624203060f857a50a3da9b40eef3a4f496db4` | совпадает |
| C: [scripts/mechanics/npc_planner.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/npc_planner.gd) | 20:46:08 | `98465842111882461f2a4e38127cc5a1dc024da8786dc3a3a72c1fc8f6bb885e` | ИЗМЕНИЛСЯ: `e66216cc93c44749853e9a68a71bf69e9f952292220d8290f75a3b7870f47fe3` |
| C: [scripts/mechanics/npc_stories.gd](E:/GoDot/.research/world-integration-2026-10-28/project/scripts/mechanics/npc_stories.gd) | 20:44:04 | `bc5e1ab0428104aecf31cf331ade5f7b16516c500dc39bbe3ed0c5f71cba57ec` | совпадает |
| C: [data/world/city-place-content.json](E:/GoDot/.research/world-integration-2026-10-28/project/data/world/city-place-content.json) | 20:41:07 | `14e02967749b91d5dc5846edfa1ca39c7088cebb8361b748b231ce044f723051` | совпадает |
| C: [data/world/city-residents.json](E:/GoDot/.research/world-integration-2026-10-28/project/data/world/city-residents.json) | 20:41:07 | `02020add9f72108199cbed0c22898b2a706861be634187d0475f8d6066475b23` | ИЗМЕНИЛСЯ: `4197df941b30f0b77da36793b6eb4c95c073dcd195e0b0f9302028008648c014` |
| C: [data/world/city-graph.json](E:/GoDot/.research/world-integration-2026-10-28/project/data/world/city-graph.json) | 20:48:22 | `5b3d0bcb728187b312726b0e20d040a29b4901f4084c94d6d326c56cbe2ebfe3` | совпадает |
| O: [scripts/mechanics/npc_dialogue.gd](E:/GoDot/ero-inc/scripts/mechanics/npc_dialogue.gd) | 20:44:04 | `36c0dbbf766a662b2c1e518437be6bd4ea48e193a761245cffff481ce52dab5a` | совпадает |
| B: [scripts/mechanics/npc_dialogue.gd](E:/GoDot/.research/world-integration-2026-10-28/base/scripts/mechanics/npc_dialogue.gd) | 20:44:04 | `1315148db7258c3a191757524fd6ccb393c3286e0c5145432afc5057775cf4be` | совпадает |

Завершающая сверка хешей: 2026-10-28 20:52:03 МСК. Это чтение, не прогон.
Если строка помечена ИЗМЕНИЛСЯ, замечания к прежнему хешу не следует автоматически переносить на новый файл без перечитывания.
