# Stage the PoC app's native libs and bundled assets (not in git: 500MB).
# Prereqs: cargo ndk build done (see below), ORT >=1.28 Android AAR extracted.
#   cd engine; $env:ANDROID_NDK_HOME="$env:LOCALAPPDATA/Android/Sdk/ndk/28.2.13676358"
#   cargo ndk -t arm64-v8a build --release -p ime-ffi --features ime-ffi/reranker
param(
    [string]$OrtSo = "$env:USERPROFILE\ime-archive\libonnxruntime.so"
)
$root = Split-Path $PSScriptRoot -Parent
$app = "$root\apps\warabi-poc-android\app"

New-Item -ItemType Directory -Force "$app\src\main\jniLibs\arm64-v8a" | Out-Null
Copy-Item "$root\engine\target\aarch64-linux-android\release\libime_ffi.so" "$app\src\main\jniLibs\arm64-v8a\"
Copy-Item $OrtSo "$app\src\main\jniLibs\arm64-v8a\"

New-Item -ItemType Directory -Force "$app\assets-staging\model" | Out-Null
$stage = @{
    "$app\assets-staging\dictionary.sqlite3" = "$root\data\dictionary-core\dictionary.sqlite3"
}
foreach ($f in "model.onnx", "ime_reranker.json", "vocab.txt", "parity_cases.json") {
    $stage["$app\assets-staging\model\$f"] = "$root\models\reranker-v2-lite\$f"
}
foreach ($entry in $stage.GetEnumerator()) {
    if (Test-Path $entry.Key) { Remove-Item $entry.Key -Force -Confirm:$false }
    New-Item -ItemType HardLink -Path $entry.Key -Target $entry.Value | Out-Null
}
Write-Output "staged: jniLibs + assets (hardlinked, no disk cost)"
