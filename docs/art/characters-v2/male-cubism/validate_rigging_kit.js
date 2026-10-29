// Structural validation only; visual rig quality requires inspection in Cubism.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
require("ag-psd/initialize-canvas");
const { readPsd } = require("ag-psd");

const root = __dirname;
const groups = [
  ["01_FRONT_HAIR", ["hair_front"]],
  ["02_HEAD_AND_NECK", ["head_neck"]],
  ["03_ARMS", ["left_arm_hand", "right_arm_hand"]],
  ["04_SHIRT", ["shirt_torso_and_sleeves"]],
  ["05_PELVIS_AND_LEGS", ["pelvis", "left_leg", "right_leg"]],
  ["06_SHOES", ["left_shoe", "right_shoe"]],
];

for (const form of ["lean", "medium", "full"]) {
  const file = path.join(root, "rigging-kit", form, `${form}-rigging-kit.psd`);
  const psd = readPsd(fs.readFileSync(file), { useImageData: true });
  assert.equal(psd.width, 1024);
  assert.equal(psd.height, 1536);
  assert.equal(psd.children.length, 7);
  for (let i = 0; i < groups.length; i++) {
    const [name, layerNames] = groups[i];
    const group = psd.children[i];
    assert.equal(group.name, name);
    assert.equal(Boolean(group.hidden), false);
    assert.deepEqual(group.children.map(child => child.name), layerNames);
    for (const layer of group.children) {
      assert.ok(layer.imageData.width > 0 && layer.imageData.width <= 1024);
      assert.ok(layer.imageData.height > 0 && layer.imageData.height <= 1536);
      assert.ok(layer.imageData.data.some((value, index) => index % 4 === 3 && value > 8),
        `${form}/${layer.name}: empty alpha`);
    }
  }
  const guide = psd.children[6];
  assert.match(guide.name, /^_REFERENCE_ONLY_/);
  assert.equal(guide.hidden, true);
  assert.equal(guide.children.length, 1);
  assert.equal(guide.children[0].hidden, true);
  assert.match(guide.children[0].name, /NOT_ALIGNED$/);
  const importPsd = readPsd(fs.readFileSync(path.join(root, "rigging-kit", form,
    `${form}-cubism-import.psd`)), { useImageData: true });
  assert.equal(importPsd.width, 1024);
  assert.equal(importPsd.height, 1536);
  assert.deepEqual(importPsd.children.map(layer => layer.name),
    groups.flatMap(([, names]) => names));
  assert.ok(importPsd.children.every(layer => !layer.hidden && !layer.children && layer.imageData));
  console.log(`${form}: 6 art groups, 10 flat import layers, 1 hidden guide`);
}
