// Node smoke test: JS tokenizer + ort-web(wasm) must reproduce the exported
// parity_cases logits. Passing this means the browser page's encoding path
// is trustworthy before any browser is opened.
//   node smoke.mjs <modelDir>
import { readFileSync } from "node:fs";
import { argv, exit } from "node:process";
import * as ort from "onnxruntime-web";
import { loadVocab, encodeTriple, batchTensors } from "./tokenizer.mjs";

const modelDir = argv[2];
const vocab = loadVocab(readFileSync(`${modelDir}/vocab.txt`, "utf-8"));
const meta = JSON.parse(readFileSync(`${modelDir}/ime_reranker.json`, "utf-8"));
const parity = JSON.parse(readFileSync(`${modelDir}/parity_cases.json`, "utf-8"));

const session = await ort.InferenceSession.create(
  new Uint8Array(readFileSync(`${modelDir}/model.onnx`)).buffer,
  { executionProviders: ["wasm"] },
);

let worst = 0;
for (const c of parity.cases) {
  const ids = encodeTriple(vocab, c.context, c.reading, c.candidate,
                           meta.max_length, meta.context_chars);
  const { ids: idArray, mask, batch, width } = batchTensors([ids]);
  const output = await session.run({
    input_ids: new ort.Tensor("int64", idArray, [batch, width]),
    attention_mask: new ort.Tensor("int64", mask, [batch, width]),
  });
  const logit = output.logits.data[0];
  const drift = Math.abs(logit - c.logit);
  worst = Math.max(worst, drift);
  const tolerance = parity.atol + parity.rtol * Math.abs(c.logit);
  if (drift > tolerance) {
    console.error(`FAIL ${c.candidate}: js ${logit} vs python ${c.logit}`);
    exit(1);
  }
}
console.log(JSON.stringify({ parity: "ok", cases: parity.cases.length, worst_drift: worst }));
