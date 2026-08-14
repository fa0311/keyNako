# keyNako

KeyNako IME(製品)/ Warabi Engine(変換エンジン)。構成は README.md、設計は docs/architecture.md。

## 原則(ユーザー指示)

- 安全寄りに倒さず綺麗なお作法で書く。防御的ハックより正しい設計。
- ドキュメント・READMEは簡潔に。数式は `clamp(...)` 風のコード表記。
- コミット: **Co-Authored-Byなし、GPG署名(-S)**。離席中のみ無署名可、復帰時に署名し直し。
- マイニングした固有名詞データは**評価専用、学習に使わない**(名前は辞書とパーソナライズの担当)。
- モデルの欠陥は蒸留データで直す。スコア融合アルゴリズムはいじらない。
- 内部イテレーション番号(v6b等)は外部に露出させない。
- 重要手順は skills/ にスキル化(.claude/skills へはジャンクション、setup.ps1が再生成)。

## 技術決定

- 学習=torch(tools)、推論=ONNX Runtime(全プラットフォーム統一)。Burn実装はwarabi-engine初回コミットに封印。
- model_candidate_count=32(学習リストと一致)。エンジン契約=ひらがな入力・正規化しない。
- 辞書は全エントリ保持・kaomoji列で顔文字分離(格子合成には不参加)。
- 評価基準はリセット済み。新基準はv7(文節世代)で設計。

## 状態(2026-08-14時点)

- **ort移行完了**: OrtReranker(パリティゲート内蔵)+ONNXエクスポータ、Burn削除済み。
  v6b(ort)=同音異義語ベンチ39/39、デスクトップCPU 113〜149ms/変換。ビルドは `engine/target`(target-dirリダイレクト廃止)。
- v8(語彙世代)完成: vocab 16,384(漢字全部入り・顔文字98%可視・絵文字97.5%、コードポイント順)。
  ime-extend-vocab の恒等拡張(drift 0)→継続学習。dev top1 83.16%、ブレンド86.03%(w=0.05)、
  同音異義語38/39(詠む/読むのノイズ差1件)、アトラクタプローブ11/14(v7比+1)。
- 認定: max系=v8、lite系=lite-v7(dev 83.59%、ブレンド85.75%、同音異義語32/39)。
  models/reranker-v2-{max,lite} に未コミットで配置済み。
- Android PoC完成(apps/warabi-poc-android): 実機動作、lite搭載、82ms/変換@S24。
  アセットは scripts/stage-poc-assets.ps1 でステージング(gitには入れない)。
- 次: ①新評価基準の設計(アトラクタ14/qualitativeプローブを種に) ②std容量診断の判定 ③lite-v8。
- 旧 D:\ime は移行残作業(キャッシュ再生成レシピの確認)後に削除予定。
