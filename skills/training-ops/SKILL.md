---
name: training-ops
description: 蒸留学習ジョブの起動・監視・停止の定型。リトライラッパー、三点殺し、クラッシュ後の復旧手順。GPU学習を回す/止める/再開する時に読む。
---

# training-ops

## 起動(リトライラッパー必須)

```bash
OK=0; for attempt in 1 2 3; do
  uv run ime-distill --student max ... >> <log> 2>&1 && { OK=1; break; }
  echo "attempt $attempt failed" >> <log>; sleep 30
done
if [ "$OK" = "1" ]; then echo DONE; else echo FAILED; exit 1; fi
```

- 必ず `run_in_background` + ログはファイルへ。tqdmは `tr '\r' '\n' < log | tail` で読む。
- max系のbatchは 8×5(VRAMヘッドルーム確保。9×4は可、12×3はOOM)。
- 進捗はエポック内で17→8 batch/sに落ちるのが正常(文脈長ソートのバケツ順)。

## 停止(三点殺し)

TaskStopはbashの子孫のpythonを殺さない。必ず3点で:
1. `TaskStop <task-id>`(ラッパー停止)
2. `tasklist //FI "IMAGENAME eq python.exe"` で残存確認 → 残っていればPID kill
3. `nvidia-smi` でVRAM解放確認(≈1GBまで戻ること)

殺し漏れは二重学習事故になる(前科あり)。

## クラッシュ後の復旧

1. Event Viewer: `nvlddmkm`イベントとbugcheck(0x133=ドライバハング系)を確認
2. チェックポイントは各エポック末保存 → `artifacts/students/<name>/` に生きていればそこから継続:
   `--init-from <ep1チェックポイント> --epochs 1 --learning-rate <元LRの半分>`(cosineのepoch 2相当)
3. GPU共有アプリ(Discord等)を疑う。学習中はGPUを触る作業を避ける

## VRAMキャップ(必須・2026-08-16確立)

- **すべての学習に `WARABI_VRAM_FRACTION=0.875`(=14GB)を付ける**。トレーナーが
  `torch.cuda.set_per_process_memory_fraction` を適用する。
- 理由: このマシンはVRAM満杯付近でドライバがシステムRAMへスピルし(Sysmem Fallback)、
  PCIe帯域で窒息 → 「バッチ時間の失速 → CUDA unknown error/BSOD」を起こす。
  歴代クラッシュ(v6b BSOD、std×2、deep-mid)は全部この機構。温度は無関係だった(62℃で死亡)。
- キャップの効果は二重: ①死線に近づかない(超過は回復可能なOOM例外になる)
  ②スピルが消えて**スループット~3.5倍**(deep-min実測 10.4→36.2 batch/s)。
- OOMが出たらバッチを縮める(実効バッチはaccumで維持: 24×2→16×3→12×4→10×5)。
  8行バッチまで落とすとGPUが遊んで逆に遅い — 縮める前にまずキャップ下で計測し直す。
