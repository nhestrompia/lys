import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const [iconset, output] = process.argv.slice(2);
if (!iconset || !output) {
  throw new Error("usage: node Scripts/create-icns.mjs ICONSET_DIRECTORY OUTPUT.icns");
}

// iconutil on some macOS/Xcode 26 combinations rejects valid generated iconsets. ICNS is a small
// typed container, and current macOS icon entries contain PNG payloads. Include both standard and
// Retina entry types; iconutil can round-trip the resulting file back to all ten source sizes.
const entries = [
  ["icp4", "icon_16x16.png"],
  ["ic11", "icon_16x16@2x.png"],
  ["icp5", "icon_32x32.png"],
  ["ic12", "icon_32x32@2x.png"],
  ["ic07", "icon_128x128.png"],
  ["ic13", "icon_128x128@2x.png"],
  ["ic08", "icon_256x256.png"],
  ["ic14", "icon_256x256@2x.png"],
  ["ic09", "icon_512x512.png"],
  ["ic10", "icon_512x512@2x.png"],
];

const chunks = [];
for (const [type, filename] of entries) {
  const png = await readFile(join(iconset, filename));
  if (png.subarray(0, 8).toString("hex") !== "89504e470d0a1a0a") {
    throw new Error(`${filename} is not a PNG`);
  }
  const chunkHeader = Buffer.alloc(8);
  chunkHeader.write(type, 0, "ascii");
  chunkHeader.writeUInt32BE(png.length + chunkHeader.length, 4);
  chunks.push(chunkHeader, png);
}

const bodyLength = chunks.reduce((length, chunk) => length + chunk.length, 0);
const header = Buffer.alloc(8);
header.write("icns", 0, "ascii");
header.writeUInt32BE(header.length + bodyLength, 4);
await writeFile(output, Buffer.concat([header, ...chunks]));
