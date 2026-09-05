import { build } from "esbuild";
import { fileURLToPath } from "node:url";
await build({
  entryPoints: [
    fileURLToPath(new URL("../server/lambda.mjs", import.meta.url)),
  ],
  outfile: fileURLToPath(new URL("../.lambda/index.cjs", import.meta.url)),
  bundle: true,
  platform: "node",
  format: "cjs",
  target: "node22",
  minify: true,
});
console.log("Score API bundled in .lambda/index.cjs");
