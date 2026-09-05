import { writeFile, rm } from "node:fs/promises";
const apiUrl = process.env.TINY_CAR_API_URL || "/api";
await writeFile(
  new URL("../zig-out/web/config.js", import.meta.url),
  `window.TINY_CAR_CONFIG = ${JSON.stringify({ apiUrl })};\n`,
);

// Remove obsolete output names from earlier builds before publishing the directory.
for (const extension of ["html", "js", "wasm", "data"])
  await rm(new URL(`../zig-out/web/tiny_car.${extension}`, import.meta.url), {
    force: true,
  });
