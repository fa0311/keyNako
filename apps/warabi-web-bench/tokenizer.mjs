// Character tokenizer — the JS twin of ime-tokenizer's contract:
// no normalization, Unicode-whitespace dropped, [CLS] ctx [SEP] read [SEP]
// cand [SEP], context left-trimmed first, ids from vocab.txt line order.

export function loadVocab(vocabText) {
  const map = new Map();
  vocabText.split("\n").forEach((token, index) => {
    if (token.length > 0) map.set(token, index);
  });
  return map;
}

const WS = /\s/u; // JS \s ⊇ Unicode White_Space for our corpus

function pushChars(ids, vocab, text) {
  for (const ch of text) {
    if (WS.test(ch)) continue;
    ids.push(vocab.get(ch) ?? 1); // [UNK]=1
  }
}

export function encodeTriple(vocab, context, reading, candidate, maxLength, contextChars) {
  const readingChars = [...reading].filter((c) => !WS.test(c));
  const candidateChars = [...candidate].filter((c) => !WS.test(c));
  // context budget: specials(4) + reading + candidate must always fit
  const budget = Math.min(
    contextChars,
    Math.max(0, maxLength - 4 - readingChars.length - candidateChars.length),
  );
  const contextChars_ = [...context].filter((c) => !WS.test(c)).slice(-budget);
  const ids = [2]; // [CLS]
  pushChars(ids, vocab, contextChars_.join(""));
  ids.push(3); // [SEP]
  pushChars(ids, vocab, readingChars.join(""));
  ids.push(3);
  pushChars(ids, vocab, candidateChars.join(""));
  ids.push(3);
  return ids;
}

export function batchTensors(sequences) {
  const batch = sequences.length;
  const width = Math.max(...sequences.map((s) => s.length), 1);
  const ids = new BigInt64Array(batch * width);
  const mask = new BigInt64Array(batch * width);
  sequences.forEach((sequence, row) => {
    sequence.forEach((id, column) => {
      ids[row * width + column] = BigInt(id);
      mask[row * width + column] = 1n;
    });
  });
  return { ids, mask, batch, width };
}
