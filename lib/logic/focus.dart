import 'dates.dart';

/// 一条专注记录（正向计时的一次开始→结束）。
class FocusSession {
  static const forward = 'forward';
  static const countdown = 'countdown';

  final String id;
  final String? category;
  final DateTime start;
  final DateTime end;
  final bool interrupted;

  /// [forward] = 正向计时；[countdown] = 锁屏倒计时
  final String kind;

  const FocusSession({
    required this.id,
    required this.category,
    required this.start,
    required this.end,
    required this.interrupted,
    this.kind = forward,
  });

  bool get isCountdown => kind == countdown;

  int get seconds {
    final n = end.difference(start).inSeconds;
    return n < 0 ? 0 : n;
  }

  DateTime get startDay => Ymd.fromDateTime(start);

  Map<String, Object?> toJson() => {
        'id': id,
        'category': category,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'interrupted': interrupted,
        'kind': kind,
      };

  static FocusSession? fromJson(Map<String, dynamic> m) {
    final id = m['id']?.toString();
    final startMs = m['start'];
    final endMs = m['end'];
    if (id == null || startMs is! int || endMs is! int) return null;
    return FocusSession(
      id: id,
      category: m['category'] as String?,
      start: DateTime.fromMillisecondsSinceEpoch(startMs),
      end: DateTime.fromMillisecondsSinceEpoch(endMs),
      interrupted: m['interrupted'] == true,
      kind: m['kind'] == countdown ? countdown : forward,
    );
  }
}

/// 某段时间内一个类别的合计。
class FocusSlice {
  final String? category;
  final int seconds;
  final int count;
  const FocusSlice(this.category, this.seconds, this.count);

  double shareOf(int total) => total <= 0 ? 0 : seconds / total;
}

/// 某段时间的汇总。
class PeriodStats {
  final int count;
  final int seconds;
  final int interrupted; // 其中锁屏倒计时被中断的次数（正向计时的退出不算）
  final List<FocusSlice> slices; // 按时长降序
  const PeriodStats({required this.count, required this.seconds, required this.slices, this.interrupted = 0});

  static const empty = PeriodStats(count: 0, seconds: 0, slices: []);
  bool get isEmpty => count == 0 && seconds == 0;
}

/// 专注统计（纯函数）。次数和时长都记在开始那一天；时段分布按实际跨越的小时拆分。
class FocusCalc {
  /// 0 秒 →「0分钟」；不足 1 分钟 →「N秒」；不足 1 小时 →「N分钟」；否则「H小时」或「H小时M分钟」。
  static String fmtDuration(int seconds) {
    if (seconds < 0) seconds = 0;
    if (seconds == 0) return '0分钟';
    if (seconds < 60) return '$seconds秒';
    if (seconds < 3600) return '${seconds ~/ 60}分钟';
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
    return m == 0 ? '$h小时' : '$h小时$m分钟';
  }

  /// 正向计时显示：HH:MM:SS（小时可超过 99）。
  static String fmtClock(int seconds) {
    if (seconds < 0) seconds = 0;
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  static PeriodStats of(Iterable<FocusSession> all, {bool Function(FocusSession s)? where}) {
    final list = where == null ? all.toList() : all.where(where).toList();
    if (list.isEmpty) return PeriodStats.empty;
    final map = <String?, ({int sec, int n})>{};
    var total = 0;
    for (final s in list) {
      total += s.seconds;
      final cur = map[s.category] ?? (sec: 0, n: 0);
      map[s.category] = (sec: cur.sec + s.seconds, n: cur.n + 1);
    }
    final slices = map.entries.map((e) => FocusSlice(e.key, e.value.sec, e.value.n)).toList()
      ..sort((a, b) => b.seconds != a.seconds ? b.seconds.compareTo(a.seconds) : (a.category ?? '').compareTo(b.category ?? ''));
    return PeriodStats(
        count: list.length, seconds: total, slices: slices, interrupted: list.where((e) => e.interrupted && e.isCountdown).length);
  }

  static PeriodStats all(Iterable<FocusSession> s) => of(s);

  static PeriodStats forDay(Iterable<FocusSession> s, DateTime day) {
    final d = Ymd.fromDateTime(day);
    return of(s, where: (e) => e.startDay == d);
  }

  /// 一周从周一开始，到周日结束。
  static PeriodStats forWeek(Iterable<FocusSession> s, DateTime anyDay) {
    final r = weekRange(anyDay);
    return forRange(s, r.$1, r.$2);
  }

  static PeriodStats forMonth(Iterable<FocusSession> s, DateTime anyDay) {
    final r = monthRange(anyDay);
    return forRange(s, r.$1, r.$2);
  }

  /// [from] 和 [to] 均为闭区间的日历日。
  static PeriodStats forRange(Iterable<FocusSession> s, DateTime from, DateTime to) {
    final a = Ymd.fromDateTime(from), b = Ymd.fromDateTime(to);
    return of(s, where: (e) {
      final d = e.startDay;
      return !d.isBefore(a) && !d.isAfter(b);
    });
  }

  static (DateTime, DateTime) weekRange(DateTime anyDay) {
    final d = Ymd.fromDateTime(anyDay);
    final mon = Ymd.add(d, 1 - d.weekday);
    return (mon, Ymd.add(mon, 6));
  }

  static (DateTime, DateTime) monthRange(DateTime anyDay) {
    final d = Ymd.fromDateTime(anyDay);
    final first = DateTime.utc(d.year, d.month, 1);
    final last = DateTime.utc(d.year, d.month + 1, 0);
    return (first, last);
  }

  /// 日均时长 = 总时长 ÷ 有过专注记录的日历天数；没有记录则为 0。
  static int averageDailySeconds(Iterable<FocusSession> s) {
    final days = <DateTime>{};
    var total = 0;
    for (final e in s) {
      days.add(e.startDay);
      total += e.seconds;
    }
    if (days.isEmpty) return 0;
    return total ~/ days.length;
  }

  /// 某月按小时（0–23）累计的秒数。跨小时 / 跨日的记录按实际重叠拆分；不属于该月的部分不计。
  static List<int> hourDistribution(Iterable<FocusSession> sessions, int year, int month) {
    final hours = List<int>.filled(24, 0);
    DateTime hourStart(DateTime t) => t.isUtc
        ? DateTime.utc(t.year, t.month, t.day, t.hour)
        : DateTime(t.year, t.month, t.day, t.hour);
    for (final s in sessions) {
      var t = s.start;
      final end = s.end;
      if (!t.isBefore(end)) continue;
      while (t.isBefore(end)) {
        final sliceEnd = hourStart(t).add(const Duration(hours: 1)).isBefore(end)
            ? hourStart(t).add(const Duration(hours: 1))
            : end;
        if (t.year == year && t.month == month) {
          hours[t.hour] += sliceEnd.difference(t).inSeconds;
        }
        t = sliceEnd;
      }
    }
    return hours;
  }
}

/// 类别配色（同一名称始终同色，与主题无关）。
class FocusColors {
  static const palette = <ColorValue>[
    ColorValue(0xFFE89AAE),
    ColorValue(0xFF5BB3AE),
    ColorValue(0xFFF2C14E),
    ColorValue(0xFF7BA3E3),
    ColorValue(0xFFC7A0D4),
    ColorValue(0xFF8FCB7D),
    ColorValue(0xFFE08A5A),
    ColorValue(0xFF6B8F71),
    ColorValue(0xFFD47BA0),
    ColorValue(0xFF5C8A9A),
  ];
  static const uncategorized = ColorValue(0xFF9AA3AE);

  static ColorValue of(String? category) {
    if (category == null || category.isEmpty) return uncategorized;
    var h = 0;
    for (final c in category.codeUnits) {
      h = 0x1fffffff & (h * 31 + c);
    }
    return palette[h % palette.length];
  }
}

/// 不依赖 Flutter 的 ARGB 颜色，UI 层再转成 Color。
class ColorValue {
  final int argb;
  const ColorValue(this.argb);
}
