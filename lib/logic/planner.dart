import 'dates.dart';
import 'todo_item.dart';

/// 日期顺延 / 提前逻辑（纯函数，直接修改传入的 item，便于单元测试）。
class Planner {
  /// 未完成且（没有开始日期 或 开始日期 <= [day]）
  static bool visibleOn(TodoItem t, DateTime day) =>
      !t.done && (t.visibleEarlyOn(day) || t.start == null || !t.start!.isAfter(day));

  /// “今日任务”：可见 且 有日期 且 日期 <= 今天（含逾期）
  static bool inToday(TodoItem t, DateTime today) {
    final d = t.displayDate;
    return visibleOn(t, today) && d != null && !d.isAfter(today);
  }

  /// 今日视图里的无日期任务（可见即显示，但不参与“全部完成”的判断）
  static bool undatedVisible(TodoItem t, DateTime today) =>
      visibleOn(t, today) && t.date == null;

  static List<TodoItem> todaySet(Iterable<TodoItem> items, DateTime today) =>
      items.where((t) => inToday(t, today)).toList();

  /// 日切“整体顺延”：从 [lastProcessed] 当天开始，到 [today] 前一天为止，
  /// 逐天检查——如果那一天结束时仍有未完成的任务（日期 <= 那天），
  /// 则把日期晚于那天的所有未完成任务 due/t 各 +1 天。
  /// 返回实际顺延的天数（0 表示没有任务被移动）。
  static int shiftBack(List<TodoItem> items, DateTime lastProcessed, DateTime today,
      {int maxDays = 366}) {
    var from = lastProcessed;
    if (Ymd.diff(today, from) > maxDays) from = Ymd.add(today, -maxDays);
    var shifted = 0;
    for (var d = from; d.isBefore(today); d = Ymd.add(d, 1)) {
      final hasUnfinished = items.any((t) {
        final dt = t.date;
        return visibleOn(t, d) && dt != null && !dt.isAfter(d);
      });
      if (!hasUnfinished) continue;
      var moved = false;
      for (final t in items) {
        final dt = t.date;
        if (!t.done && dt != null && dt.isAfter(d)) {
          t.shift(1);
          moved = true;
        }
      }
      if (moved) shifted++;
    }
    return shifted;
  }

  /// 只让下一日期批次提前显示，保留所有任务的 due/t 和后续批次日期。
  /// 返回显示提前的间隔；force 允许今日尚未清空时手动再显示一批。
  static int pullForward(List<TodoItem> items, DateTime today, {bool force = false}) {
    for (final t in items) { t.migrateLegacyPulls(); }
    if (!force && items.any((t) => inToday(t, today))) return 0;
    DateTime? next;
    for (final t in items) {
      final d = t.date;
      if (t.done || d == null || !d.isAfter(today) || inToday(t, today)) continue;
      if (next == null || d.isBefore(next)) next = d;
    }
    if (next == null) return 0;
    final gap = Ymd.diff(next, today);
    final seq = _nextSeq(items, today);
    for (final t in items) {
      if (!t.done && t.date == next && !inToday(t, today)) t.addPull(today, seq, gap);
    }
    return gap;
  }

  static int _nextSeq(List<TodoItem> items, DateTime today) {
    var m = 0;
    for (final t in items) {
      for (final r in t.pulls) {
        if (r.day == today && r.seq > m) m = r.seq;
      }
    }
    return m + 1;
  }

  /// 取消完成后，撤回同类中更晚批次的“提前显示”，不修改任何任务日期。
  /// 已提前完成又取消的任务保留自身 pv，作为锚点；只撤回其后的批次。
  static int revertPulls(List<TodoItem> items, DateTime today, String? category) {
    final group = items.where((t) => !t.done && t.category == category).toList();
    for (final t in group) { t.migrateLegacyPulls(); }
    final todays = group.where((t) => inToday(t, today)).toList();
    if (todays.isEmpty) return 0;
    int batch(TodoItem t) => t.pulledOn(today) ? t.pulls.last.seq : 0;
    final earliest = todays.map(batch).reduce((a, b) => a < b ? a : b);
    final removed = <int>{};
    for (final t in group) {
      while (t.pulledOn(today) && t.pulls.last.seq > earliest) {
        removed.add(t.popPull()!.seq);
      }
    }
    return removed.length;
  }

  /// 按类别分组（保持原顺序）。key 为 null 表示“未分类”。
  static Map<String?, List<TodoItem>> groupByCategory(Iterable<TodoItem> items) {
    final m = <String?, List<TodoItem>>{};
    for (final t in items) {
      m.putIfAbsent(t.category, () => []).add(t);
    }
    return m;
  }

  /// 分类别的“整体顺延”：每个类别独立判断“昨天是否有该类别的未完成任务”，
  /// 只顺延该类别自己的后续任务。[enabled] 决定某类别是否参与。
  /// 返回 类别 → 顺延天数（仅包含实际有任务被移动的类别）。
  static Map<String?, int> shiftBackByCategory(List<TodoItem> items, DateTime lastProcessed, DateTime today,
      {bool Function(String? category)? enabled}) {
    final out = <String?, int>{};
    groupByCategory(items).forEach((cat, group) {
      if (enabled != null && !enabled(cat)) return;
      final n = shiftBack(group, lastProcessed, today);
      if (n > 0) out[cat] = n;
    });
    return out;
  }

  /// 分类别的“完成即提前”：只看 [category] 的任务（null = 未分类）。
  static int pullForwardCategory(List<TodoItem> items, DateTime today, String? category,
      {bool force = false}) {
    final group = items.where((t) => t.category == category).toList();
    return pullForward(group, today, force: force);
  }
}
