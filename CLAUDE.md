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
- 認定候補: max系=v6b(models/reranker-v2-max に未コミットで配置済み)、lite系=lite-c1(同v2-lite)。
- 次の大仕事: ①v7文節マイニング(タスク#16) ②Android PoC(apps/、文脈+読み入力→候補表示)。
- 旧 D:\ime は移行残作業(キャッシュ再生成レシピの確認)後に削除予定。
