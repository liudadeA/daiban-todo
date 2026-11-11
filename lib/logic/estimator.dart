import 'dates.dart';
import 'todo_item.dart';

/// 某个类别的进度与预计完成时间（纯函数，仅应用内显示，桌面组件不使用）。
class CategoryEstimate {
  final String? category;
  final int open; // 剩余未完成
  final int done; // 已完成（done.txt）
  final DateTime? planDate; // 计划完成：未完成任务里最晚的 due / t
  final DateTime? estDate; // 预计完成：按近期速度推算；数据不足时为 null
  final double? rate; // 近期平均每天完成数（数据不足时为 null）
  final int? aheadDays; // 相对计划：正数 = 提前 N 天，负数 = 落后 N 天，0 = 持平
  final bool tooFar; // 按速度要一年以上

  const CategoryEstimate({
    required this.category,
    required this.open,
    required this.done,
    required this.planDate,
    required this.estDate,
    required this.rate,
    required this.aheadDays,
    required this.tooFar,
  });

  int get total => open + done;
  double get progress => total == 0 ? 0 : done / total;
  bool get finished => open == 0 && done > 0;
  bool get hasEstimate => estDate != null || tooFar;
}

class Estimator {
  /// 统计最近多少天（含今天）的完成记录
  static const windowDays = 7;

  /// 至少要在几个不同的日子里有完成记录，才认为数据足够推算
  static const minActiveDays = 2;

  /// 预计超过这么多天就不给具体日期
  static const maxDays = 365;

  /// 按类别（null = 未分类）计算。只统计出现过的类别。
  static Map<String?, CategoryEstimate> all(Iterable<TodoItem> todo, Iterable<TodoItem> done, DateTime today) {
    final cats = <String?>{...todo.map((e) => e.category), ...done.map((e) => e.category)};
    return {for (final c in cats) c: forCategory(todo, done, today, c)};
  }

  static CategoryEstimate forCategory(Iterable<TodoItem> todo, Iterable<TodoItem> done, DateTime today, String? cat) {
    final open = todo.where((t) => !t.done && t.category == cat).toList();
    final doneItems = done.where((t) => t.category == cat).toList();

    DateTime? plan;
    for (final t in open) {
      final d = t.date;
      if (d != null && (plan == null || d.isAfter(plan))) plan = d;
    }

    // 近 windowDays 天（含今天）的完成记录
    final from = Ymd.add(today, -(windowDays - 1));
    final days = <DateTime>{};
    var count = 0;
    DateTime? first;
    for (final t in doneItems) {
      final c = t.completionDate;
      if (c == null || c.isBefore(from) || c.isAfter(today)) continue;
      count++;
      days.add(c);
      if (first == null || c.isBefore(first)) first = c;
    }

    double? rate;
    DateTime? est;
    var tooFar = false;
    if (open.isNotEmpty && first != null && days.length >= minActiveDays) {
      final span = Ymd.diff(today, first) + 1; // 从第一次完成到今天，至多 windowDays 天
      rate = count / span;
      final need = (open.length / rate).ceil(); // 需要的天数（今天算第 1 天）
      if (need > maxDays) {
        tooFar = true;
      } else {
        est = Ymd.add(today, need <= 1 ? 0 : need - 1);
      }
    }

    int? ahead;
    if (est != null && plan != null) ahead = Ymd.diff(plan, est);

    return CategoryEstimate(
      category: cat,
      open: open.length,
      done: doneItems.length,
      planDate: plan,
      estDate: est,
      rate: rate,
      aheadDays: ahead,
      tooFar: tooFar,
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
    if (e.planDate != null) parts.add('计划 ${_md(e.planDate!)}');
    if (e.tooFar) {
      parts.add('预计 一年以上');
    } else if (e.estDate != null) {
      final a = aheadText(e.aheadDays);
      parts.add('预计 ${_md(e.estDate!)}${a.isEmpty ? '' : '（$a）'}');
    } else if (e.open > 0) {
      parts.add('预计 数据不足');
    }
    return parts.join(' · ');
  }

  /// 多行说明（类别管理页）。
  static List<String> detail(CategoryEstimate e, DateTime today) {
    final out = <String>['待办 ${e.open} · 已完成 ${e.done} · 进度 ${(e.progress * 100).round()}%'];
    if (e.finished) return out;
    if (e.planDate != null) out.add('计划完成 ${_rel(e.planDate!, today)}');
    if (e.tooFar) {
      out.add('预计完成 一年以上（近 $windowDays 天平均每天完成 ${e.rate!.toStringAsFixed(1)} 项）');
    } else if (e.estDate != null) {
      final a = aheadText(e.aheadDays);
      out.add('预计完成 ${_rel(e.estDate!, today)}${a.isEmpty ? '' : '，$a'}'
          '（近 $windowDays 天平均每天完成 ${e.rate!.toStringAsFixed(1)} 项）');
    } else if (e.open > 0) {
      out.add('预计完成：近 $windowDays 天完成记录不足（至少需要 $minActiveDays 个不同日期），暂以计划日期为准');
    }
    return out;
  }
}
