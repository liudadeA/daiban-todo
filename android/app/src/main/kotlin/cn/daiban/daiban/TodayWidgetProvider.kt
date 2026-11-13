package cn.daiban.daiban

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * 「待办 · 今日」桌面组件：展示今日未完成任务，勾选框在后台调用 Dart 完成逻辑，
 * 点标题打开应用。列表数据来自 Flutter 写入的 today_json（HomeWidgetPreferences）。
 */
class TodayWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val today = todayYmd()
        val (rows, count, emptyMessage) = resolveRows(widgetData, today)
        // 把解析后的行再写回，供 RemoteViewsFactory 直接读取（避免工厂里再做日期判断不一致）
        widgetData.edit().putString(KEY_RENDER_JSON, rowsToJson(rows, count, emptyMessage)).apply()

        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.today_widget)
            views.setTextViewText(R.id.widget_title, context.getString(R.string.widget_title))
            if (count > 0) {
                views.setTextViewText(R.id.widget_count, "${count} 项")
                views.setViewVisibility(R.id.widget_list, android.view.View.VISIBLE)
                views.setViewVisibility(R.id.widget_empty, android.view.View.GONE)
            } else {
                views.setTextViewText(R.id.widget_count, "")
                views.setTextViewText(R.id.widget_empty, emptyMessage)
                views.setViewVisibility(R.id.widget_list, android.view.View.GONE)
                views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
            }

            val launch = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            views.setOnClickPendingIntent(R.id.widget_header, launch)
            views.setOnClickPendingIntent(R.id.widget_title, launch)
            views.setOnClickPendingIntent(R.id.widget_empty, launch)

            val svc = Intent(context, TodayWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                data = Uri.parse("content://${context.packageName}.todaywidget/$id")
            }
            views.setRemoteAdapter(R.id.widget_list, svc)
            views.setEmptyView(R.id.widget_list, R.id.widget_empty)

            // 列表项必须用可变的 PendingIntent 模板，才能填入每条任务的 id。
            val template = Intent(context, TodayWidgetProvider::class.java).apply {
                action = ACTION_COMPLETE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                data = Uri.parse("content://${context.packageName}.todaywidget/click/$id")
            }
            views.setPendingIntentTemplate(R.id.widget_list, pendingBroadcast(context, template, REQ_TEMPLATE, mutable = true))

            appWidgetManager.updateAppWidget(id, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(id, R.id.widget_list)
        }
        scheduleMidnight(context)
        if (needsDartRefresh(widgetData, today)) {
            startBackground(context, "daiban-basic://refresh")
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        scheduleMidnight(context)
        startBackground(context, "daiban-basic://refresh")
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        cancelMidnight(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_COMPLETE -> {
                val id = intent.getStringExtra(EXTRA_TASK_ID)
                if (!id.isNullOrEmpty()) {
                    startBackground(context, "daiban-basic://complete?id=${Uri.encode(id)}")
                }
            }
            ACTION_MIDNIGHT, Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_DATE_CHANGED -> {
                scheduleMidnight(context)
                startBackground(context, "daiban-basic://refresh")
                requestUpdate(context)
            }
            else -> super.onReceive(context, intent)
        }
    }

    companion object {
        const val ACTION_COMPLETE = "cn.daiban.daiban.basic.widget.COMPLETE"
        const val ACTION_MIDNIGHT = "cn.daiban.daiban.basic.widget.MIDNIGHT"
        const val EXTRA_TASK_ID = "task_id"
        const val KEY_TODAY_JSON = "today_json"
        const val KEY_RENDER_JSON = "today_render_json"
        private const val REQ_TEMPLATE = 100
        private const val REQ_MIDNIGHT = 101
        private const val BACKGROUND_ACTION = "es.antonborri.home_widget.action.BACKGROUND"

        fun pendingBroadcast(context: Context, intent: Intent, requestCode: Int, mutable: Boolean): PendingIntent {
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            flags = if (mutable) {
                if (Build.VERSION.SDK_INT >= 31) flags or PendingIntent.FLAG_MUTABLE else flags
            } else {
                if (Build.VERSION.SDK_INT >= 23) flags or PendingIntent.FLAG_IMMUTABLE else flags
            }
            return PendingIntent.getBroadcast(context, requestCode, intent, flags)
        }

        fun startBackground(context: Context, uri: String) {
            val i = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
                action = BACKGROUND_ACTION
                data = Uri.parse(uri)
            }
            context.sendBroadcast(i)
        }

        fun requestUpdate(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val cn = ComponentName(context, TodayWidgetProvider::class.java)
            val ids = mgr.getAppWidgetIds(cn)
            if (ids.isEmpty()) return
            val i = Intent(context, TodayWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(i)
        }

        fun todayYmd(): String {
            val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            // 与 Dart Ymd 一样按本地日历日（设备时区）
            fmt.timeZone = TimeZone.getDefault()
            return fmt.format(Date())
        }

        fun needsDartRefresh(prefs: SharedPreferences, today: String): Boolean {
            val raw = prefs.getString(KEY_TODAY_JSON, null) ?: return true
            return try {
                JSONObject(raw).optString("date") != today
            } catch (_: Exception) {
                true
            }
        }

        fun resolveRows(prefs: SharedPreferences, today: String): Triple<List<WidgetRow>, Int, String> {
            val raw = prefs.getString(KEY_TODAY_JSON, null)
            if (raw.isNullOrBlank()) return Triple(emptyList(), 0, "今日暂无任务")
            return try {
                val obj = JSONObject(raw)
                if (obj.optString("date") == today) {
                    val rows = parseRows(obj.optJSONArray("rows"))
                    val count = obj.optInt("count", rows.count { it.type == "task" })
                    val msg = if (count == 0) "今日已完成 🎉" else ""
                    Triple(rows, count, msg)
                } else {
                    rebuildFromOpen(obj.optJSONArray("open"), today)
                }
            } catch (_: Exception) {
                Triple(emptyList(), 0, "今日暂无任务")
            }
        }

        private fun rebuildFromOpen(open: JSONArray?, today: String): Triple<List<WidgetRow>, Int, String> {
            if (open == null) return Triple(emptyList(), 0, "今日已完成 🎉")
            data class Item(val id: String, val text: String, val category: String)
            val byCat = linkedMapOf<String, MutableList<Item>>()
            for (i in 0 until open.length()) {
                val o = open.optJSONObject(i) ?: continue
                val date = if (o.isNull("date")) null else o.optString("date").ifBlank { null }
                val start = if (o.isNull("start")) null else o.optString("start").ifBlank { null }
                val visible = start == null || start <= today
                val inToday = visible && date != null && date <= today
                val undated = visible && date == null
                if (!inToday && !undated) continue
                val cat = o.optString("category").ifBlank { "未分类" }
                byCat.getOrPut(cat) { mutableListOf() }.add(
                    Item(o.optString("id"), o.optString("text"), cat)
                )
            }
            val rows = mutableListOf<WidgetRow>()
            var count = 0
            for ((cat, items) in byCat) {
                rows.add(WidgetRow("header", null, cat))
                for (it in items) {
                    rows.add(WidgetRow("task", it.id, it.text))
                    count++
                }
            }
            val msg = if (count == 0) "今日已完成 🎉" else ""
            return Triple(rows, count, msg)
        }

        fun parseRows(arr: JSONArray?): List<WidgetRow> {
            if (arr == null) return emptyList()
            val out = mutableListOf<WidgetRow>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                out.add(WidgetRow(o.optString("type"), o.optString("id").ifBlank { null }, o.optString("text")))
            }
            return out
        }

        fun rowsToJson(rows: List<WidgetRow>, count: Int, empty: String): String {
            val arr = JSONArray()
            for (r in rows) {
                arr.put(JSONObject().put("type", r.type).put("id", r.id ?: "").put("text", r.text))
            }
            return JSONObject().put("count", count).put("empty", empty).put("rows", arr).toString()
        }

        private fun midnightIntent(context: Context): PendingIntent {
            val i = Intent(context, TodayWidgetProvider::class.java).apply { action = ACTION_MIDNIGHT }
            return pendingBroadcast(context, i, REQ_MIDNIGHT, mutable = false)
        }

        fun scheduleMidnight(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val cal = Calendar.getInstance()
            cal.add(Calendar.DAY_OF_MONTH, 1)
            cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 1)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            val pi = midnightIntent(context)
            if (Build.VERSION.SDK_INT >= 23) {
                am.setAndAllowWhileIdle(AlarmManager.RTC, cal.timeInMillis, pi)
            } else {
                am.set(AlarmManager.RTC, cal.timeInMillis, pi)
            }
        }

        fun cancelMidnight(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(midnightIntent(context))
        }
    }
}

data class WidgetRow(val type: String, val id: String?, val text: String)
