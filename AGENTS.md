# Project guidance

- Development coordination is maintained by the chat «Правила для агентов»
  (`01a17e92-142c-7992-ad8e-3e93fa96376d`), as requested by the owner on
  2026-10-28. Read `docs/coordination/README.md` before taking the next task;
  preserve direct user instructions in each chat and other agents' edits.
- For game-development tasks, read `C:/Users/vladi/.codex/skills/router/SKILL.md`
  and then only the relevant installed specialist skills. The local bundle is
  `awesome-gamedev-agent-skills`; its 75 skills are installed in
  `C:/Users/vladi/.codex/skills`. On another machine, install the same
  `gamedev-skills/awesome-gamedev-agent-skills` bundle and read its installed
  router; macOS user skills may reside under `~/.agents/skills`. Follow the
  user's current scope over skill defaults.
- EroInc is unreleased: replace obsolete systems directly. Do not retain legacy
  implementations, backward-compatibility layers, adapters, or fallback paths for
  superseded systems unless the user explicitly requests them. Update affected
  callers and remove superseded code as part of the replacement.
- The project is pinned to Godot 4.7.2 stable (`.godot-version`), upgraded with
  the user's authorization on 2026-10-18. Use `tools/godot.ps1` and keep future
  upgrades explicit. Godot 4.6.3 remains installed locally as a fallback.
- Preserve EroInc's established art direction: painted nocturnal environments,
  blue-black translucent panels, thin steel-blue rectangular borders, pale blue
  selection, off-white typography, restrained orange accents. Avoid introducing
  unrelated rounded purple dashboard styling.
- Character art direction was revised on 2026-10-18: use the TV anime Nukitashi
  as a rendering reference (thin lines, matte colors, controlled cel shadows),
  with original adult EroInc characters. Read `docs/art/characters-v2/STYLE.md`.
  Stabilize and validate the style adapter before producing pose/wardrobe sets.
  Earlier glossy `characters_v1/bodies_v2` and `bodies_v3` are anatomy studies,
  not the approved rendering style. Keep generation/training tools and data on E:.
- Local art generation/training must respect `E:/Ai/ComfyUI-EroInc/gpu-budget.json`:
  on 2026-10-19 the user authorized full GPU power, replacing the earlier 80%
  request. Current setting is 100% duty, normal CPU/GPU priority, 1 GB VRAM reserve.
  Use the configured launchers; see `docs/art/characters-v2/GPU_BUDGET.md`.
- New-game world/NPC settings and difficulty belong before the prologue.
  Character creation belongs later at home in the bathroom mirror, when
  `TimeLine/prolog/scene_05_mirror_and_photo.dtl` emits `open_character_creator`.
  The changing character must appear as a reflection, not an unrelated portrait.
- Mechanics research and independent runtime live in `docs/mechanics`,
  `scripts/mechanics`, and `data/mechanics`. Consult the parity matrix before
  claiming feature or numeric parity. Do not copy donor narrative, art, or code.
- Keep new mechanics and design studies separate from the main game until
  integration is requested. Do not change existing saves without an explicit request.
- Run appropriate checks using `tools/test_mechanics.ps1`; `-Isolated -Pack`
  verifies the exported standalone runtime. Screenshots and generated references
  must be visually inspected and identified as references rather than live screens.
