# Pregnancy appearance in the prototype portrait

2026-10-27. The user requested temporary School pregnancy layers and a real
before/after comparison. Nine normal portrait abdomen PNGs were imported
unchanged; provenance and hashes are in `SCHOOL_PREGNANCY_ASSETS.json`.
No donor scripts or narrative were imported. These are temporary art assets,
not the approved original EroInc character rendering style.

`data/art/pregnancy_materials.json` maps nine presentation variants to separate
painted abdomen textures and `.tres` garment materials. The original face, hair,
arms and body remain separate sprites. Athletic abdomen detail is suppressed
while the replacement abdomen is visible. Clothes use the abdomen alpha for
coverage and broad fabric lighting; skin details are not printed on the cloth.
Pregnancy no longer stretches UVs of every portrait layer.

`pregnancy_visuals.gd` derives the variant from the active world condition and
calendar month. It only copies presentation data; it does not migrate or write
saves, advance time, consume gameplay RNG, or change reproduction rules.
Without a condition, existing coarse stages 0–4 map to 0/1/4/7/9. Completed
conditions clear the visual. The common portrait presenter applies this to
both NPC and player views. Fully furry and male rigs never receive this art.

## Visual verification

`tests/gameplay/capture_pregnancy_materials.gd` renders the actual shared Godot
portrait component. The fixture is a 30-year-old adult, the same identity,
pose, clothing and late stage on both sides. The old shader is preserved only
in `tests/fixtures/legacy_pregnancy.gdshader` to reproduce the before image.

Captures in `verification/pregnancy-materials-2026-10-27/`:

- `comparison.png`: actual runtime assemblies with the same casual dress.
- `abdomen-detail.png`: cropped assembly check with base clothing retained,
  exposing the painted abdomen and the effect on underlying waistband layers.

The `*-verified.png` copies contain identical bytes and are used in the chat
preview to avoid stale image caching. Run the capture script with `-- --detail`
for the second image, in a separate engine process.

Both captures were visually inspected. The painted layer clearly distinguishes
the abdomen from general widening. The dress uses a provisional material fit;
its frontal silhouette and folds are restrained and do not replace individually
drawn pregnancy wardrobe variants. This does not certify all costumes, poses,
body types or the original EroInc art pack. No exported release is claimed.

Focused regression: run `tools/godot.ps1 --headless --script
res://tests/gameplay/run_pregnancy_visuals.gd`. It covers all nine variants,
wardrobes, identity preservation, calendar transitions, baseline restoration,
sprite cleanup, rig restrictions and unchanged simulation data/RNG.

Verification result: 39 focused portrait checks passed; the standalone mechanics
PCK passed 2,394 checks. The full gameplay run passed 651 of 652 checks, with the
unrelated phone test `incoming messages do not pull the reader away from older
chat history` failing. Its implementation was not changed here. Logs and result
metadata are alongside the captures. Main-project runs retain the existing exit
warnings (63 ObjectDB objects, 27 resources); the standalone PCK exits cleanly.
