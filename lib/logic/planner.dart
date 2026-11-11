import 'dates.dart';
import 'todo_item.dart';

/// 日期顺延 / 提前逻辑（纯函数，直接修改传入的 item，便于单元测试）。
class Planner {
  /// 未完成且（没有开始日期 或 开始日期 <= [day]）
  static bool visibleOn(TodoItem t, DateTime day) =>
      !t.done && (t.start == null || !t.start!.isAfter(day));

  /// “今日任务”：可见 且 有日期 且 日期 <= 今天（含逾期）
  static bool inToday(TodoItem t, DateTime today) {
    final d = t.date;
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

  /// “完成即提前”：如果今日任务（今天 + 逾期）已全部完成，
  /// 找到下一个日期批次 N，把日期 >= N 的所有未完成任务 due/t 各 -(N - 今天) 天，
  /// 使下一批出现在今天。返回提前的天数（0 表示没有变化）。
  /// [force] 为 true 时（手动“提前下一批”）即使今天还有未完成任务也提前。
  static int pullForward(List<TodoItem> items, DateTime today, {bool force = false}) {
    final todayEmpty = !items.any((t) => inToday(t, today));
    if (!force && !todayEmpty) return 0;
    DateTime? next;
    for (final t in items) {
      final d = t.date;
      if (t.done || d == null || !d.isAfter(today)) continue;
      if (next == null || d.isBefore(next)) next = d;
    }
    if (next == null) return 0;
    final gap = Ymd.diff(next, today);
    // 今日已清空时的提前才记录（可由“取消完成”还原）；今天还有任务时的手动强制提前不记录。
    final seq = todayEmpty ? _nextSeq(items, today) : null;
    for (final t in items) {
      final d = t.date;
      if (!t.done && d != null && !d.isBefore(next)) {
        t.shift(-gap);
        if (seq != null) t.addPull(today, seq, gap);
      }
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

  /// 还原“完成即提前”：只要今天的任务里同时存在“原本就是今天的未完成任务”（没有今日提前记录）
  /// 和“被提前过来的任务”，就把最近一次提前整体还原（被平移的任务各自回到原日期），
  /// 必要时连续还原多次，直到今日里不再同时有两种任务。返回还原的次数。
  /// 只处理 [category]（null = 未分类）的任务，只还原今天做的提前。
  static int revertPulls(List<TodoItem> items, DateTime today, String? category) {
    var n = 0;
    for (var guard = 0; guard < 50; guard++) {
      final group = items.where((t) => !t.done && t.category == category).toList();
      final todays = group.where((t) => inToday(t, today)).toList();
      final hasOriginal = todays.any((t) => !t.pulledOn(today));
      final hasPulled = todays.any((t) => t.pulledOn(today));
      if (!hasOriginal || !hasPulled) break;
      var latest = 0;
      for (final t in group) {
        final l = t.pulls;
        if (l.isNotEmpty && l.last.day == today && l.last.seq > latest) latest = l.last.seq;
      }
      if (latest == 0) break;
      for (final t in group) {
        final l = t.pulls;
        if (l.isNotEmpty && l.last.day == today && l.last.seq == latest) {
          final r = t.popPull()!;
          t.shift(r.gap);
        }
      }
      n++;
    }
    return n;
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
