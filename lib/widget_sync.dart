import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/store.dart';
import 'logic/widget_actions.dart';

const widgetProviderName = 'TodayWidgetProvider';
const widgetProviderQualified = 'cn.daiban.daiban.TodayWidgetProvider';

/// 把今日任务快照写给桌面组件，并请求刷新。测试环境下不调用。
Future<void> syncTodayWidget(TodoStore store) async {
  if (kIsWeb) return;
  try {
    if (!Platform.isAndroid) return;
  } catch (_) {
    return;
  }
  try {
    final payload = WidgetActions.snapshot(store);
    await HomeWidget.saveWidgetData<String>('today_json', jsonEncode(payload));
    await HomeWidget.updateWidget(
      name: widgetProviderName,
      androidName: widgetProviderName,
      qualifiedAndroidName: widgetProviderQualified,
    );
  } catch (e, st) {
    debugPrint('syncTodayWidget: $e\n$st');
  }
}

/// 组件勾选 / 跨日刷新时由 home_widget 在后台 isolate 调用。必须与 [main] 里注册的是同一个顶层函数。
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // 后台 isolate 会长期复用，必须先重读，否则看不到主界面写入的“上次处理日期”和各开关，
  // 会重复顺延或用过期设置。
  await prefs.reload();
  final dir = await getApplicationDocumentsDirectory();
  final store = TodoStore(dir: dir, prefs: prefs);
  await store.load();
  await WidgetActions.handle(store, uri);
  await syncTodayWidget(store);
}
