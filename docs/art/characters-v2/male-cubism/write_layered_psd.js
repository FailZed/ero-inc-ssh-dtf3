// Write a layered Photoshop file that Cubism 5.2 imports with visible pixels.
// The previous pytoshop output parsed in psd-tools but imported as empty ArtMesh.
const fs = require("node:fs");
const path = require("node:path");
const { PNG } = require("pngjs");
require("ag-psd/initialize-canvas");
const { writePsdBuffer } = require("ag-psd");

const root = __dirname;
const form = process.argv[2];
const output = process.argv[3];
if (!["lean", "medium", "full"].includes(form) || !output) {
  throw new Error("Usage: node write_layered_psd.js lean|medium|full output.psd");
}

const names = [
  "shirt_torso_and_sleeves", "left_arm_hand", "right_arm_hand",
  "hair_front", "head_neck", "left_shoe", "right_shoe", "pelvis",
  "left_leg", "right_leg",
];
const load = (file) => {
  const png = PNG.sync.read(fs.readFileSync(file));
  return { width: png.width, height: png.height,
    data: new Uint8ClampedArray(png.data) };
};
const source = load(path.join(root, "reference", `${form}-concept.png`));
const children = names.map((name) => ({
  name,
  imageData: load(path.join(root, "layered", form, `${name}.png`)),
}));
const psd = {
  width: source.width,
  height: source.height,
  imageData: source,
  children,
};
fs.writeFileSync(output, writePsdBuffer(psd, {
  trimImageData: true,
  noBackground: true,
}));
console.log(output);
