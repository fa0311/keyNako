// WASM latency probe (node; the browser wasm engine is the same core).
//   node bench.mjs <modelDir> [runs]
import { readFileSync } from "node:fs";
import { argv } from "node:process";
import * as ort from "onnxruntime-web";
import { loadVocab, encodeTriple, batchTensors } from "./tokenizer.mjs";

const modelDir = argv[2];
const runs = Number(argv[3] ?? 20);
const vocab = loadVocab(readFileSync(`${modelDir}/vocab.txt`, "utf-8"));
const meta = JSON.parse(readFileSync(`${modelDir}/ime_reranker.json`, "utf-8"));

const session = await ort.InferenceSession.create(
  new Uint8Array(readFileSync(`${modelDir}/model.onnx`)).buffer,
  { executionProviders: ["wasm"] },
);

const candidates = [
  "帰る", "変える", "代える", "替える", "換える", "返る", "還る", "孵る",
  "蛙", "カエル", "かえる", "買える", "飼える", "帰える", "却る", "反る",
  "帰るか", "変えるか", "帰ると", "変えると", "帰るの", "変えるの", "帰るが",
  "変えるが", "帰るよ", "変えるよ", "帰るね", "変えるね", "帰るし", "変えるし",
  "帰るぞ", "変えるぞ",
];
const sequences = candidates.map((candidate) =>
  encodeTriple(vocab, "家に", "かえる", candidate, meta.max_length, meta.context_chars),
);
const { ids, mask, batch, width } = batchTensors(sequences);
const feed = {
  input_ids: new ort.Tensor("int64", ids, [batch, width]),
  attention_mask: new ort.Tensor("int64", mask, [batch, width]),
};

for (let i = 0; i < 3; i++) await session.run(feed);
const times = [];
for (let i = 0; i < runs; i++) {
  const start = performance.now();
  await session.run(feed);
  times.push(performance.now() - start);
}
times.sort((a, b) => a - b);
console.log(JSON.stringify({
  model: modelDir, batch, width,
  mean_ms: +(times.reduce((a, b) => a + b) / times.length).toFixed(1),
  p50_ms: +times[Math.floor(times.length / 2)].toFixed(1),
  min_ms: +times[0].toFixed(1),
}));
