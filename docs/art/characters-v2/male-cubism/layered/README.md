# Male segmented PSD research sources

`lean`, `medium`, and `full` each contain a ten-layer PSD and aligned RGBA PNG
layers cut from the original generated adult character illustration. The
`*-composite-check.png` files are **reference/QA renders**, not live Cubism or
Godot screenshots. All three were visually inspected on 2026-10-29.

`psd-tools` parses all three PSDs as 1024×1536 with ten image layers. Forced
layer compositing differs from the original visible character pixels by at
most one 8-bit value per channel; background alpha values <=8 were discarded.
The first PSD writer produced readable PSDs that Cubism imported as empty
ArtMeshes. The current `ag-psd` writer was visually checked in Cubism 5.2.03:
all three ten-layer files show visible artwork and can be saved as `.cmo3`.
Copies in `source/` sit next to the Cubism projects.

This segmentation is **not production-ready**. It mechanically separates
existing visible pixels; there is no newly painted skin behind sleeves or
shirt, no continuous body behind clothing, no eye/eyelid/mouth layers, and no
underlap at shoulders, waist, crotch, knees, or ankles. Individual layer
previews reveal jagged boundary remnants, especially along the shirt hem.
Large deformations will show holes and seams. The art style also has not been
validated against `docs/art/characters-v2/STYLE.md` using the approved adapter.

To rebuild, install `requirements-layered.txt` with Python and run `npm ci` in
the parent `male-cubism` directory. Then run `python3 build_layered_psd.py`.
The generated PSDs and `.cmo3` files are authoring studies, not finished rigs.
Matching `*-layered-pilot` `.moc3` files are exported from all three layered
sources. Earlier flat `*-sips` studies remain only in the research `source/`
directory, outside the game's runtime assets.

The separate `rigging-kit/` PSDs group these same ten layers by future Cubism
part and include a hidden, unaligned anatomy reference for each form. See
`rigging-kit/README_RU.md` for the work needed to make them riggable.
