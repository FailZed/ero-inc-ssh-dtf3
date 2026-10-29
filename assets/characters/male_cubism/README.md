# Male Cubism pilots

These are three original adult male Cubism source/runtime pilots (`lean`,
`medium`, `full`). They are **not production character rigs**. The
`authoring/*/*-layered-pilot.cmo3` sources and matching
`runtime/*/*-layered-pilot.model3.json` exports contain ten visible ArtMeshes
cut from the concept images. Each layered model has a three-key
`ParamTorsoWidth` warp experiment. The lean and medium deformers move the shirt
layer; the full deformer also distorts the arms. These exploratory changes are
not accepted body adjustments: the artwork has no painted overlap under moving
edges.

The `.moc3` files were exported with Cubism Editor 5.2.03 for SDK 5.0 and load
in the project's Cubism Core 5.0. The focused import check is
`tests/characters/male_cubism_layered.gd`. It checks file loading,
mesh counts, and parameter metadata; they do not establish visual quality or
independent body deformation. All three have 28 parameters, but the 27
template parameters have no authored movement in these rigs.

Do not connect these pilots to character creation or saves. Production acceptance
requires redrawn overlapping artwork, local meshes and body parameters, keyed
deformations, and visual verification at parameter extrema in Godot. See
`docs/coordination/male-live2d-2026-10-29.md` for the current audit.

The editable starting PSDs, hidden anatomy studies, and a step-by-step Russian
rigging guide are in `docs/art/characters-v2/male-cubism/rigging-kit/`.
They are a construction kit, not an exported rig. Run
`node docs/art/characters-v2/male-cubism/validate_rigging_kit.js` after
`npm ci` in that directory to check PSD structure.
