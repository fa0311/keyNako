# keyNako

KeyNako IME — 文脈変換IMEのワークスペース。実体はsubmodule、ここは地図と糊。

## 構成

| パス | リポジトリ | 内容 |
|---|---|---|
| `engine/` | [warabi-engine](https://github.com/fa0311/warabi-engine) | Rust変換エンジン(Warabi)。格子・辞書・ort推論・FFI |
| `tools/` | [warabi-tools](https://github.com/fa0311/warabi-tools) | Python学習(torch)・辞書ビルド・評価 |
| `apps/` | (直入れ) | プラットフォームアプリ・PoC |
| `models/reranker-v2-max` | [HF](https://huggingface.co/fa0311/warabi-reranker-v2-max) | maxモデル(デスクトップGPU級) |
| `models/reranker-v2-lite` | [HF](https://huggingface.co/fa0311/warabi-reranker-v2-lite) | liteモデル(CPU/モバイル) |
| `models/reranker-v1` | HF warabi-reranker-v1 | 蒸留の教師(凍結) |
| `data/` | HF warabi-dictionary-* / warabi-context-dataset | 辞書パック・データセット |
| `skills/` | (直入れ) | 重要手順のランブック(.claude/skills にリンク) |

## セットアップ

```powershell
git clone --recurse-submodules https://github.com/fa0311/keyNako
./scripts/setup.ps1
```

## アーキテクチャ

学習 = torch(Python) → ONNXエクスポート → 推論 = ONNX Runtime(全プラットフォーム統一)。
詳細は `docs/architecture.md`。
