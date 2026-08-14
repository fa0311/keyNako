# アーキテクチャ

## 全体

```
[torch 学習 (tools)] → safetensors + ONNX エクスポート → [HF models/*]
                                                            ↓ 実行時DL or 同梱
[warabi-engine (Rust)] 格子・辞書(sqlite) + ort推論(全プラットフォーム統一)
    → UniFFI (Kotlin/Swift/Python) + C-ABI → apps/
```

- 推論は ONNX Runtime に統一(実測: lite 32候補で 実機CPU 54ms / デスクトップCPU 12.5ms)。
  Burn実装は warabi-engine の初回コミットに封印(履歴から復元可)。
- エンジン契約: ひらがなを受け取り漢字を返す。正規化・ローマ字はフロントエンドの責務
  (`normalize_reading` / `romaji_to_hiragana` ヘルパは提供)。

## モデル命名

- メジャー(リポ名: warabi-reranker-v1 / v2-*)= 入力契約の断絶(v1=MeCabサブワード、v2=文字レベル)。
- 契約が変わらない品質更新は同一リポ内で更新。内部イテレーション番号は外に出さない。
- tier: lite(CPU/モバイル)/ standard / max(品質上限・カスケード教師)。

## 文字語彙(vocab)

- 1文字=1トークン、正規化なし、空白dropのみ。並びはコードポイント順(idはモデルに無意味、人間の監査性を優先)。
- 選定規則: ①かな+ASCII(読みは絶対UNK不可)②頻出記号・顔文字構成字・頻出絵文字 ③残枠すべて漢字(辞書+コーパス頻度順。辞書に無い漢字は候補に出ないので保証不要)。
- 拡張は `ime-extend-vocab`: 旧語彙∪追加をコードポイント順に再配列し embedding 行を同置換で追従、新行は[UNK]行コピー(厳密な恒等変換、ゲートで検証)。既存重みを壊さず継続学習で新文字を教える。
- 絵文字同士の順位はモデルに判別させず辞書コスト(将来パーソナライズ)が担う。vocabの役目は文脈読解と「候補が場に合うか」の判定まで。

## 実行時定数

- model_candidate_count = 32(学習リストと一致。recall@32 = 100%)
- blend = `ai_logit - w * calibrated_cost / 1000`
- 辞書: 全エントリ保持。kaomoji列(0/1)で顔文字を分離
  (格子は合成にkaomoji不参加、読み全体一致・予測は参加)。

## 評価

- 旧基準(locked-276等)はリセット済み、`data/context-dataset` に legacy として封印予定。
- 新基準は文節世代(v7)で設計: 同音異義語ベンチ・文節読み分布・汚染管理を一級市民に。
