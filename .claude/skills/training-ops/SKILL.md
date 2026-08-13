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
