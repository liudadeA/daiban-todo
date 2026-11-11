import 'dates.dart';

/// 一条 todo.txt 任务。语义参考 topydo / todo.txt 规范：
///   [x 完成日期] [(A)] [创建日期] 文本 +项目 @情境 key:value ...
/// 其中 due:YYYY-MM-DD 为截止日期，t:YYYY-MM-DD 为开始日期（未到开始日期不在“今日”显示）。
/// 一次“完成即提前”的记录：哪天、第几次（同一天内递增）、提前了几天。
class PullRecord {
  final DateTime day;
  final int seq;
  final int gap;
  const PullRecord(this.day, this.seq, this.gap);

  String get encoded => '${Ymd.fmt(day).replaceAll('-', '')}.$seq.$gap';

  static PullRecord? decode(String s) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})\.(\d+)\.(\d+)$').firstMatch(s);
    if (m == null) return null;
    final d = Ymd.parse('${m[1]}-${m[2]}-${m[3]}');
    if (d == null) return null;
    return PullRecord(d, int.parse(m[4]!), int.parse(m[5]!));
  }
}

class TodoItem {
  static int _counter = 0;

  /// 运行期唯一 id（不持久化）
  final int id;
  bool done;
  String? priority; // 'A'..'Z'
  DateTime? completionDate;
  DateTime? creationDate;

  /// 正文 token（保留 due:/t:/其它 key:value 的原始位置，尽量不改动原文）
  List<String> tokens;

  TodoItem({
    this.done = false,
    this.priority,
    this.completionDate,
    this.creationDate,
    required this.tokens,
  }) : id = _counter++;

  static final _dateRe = RegExp(r'^(\d{4}-\d{2}-\d{2})(?:\s+|$)');
  static final _priRe = RegExp(r'^\(([A-Z])\)(?:\s+|$)');

  /// 把全角冒号/括号等中文输入习惯规整为 todo.txt 标准写法。
  static String normalizeLine(String s) {
    var t = s.replaceAll('\u00a0', ' ').replaceAll('\u3000', ' ').trim();
    t = t.replaceAllMapped(
        RegExp(r'(^|\s)(due|t|DUE|T)[：:]'), (m) => '${m[1]}${m[2]!.toLowerCase()}:');
    t = t.replaceFirstMapped(RegExp(r'^（([A-Za-z])）'), (m) => '(${m[1]!.toUpperCase()}) ');
    t = t.replaceFirstMapped(RegExp(r'^\(([a-z])\)'), (m) => '(${m[1]!.toUpperCase()})');
    return t;
  }

  /// 解析一行；空行/注释行返回 null。[today] 非空时会把 due:明天 / t:3d 等相对日期换算为绝对日期。
  static TodoItem? parse(String line, {DateTime? today}) {
    var s = normalizeLine(line);
    if (s.isEmpty || s.startsWith('#')) return null;
    var done = false;
    String? pri;
    DateTime? completion, creation;
    if (s.startsWith('x ')) {
      done = true;
      s = s.substring(2).trimLeft();
      final m1 = _dateRe.firstMatch(s);
      if (m1 != null && Ymd.parse(m1[1]!) != null) {
        completion = Ymd.parse(m1[1]!);
        s = s.substring(m1.end);
        final m2 = _dateRe.firstMatch(s);
        if (m2 != null && Ymd.parse(m2[1]!) != null) {
          creation = Ymd.parse(m2[1]!);
          s = s.substring(m2.end);
        }
      }
    } else {
      final mp = _priRe.firstMatch(s);
      if (mp != null) {
        pri = mp[1];
        s = s.substring(mp.end);
      }
      final md = _dateRe.firstMatch(s);
      if (md != null && Ymd.parse(md[1]!) != null) {
        creation = Ymd.parse(md[1]!);
        s = s.substring(md.end);
      }
    }
    final tokens = s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (tokens.isEmpty) return null;
    if (today != null) {
      for (var i = 0; i < tokens.length; i++) {
        final tk = tokens[i];
        for (final key in const ['due', 't']) {
          if (tk.startsWith('$key:')) {
            final v = tk.substring(key.length + 1);
            if (Ymd.parse(v) == null) {
              final r = Ymd.parseRelative(v, today);
              if (r != null) tokens[i] = '$key:${Ymd.fmt(r)}';
            }
          }
        }
      }
    }
    return TodoItem(
        done: done, priority: pri, completionDate: completion, creationDate: creation, tokens: tokens);
  }

  TodoItem copy() => TodoItem(
      done: done,
      priority: priority,
      completionDate: completionDate,
      creationDate: creationDate,
      tokens: List.of(tokens));

  String toLine() {
    final b = StringBuffer();
    if (done) {
      b.write('x ');
      if (completionDate != null) {
        b.write('${Ymd.fmt(completionDate!)} ');
        if (creationDate != null) b.write('${Ymd.fmt(creationDate!)} ');
      }
    } else {
      if (priority != null) b.write('($priority) ');
      if (creationDate != null) b.write('${Ymd.fmt(creationDate!)} ');
    }
    b.write(tokens.join(' '));
    return b.toString();
  }

  DateTime? _tag(String key) {
    for (final t in tokens) {
      if (t.startsWith('$key:')) {
        final d = Ymd.parse(t.substring(key.length + 1));
        if (d != null) return d;
      }
    }
    return null;
  }

  void _setTag(String key, DateTime? v) {
    final idx = tokens.indexWhere(
        (t) => t.startsWith('$key:') && Ymd.parse(t.substring(key.length + 1)) != null);
    if (v == null) {
      if (idx >= 0) tokens.removeAt(idx);
    } else if (idx >= 0) {
      tokens[idx] = '$key:${Ymd.fmt(v)}';
    } else {
      tokens.add('$key:${Ymd.fmt(v)}');
    }
  }

  DateTime? get due => _tag('due');
  DateTime? get start => _tag('t');
  set due(DateTime? v) => _setTag('due', v);
  set start(DateTime? v) => _setTag('t', v);

  /// 任务所属日期：截止日期优先，其次开始日期；都没有则为 null（无日期任务）。
  DateTime? get date => due ?? start;

  /// 把 due / t 同时平移 [days] 天（负数为提前）。
  void shift(int days) {
    final d = due, s = start;
    if (d != null) due = Ymd.add(d, days);
    if (s != null) start = Ymd.add(s, days);
  }

  bool _isTag(String t) =>
      (t.startsWith('due:') && Ymd.parse(t.substring(4)) != null) ||
      (t.startsWith('t:') && Ymd.parse(t.substring(2)) != null) ||
      _isPf(t);

  // ------------------------------------------------ 提前记录（隐藏标签 pf:）
  //
  // 每次“完成即提前”会给被平移的所有未完成任务写入 pf:YYYYMMDD.序号.天数（多次提前用逗号累加），
  // 记录文件里，所以重启 / 组件后台操作后仍能据此把这一批还原。标签不在界面中显示，
  // 任务完成时清除，隔天由 [TodoStore.checkDayChange] 清理。
  static bool _isPf(String t) => t.startsWith('pf:') && t.length > 3 && _decodePf(t) != null;

  static List<PullRecord>? _decodePf(String t) {
    final out = <PullRecord>[];
    for (final part in t.substring(3).split(',')) {
      final r = PullRecord.decode(part);
      if (r == null) return null;
      out.add(r);
    }
    return out;
  }

  int get _pfIndex => tokens.indexWhere(_isPf);

  /// 按时间顺序（先 → 后）的提前记录
  List<PullRecord> get pulls {
    final i = _pfIndex;
    return i < 0 ? const [] : _decodePf(tokens[i]) ?? const [];
  }

  void _setPulls(List<PullRecord> l) {
    final i = _pfIndex;
    if (l.isEmpty) {
      if (i >= 0) tokens.removeAt(i);
    } else {
      final t = 'pf:${l.map((e) => e.encoded).join(',')}';
      if (i >= 0) {
        tokens[i] = t;
      } else {
        tokens.add(t);
      }
    }
  }

  void addPull(DateTime day, int seq, int gap) => _setPulls([...pulls, PullRecord(day, seq, gap)]);

  /// 弹出最近一次提前记录（用于还原）
  PullRecord? popPull() {
    final l = [...pulls];
    if (l.isEmpty) return null;
    final r = l.removeLast();
    _setPulls(l);
    return r;
  }

  void clearPulls() => _setPulls(const []);

  /// 清理早于 [day] 的记录（隔天后不再允许还原）
  void dropPullsBefore(DateTime day) => _setPulls(pulls.where((e) => !e.day.isBefore(day)).toList());

  /// 今天被提前过（且记录仍在）
  bool pulledOn(DateTime day) => pulls.any((e) => e.day == day);

  List<String> get projects =>
      tokens.where((t) => t.length > 1 && t.startsWith('+')).map((t) => t.substring(1)).toList();
  List<String> get contexts =>
      tokens.where((t) => t.length > 1 && t.startsWith('@')).map((t) => t.substring(1)).toList();

  static bool _isProject(String t) => t.length > 1 && t.startsWith('+');

  /// 规整类别名：去掉前导 +、空白；空串视为无类别。
  static String? normCategory(String? c) {
    var s = (c ?? '').trim();
    while (s.startsWith('+')) {
      s = s.substring(1);
    }
    s = s.replaceAll(RegExp(r'\s+'), '');
    return s.isEmpty ? null : s;
  }

  /// 类别 = 第一个 +项目 标签；没有则为 null（“未分类”）。
  String? get category {
    for (final t in tokens) {
      if (_isProject(t)) return t.substring(1);
    }
    return null;
  }

  /// 导入时设置类别：把 +类别 放到所有 +标签 的最前面。
  /// [keepOther] 为 false 时先清除原有的全部 +标签。[cat] 为空且保留旧标签时不改动。
  void setCategory(String? cat, {bool keepOther = true}) {
    final c = normCategory(cat);
    if (!keepOther) tokens.removeWhere(_isProject);
    if (c == null) return;
    final tag = '+$c';
    tokens.removeWhere((t) => t == tag);
    final idx = tokens.indexWhere(_isProject);
    if (idx >= 0) {
      tokens.insert(idx, tag);
    } else {
      tokens.add(tag);
    }
  }

  /// 更改类别（批量更改 / 编辑）：原来的第一个 +标签 就地换成新类别，其余标签不动；
  /// [cat] 为空表示改为“未分类”（移除全部 +标签）。
  void replaceCategory(String? cat) {
    final c = normCategory(cat);
    if (c == null) {
      tokens.removeWhere(_isProject);
      return;
    }
    final tag = '+$c';
    final idx = tokens.indexWhere(_isProject);
    if (idx >= 0 && tokens[idx] == tag) return;
    tokens.removeWhere((t) => t == tag);
    final i2 = tokens.indexWhere(_isProject);
    if (i2 >= 0) {
      tokens[i2] = tag;
    } else {
      tokens.add(tag);
    }
  }

  /// 编辑框使用的正文：去掉日期标签、pri 标签和“类别”标签（类别单独编辑）
  String get editableTextNoCategory {
    final i = tokens.indexWhere(_isProject);
    final out = <String>[];
    for (var k = 0; k < tokens.length; k++) {
      final t = tokens[k];
      if (k == i || _isTag(t) || t.startsWith('pri:')) continue;
      out.add(t);
    }
    return out.join(' ');
  }

  /// 用于显示的正文（去掉日期标签、pri 标签、+项目、@情境）
  String get text => tokens
      .where((t) =>
          !_isTag(t) &&
          !t.startsWith('pri:') &&
          !(t.length > 1 && (t.startsWith('+') || t.startsWith('@'))))
      .join(' ');

  /// 编辑框使用的正文：去掉日期标签与 pri 标签，保留 +项目 @情境
  String get editableText =>
      tokens.where((t) => !_isTag(t) && !t.startsWith('pri:')).join(' ');

  /// 标记完成：写入完成日期；按 topydo 习惯把优先级移到 pri:X 标签。
  void complete(DateTime today) {
    if (done) return;
    done = true;
    completionDate = today;
    clearPulls(); // 提前记录只对未完成任务有意义
    if (priority != null) {
      tokens.add('pri:$priority');
      priority = null;
    }
  }

  /// 取消完成：恢复优先级。
  void reopen() {
    if (!done) return;
    done = false;
    completionDate = null;
    final i = tokens.indexWhere((t) => RegExp(r'^pri:[A-Z]$').hasMatch(t));
    if (i >= 0) {
      priority = tokens[i].substring(4);
      tokens.removeAt(i);
    }
  }
}
