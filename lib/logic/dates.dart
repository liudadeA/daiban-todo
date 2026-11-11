/// 纯日期（无时分秒）工具，统一使用 UTC 零点，避免夏令时 / 时区问题。
class Ymd {
  static DateTime of(int y, int m, int d) => DateTime.utc(y, m, d);

  static DateTime fromDateTime(DateTime t) => DateTime.utc(t.year, t.month, t.day);

  static DateTime add(DateTime d, int days) =>
      DateTime.utc(d.year, d.month, d.day + days);

  /// a - b 的天数
  static int diff(DateTime a, DateTime b) => fromDateTime(a).difference(fromDateTime(b)).inDays;

  static final _re = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// 严格解析 YYYY-MM-DD；非法日期（如 2026-02-31）返回 null。
  static DateTime? parse(String s) {
    final m = _re.firstMatch(s);
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    final dt = DateTime.utc(y, mo, d);
    if (dt.year != y || dt.month != mo || dt.day != d) return null;
    return dt;
  }

  static String fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  static String weekday(DateTime d) => weekdays[d.weekday - 1];

  /// 解析相对日期：today/tomorrow/今天/明天/后天/3d/+3d/2w；无法识别返回 null。
  static DateTime? parseRelative(String s, DateTime today) {
    final v = s.trim().toLowerCase();
    switch (v) {
      case 'today':
      case '今天':
        return today;
      case 'tomorrow':
      case '明天':
        return add(today, 1);
      case 'yesterday':
      case '昨天':
        return add(today, -1);
      case '后天':
        return add(today, 2);
    }
    final m = RegExp(r'^\+?(\d+)([dw])$').firstMatch(v);
    if (m != null) {
      final n = int.parse(m[1]!) * (m[2] == 'w' ? 7 : 1);
      return add(today, n);
    }
    return null;
  }
}
