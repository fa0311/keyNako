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

## 基準値(Galaxy S24 / SD8Gen3, lite 5.3M, 32候補)

ort CPU 54ms(seq40)/ 407ms(seq224)。candle CPU ~500ms。burn wgpu ~6.2s(要最適化)。
