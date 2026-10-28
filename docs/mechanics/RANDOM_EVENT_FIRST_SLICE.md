# Первый набор случайных событий: точный контракт подключения

Актуальная реализация по последующему прямому поручению владельца описана в
[RANDOM_EVENTS_RUNTIME.md](RANDOM_EVENTS_RUNTIME.md). Ниже сохранён исходный
статический контракт и обнаруженные до реализации недостающие привязки;
его design-only статус не описывает более поздний runtime-кандидат.

28 октября 2026. По дополнительному назначению координатора. Статус: **design_prepared_not_executable**. Подготовлены только два уже существующих ID; каталог 144 карточек не расширяется и не меняется. Runtime, UI, общие матрицы, город и сохранения этим этапом не правятся.

Канонический план: [random_event_first_slice.json](../../data/mechanics/design/random_event_first_slice.json). Исходный дизайн: [RANDOM_EVENTS.md](RANDOM_EVENTS.md).

## Результат чтения source

Для героя уже есть отправка сообщения и транзакционная граница, но нет привязки выбранного сообщения к уточнению, фактическому ответу и единственному результату события. Для NPC уже есть настоящий автономный социальный цикл, но нет подтверждённого источника отменённых встреч NPC-пары и команды предложения/личной реплики этого случая. Обе карточки пока заблокированы перечисленными binding gaps. Это конкретный план следующей небольшой правки владельца, не действующий игровой срез.

Основная игра устанавливает CityAgency, наследующий HumanAgency; поэтому результат NPC идёт через `human_agency.gd::_social_outcome` и `npc_relationships.resolve`, а не через старую формулу базового NPC-модуля. CityDialogue сохраняет публичные open/choose базового диалога, PlayerRelationships меняет response_bias, но не снимает запрет публичного NPC→NPC interact.

## Существующие сигнатуры и их пределы

| ID / тип | Реальная сигнатура | Результат и предел применения |
| --- | --- | --- |
| `gameplay_execute` / public_main_entry | `Gameplay.execute(module_id: String, operation: String, args: Dictionary = {}) -> Dictionary` | Rules dictionary; successful call syncs global time, location, checkpoints and changed signal. Future event input must use the existing main entry after a runtime operation is approved. |
| `simulation_command` / public_transaction | `command(module_id: String, operation: String, args: Dictionary = {}) -> Dictionary` | {ok:true,data:Dictionary} or {ok:false,error:String}; restores state and rng.state on failure. One transaction boundary; do not nest command calls or dispatch synchronously from domain_event. |
| `social_message` / public_player_command | `command("social", "message", {"id": npc_id, "text": body})` | Rules.ok() with empty data; appends id/npc/text/incoming/read/minute and increments next_message_id. Can send a player message, but has no source_message_id, in_reply_to, instance_id or returned message_id. HumanSocial additionally checks contact boundary. |
| `social_read` / public_player_command | `command("social", "read", {"id": npc_id})` | Marks ALL messages whose npc==id read, returns empty Rules.ok(). Not a message-specific acknowledgement; do not silently mark unrelated messages read. |
| `dialogue_open` / public_player_command | `command("npc_dialogue", "open", {"id": npc_id, "channel": "message"})` | Rules.ok(presentation) with node/channel/turn/utterance/choices, or failure; availability checks contact/sleep/busy. Opens authored root/initiative; cannot claim it clarifies the selected source message. |
| `dialogue_choose` / public_player_command | `command("npc_dialogue", "choose", {"id": npc_id, "choice": existing_choice_id, "turn": current_turn})` | Rules.ok(reply); topic choices in message channel append player_reply and npc_reply immediately. Wrong binding for asynchronous tone clarification; cannot invent clarify choice. |
| `npc_bond_view` / internal_read_projection | `sim.services.npc_relationships.view(from: String, toward: String) -> Dictionary` | Copy with scales, last_contact and stage; missing bond synthesizes _new_bond with last_contact=now. Existing friendship projection; not evidence of cancelled NPC meetings or a newly generated bond. |
| `npc_interact_public` / public_player_command | `command("npc_relationships", "interact", {"id": npc_id, "action": "connect", "other": "player"})` | For valid player interaction returns Rules.ok({accepted,chance,reason}) after owner time; NPC pair call is rejected. Explicitly forbidden as NPC→NPC event binding. |
| `calendar_conflict` / internal_read_projection | `calendar.conflict(id: String, destination: String, minutes: int, priority: int = 50, ignore_appointment: int = -1, ignore_schedule: int = -1, forecast: Dictionary = {}) -> String` | Empty string or schedule_conflict/obligation_unreachable/obligation_travel_conflict. Check both NPCs independently and retain onward travel to next obligation. |
| `planner_pair` / internal_queue_not_public_command | `submit_pair(a: String, b: String, action: String = "") -> bool` | true means request enqueued, not consent, execution, completion or reward; execute only supports inspect. Do not call with empty action. Not a complete calendar/consent guard; future owner must validate matching case and both schedules. |
| `human_social_outcome` / existing_internal_autonomy_path | `_social_outcome(npc: Dictionary, active: Dictionary) -> bool` | Delegates resolve(actor,target,action), sets last_social, records social_outcome and returns accepted. This is the running NPC path inherited by CityAgency, not the older base NPC formula. |
| `relationship_resolve` / internal_effectful_helper_not_public_command | `resolve(actor: String, target: String, action: String) -> Dictionary` | {accepted,chance,reason}; uses RNG, directed gains/limits and emits pending npc_social_outcome(actor,target,action,accepted). Does not advance time. Do not invoke directly to skip owner duration, consent/availability or action completion; emitted payload lacks case/action instance ID. |
| `social_appointment` / public_player_command | `command("social", "appointment", {"id": npc_id, "minute": due, "location": location_id})` | Appends {npc,minute,location,status:pending}; no a/b fields, proposal acceptance record or NPC-pair cancellation archive. Not a scheduler or factual trigger source for an NPC-only meeting. |
| `snapshot` / public_in_memory_snapshot | `export_snapshot() -> Dictionary; restore_snapshot(snapshot: Dictionary) -> Dictionary` | Base exports schema/catalog_hash/rng_seed/rng_state/state. Restore rehydrates existing state or rejects. Current active actions and messages have persistence; proposed random-event instances do not exist in the current state contract. |

Примечания к командам: `social.message` использует player contacts, а HumanSocial проверяет contact boundary. Его 0 минут и пустой `data` нельзя описывать как готовое 4-минутное уточнение с возвращённым message_id. `social.read` читает весь тред NPC. `npc_dialogue.choose` требует реальный choice и turn; штатные day/feelings/goal занимают 3 минуты и в message-канале сразу добавляют ответ NPC. Выдуманного choice="clarify" нет.

`submit_pair(A,B,"")` означает репродуктивный encounter; это нельзя использовать для обычной дружеской встречи. Даже непустой connect лишь ставит запрос, а true не доказывает календарь, согласие или завершение. Публичный `npc_relationships.interact` с other=B выдаёт `use_npc_autonomy`. Прямой вызов `_start` или `resolve` обходит существенные проверки и не является предложенным binding.

## re_phone_message_tone — герой

Источник: конкретная существующая входящая непрочитанная запись `state.social.messages` с id/npc/minute; получатель — герой, отправитель — существующий взрослый знакомый. Один короткий текст или kind=npc_reply не доказывает раздражение или неоднозначность. Нужна авторская семантическая метка именно этого сообщения; сейчас её нет. Игрок не получает информацию из чужого чата.

Ключ случая: event ID + source_message_id + направленные роли player/отправитель. Перед нажатием снова проверить source, контакт, отсутствие явного отказа, занятость и необходимые gates. Если запись удалена ограничением истории, не подставлять последнее сообщение того же NPC.

| Выбор исходного каталога | Проектное местное время | Требуемый результат | Что отсутствует |
| --- | --- | --- | --- |
| a: спокойно уточнить смысл |4 мин | Одно исходящее сообщение и ожидание фактического связанного ответа; деньги/вещи 0 | ID результата отправки, source/reply correlation, атомарная фиксация 4 мин |
| b: подождать |2 мин | Ничего не отправляется, текущий случай отложен без обязанности | Сохраняемая запись экземпляра/откладывания и атомарные 2 мин |
| leave |0 мин | Закрыто только это предложение без новой потери отношений | Instance-dismiss; не подменять закрытием другого диалога |

Временная цена владельца заменяет проектную оценку шага; два внешних вызова message→clock.advance дают частичный успех и не образуют транзакцию события. Будущий владелец выполняет проверку, время и запись один раз в существующей общей транзакции. Готовый npc_dialogue с немедленным npc_reply не подходит для асинхронного ответа.

Один геройский walkthrough, **вымышленный приёмочный контекст, не прогон**:

- Read-only eligibility binds source57 and NPC42; preview does not consume RNG/time or mark messages read.
- Future approved choice a validates exact source and contact, consumes4 minutes within one transaction, then owner appends outgoing58 once. Current social.message alone would use0 minutes and return empty data.
- Record one parent result tied to outgoing58; balance120/80 and inventories unchanged. No incoming59 is invented. Event waits for real reply.
- If a genuine correlated incoming59 arrives later, validate same NPC and source/parent then make existing re_phone_tone_reply available once.
- Reopening, repeated click or restoring a post-send snapshot cannot append another58 or replay4 minutes.

Fixture: minute2880; взрослые 27/31; source57, next_message58; деньги 120/80; свободно до 2920. При a ожидается minute2884 и ровно одна исходящая 58; при b —2882 без отправки; при leave —2880 без изменений денег/вещей. Входящая 59 не создаётся сценарием. Существующий `re_phone_tone_reply` — ссылка на уже принятую карточку, а не новый контент; он открывается лишь на настоящем коррелированном ответе.

## re_npc_life_friend_distance — только NPC

Источник должен подтверждать прошлые реально принятые встречи A/B и их отмены: IDs планов, пары, время, причина и источник знания обоих. Текущие player-centric social.appointments этого не хранят. last_contact показывает контакт, а не неудавшийся визит; `view()` при отсутствии сохранённого bond вообще синтезирует last_contact=now. Бounded mind.history без устойчивого идентификатора встречи не превращать в архив отмен. Пока данных нет — событие недоступно.

Только существующие взрослые NPC. Проверить сохранённые directed bonds, фактический доступ и свободные окна обоих с дорогой после встречи. Герой не участвует, не оплачивает и не наблюдает автоматически. Пример места — city_park при реальном присутствии обоих; новое перемещение или принудительный визит не создаются.

| Выбор исходного каталога | Проектное время | Требуемый результат | Реальная граница |
| --- | --- | --- | --- |
| a: предложить короткий визит |6 мин предложения | B отдельно согласен/отказал; принятый план ещё не завершённая встреча | NPC invitation binding отсутствует; действующий connect длится 30 мин |
| b: признать временную дистанцию |8 мин | Реальная частная реплика A→B, без стирания связи и прошлого | NPC-private utterance binding отсутствует; player dialogue не подходит |
| leave |0 мин | Нет нового контакта, старые факты/расписание/обычный neglect остаются | Нужен case-scoped dismiss, без уведомления героя |

Предложение 6 мин и последующий connect30 мин — разные фазы, только если обе действительно состоялись. Нельзя начислить результат встречи на 6-й минуте, подменить owner action его проектной оценкой или прибавить 30 мин дважды. Окончательный контракт времени принимает владелец автономии; здесь он не реализован.

Один NPC-only walkthrough, **вымышленный приёмочный контекст, не прогон**:

- Current build must stop: no authoritative NPC-pair cancellation source and no event instance exist. Do not substitute player appointments or last_contact.
- After future approved bindings, A independently chooses a. B independently agrees or refuses. During6-minute proposal check both calendars including subsequent30-minute connect and10-minute onward route:6+30+10=46 <=60.
- Accepted proposal binds one plan/result, not a completed meeting. No salary, XP or relation gain for invitation. A/B/player money remain90/70/120 for this local case.
- Only if ordinary autonomy actually starts matched connect for the pair: both active records refer to each other; due uses owner catalog30 minutes, and existing CityAgency→HumanAgency path controls interruption/completion.
- At actual completion HumanAgency._social_outcome calls resolve once, which may accept or decline. Record only matching committed owner outcome. Clock advance by a player elsewhere is not itself proof of this meeting.
- No player notification or knowledge is added. Restore mid-action must preserve existing due and event correlation; after completed snapshot no second outcome or relation gain.

Fixture: A28/B35, деньги 90/70; герой в другом месте со 120. Два source-плана 11/12 — требуемые будущие подтверждённые факты, которых текущий NPC-pair runtime не предоставляет. В city_park оба уже присутствуют,60 мин до обязательства, дорога после 10 мин;6+30+10=46 мин помещается. Все IDs fixture, жители не создаются. Игровые часы общие: фоновые 36 мин не добавляются поверх тех же 36 мин внешнего clock.advance.

## Недостающие привязки — конечный список

| ID | Область | Нужный контракт |
| --- | --- | --- |
| `instance_commit` | `both` | A bounded saved event instance keyed by event_id+owner_incident_id+ordered roles, selected choice, due, result identity and consumed marker, committed inside existing transaction. No new public signature is asserted. |
| `tone_source` | `re_phone_message_tone` | Author-owned ambiguity/non-refusal semantic tag and source_message_id. Existing kind=npc_reply or message length does not prove tone; do not infer anger from random text. |
| `message_correlation` | `re_phone_message_tone` | Owner-confirmed outgoing message_id, in_reply_to/source correlation and single-message read semantics; exactly one source-bound reply, no arbitrary incoming injection. |
| `tone_atomic_duration` | `re_phone_message_tone` | Apply4/2/0 minutes once inside owner-approved instance transaction, revalidate contact after elapsed time, append no automatic NPC answer. Do not compose two external commands with partial success. |
| `npc_cancel_evidence` | `re_npc_life_friend_distance` | Stable real cancelled/missed commitments between A and B with their roles, accepted plan identity, time, reason and knowledge provenance. last_contact and player appointments are insufficient. |
| `npc_invitation_choice` | `re_npc_life_friend_distance` | Owner-approved choice a/b/leave attached to the actual A→B case with independent response by B; do not force _start or call player interact. |
| `npc_outcome_correlation` | `re_npc_life_friend_distance` | Correlate actual start/completion/cancel to event instance, pair, action, started/due and unique owner outcome; ordinary clock.advance success cannot identify this event. |
| `npc_phrase_b` | `re_npc_life_friend_distance` | A genuine private A→B acknowledgement of distance with8-minute proposed local duration; current player dialogue is not NPC→NPC speech. Do not use romantic separate or apply false friend breakup. |
| `reply_continuation` | `re_phone_message_tone` | Activate existing re_phone_tone_reply only on actual correlated incoming reply; keep same participants and parent result. No new card is added. |

Названия gaps — идентификаторы требований дизайна, не придуманные публичные методы или уже зарегистрированные сервисы. Новые сервисы не строились и этим документом не назначаются.

## Отказ, дубли, деньги, время и restore

У обоих случаев нет собственной платы, XP, подарка и прибавки отношения. Реальный социальный исход применяет только действующий владелец с его RNG, суточным бюджетом и памятью. Для локального NPC-примера дорога 0, деньги 90/70/120 неизменны; для иной реальной дороги стоимость платит соответствующий NPC, без кошелька героя.

Один owner-result на один экземпляр. Не использовать текст сообщения, ID NPC или успешный clock.advance как универсальный уникальный ключ. Повторное открытие/двойной клик/другая вкладка не отправляют сообщение, не двигают часы и не вызывают resolve. Истечение предложения и отказ не отменяют настоящие долги, уход или уже принятые встречи.

В текущем snapshot сохраняются state и RNG, активное NPC-действие с started/due/partner и сообщения. Схемы экземпляров этих случайных событий ещё нет. Поэтому restore событий сейчас не проверен и не может считаться готовым по одному наличию export_snapshot. Предстоящая интеграция должна сохранять source IDs, направленные роли, выбор, parent/result identity, consumed marker, actual due и suppression. При несовместимой схеме действует текущий явный отказ загрузки; миграции/переписывание saves не выполняются.

Проверяемые точки: до предложения; после отправки 58 до ответа; после NPC-предложения до старта; посреди фактического connect; после конечного результата. Во всех случаях нельзя повторить локальную цену, сообщение или gain. При неопределённой старой корреляции блокировать продолжение, не восстанавливать успех по тексту истории.

## Remote events.observe из 468aa32

Проверен read-only `git show 468aa32:scripts/mechanics/events.gd`, метод observe начинается на строке 67. Сигнатура: `observe(module_id: String, operation: String, args: Dictionary, result: Dictionary) -> void`. В той версии simulation.command вызывает его после успешных hooks и перед poll/валидацией. Метод продвигает активные quest objectives по module/operation/args/result, умеет different_days или unique_arg. Это не диспетчер случайных экземпляров, не NPC-диалог и не источник результата каждого NPC внутри перемотки.

Снимок на момент чтения: local events.observe присутствует=false, local command hook=false. Соединение remote ведёт координатор параллельно; данный исполнитель не объединял код и не заявляет его состояние позже этого снимка. Наличие remote observe не снимает ни один из перечисленных source/NPC/instance gaps.

Domain event `npc_social_outcome` содержит actor,target,action,accepted, но пока не уникальный ID action/case. Он публикуется после commit при занятой command-границе; синхронный новый command получит reentrant_command. Для общей атомарности потребуется согласованная owner-привязка внутри commit, а не UI-слушатель, повторяющий команду.

## Источники и проверка

JSON содержит SHA-256 и точные строки-якоря всех прочитанных файлов, а также отдельный hash remote-файла. Это снимок занятого рабочего дерева; последующие параллельные изменения требуют повторного чтения нужных сигнатур перед реализацией. Упомянутые классы и методы исследованы статически, не исполнены этим этапом.

| Source | Проверенные якоря |
| --- | --- |
| `scripts/gameplay/gameplay.gd` | 129: `func execute(module_id: String, operation: String, args: Dictionary = {}) -> Dictionary:` |
| `scripts/gameplay/main_simulation.gd` | 23: `const MAIN_SCHEMA :=`; 97: `func after_command(`; 128: `func restore_snapshot(` |
| `scripts/mechanics/simulation.gd` | 102: `func command(`; 158: `func advance(`; 245: `func export_snapshot(`; 249: `func restore_snapshot(` |
| `scripts/mechanics/social.gd` | 30: `"message", "call":`; 35: `"read":`; 41: `"appointment":`; 132: `func remember(` |
| `scripts/mechanics/human_social.gd` | 3: `func execute(` |
| `scripts/mechanics/npc_dialogue.gd` | 281: `func availability(`; 331: `func execute(`; 479: `func _message(` |
| `scripts/gameplay/city_dialogue.gd` | 4: `func local_initiative(` |
| `scripts/mechanics/npc_relationships.gd` | 25: `func view(`; 108: `func blocked(`; 197: `func resolve(`; 285: `func execute(` |
| `scripts/gameplay/player_relationships.gd` | 3: `func response_bias(` |
| `scripts/mechanics/npc_agency.gd` | 264: `func _log(`; 373: `func _partner(`; 496: `func _start(`; 553: `func _finish(` |
| `scripts/mechanics/human_agency.gd` | 61: `func _social_outcome(` |
| `scripts/gameplay/city_agency.gd` | 3: `func _destination(` |
| `scripts/mechanics/npc_planner.gd` | 28: `func submit_pair(`; 80: `func resolve(`; 116: `func _dispatch(` |
| `scripts/mechanics/npc_calendar.gd` | 38: `func conflict(`; 57: `func site_open(` |
| `scripts/mechanics/npc_life_simulation.gd` | 14: `services["npc_agency"] =`; 22: `func after_minute(` |
| `scripts/mechanics/events.gd` | 3: `func execute(`; 56: `func eligible(` |
| `scripts/mechanics/core/module.gd` | 23: `func emit_event(` |
| `data/mechanics/npc_life.json` | 25: `"connect":` |
| `data/mechanics/npc_dialogue.json` | 2232: `"dialogue_choices":` |

Проверка подготовки: JSON прочитан стандартным парсером; оба root-ID и единственная ссылка на прежний followup найдены в неизменённом каталоге; source paths/anchors, remote observer и сигнатуры сверены. Таблица 12 будущих приёмочных случаев находится в JSON: это спецификация, не 12 пройденных игровых тестов.

Не выполнялись Godot/test_mechanics, запуск игры, probability/balance, события после загрузки, remote-merge regression, UI/PCK и операции с saves. Никакого runtime-кода не менялось.

Переносимая проверка синтаксиса без внешних библиотек из корня проекта:

```powershell
python -m json.tool data/mechanics/design/random_event_first_slice.json > $null
```

Полная статическая сверка при подготовке дополнительно проверила два root-ID, неизменность choices/минут и SHA-256 исходного 144-карточного каталога, прежний followup, 14 контрактов и 19 source-якорей/хешей. Результат успешный; изменений этих source-файлов между чтением и проверкой не обнаружено. Это проверка согласованности спецификации, а не исполнение описанных шагов.

Следующий малый этап по решению координатора: сначала согласовать у владельца сообщений source/result correlation и атомарную отправку одного сообщения героя. NPC-only часть до появления настоящего pair-cancellation source остаётся заблокированной; не заменять её фиктивной player-встречей. Каталог 144 не расширять.
