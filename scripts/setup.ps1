# keyNako workspace setup: submodules + local tooling checks.
$ErrorActionPreference = "Stop"

git submodule update --init --recursive

# HF private repos need git credentials for huggingface.co.
# One-time: hf auth login (or store a write token via git credential approve).

Write-Host "engine build:  cd engine; cargo build --release -p ime-cli --features ime-cli/reranker"
Write-Host "tools env:     cd tools; uv sync"

# skills -> .claude/skills junctions (machine-local)
New-Item -ItemType Directory -Force .claude\skills | Out-Null
Get-ChildItem skills -Directory | ForEach-Object { if (-not (Test-Path ".claude\skills\$($_.Name)")) { New-Item -ItemType Junction -Path ".claude\skills\$($_.Name)" -Target $_.FullName | Out-Null } }
