# NPC life: first decision tick performance (2026-10-29)

Godot 4.7.2, seed 128, 100 generated NPCs, agency enabled, simulation starts at minute 480. The focused profiler advances 15 minutes to the first decision tick. Times below are `Time.get_ticks_msec()` around `clock.advance`, excluding startup and population generation.

| Revision | Plain 15-minute advance | Instrumented breakdown |
| --- | ---: | --- |
| Before | 23,558 ms; repeat 23,149 ms | `npc_planner.resolve` 22,134 ms; `agency._choose` 20,943 ms; `agency.evaluate` 18,311 ms; `agency._route` 12,820 ms |
| After | 240 ms; repeat 239 ms | `npc_planner.resolve` 229 ms; `agency._choose` 209 ms; `agency.evaluate` 189 ms; `agency._route` 94 ms |

`world.actor_availability()` deeply copied the entire state for every route edge. With 100 NPCs, route evaluation dominated the first decision tick. It now copies only the root dictionary. This still keeps the temporary arrival `clock` out of `sim.state`; `Rules.check()` recursively reads nested dictionaries without writing to them. The location result remains deeply copied as before.

Verification:

- `tools/godot.sh --headless --path . --script res://tests/mechanics/world_availability_optimization.gd`: 150 comparisons against the previous deep-copy implementation across actors, locations, times, opening-hour overrides and nested `all`/`any` requirements; 0 mismatches; snapshot and RNG unchanged.
- `tools/godot.sh --headless --path . --script res://tests/mechanics/npc_life_profile.gd`: 15-minute plain and instrumented runs have identical starting and ending snapshots/RNG; exported snapshot restores identically.
- `tools/godot.sh --headless --path . --script res://tests/mechanics/npc_life_profile.gd -- --minutes=120`: 120-minute plain run 811 ms; instrumented run 841 ms; snapshots/RNG and restore match.
- `tools/godot.sh --headless --path . --script res://tests/mechanics/run_depth_audit.gd`: 81 checks, 0 failures.

The 15-minute comparison isolates one decision tick. It does not establish a 7-day runtime or whole-game speedup. The full `tests/mechanics/run.gd` was not run for this task.
