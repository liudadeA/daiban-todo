import '../data/store.dart';
import 'dates.dart';
import 'planner.dart';
import 'todo_item.dart';

/// 桌面组件用的纯 Dart 逻辑：构造今日任务快照，以及处理后台勾选 / 刷新。
/// 不依赖 home_widget，便于在 VM 上单测，并与应用内的完成 / 提前语义保持一致。
class WidgetActions {
  static const scheme = 'daiban';

  /// 由任务行内容算出的稳定短 ID（FNV-1a 64），用于组件勾选时找回同一条任务。
  static String idOf(TodoItem t) {
    const offset = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    var h = offset;
    for (final c in t.toLine().codeUnits) {
      h ^= c;
      h = (h * prime) & 0xffffffffffffffff;
    }
    return h.toRadixString(16);
  }

  static Uri completeUri(String id) => Uri(scheme: scheme, host: 'complete', queryParameters: {'id': id});
  static Uri get refreshUri => Uri(scheme: scheme, host: 'refresh');

  static int compareItems(TodoItem a, TodoItem b) {
    final da = a.date, db = b.date;
    if (da != null && db != null && da != db) return da.compareTo(db);
    final pa = a.priority ?? '[', pb = b.priority ?? '[';
    return pa.compareTo(pb);
  }

  /// 与今日页相同的分组：有今日任务（含逾期）或可见无日期任务的类别，按名称排序，未分类靠后。
  static Map<String, dynamic> snapshot(TodoStore store) {
    final today = store.today;
    final groups = Planner.groupByCategory(store.todo);
    final rows = <Map<String, dynamic>>[];
    var count = 0;
    final cats = groups.keys.toList()
      ..sort((a, b) {
        if (a == null || b == null) return a == null ? 1 : -1;
        return a.compareTo(b);
      });
    // 有今日任务的类别排前面
    cats.sort((a, b) {
      bool has(String? c) => groups[c]!.any((t) => Planner.inToday(t, today));
      final ha = has(a), hb = has(b);
      if (ha != hb) return ha ? -1 : 1;
      if (a == null || b == null) return a == null ? 1 : -1;
      return a.compareTo(b);
    });
    for (final cat in cats) {
      final items = groups[cat]!;
      final tset = items.where((t) => Planner.inToday(t, today)).toList()..sort(compareItems);
      final undated = items.where((t) => Planner.undatedVisible(t, today)).toList()..sort(compareItems);
      if (tset.isEmpty && undated.isEmpty) continue;
      rows.add({'type': 'header', 'text': store.categoryLabel(cat)});
      for (final t in [...tset, ...undated]) {
        rows.add({
          'type': 'task',
          'id': idOf(t),
          'text': t.text,
          'category': store.categoryLabel(t.category),
        });
        count++;
      }
    }
    final open = [
      for (final t in store.todo)
        {
          'id': idOf(t),
          'text': t.text,
          'category': store.categoryLabel(t.category),
          'date': t.date == null ? null : Ymd.fmt(t.date!),
          'start': t.start == null ? null : Ymd.fmt(t.start!),
        }
    ];
    return {
      'date': Ymd.fmt(today),
      'count': count,
      'rows': rows,
      'open': open,
    };
  }

  /// 处理后台回调：先按设置做跨日顺延，再按 URI 勾选完成（含按类别提前）。
  /// [uri] 形如 `daiban-basic://complete?id=…` 或 `daiban-basic://refresh`。
  static Future<String?> handle(TodoStore store, Uri? uri) async {
    await store.checkDayChange();
    if (uri == null) return null;
    final action = uri.host;
    if (action == 'complete') {
      final id = uri.queryParameters['id'];
      if (id == null || id.isEmpty) return null;
      for (final t in store.todo) {
        if (idOf(t) == id) return store.complete(t);
      }
    }
    return null;
  }
}
