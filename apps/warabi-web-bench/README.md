# warabi-web-bench

ort-web(WASM/WebGPU)でリランカーを計測するベンチページ。#26の第一成果物。

- 準備: `npm install onnxruntime-web` → `dist/` に ort.all.min.js と ort-wasm-simd-threaded* をコピー
- 検証: `node smoke.mjs <モデルdir>`(JSトークナイザ+wasmが parity_cases と一致することを確認)
- Node計測: `node bench.mjs <モデルdir>`
- ブラウザ計測: `node serve.mjs` → http://localhost:8380(COOP/COEP付き=スレッドwasm有効)

実測(2026-08-15、Node wasm、32候補): lite-v8 16.9ms / max-v8 184ms。
