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

- メジャー(リポ名: warabi-reranker-v1 / v2-*)= 入力契約の断絶(v1=MeCabサブワード、v2=文字レベル8k)。
- 契約が変わらない品質更新は同一リポ内で更新。内部イテレーション番号は外に出さない。
- tier: lite(CPU/モバイル)/ standard / max(品質上限・カスケード教師)。

## 実行時定数

- model_candidate_count = 32(学習リストと一致。recall@32 = 100%)
- blend = `ai_logit - w * calibrated_cost / 1000`
- 辞書: 全エントリ保持。kaomoji列(0/1)で顔文字を分離
  (格子は合成にkaomoji不参加、読み全体一致・予測は参加)。

## 評価

- 旧基準(locked-276等)はリセット済み、`data/context-dataset` に legacy として封印予定。
- 新基準は文節世代(v7)で設計: 同音異義語ベンチ・文節読み分布・汚染管理を一級市民に。
