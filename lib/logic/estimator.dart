import 'dates.dart';
import 'todo_item.dart';

/// 某个类别的进度与预计完成时间（纯函数，仅应用内显示，桌面组件不使用）。
///
/// 按“量”来算，不看速度：
///  * 每条任务有一个原计划日期（隐藏标签 plan:，不受“完成即提前 / 整体顺延”改写 due/t 的影响）。
///  * 把同一原计划日期的任务看作“一天的量”。某天的任务全部完成，这一天才算完成；只完成一部分不算。
///  * 提前天数 = 原计划日期在今天之后、且已全部完成的天数
///              − 原计划日期在今天之前、但还没全部完成的天数（落后）。
///  * 预计完成 = 原计划最后一天 − 提前天数（落后时为 + 落后天数）。
class CategoryEstimate {
  final String? category;
  final int open; // 剩余未完成
  final int done; // 已完成（done.txt）
  final DateTime? planDate; // 计划完成：原计划的最后一天（含已完成的）
  final DateTime? estDate; // 预计完成 = 计划完成 − 净提前天数
  final int earlyDays; // 提前完成的整天数（计划日在今天之后且全部完成）
  final int lateDays; // 落后的整天数（计划日在今天之前但没做完）

  const CategoryEstimate({
    required this.category,
    required this.open,
    required this.done,
    required this.planDate,
    required this.estDate,
    required this.earlyDays,
    required this.lateDays,
  });

  int get total => open + done;
  double get progress => total == 0 ? 0 : done / total;
  bool get finished => open == 0 && done > 0;
  bool get hasEstimate => estDate != null;

  /// 相对计划：正数 = 提前 N 天，负数 = 落后 N 天，0 = 持平（无计划日期时为 null）
  int? get aheadDays => planDate == null ? null : earlyDays - lateDays;
}

class Estimator {
  /// 按类别（null = 未分类）计算。只统计出现过的类别。
  static Map<String?, CategoryEstimate> all(Iterable<TodoItem> todo, Iterable<TodoItem> done, DateTime today) {
    final cats = <String?>{...todo.map((e) => e.category), ...done.map((e) => e.category)};
    return {for (final c in cats) c: forCategory(todo, done, today, c)};
  }

  static CategoryEstimate forCategory(Iterable<TodoItem> todo, Iterable<TodoItem> done, DateTime today, String? cat) {
    final open = todo.where((t) => !t.done && t.category == cat).toList();
    final doneItems = done.where((t) => t.done && t.category == cat).toList();

    // 原计划日期 → 这一天的任务是否已全部完成
    final dayDone = <DateTime, bool>{};
    for (final t in [...open, ...doneItems]) {
      final d = t.planOrDate;
      if (d == null) continue; // 无日期任务不构成“一天的量”
      dayDone[d] = (dayDone[d] ?? true) && t.done;
    }

    DateTime? plan;
    var early = 0, late = 0;
    dayDone.forEach((d, allDone) {
      if (plan == null || d.isAfter(plan!)) plan = d;
      if (d.isAfter(today) && allDone) early++;
      if (d.isBefore(today) && !allDone) late++;
    });

    return CategoryEstimate(
      category: cat,
      open: open.length,
      done: doneItems.length,
      planDate: plan,
      estDate: plan == null ? null : Ymd.add(plan!, late - early),
      earlyDays: early,
      lateDays: late,
    );
  }

  static String _md(DateTime d) => '${d.month}月${d.day}日';

  static String _rel(DateTime d, DateTime today) {
    final r = Ymd.relative(d, today);
    return r == null || r.startsWith('逾期') || r == '昨日' ? _md(d) : '${_md(d)}（$r）';
  }

  static String aheadText(int? ahead) {
    if (ahead == null) return '';
    if (ahead > 0) return '提前 $ahead 天';
    if (ahead < 0) return '落后 ${-ahead} 天';
    return '与计划持平';
  }

  /// 紧凑一行（今日页类别标题下）：进度 · 计划 · 预计（提前/落后）。
  static String compact(CategoryEstimate e, DateTime today) {
    if (e.finished) return '已全部完成 ${e.done}/${e.total}';
    final parts = <String>['进度 ${e.done}/${e.total}'];
    if (e.planDate != null && e.estDate != null) {
      parts.add('计划 ${_md(e.planDate!)}');
      parts.add('预计 ${_md(e.estDate!)}（${aheadText(e.aheadDays)}）');
    }
    return parts.join(' · ');
  }

  /// 多行说明（类别管理页）。
  static List<String> detail(CategoryEstimate e, DateTime today) {
    final out = <String>['待办 ${e.open} · 已完成 ${e.done} · 进度 ${(e.progress * 100).round()}%'];
    if (e.finished) return out;
    if (e.planDate != null && e.estDate != null) {
      out.add('计划完成 ${_rel(e.planDate!, today)}');
      final basis = <String>[];
      if (e.earlyDays > 0) basis.add('已提前完成 ${e.earlyDays} 天的量');
      if (e.lateDays > 0) basis.add('有 ${e.lateDays} 天的量未完成');
      out.add('预计完成 ${_rel(e.estDate!, today)}，${aheadText(e.aheadDays)}'
          '${basis.isEmpty ? '' : '（${basis.join('，')}）'}');
    }
    return out;
  }
}
