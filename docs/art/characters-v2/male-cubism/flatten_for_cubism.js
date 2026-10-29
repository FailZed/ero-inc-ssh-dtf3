// Convert an edited grouped art PSD into Cubism's proven flat-layer import form.
// Hidden reference groups/layers are excluded. This preserves raster layer data.
const fs = require("node:fs");
const path = require("node:path");
require("ag-psd/initialize-canvas");
const { readPsd, writePsdBuffer } = require("ag-psd");

const [input, output] = process.argv.slice(2);
if (!input || !output) {
  throw new Error("Usage: node flatten_for_cubism.js edited-grouped.psd output-cubism-import.psd");
}
if (path.resolve(input) === path.resolve(output)) {
  throw new Error("Output must differ from input");
}
const psd = readPsd(fs.readFileSync(input), { useImageData: true });
const layers = [];
function visit(items, hidden = false) {
  for (const item of items || []) {
    const isHidden = hidden || Boolean(item.hidden);
    if (isHidden || item.name?.startsWith("_REFERENCE_ONLY_")) continue;
    if (item.children) visit(item.children, isHidden);
    else if (item.imageData) layers.push({
      name: item.name,
      top: item.top,
      left: item.left,
      imageData: item.imageData,
    });
  }
}
visit(psd.children);
if (!layers.length) throw new Error("No visible raster layers to import");
const result = {
  width: psd.width,
  height: psd.height,
  imageData: psd.imageData,
  children: layers,
};
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, writePsdBuffer(result, {
  trimImageData: true,
  noBackground: true,
}));
console.log(`${output}: ${layers.length} visible raster layers`);
