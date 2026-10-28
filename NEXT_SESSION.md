# Передача EroInc на 29 октября 2026

**FINAL_HANDOFF_READY — итоговая передача на 29 октября.**
28 октября все **7 исполнителей и 3 мировых агента завершили задачи**, их изменения
сведены в основной проект; новых задач сегодня нет. Последним прямым поручением
владелец попросил собрать этот файл и отправить всё до 23:30 МСК. Итоговый обход
состоялся в 22:38 МСК; запущенная по просьбе владельца игра оставлена открытой.
Версия передачи — commit, содержащий этот файл: `git log -1 --format=%H`.

## Другой компьютер: начало работы

Репозиторий публичный по прямому решению владельца:
https://github.com/FailZed/ero-inc-ssh-dtf3.git, ветка `main`.
Для нового рабочего каталога можно получить только актуальную историю:

```sh
git clone --depth 1 https://github.com/FailZed/ero-inc-ssh-dtf3.git
cd ero-inc-ssh-dtf3
python3 tools/runtime.py setup
python3 tools/runtime.py doctor
python3 tools/runtime.py run -- --editor
```

Windows: заменить `python3` на `py -3`; также доступен `tools/godot.ps1`.
macOS: `tools/godot.sh`. Godot закреплён на **4.7.2 stable**; launcher проверяет
версию и использует **Dummy audio**. Системный движок автоматически не заменяется.
Шаблоны нужны для экспорта: `python3 tools/runtime.py setup --templates`.
Для обычной работы не нужны компилятор, E:/Ai или E:/Tools.

Прочитать `AGENTS.md`, этот файл и документы выбранной области. На новом ПК
установить пакет навыков `gamedev-skills/awesome-gamedev-agent-skills`; абсолютные
пути навыков старого ПК заменить фактическим установленным расположением.
Не перезаписывать незакоммиченные изменения уже существующего checkout.
Для полной старой истории shallow clone потребует отдельного fetch; она велика.

Основная схема нового состояния **14**. Старые слоты не мигрируются. Не удалять,
не менять и не перезаписывать пользовательские сохранения; использовать новое
прохождение или изолированную тестовую копию. Не возобновлять старую бесконечную
очередь исполнителей: сессия 28 октября закрывается отдельным поручением.

## Что включено в текущий source

Root свёл изменения местных исполнителей с remote `468aa32304379c7046879079d3d4ddcb5e642bdc`
по baseline, с пофайловыми hash-guards и backup. Remote computer, companion,
antagonism, day_planning, education, club_work и portable desktop tools сохранены.
Общий commit продолжает удалённую историю `468aa32304379c7046879079d3d4ddcb5e642bdc`;
старая локальная база `e219e53357ed7f84636f7884ae555bd2ad3d1afc` является её предком.
Удалённая история сохраняется; force/reset/blind pull не применялись.

| Область | Реальное включение и границы |
| --- | --- |
| Город | Единый граф71место/79переходов, пять районов, учёба/работы/клиника/четыре вида жилья. Четыре наполненные локации, предметные действия через существующий actions.perform. Первая пара взрослых жителей уважает N/пролог/restore. Карта пока схема, арт-брифы не готовые фоны. |
| Профессии | A01/A03/A04: расписания, профильные навыки/оплата,17банков×3ступени×10задач. Две remote-профессии переведены на тот же контракт без выдуманных новых уровней. Typed Education и Residents validation сохранены. |
| Здоровье/семья | H01/H02/H05: полные интервалы доступа к медуслугам, строгие комнаты конкретного владельца, уход/семья. Club не перехватывает срочную помощь и назначенный уход. H04 ниже остаётся открытым. |
| Общение | Каталог действий, направленные отношения, память и actor lifecycle сохранены. Учебный Live2D не заменяет утверждённый собственный арт. |
| Бой | Сегодня по новому прямому поручению включён School-подобный цикл: выбор/подтверждение удара, отдельная защита, один ответ NPC на подтверждение; время начисляется в границах существующего action policy. Полный числовой/визуальный паритет School не заявлен. |
| Случайные события | Включены только два настоящих runtime-case: связанный ответ на сообщение и дистанция друзей после двух реальных срывов контакта. Используют существующих owners/clock/RNG, guards от повторов и restore. Дизайн144карточек не равен144подключённым событиям. |
| UI | Компактные Actions/People/Places/сумка, Tab/focus, книга и окно спутника. При сведении сохранены source navigation hooks и remote book/companion. |
| Мастерская | Меню открывает res://assets/characters/mdrg_study/scenes/browser.tscn; «Закрыть»/Esc возвращают в меню. Старый editor удалён без fallback. |

Главный фактический Main14 на момент сведения:
SHA256 `b6055b6d6732c561787074f6903d2b917d4cab2303187cbec50b058b91a407a3`.
Проверять актуальный хеш перед будущими правками, не копировать старые снимки
из локального `.research` поверх новой версии.

## Проверки: что они действительно доказывают

Это отдельные ограниченные наборы, **не общая зелёная приёмка игры**.
Assertions не являются количеством механик. Финальная массовая проверка ради
Git не запускалась по указанию владельца.

| Набор | Результат и срез |
| --- | --- |
| Сведённый city domain |89/0, Godot4.7.2/Dummy, in-memory без настоящих autoloads/окон/saves |
| Два events v2 |112/0 own isolated PCK и112/0 в сведённой staging; reset/restore, повторы/отказы, реальный reply/agency completion. Native телефон целиком не принимался. |
| School combat |47/0 domain,8/0 portrait controls,15/0 actual Main commands в candidate/staging; финальная вся native UI не проверена. |
| Health postmerge |155/0 на фактических original Main14/career/club данных,306source hashes стабильны, без fixture rewrites. Один согласованный postmerge probe. |
| Closing careers |35/0, точечная совместимость банков/сертификата/typed validation, не весь gameplay |
| Closing UI |4класса и18/0 headless +18/0 native синтетическая fixture; не вся объединённая сцена |
| Retained Live2D |13/0 чистая retained-only копия/Windows SDK5; lipsync и загрузка модели. Не полная визуальная приёмка всех моделей/физики. |
| Переключение browser |14/0 по отчёту владельца caller; окно показано им. Root не выполнял повторный native запуск. |
| Main menu caller |Изолированный parser true после сохранения browser + remote load-error. Не полный startup всех autoloads. |

Точные отчёты: `docs/coordination/closing-*.md`,
`docs/mechanics/verification/care-postmerge-2026-10-28/`,
`docs/mechanics/verification/random-events-2026-10-28/`,
`docs/gameplay/verification/school-combat-2026-10-28/`, `docs/world/verification/`.
Исторические результаты более ранних версий не подменяют эти границы.

## Очистка и ресурсы мастерской

По прямому поручению владельца удалены893старых screenshot/import-файла
(около1,059ГБ) и около50,71МБ дублирующих builtin-моделей.
Оставлены текущие compact-1920/1366/ultrawide capture-наборы и авторские references.
Сырой Unity MDRG-архив77105файлов не включён в текущую версию.
Сохранён граф мастерской из114ресурсов (~53,35МБ), включая referenced shader/sidecar;
полный переносимый перечень с native/license содержит129файлов (~57,56МБ).
Переносимый перечень с хешами: `tools/manifests/browser_resources.json`;
отчёт: `docs/coordination/verification/project-cleanup-2026-10-28.json`.
Промежуточная инвентаризация текущих файлов для Git: около588МБ вместо1,62ГБ
до очистки. Размер сжатого clone, всей Git-истории и экспортированной игры иной.

Windows matched renderer/Core лежат в `addons/gd_cubism/bin/sdk5/`, macOS universal
library — в `addons/gd_cubism/bin/`. GDExtension и portable tools используют эти
точные пути. Старую локальную загруженную DLL в rootbin не использовать и не
публиковать; она исключена bin/.gitignore. Пользовательские приложения не завершались.
Для применения новой native библиотеки ранее открытый редактор потребуется
самостоятельно перезапустить. macOS здесь не запускалась; библиотека сохранена.

**Git-история не переписывалась.** Исторический archive LFS-объект114485752байт
OID `7a451797109a400e857aac9ac569cabcaa1a05d2907cbe58df72073913e98c80`
недоступен из-за квоты GitHub. Для актуальной мастерской этот объект не нужен;
`git lfs pull` всего исторического архива не является шагом настройки.
Очистка текущего дерева не освобождает историческое хранилище автоматически.

## Итоги исполнителей и точные отчёты

| Исполнитель | Передача |
| --- | --- |
| Карьеры | `docs/coordination/npc-careers.md`, `closing-careers.md`, `docs/gameplay/NPC_CAREERS.md` |
| Live2D | `docs/coordination/dialogue-live2d.md`, `closing-live2d.md`, `closing-live2d-manifest.json` |
| Здоровье/семья | `docs/coordination/health-family.md`, `closing-health.md`, `docs/mechanics/verification/care-postmerge-2026-10-28/report.json` |
| UI | `docs/coordination/ui-ux.md`, `closing-ui.md` |
| Бой | `docs/coordination/dialogue-combat.md`, `docs/gameplay/SCHOOL_COMBAT_HANDOFF.md` |
| События | `docs/coordination/random-events.md`, `docs/mechanics/RANDOM_EVENTS_RUNTIME.md` |
| Новая мастерская/запуск | `docs/coordination/workshop-entry-2026-10-28.md`, verification рядом |
| Три автора мира/интегратор | `docs/coordination/world-geography.md`, `world-places.md`, `world-residents.md`, `docs/gameplay/FINAL_INTEGRATION_HANDOFF.md` |

В отдельных отчётах сохранена хронология ранних кандидатов. При расхождении
старого статуса «не включён» с этим файлом использовать финальный интеграционный
журнал и текущий source, не восстанавливать старый snapshot целиком.
Standalone browser packager обновлён под текущий inventory: `python3 tools/build_live2d_study.py --check`.
Проверен состав Windows/macOS/both и синтаксис, **готовый standalone пакет не собирался**.

## Первые задачи завтра

1. На новом ПК выполнить один осмысленный startup/native проход актуального
   merged game: пролог→зеркало/создание→город→разговор/бой/телефон/мастерская.
   Проверить несовместимость старых слотов без их перезаписи. Сначала локализовать
   конкретные ошибки; не запускать все большие пакеты несколько раз ради числа.
2. Визуально принять объединённые School combat/Phone/Book/Companion и Live2D.
   Сегодняшние bounded assertions не закрывают этот этап. Числовой баланс,
   long-run NPC поведение и macOS остаются отдельной работой.
3. Прочитать medical H04: social/invite и housing/remove_tenant непосредственно
   меняют NPC.location. Исправлять как конкретный маршрут/прекращение задач,
   не объявлять устранённым самим появлением нового графа. A07взросление — дизайн,
   A05предметный результат профессий — следующий отдельный scope, сегодня не сделаны.
4. Сверить город с доступным авторским сценарием, затем делать собственные виды
   с улицы по `docs/world/LOCATION_ART_BRIEFS.md`, сохраняя утверждённый стиль.
   GoogleDoc17MGdEhAfeDBCamzr-jgrxNOOKDjFBuj_J9Xi0HMJFUQ **не прочитан**
   (401/CUA stopped). Не выдумывать его канон и не повторять вход/смену доступа;
   нужен доступный текст/экспорт владельца. Пока использованы TimeLine/STORY_LOCKS.
5. Расширять события из дизайн-матрицы только небольшими согласованными срезами;
   не подключать144карточки автоматически и не создавать второй runner/clock.

## Внешние зависимости

В Git не входят E:/Ai/ComfyUI, GPU training/venv, рабочие EXE/PCK, engine/template
кэши, исследовательские стенды `.research` и личные сохранения. Их абсолютные
пути в старых отчётах — происхождение доказательств, не обязательные runtime пути.
Для DOCX-утилит отдельно: `python3 -m pip install -r tools/requirements-story.txt`;
генераторы TimeLine не запускать без намеренной авторской пересборки.
Сборка desktop: `python3 tools/export.py --platform windows` либо `macos`,
после установки templates. Экспорт после сегодняшнего сведения ещё не выполнялся.
Native C++ rebuilding необязателен; если понадобится, официальный SDK/build inputs
и команды описаны в `docs/DEVELOPMENT_SETUP.md`.
