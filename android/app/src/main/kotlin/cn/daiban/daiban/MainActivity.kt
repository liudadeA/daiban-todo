package cn.daiban.daiban

import android.app.ActivityManager
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** 接收「分享 / 用…打开」的 todo.txt 文本，并交给 Flutter 导入；屏幕固定与分享走 daiban/pin。 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pinChannel: MethodChannel? = null
    private var pendingText: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private var watchingPin = false
    private var sawPinned = false
    private val pinWatch = object : Runnable {
        override fun run() {
            if (!watchingPin) return
            val pinned = isPinned()
            if (pinned) {
                sawPinned = true
            } else if (sawPinned) {
                sawPinned = false
                pinChannel?.invokeMethod("onPinState", false)
                stopWatch()
                return
            }
            handler.postDelayed(this, 400)
        }
    }

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
        pinChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "daiban/pin")
        pinChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "startPin" -> {
                    try {
                        startLockTask()
                        sawPinned = isPinned()
                        startWatch()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "stopPin" -> {
                    stopWatch()
                    sawPinned = false
                    try {
                        stopLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "isPinned" -> result.success(isPinned())
                "setKeepScreenOn" -> {
                    val on = call.arguments as Boolean
                    if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                "share" -> {
                    val text = (call.arguments as? Map<*, *>)?.get("text") as? String ?: ""
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    startActivity(Intent.createChooser(send, "分享"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startWatch() {
        if (watchingPin) return
        watchingPin = true
        handler.postDelayed(pinWatch, 400)
    }

    private fun stopWatch() {
        watchingPin = false
        handler.removeCallbacks(pinWatch)
    }

    private fun isPinned(): Boolean {
        val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        return am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
    }

    override fun onDestroy() {
        stopWatch()
        super.onDestroy()
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
