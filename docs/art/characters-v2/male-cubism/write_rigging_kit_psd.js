// Build an editable study PSD with named Cubism parts and a hidden anatomy guide.
// The guide is generated reference art: it is not aligned production underpainting.
const fs = require("node:fs");
const path = require("node:path");
const { PNG } = require("pngjs");
require("ag-psd/initialize-canvas");
const { writePsdBuffer } = require("ag-psd");

const root = __dirname;
const form = process.argv[2];
const output = process.argv[3];
if (!["lean", "medium", "full"].includes(form) || !output) {
  throw new Error("Usage: node write_rigging_kit_psd.js lean|medium|full output.psd");
}

function load(file) {
  const png = PNG.sync.read(fs.readFileSync(file));
  if (png.width !== 1024 || png.height !== 1536) {
    throw new Error(`${file}: expected 1024x1536 RGBA`);
  }
  return { width: png.width, height: png.height,
    data: new Uint8ClampedArray(png.data) };
}
function layer(name) {
  return { name, imageData: load(path.join(root, "layered", form, `${name}.png`)) };
}

const source = load(path.join(root, "reference", `${form}-concept.png`));
const guide = load(path.join(root, "anatomy-reference", `${form}-underlayer-draft.png`));
const psd = {
  width: 1024,
  height: 1536,
  imageData: source,
  children: [
    { name: "01_FRONT_HAIR", children: [layer("hair_front")] },
    { name: "02_HEAD_AND_NECK", children: [layer("head_neck")] },
    { name: "03_ARMS", children: [layer("left_arm_hand"), layer("right_arm_hand")] },
    { name: "04_SHIRT", children: [layer("shirt_torso_and_sleeves")] },
    { name: "05_PELVIS_AND_LEGS", children: [layer("pelvis"), layer("left_leg"), layer("right_leg")] },
    { name: "06_SHOES", children: [layer("left_shoe"), layer("right_shoe")] },
    { name: "_REFERENCE_ONLY_HIDE_BEFORE_CUBISM_EXPORT", hidden: true, children: [
      { name: `${form}_anatomy_draft_NOT_ALIGNED`, hidden: true, imageData: guide },
    ] },
  ],
};
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, writePsdBuffer(psd, {
  trimImageData: true,
  noBackground: true,
}));
console.log(output);
