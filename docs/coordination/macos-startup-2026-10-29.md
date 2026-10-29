# macOS native sandbox startup — 2026-10-29

Owner: macOS UI/native startup agent. Run ID: `mac-startup-20261029`. This was a live Godot window walkthrough, not an automated assertion or a full playtest.

## Isolation and baseline

- Copied the project before H04 work to `.artifacts/mac-startup-20261029/project/`; recorded 5,257 file hashes in `baseline.json`. Source commit at capture: `f8ffdb2e02e2e2280c579be114504f9c53287e61`.
- The copy uses Godot's custom `user://` directory `/Users/vladzvezdin/Library/Application Support/mac-startup-20261029`. Existing game saves were untouched. Runtime: Godot `4.7.2.stable.official.ed1daf0bf`, GUI Compatibility renderer (OpenGL 4.1 Metal on Apple M4 Pro) and `Dummy` **audio driver** via `tools/runtime.py`. Editor import completed before native launch.
- Only `tools/godot.sh` was changed in the source checkout (executable bit); `./tools/godot.sh --version` returned 4.7.2.

## Baseline native path

1. Main menu → new game → sandbox world/NPC setup (36 NPCs: 22 human, 9 demi, 5 furry) → second settings page → “Начать песочницу” → bathroom mirror character creator → “Это я” → bedroom at Sunday 12 April 08:00. The creator showed a reflection. Its long-hair selector was used, but a visual appearance change was not established, so this is **not** an art acceptance check.
2. Inventory showed four stacks. Eating one prepared meal reduced its count 3→2 and advanced the clock 08:00→08:05. Places travel worked bedroom → hall → home gate → residential courtyards → trade street, reaching 08:14. The phone opened; Messages reported no contacts.
3. At the home gate, city-map markers and “К СЦЕНЕ” did not react to mouse clicks. The map was visible but blocked by the fullscreen shell chrome. This native defect was sent to the HUD owner for repair.
4. Manual save in “Мои сохранения”, slot 1, at trade street 08:14 succeeded. After travel to cafe frontage at 08:18, loading slot 1 restored trade street and 08:14. “Авто и быстрые” empty slots did not offer manual save; use “Мои сохранения”.
5. Book opened and Escape returned to Places. Wait advanced 08:14→08:29 (15 minutes). Travel to cafe room reached 08:34; the People panel showed three NPCs. A conversation with Илья Белов about his day produced a reply and advanced 08:34→08:37.

## UI-patched native retest

After the baseline save/load check, copied **only** `scripts/ui/gameplay/gameplay_shell.gd` and the new `scripts/ui/gameplay/sleep_picker.gd` from the HUD owner's current source into the isolated project, then restarted and loaded the original slot. No story catalog, mechanics, H04, or Live2D changes entered this copy.

- Map marker “Перед кафе” responded: destination card showed 4 minutes, “ИДТИ” traveled trade street 08:14→cafe frontage 08:18, and “К СЦЕНЕ” returned to the scene. Another map route to “У калитки дома” showed 11 minutes and traveled 08:18→08:29. Places then worked home gate→hall 08:30→bedroom 08:31.
- Bedroom “Поспать” opened the duration picker. Cancel left the time at 08:31. Reopening, selecting `0 ч 30 мин` via keyboard, and confirming advanced the clock exactly to 09:01. HUD phone remained clickable and opened its home screen.
- Saved this patched state to a separate manual slot 2. Both native processes exited normally with code 0. The four native console/Godot logs had no `ERROR`, script error, parse error, crash, or assertion-failure lines.

## Evidence and limits

- Live, visually inspected save thumbnails: [baseline trade street, 08:14](../../.artifacts/mac-startup-20261029/live-captures/baseline-trade-0814.png) and [patched bedroom, 09:01](../../.artifacts/mac-startup-20261029/live-captures/ui-patched-bedroom-0901.png). These are captures produced by the running game in the isolated profile, not design references. The creator, map route, and sleep picker were visually checked in the native window but have no standalone capture file.
- Logs: `.artifacts/mac-startup-20261029/native-console.log`, `native-godot.log`, `ui-patched-console.log`, `ui-patched-godot.log`. The manifest and isolated saves remain local to this run. The disposable project copy was deleted after the test to reclaim disk space; logs, manifest, and live captures were retained.
- This verifies one sandbox startup and its listed interactions. It does not cover the prologue, combat, companions, every NPC setting, or save compatibility with later H04/story-catalog changes. A fresh integrated run is needed after those edits land; the baseline slot should not be used as proof of catalog compatibility.

## Compact HUD follow-up — isolated GUI capture

After the HUD owner added scene markers and the credit icon, a fresh source copy was run with a separate `user://mac-hud-native-20261029` profile under Godot 4.7.2 GUI Compatibility/OpenGL Metal, Dummy audio. This was a scripted live-window capture because CUA selected the unrelated Godot Project Manager window; it is **not** a manual walkthrough. No user save was opened.

- Sandbox opened in the bedroom. At 1440×900 the live render shows compact action markers with readable labels (`Выход`, `Поспать`, `Стол`, `Порядок`, `Люди рядом`), an orange original credit glyph and `250` in the header. The inventory panel opened with items and retained the header amount.
- A real pointer event selected `Перед кафе` on the city map; its route card showed `13 мин пешком` and an enabled `ИДТИ`. A pointer event on the confirmation button traveled there and returned to the scene. A world route returned to the bedroom. Canceling sleep left the clock unchanged; confirming 30 minutes advanced it by 30. The focused capture result was `failed: 0`.
- The first **700×900** live screenshot had very small, hard-to-read scene labels and HUD targets. Its original pixels are retained in [bedroom before adaptation](../../.artifacts/mac-hud-native-20261029/captures/03-bedroom-700x900-before.png). This was a real narrow-window visual defect, not an image-viewer resize artifact.
- The 1440×900 captures at these paths were refreshed after adaptation and visually inspected: [bedroom](../../.artifacts/mac-hud-native-20261029/captures/01-bedroom-1440x900.png) and [selected map route](../../.artifacts/mac-hud-native-20261029/captures/02-map-route-1440x900.png). An earlier capture attempt used a mid-edit HUD copy and hit the creator selection rectangle error; the coordinator fixed `_draw_selection`, the updated modal was copied, and the completed initial run had no `ERROR` or `SCRIPT ERROR`.

### Narrow-window adaptation retest

After the HUD owner froze the responsive update, copied six source scripts into the **same isolated test project**. Source and copy SHA-256 matched:

| `scripts/ui/gameplay/` file | SHA-256 |
| --- | --- |
| `gameplay_shell.gd` | `eb0c498b639b2a7e9daa605374f50cbffe53227fca193aee53877cc0e1102523` |
| `scene_interaction.gd` | `5f30cd62848b681d491bd2920580bda3c0b5bd26c1e3eafacc5ac02be3792446` |
| `player_hud.gd` | `594faba93e7cb9c3ef5efad0f6383c7268d5bac86ca34c718ae4cbefa0d00465` |
| `need_indicator.gd` | `e732bbdc5fe92cab815ba9480a73edfeb4c117968c1119ab71b6f88b98877263` |
| `hud_widgets.gd` | `d1d34f60926a585e1a108497087928aca125142ddb7521e662860f75916e08fd` |
| `ui_review.gd` | `030b4baa262950224981e0de6a4a7aef2f2c293f62be25be6f351da510dadf62` |

No production gameplay/UI file was edited by this QA run.

- The refreshed native 700×900 PNG has readable top time, `€` credit icon and `250`, large scene interaction targets, legible bottom HUD values, and `Телефон / Сумка / Книга / Разделы` labels. A real pointer click on the bed marker opened a legible two-action menu, `Поспать` and `Отдохнуть · 1 час`. These are visually inspected **live game renders**: [bedroom after adaptation](../../.artifacts/mac-hud-native-20261029/captures/03-bedroom-700x900.png) and [bed menu after adaptation](../../.artifacts/mac-hud-native-20261029/captures/04-bed-menu-700x900.png). Both are actual 700×900 PNGs. A transient 30-minute sleep notification was allowed to fade before capture so it did not obscure the bottom labels.
- The focused scripted run still checked sandbox creation, inventory, map-marker pointer selection, route confirmation and travel, bedroom return, sleep cancel, and 30-minute sleep. Its final result was `COMPACT_HUD_RESULT {"failed":0}`, exit 0. One intermediate run clicked the map before its layout settled and failed three pointer assertions; the capture harness was adjusted to wait six frames after panel change, and the final run passed. This remains scripted UI evidence, not a complete manual playthrough.
- Final logs: `.artifacts/mac-hud-native-20261029/capture-console-after.log` and `capture-godot-after.log` (Godot `4.7.2.stable`, OpenGL 4.1 Metal Compatibility, Dummy **audio**). Neither contains `ERROR` nor `SCRIPT ERROR`. The disposable project copy was deleted after verification; the capture script, logs and PNG evidence remain under `.artifacts/mac-hud-native-20261029/`. No broad test suite was rerun here.
