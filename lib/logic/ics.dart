import 'dates.dart';
import 'plan_splitter.dart';

class IcsEvent {
  final String summary;
  final String description;
  final DateTime start; // 含
  final DateTime end; // 含（已把 DTEND 的“不含”换算好）
  final bool isDaibanTask; // 本应用导出的 .ics：原样导入，不再拆分
  IcsEvent(this.summary, this.description, this.start, this.end, {this.isDaibanTask = false});
}

class IcsCalendar {
  final String name;
  final List<IcsEvent> events;
  IcsCalendar(this.name, this.events);
}

/// 解析 iCalendar：行展开、转义、DATE / DATE-TIME、DTEND 不含、多日事件。
class Ics {
  static bool looksLikeIcs(String text) =>
      RegExp(r'^\s*BEGIN:VCALENDAR', caseSensitive: false).hasMatch(text.replaceFirst('\uFEFF', ''));

  static String unfold(String s) => s.replaceAll(RegExp(r'\r?\n[ \t]'), '');

  static String unescape(String v) {
    final b = StringBuffer();
    for (var i = 0; i < v.length; i++) {
      final c = v[i];
      if (c == r'\' && i + 1 < v.length) {
        final n = v[i + 1];
        if (n == 'n' || n == 'N') {
          b.write('\n');
        } else {
          b.write(n); // \, \; \\ 
        }
        i++;
      } else {
        b.write(c);
      }
    }
    return b.toString();
  }

  static String escape(String v) => v
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n');

  /// [localOffset]：带 Z 的 UTC 时间换算成本地日期时用的偏移（默认取设备时区）。
  static IcsCalendar parse(String text, {Duration? localOffset}) {
    final offset = localOffset ?? DateTime.now().timeZoneOffset;
    final lines = unfold(text.replaceFirst('\uFEFF', '')).split(RegExp(r'\r?\n'));
    var calName = '';
    final events = <IcsEvent>[];
    Map<String, String>? cur;
    Map<String, Map<String, String>> curParams = {};
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final up = line.trim().toUpperCase();
      if (up == 'BEGIN:VEVENT') {
        cur = {};
        curParams = {};
        continue;
      }
      if (up == 'END:VEVENT') {
        if (cur != null) {
          final ev = _build(cur, curParams, offset);
          if (ev != null) events.add(ev);
        }
        cur = null;
        continue;
      }
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final head = line.substring(0, colon);
      final value = line.substring(colon + 1);
      final segs = head.split(';');
      final name = segs.first.toUpperCase();
      final params = <String, String>{};
      for (final p in segs.skip(1)) {
        final eq = p.indexOf('=');
        if (eq > 0) params[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1).toUpperCase();
      }
      if (cur == null) {
        if (name == 'X-WR-CALNAME') calName = unescape(value);
      } else {
        cur.putIfAbsent(name, () => value);
        curParams.putIfAbsent(name, () => params);
      }
    }
    return IcsCalendar(calName, events);
  }

  static DateTime? _date(String v, Map<String, String> params, Duration offset, {required bool isEnd}) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$').firstMatch(v.trim());
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    if (m[4] == null) return DateTime.utc(y, mo, d);
    var dt = DateTime.utc(y, mo, d, int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6] ?? '0'));
    if (m[7] != null) dt = dt.add(offset); // UTC → 本地墙上时间
    return dt;
  }

  static IcsEvent? _build(Map<String, String> p, Map<String, Map<String, String>> params, Duration offset) {
    final ds = p['DTSTART'];
    if (ds == null) return null;
    final start = _date(ds, params['DTSTART'] ?? {}, offset, isEnd: false);
    if (start == null) return null;
    final startDay = DateTime.utc(start.year, start.month, start.day);
    var endDay = startDay;
    final de = p['DTEND'];
    if (de != null) {
      final end = _date(de, params['DTEND'] ?? {}, offset, isEnd: true);
      if (end != null) {
        final allDay = !RegExp(r'T').hasMatch(de) || !RegExp(r'T').hasMatch(ds);
        final endBase = DateTime.utc(end.year, end.month, end.day);
        final midnight = end.hour == 0 && end.minute == 0 && end.second == 0;
        // DTEND 不含：全日事件 / 结束于 00:00 的事件，最后一天要减 1
        endDay = (allDay || midnight) ? Ymd.add(endBase, -1) : endBase;
        if (endDay.isBefore(startDay)) endDay = startDay;
      }
    }
    if (Ymd.diff(endDay, startDay) > 366) endDay = Ymd.add(startDay, 366);
    return IcsEvent(unescape(p['SUMMARY'] ?? '').trim(), unescape(p['DESCRIPTION'] ?? '').trim(), startDay, endDay,
        isDaibanTask: p.containsKey('X-DAIBAN-TASK'));
  }

  /// ICS → todo.txt 行：每个事件的每一天、每个学习条目一行，
  /// 形如 `数据结构 KMP 手算 next/nextval +408 +数据结构 due:2026-11-11 t:2026-11-11`。
  static List<String> toTodoLines(String text, {Duration? localOffset}) {
    final cal = parse(text, localOffset: localOffset);
    final calTag = _calendarTag(cal.name);
    final rows = <MapEntry<DateTime, String>>[];
    for (final ev in cal.events) {
      if (ev.summary.isEmpty && ev.description.isEmpty) continue;
      List<String> texts;
      List<String> extraTags = [];
      if (ev.isDaibanTask) {
        // 本应用导出的 .ics：SUMMARY 是正文，DESCRIPTION 里是 +项目 @情境
        texts = [ev.summary];
        extraTags = ev.description.split(RegExp(r'\s+')).where((t) => t.startsWith('+') || t.startsWith('@')).toList();
      } else {
        texts = PlanSplitter.split(ev.summary.isEmpty ? ev.description : ev.summary,
            ev.summary.isEmpty ? '' : ev.description);
      }
      final subject = ev.summary.split(RegExp(r'\s+')).first;
      for (var d = ev.start; !d.isAfter(ev.end); d = Ymd.add(d, 1)) {
        for (final t in texts) {
          final tags = ev.isDaibanTask
              ? extraTags
              : [
                  if (calTag != null) '+$calTag',
                  if (subject.isNotEmpty && subject != calTag) '+${_safe(subject)}',
                ];
          final ds = Ymd.fmt(d);
          rows.add(MapEntry(d, [_oneLine(t), ...tags, 'due:$ds', 't:$ds'].join(' ')));
        }
      }
    }
    // 按日期稳定排序（保持同一天内的原顺序）
    final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])];
    indexed.sort((a, b) {
      final c = a.$2.key.compareTo(b.$2.key);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return indexed.map((e) => e.$2.value).toList();
  }

  /// 日历名的第一个词，用作导入时默认类别（例如“408 复习计划” → 408）。
  static String? categoryOf(String icsText) => _calendarTag(parse(icsText).name);

  static String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
  static String _safe(String s) => s.replaceAll(RegExp(r'\s+'), '');

  /// 日历名的第一个词当作项目标签，例如“408 复习计划” → 408
  static String? _calendarTag(String name) {
    final t = name.trim().split(RegExp(r'\s+')).first;
    return t.isEmpty ? null : _safe(t);
  }

  // ------------------------------------------------------------ 导出

  /// 把待办导出为 .ics（每个有日期的任务一个全日事件）。
  static String exportTodo(Iterable<({String text, String note, DateTime date, String uid})> tasks,
      {String calName = '待办', DateTime? now}) {
    final stamp = _stamp(now ?? DateTime.now().toUtc());
    final b = StringBuffer();
    void line(String l) {
      b.write(_fold(l));
      b.write('\r\n');
    }

    line('BEGIN:VCALENDAR');
    line('VERSION:2.0');
    line('PRODID:-//daiban//todo//CN');
    line('CALSCALE:GREGORIAN');
    line('X-WR-CALNAME:${escape(calName)}');
    for (final t in tasks) {
      line('BEGIN:VEVENT');
      line('UID:${t.uid}@daiban');
      line('DTSTAMP:$stamp');
      line('DTSTART;VALUE=DATE:${_ymd(t.date)}');
      line('DTEND;VALUE=DATE:${_ymd(Ymd.add(t.date, 1))}');
      line('SUMMARY:${escape(t.text)}');
      if (t.note.isNotEmpty) line('DESCRIPTION:${escape(t.note)}');
      line('TRANSP:TRANSPARENT');
      line('X-DAIBAN-TASK:1');
      line('END:VEVENT');
    }
    line('END:VCALENDAR');
    return b.toString();
  }

  static String _ymd(DateTime d) => Ymd.fmt(d).replaceAll('-', '');
  static String _stamp(DateTime u) =>
      '${_ymd(u)}T${u.hour.toString().padLeft(2, '0')}${u.minute.toString().padLeft(2, '0')}${u.second.toString().padLeft(2, '0')}Z';

  /// RFC 5545：每行不超过 75 字节（按 UTF-8 字节计），续行以空格开头。
  static String _fold(String l) {
    final out = StringBuffer();
    var bytes = 0;
    for (final r in l.runes) {
      final ch = String.fromCharCode(r);
      final n = ch.codeUnitAt(0) < 0x80
          ? 1
          : r < 0x800
              ? 2
              : r < 0x10000
                  ? 3
                  : 4;
      if (bytes + n > 74) {
        out.write('\r\n ');
        bytes = 1;
      }
      out.write(ch);
      bytes += n;
    }
    return out.toString();
  }
}
