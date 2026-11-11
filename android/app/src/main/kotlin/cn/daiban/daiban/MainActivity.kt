package cn.daiban.daiban

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** 接收「分享 / 用…打开」的 todo.txt 文本，并交给 Flutter 导入。 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "daiban/intent")
        channel!!.setMethodCallHandler { call, result ->
            if (call.method == "getInitialText") {
                val t = pendingText ?: extractText(intent)
                pendingText = null
                result.success(t)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val t = extractText(intent)
        if (t != null) channel?.invokeMethod("onText", t)
    }

    private fun extractText(i: Intent?): String? {
        if (i == null) return null
        try {
            when (i.action) {
                Intent.ACTION_SEND -> {
                    val txt = i.getStringExtra(Intent.EXTRA_TEXT)
                    if (txt != null) return txt
                    @Suppress("DEPRECATION")
                    val uri = i.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                    return if (uri != null) readUri(uri) else null
                }
                Intent.ACTION_VIEW -> {
                    val uri = i.data
                    return if (uri != null) readUri(uri) else null
                }
            }
        } catch (e: Exception) {
            return null
        }
        return null
    }

    private fun readUri(uri: Uri): String? =
        contentResolver.openInputStream(uri)?.use { String(it.readBytes(), Charsets.UTF_8) }
}
