package dev.warabi.poc

import android.os.Bundle
import android.system.Os
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.ime_ffi.Candidate
import uniffi.ime_ffi.Ime
import java.io.File

/** Bundled assets are extracted once; sqlite and ort need real file paths. */
private fun installAssets(activity: ComponentActivity, report: (String) -> Unit): File {
    val root = File(activity.filesDir, "warabi")
    // Re-extract when the APK changes: model updates keep identical file
    // sizes (same architecture), so only the install timestamp is reliable.
    val stamp = File(root, ".apk-stamp")
    val installedAt = activity.packageManager
        .getPackageInfo(activity.packageName, 0).lastUpdateTime.toString()
    if (stamp.takeIf { it.isFile }?.readText() != installedAt) {
        val names = listOf(
            "dictionary.sqlite3", "model/model.onnx",
            "model/ime_reranker.json", "model/parity_cases.json", "model/vocab.txt",
        )
        for (name in names) {
            report("展開中: $name")
            val target = File(root, name)
            target.parentFile?.mkdirs()
            activity.assets.open(name).use { input ->
                target.outputStream().use { input.copyTo(it, 1 shl 20) }
            }
        }
        stamp.writeText(installedAt)
    }
    return root
}

class MainActivity : ComponentActivity() {
    private val status = MutableStateFlow("初期化中…")
    private val engines = HashMap<Boolean, Ime>() // key: kaomoji included

    private fun engine(root: File, kaomoji: Boolean): Ime = synchronized(engines) {
        engines.getOrPut(kaomoji) {
            val dictionary = File(root, "dictionary.sqlite3").path
            val model = File(root, "model").path
            if (kaomoji) Ime(dictionary, model) else Ime.newNoKaomoji(dictionary, model)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // ort is built with load-dynamic; point it at the bundled runtime
        // before the first session is created.
        Os.setenv("ORT_DYLIB_PATH", "${applicationInfo.nativeLibraryDir}/libonnxruntime.so", true)
        setContent { MaterialTheme { Screen() } }
    }

    @Composable
    private fun Screen() {
        var ready by remember { mutableStateOf<File?>(null) }
        val statusText by status.collectAsState()
        LaunchedEffect(Unit) {
            withContext(Dispatchers.IO) {
                val root = installAssets(this@MainActivity) { status.value = it }
                status.value = "モデル読み込み中…(パリティ検証込み)"
                engine(root, true)
                ready = root
            }
        }
        val root = ready
        if (root == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator()
                    Spacer(Modifier.height(16.dp))
                    Text(statusText)
                }
            }
        } else {
            Converter(root)
        }
    }

    @Composable
    private fun Converter(root: File) {
        var context by remember { mutableStateOf("") }
        var rawReading by remember { mutableStateOf("") }
        var kaomoji by remember { mutableStateOf(true) }
        var limit by remember { mutableStateOf(10) }
        var reading by remember { mutableStateOf("") }
        var candidates by remember { mutableStateOf(listOf<Candidate>()) }
        var elapsedMs by remember { mutableStateOf<Long?>(null) }
        var backend by remember { mutableStateOf("") }
        var rebuilding by remember { mutableStateOf(false) }
        val scope = rememberCoroutineScope()

        LaunchedEffect(context, rawReading, kaomoji, limit) {
            withContext(Dispatchers.Default) {
                rebuilding = !synchronized(engines) { engines.containsKey(kaomoji) }
                val ime = engine(root, kaomoji)
                rebuilding = false
                backend = ime.backendName()
                val hira = ime.romajiToKana(rawReading)
                val result: List<Candidate>
                val startedAt = System.nanoTime()
                result = if (hira.isBlank()) emptyList()
                         else ime.convert(hira, context, limit.toUInt())
                val elapsed = (System.nanoTime() - startedAt) / 1_000_000
                withContext(Dispatchers.Main) {
                    reading = hira
                    candidates = result
                    elapsedMs = if (hira.isBlank()) null else elapsed
                }
            }
        }

        Column(Modifier.fillMaxSize().padding(16.dp)) {
            Text("Warabi PoC", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = context, onValueChange = { context = it },
                label = { Text("文脈(確定済みテキスト)") },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = rawReading, onValueChange = { rawReading = it },
                label = { Text("読み(かな/ローマ字)") },
                supportingText = { if (reading.isNotBlank()) Text("正規化: $reading") },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = kaomoji, onCheckedChange = { kaomoji = it })
                Text("顔文字", Modifier.padding(start = 4.dp, end = 16.dp))
                Text("候補数 $limit")
                Slider(
                    value = limit.toFloat(), onValueChange = { limit = it.toInt() },
                    valueRange = 3f..32f, modifier = Modifier.width(160.dp),
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                val timing = elapsedMs?.let { "${it}ms" } ?: "—"
                Text(
                    "backend=$backend  変換 $timing" + if (rebuilding) "  (辞書再読込中…)" else "",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Spacer(Modifier.height(8.dp))
            LazyColumn(Modifier.weight(1f)) {
                items(candidates) { candidate ->
                    ListItem(
                        modifier = Modifier.clickable {
                            context += candidate.text
                            rawReading = ""
                        },
                        headlineContent = { Text(candidate.text) },
                        supportingContent = {
                            val score = candidate.blendedScore?.let {
                                "blend=%.3f".format(it)
                            } ?: "cost=${candidate.searchCost}"
                            Text("${candidate.kind}  $score", fontFamily = FontFamily.Monospace)
                        },
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}
