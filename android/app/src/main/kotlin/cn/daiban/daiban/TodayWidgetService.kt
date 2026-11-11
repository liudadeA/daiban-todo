package cn.daiban.daiban

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject

/** 为「待办 · 今日」组件提供可滚动列表行。 */
class TodayWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Factory(applicationContext)
}

private class Factory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private var rows: List<WidgetRow> = emptyList()

    override fun onCreate() = reload()

    override fun onDataSetChanged() = reload()

    override fun onDestroy() {
        rows = emptyList()
    }

    private fun reload() {
        val prefs = HomeWidgetPlugin.getData(context)
        val render = prefs.getString(TodayWidgetProvider.KEY_RENDER_JSON, null)
        rows = if (!render.isNullOrBlank()) {
            try {
                TodayWidgetProvider.parseRows(JSONObject(render).optJSONArray("rows"))
            } catch (_: Exception) {
                emptyList()
            }
        } else {
            TodayWidgetProvider.resolveRows(prefs, TodayWidgetProvider.todayYmd()).first
        }
    }

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews {
        if (position < 0 || position >= rows.size) return getLoadingView()
        val row = rows[position]
        if (row.type == "header") {
            return RemoteViews(context.packageName, R.layout.today_widget_header).apply {
                setTextViewText(R.id.header_text, row.text)
            }
        }
        return RemoteViews(context.packageName, R.layout.today_widget_item).apply {
            setTextViewText(R.id.item_text, row.text)
            val fill = Intent().putExtra(TodayWidgetProvider.EXTRA_TASK_ID, row.id ?: "")
            setOnClickFillInIntent(R.id.item_check, fill)
        }
    }

    override fun getLoadingView(): RemoteViews =
        RemoteViews(context.packageName, R.layout.today_widget_header).apply {
            setTextViewText(R.id.header_text, context.getString(R.string.widget_loading))
        }

    override fun getViewTypeCount(): Int = 2

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
}
