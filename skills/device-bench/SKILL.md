---
name: device-bench
description: Android実機でエンジン/モデルの変換レイテンシを測る手順。adbのパス罠、クロスビルド、ort/burnベンチ。実機性能を測る時に読む。
---

# device-bench

## 罠(先に読む)

- **adbはPowerShellから叩く**。Git Bashは `/data/local/tmp` をWindowsパスに変換して壊す
  (成功表示でもリモートに届いていないことがある。`adb shell ls` で必ず実在確認)。
- adb.exeがbad_allocで死んだら `adb kill-server; adb start-server`。

## エンジンCLIのクロスビルド

```bash
ANDROID_NDK_HOME="$LOCALAPPDATA/Android/Sdk/ndk/28.2.13676358" \
  cargo ndk -t arm64-v8a build --release -p ime-cli --features ime-cli/reranker
```

push先: `/data/local/tmp/`(chmod +x を忘れない)。辞書sqliteとモデルdirもpush。

## 計測

```powershell
$in = @("家に|かえる", "..."); $in -join "`n" |
  adb shell "cd /data/local/tmp && ./ime-cli repl dictionary.sqlite3 <model> 5" |
  Select-String "ms\)"
```

- 同一入力の連打で「初回コスト」と「定常コスト」を分離する。
- ortベンチ(純forward)は scratchpad の ort-bench 相当: ort 2.0.0-rc系はORT本体>=1.28のAAR必須、
  `load-dynamic` + `ORT_DYLIB_PATH`、ndarrayはortの要求版に合わせる。
  プロセス終了時のmutex abortは既知・無害。

## UI自動化の掟(PoCアプリをadbで操作する時)

- **座標の決め打ち禁止**。レイアウトはキーボード表示・ローディング画面・アセット展開で毎回ズレる。
  タップ前に必ず `adb shell uiautomator dump` → 対象テキストのboundsを解決 → 中心を**整数で**タップ
  (PowerShellの `/2` はDoubleを返し `input tap 788.5` は黙って失敗する — [math]::Floor必須)。
- **タップごとに遷移検証**。次のdumpに期待テキスト(設定なら「モデル」、適用後なら「model=」)が
  無ければその時点で失敗として中断。検証なしの連打は「成功したように見えて人間が介助していた」
  事故を起こす(2026-08-15の教訓)。
- テキスト入力先の確認は `focused="true"` を持つEditTextのboundsで行う。値の帰属は
  XMLの並び順ではなくboundsで判定する。

## QNN(Hexagon HTP)の記録(2026-08-15時点)

- 配管一式はある: ort qnn feature+EP登録(QNN_BACKEND_PATH/ADSP_LIBRARY_PATH)、静的形状エクスポート
  (--static-shape)、QDQ量子化(ime_context_tools.training.quantize_reranker)、ランタイムは
  C:\Users\yuki\ime-archive\ort-qnn(2.49と2.38)。
- 結果: ロード+パリティは常に通るが実行が秒級(fp16=26s、w8a16=52s、a8w8@2.49=2.3s)。
  グラフの大半がHTPに載っていない。再開するならQNN EPの with_profiling でノード単位の
  配置を取るところから。CPU(max 0.55s)に勝てるまで製品には載せない。

## 基準値(Galaxy S24 / SD8Gen3, lite 5.3M, 32候補)

ort CPU 54ms(seq40)/ 407ms(seq224)。candle CPU ~500ms。burn wgpu ~6.2s(要最適化)。
