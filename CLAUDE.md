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
- 認定: max系=v8(38/39)、lite系=lite-v8(dev 84.03%、ブレンド85.99%、36/39、実機33ms)。
  models/reranker-v2-{max,lite} に未コミットで配置済み。
- **tier実験の判定**(詳細は docs/research-log.md): 深さ>幅、教師信号の質が最安レバー。
  総合王者は deep-lite-b(6L×256、7.9M、dev 85.20%、ブレンド87.27%、36/39)→ v9で正式tier化検討。
  現std(4L×512)は廃止候補。QNNは凍結(HTP非ネイティブ実行、タスク#25に再開手順)。
- Android PoC完成(apps/warabi-poc-android): 実機動作、モデル/バックエンド切替UI付き、
  lite-v8で32〜41ms/変換@S24。アセットは scripts/stage-poc-assets.ps1(gitには入れない)。
- 次: ①新評価基準の設計(#19) ②v9 tier再編(細く深く) ③Web展開調査(#26)。
- 旧 D:\ime: ime-context-tools(17GB)は削除済み(貴重物は C:\Users\yuki\ime-archive に退避)。
  残り~1GBはユーザー判断待ち。
