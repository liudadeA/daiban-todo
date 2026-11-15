package cn.daiban.daiban

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "daiban/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppInfo" -> {
                    try {
                        val p = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= 28) p.longVersionCode else p.versionCode.toLong()
                        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"
                        result.success(hashMapOf(
                            "versionName" to (p.versionName ?: ""),
                            "versionCode" to code.toInt(),
                            "abi" to abi,
                        ))
                    } catch (e: Exception) {
                        result.error("app_info", e.message, null)
                    }
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    try {
                        val file = File(path ?: "")
                        val updatesDir = File(cacheDir, "updates").canonicalPath
                        if (path == null || !file.isFile || !file.canonicalPath.startsWith(updatesDir + File.separator)) {
                            result.error("bad_path", "安装包不存在", null)
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()) {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success("needPermission")
                        } else {
                            val uri = FileProvider.getUriForFile(this, "$packageName.shareprovider", file)
                            val install = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(install)
                            result.success("started")
                        }
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
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
