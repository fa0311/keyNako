package dev.warabi.poc

import android.os.Bundle
import android.system.Os
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import uniffi.ime_ffi.Candidate
import uniffi.ime_ffi.Ime
import java.io.File

/** Engine configuration selected on the settings page. */
data class EngineConfig(
    val model: String,
    val backend: String,
    val kaomoji: Boolean,
)

private val BACKENDS = listOf("cpu", "nnapi", "xnnpack")

/** Bundled assets are extracted once per APK install (models keep identical
 *  sizes across versions, so only the install timestamp is reliable). */
private fun installAssets(activity: ComponentActivity, report: (String) -> Unit): File {
    val root = File(activity.filesDir, "warabi")
    val stamp = File(root, ".apk-stamp")
    val installedAt = activity.packageManager
        .getPackageInfo(activity.packageName, 0).lastUpdateTime.toString()
    if (stamp.takeIf { it.isFile }?.readText() != installedAt) {
        val names = mutableListOf("dictionary.sqlite3")
        for (model in activity.assets.list("models").orEmpty()) {
            for (file in activity.assets.list("models/$model").orEmpty()) {
                names += "models/$model/$file"
            }
        }
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
    private val engines = HashMap<EngineConfig, Ime>()

    private fun engine(root: File, config: EngineConfig): Ime = synchronized(engines) {
        engines.getOrPut(config) {
            Ime.newWith(
                File(root, "dictionary.sqlite3").path,
                File(root, "models/${config.model}").path,
                !config.kaomoji,
                config.backend,
            )
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
        var models by remember { mutableStateOf(listOf<String>()) }
        val statusText by status.collectAsState()
        LaunchedEffect(Unit) {
            withContext(Dispatchers.IO) {
                val root = installAssets(this@MainActivity) { status.value = it }
                models = assets.list("models").orEmpty().sorted()
                ready = root
            }
        }
        val root = ready
        if (root == null) {
            Loading(statusText)
        } else {
            App(root, models)
        }
    }

    @Composable
    private fun Loading(message: String) {
        Box(Modifier.fillMaxSize().safeDrawingPadding(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator()
                Spacer(Modifier.height(16.dp))
                Text(message)
            }
        }
    }

    @Composable
    private fun App(root: File, models: List<String>) {
        var config by remember {
            mutableStateOf(EngineConfig(models.firstOrNull() ?: "lite", "cpu", kaomoji = true))
        }
        var active by remember { mutableStateOf<Ime?>(null) }
        var loadError by remember { mutableStateOf<String?>(null) }
        var showSettings by remember { mutableStateOf(false) }
        var applying by remember { mutableStateOf(false) }

        LaunchedEffect(config) {
            applying = true
            loadError = null
            withContext(Dispatchers.IO) {
                try {
                    val ime = engine(root, config)
                    withContext(Dispatchers.Main) { active = ime }
                } catch (error: Exception) {
                    withContext(Dispatchers.Main) {
                        loadError = error.message ?: error.toString()
                    }
                }
            }
            applying = false
        }

        when {
            applying -> Loading("エンジン構築中… (${config.model} / ${config.backend})")
            showSettings -> Settings(
                models = models,
                current = config,
                error = loadError,
                onApply = { selected ->
                    showSettings = false
                    config = selected  // triggers the LaunchedEffect rebuild
                },
                onBack = { showSettings = false },
            )
            else -> Converter(
                ime = active,
                config = config,
                error = loadError,
                onOpenSettings = { showSettings = true },
            )
        }
    }

    @Composable
    private fun Settings(
        models: List<String>,
        current: EngineConfig,
        error: String?,
        onApply: (EngineConfig) -> Unit,
        onBack: () -> Unit,
    ) {
        var model by remember { mutableStateOf(current.model) }
        var backend by remember { mutableStateOf(current.backend) }
        var kaomoji by remember { mutableStateOf(current.kaomoji) }

        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp)) {
            Text("設定", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(16.dp))

            Text("モデル", style = MaterialTheme.typography.titleMedium)
            models.forEach { name ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().clickable { model = name },
                ) {
                    RadioButton(selected = model == name, onClick = { model = name })
                    Text(name)
                }
            }
            Spacer(Modifier.height(16.dp))

            Text("バックエンド", style = MaterialTheme.typography.titleMedium)
            BACKENDS.forEach { name ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().clickable { backend = name },
                ) {
                    RadioButton(selected = backend == name, onClick = { backend = name })
                    Text(name.uppercase())
                }
            }
            Spacer(Modifier.height(16.dp))

            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = kaomoji, onCheckedChange = { kaomoji = it })
                Text("顔文字を含める", Modifier.padding(start = 8.dp))
            }
            if (error != null) {
                Spacer(Modifier.height(8.dp))
                Text("エラー: $error", color = MaterialTheme.colorScheme.error)
            }
            Spacer(Modifier.weight(1f))

            Row {
                OutlinedButton(onClick = onBack, modifier = Modifier.weight(1f)) { Text("戻る") }
                Spacer(Modifier.width(12.dp))
                Button(
                    onClick = { onApply(EngineConfig(model, backend, kaomoji)) },
                    modifier = Modifier.weight(1f),
                ) { Text("決定") }
            }
        }
    }

    @Composable
    private fun Converter(
        ime: Ime?,
        config: EngineConfig,
        error: String?,
        onOpenSettings: () -> Unit,
    ) {
        var context by remember { mutableStateOf("") }
        var rawReading by remember { mutableStateOf("") }
        var limit by remember { mutableStateOf(10) }
        var reading by remember { mutableStateOf("") }
        var candidates by remember { mutableStateOf(listOf<Candidate>()) }
        var elapsedMs by remember { mutableStateOf<Long?>(null) }

        LaunchedEffect(ime, context, rawReading, limit) {
            if (ime == null) return@LaunchedEffect
            withContext(Dispatchers.Default) {
                val hira = ime.romajiToKana(rawReading)
                val startedAt = System.nanoTime()
                val result = if (hira.isBlank()) emptyList()
                             else ime.convert(hira, context, limit.toUInt())
                val elapsed = (System.nanoTime() - startedAt) / 1_000_000
                withContext(Dispatchers.Main) {
                    reading = hira
                    candidates = result
                    elapsedMs = if (hira.isBlank()) null else elapsed
                }
            }
        }

        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Warabi PoC", style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.weight(1f))
                IconButton(onClick = onOpenSettings) {
                    Icon(Icons.Filled.Settings, contentDescription = "設定")
                }
            }
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
                Text("候補数 $limit")
                Slider(
                    value = limit.toFloat(), onValueChange = { limit = it.toInt() },
                    valueRange = 3f..32f, modifier = Modifier.width(180.dp),
                )
            }
            val backendLabel = ime?.backendName() ?: "未ロード"
            val timing = elapsedMs?.let { "${it}ms" } ?: "—"
            Text(
                "model=${config.model}  backend=$backendLabel  変換 $timing",
                style = MaterialTheme.typography.bodySmall,
            )
            if (error != null) {
                Text("エラー: $error", color = MaterialTheme.colorScheme.error)
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
