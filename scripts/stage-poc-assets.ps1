# Stage the PoC app's native libs and bundled assets (not in git: 500MB).
# Prereqs: cargo ndk build done (see below), ORT >=1.28 Android AAR extracted.
#   cd engine; $env:ANDROID_NDK_HOME="$env:LOCALAPPDATA/Android/Sdk/ndk/28.2.13676358"
#   cargo ndk -t arm64-v8a build --release -p ime-ffi --features ime-ffi/reranker
param(
    # QNN-enabled ORT build (also serves CPU); QNN backend libs ride along.
    [string]$OrtQnnDir = "$env:USERPROFILE\ime-archive\ort-qnn"
)
$root = Split-Path $PSScriptRoot -Parent
$app = "$root\apps\warabi-poc-android\app"

New-Item -ItemType Directory -Force "$app\src\main\jniLibs\arm64-v8a" | Out-Null
Copy-Item "$root\engine\target\aarch64-linux-android\release\libime_ffi.so" "$app\src\main\jniLibs\arm64-v8a\"
Copy-Item "$OrtQnnDir\extracted\jni\arm64-v8a\libonnxruntime.so" "$app\src\main\jniLibs\arm64-v8a\"
foreach ($qnn in "libQnnSystem.so", "libQnnHtp.so", "libQnnHtpPrepare.so",
                 "libQnnHtpV75Skel.so", "libQnnHtpV75Stub.so") {
    Copy-Item "$OrtQnnDir\qnn-rt\jni\arm64-v8a\$qnn" "$app\src\main\jniLibs\arm64-v8a\"
}

if (Test-Path "$app\assets-staging\model") { Remove-Item -Recurse -Force "$app\assets-staging\model" -Confirm:$false }
$stage = @{
    "$app\assets-staging\dictionary.sqlite3" = "$root\data\dictionary-core\dictionary.sqlite3"
}
# Every present tier ships in the APK; absent tiers (e.g. std before its
# gate) are simply skipped and the app enumerates what it finds.
$tiers = @{
    max  = "$root\models\reranker-v2-max"
    std  = "$root\models\reranker-v2-std"
    lite = "$root\models\reranker-v2-lite"
    # comparison builds (internal iterations; PoC app only, never published)
    "max-v7"  = "$root\tools\artifacts\exports\max-v7"
    "max-qnn" = "$root\tools\artifacts\exports\max-qnn"
}
foreach ($tier in $tiers.GetEnumerator()) {
    if (-not (Test-Path $tier.Value)) { continue }
    New-Item -ItemType Directory -Force "$app\assets-staging\models\$($tier.Key)" | Out-Null
    foreach ($f in "model.onnx", "ime_reranker.json", "vocab.txt", "parity_cases.json") {
        $stage["$app\assets-staging\models\$($tier.Key)\$f"] = "$($tier.Value)\$f"
    }
}
foreach ($entry in $stage.GetEnumerator()) {
    if (Test-Path $entry.Key) { Remove-Item $entry.Key -Force -Confirm:$false }
    New-Item -ItemType HardLink -Path $entry.Key -Target $entry.Value | Out-Null
}
Write-Output "staged: jniLibs + assets (hardlinked, no disk cost)"
