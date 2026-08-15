// Static server with cross-origin isolation (threaded wasm) and model
// staging via the workspace's exported model dirs.
//   node serve.mjs   →  http://localhost:8380
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join } from "node:path";

const ROOT = import.meta.dirname;
const MODELS = {
  lite: "D:/keyNako/models/reranker-v2-lite",
  max: "D:/keyNako/models/reranker-v2-max",
};
const TYPES = {
  ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript",
  ".wasm": "application/wasm", ".json": "application/json",
  ".txt": "text/plain", ".onnx": "application/octet-stream",
};

createServer(async (request, response) => {
  let url = decodeURIComponent(request.url.split("?")[0]);
  if (url === "/") url = "/index.html";
  const model = url.match(/^\/models\/([^/]+)\/(.+)$/);
  const path = model ? join(MODELS[model[1]] ?? "", model[2]) : join(ROOT, url);
  try {
    const body = await readFile(path);
    response.writeHead(200, {
      "Content-Type": TYPES[extname(path)] ?? "application/octet-stream",
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    });
    response.end(body);
  } catch {
    response.writeHead(404).end("not found");
  }
}).listen(8380, () => console.log("http://localhost:8380"));
