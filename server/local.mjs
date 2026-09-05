import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { resolve, extname, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { FileStore } from "./file-store.mjs";
import { createService } from "./service.mjs";
const root = resolve(fileURLToPath(new URL("../zig-out/web", import.meta.url)));
const store = await new FileStore(
  fileURLToPath(new URL("../.local/scores.json", import.meta.url)),
).load();
const service = createService(store);
const mime = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".wasm": "application/wasm",
  ".data": "application/octet-stream",
};
const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://localhost");
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("X-Content-Type-Options", "nosniff");
    // A production build may have written an AWS URL. Local play always uses this server.
    if (url.pathname === "/config.js" && ["GET", "HEAD"].includes(req.method)) {
      res.writeHead(200, { "Content-Type": "text/javascript" });
      res.end(
        req.method === "HEAD"
          ? undefined
          : 'window.TINY_CAR_CONFIG = { apiUrl: "/api" };\n',
      );
      return;
    }
    if (url.pathname.startsWith("/api/")) {
      let raw = "";
      for await (const chunk of req) {
        raw += chunk;
        if (raw.length > 8192) {
          res.writeHead(413).end();
          return;
        }
      }
      let body;
      try {
        body = raw ? JSON.parse(raw) : {};
      } catch {
        res
          .writeHead(400, { "Content-Type": "application/json" })
          .end(JSON.stringify({ error: "Invalid JSON." }));
        return;
      }
      const result = await service(
        req.method,
        url.pathname,
        body,
        url.searchParams,
      );
      res
        .writeHead(result.status, { "Content-Type": "application/json" })
        .end(JSON.stringify(result.data));
      return;
    }
    const path = resolve(
      root,
      `.${decodeURIComponent(url.pathname === "/" ? "/index.html" : url.pathname)}`,
    );
    if (!path.startsWith(root + sep) || !["GET", "HEAD"].includes(req.method)) {
      res.writeHead(404).end();
      return;
    }
    const info = await stat(path);
    if (!info.isFile()) {
      res.writeHead(404).end();
      return;
    }
    res.writeHead(200, {
      "Content-Type": mime[extname(path)] || "application/octet-stream",
    });
    res.end(req.method === "HEAD" ? undefined : await readFile(path));
  } catch (error) {
    res
      .writeHead(error.code === "ENOENT" ? 404 : 500)
      .end("Unable to serve this request.");
  }
});
server.listen(
  Number(process.env.PORT || 8081),
  process.env.HOST || "127.0.0.1",
  () =>
    console.log(
      `Tiny Car + score API: http://${process.env.HOST || "127.0.0.1"}:${process.env.PORT || 8081}`,
    ),
);
