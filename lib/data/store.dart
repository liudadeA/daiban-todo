import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/dates.dart';
import '../logic/ics.dart';
import '../logic/planner.dart';
import '../logic/todo_item.dart';

class ImportPreview {
  final List<TodoItem> todo;
  final List<TodoItem> done;
  final bool fromIcs;

  /// ICS 的日历名第一个词（如 408），作为默认类别
  final String? calendarCategory;
  ImportPreview(this.todo, this.done, {this.fromIcs = false, this.calendarCategory});
  int get total => todo.length + done.length;

  /// 默认类别：ICS 日历名 → 否则任务里出现最多的第一个 +标签
  String? get defaultCategory {
    if (calendarCategory != null) return calendarCategory;
    final count = <String, int>{};
    for (final t in [...todo, ...done]) {
      final c = t.category;
      if (c != null) count[c] = (count[c] ?? 0) + 1;
    }
    if (count.isEmpty) return null;
    return count.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  /// 把 [category] 设为所有导入任务的第一个 +标签。
  void applyCategory(String? category, {bool keepOtherTags = true}) {
    for (final t in [...todo, ...done]) {
      t.setCategory(category, keepOther: keepOtherTags);
    }
  }
}

/// 数据层：todo.txt / done.txt 存在应用私有目录，设置与“上次处理日期”存在 SharedPreferences。
class TodoStore extends ChangeNotifier {
  static const kShiftBack = 'shiftBack';
  static const kPullForward = 'pullForward';
  static const kLastProcessed = 'lastProcessed';

  final Directory dir;
  final SharedPreferences prefs;
  final DateTime Function() _now;

  List<TodoItem> todo = [];
  List<TodoItem> done = [];

  /// 单步撤销快照（两个文件的全部行 + 上次处理日期）
  _Snapshot? _undo;

  TodoStore({required this.dir, required this.prefs, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  File get todoFile => File('${dir.path}/todo.txt');
  File get doneFile => File('${dir.path}/done.txt');

  DateTime get today => Ymd.fromDateTime(_now());

  bool get shiftBackEnabled => prefs.getBool(kShiftBack) ?? true;
  bool get pullForwardEnabled => prefs.getBool(kPullForward) ?? true;
  DateTime? get lastProcessed {
    final s = prefs.getString(kLastProcessed);
    return s == null ? null : Ymd.parse(s);
  }

  bool get canUndo => _undo != null;

  // ---------------------------------------------------------------- 类别

  static String _key(String prefix, String? cat) => '$prefix:${cat ?? ''}';

  /// 当前所有类别（待办 + 已完成，不含“未分类”），按名称排序
  List<String> get categories {
    final set = <String>{};
    for (final t in [...todo, ...done]) {
      final c = t.category;
      if (c != null) set.add(c);
    }
    return set.toList()..sort();
  }

  bool get hasUncategorized => [...todo, ...done].any((t) => t.category == null);

  String categoryLabel(String? c) => c ?? '未分类';

  /// 某类别“完成即提前”的单独设置：null = 继承全局
  bool? categoryPullSetting(String? cat) => prefs.getBool(_key('catPull', cat));
  bool? categoryShiftSetting(String? cat) => prefs.getBool(_key('catShift', cat));

  bool pullEnabledFor(String? cat) => categoryPullSetting(cat) ?? pullForwardEnabled;
  bool shiftEnabledFor(String? cat) => categoryShiftSetting(cat) ?? shiftBackEnabled;

  Future<void> setCategoryPull(String? cat, bool? v) async {
    v == null ? await prefs.remove(_key('catPull', cat)) : await prefs.setBool(_key('catPull', cat), v);
    notifyListeners();
  }

  Future<void> setCategoryShift(String? cat, bool? v) async {
    v == null ? await prefs.remove(_key('catShift', cat)) : await prefs.setBool(_key('catShift', cat), v);
    notifyListeners();
  }

  /// 新建任务时的默认类别（设置里的“主类别”）
  String? get primaryCategory {
    final v = prefs.getString('primaryCategory');
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setPrimaryCategory(String? v) async {
    await prefs.setString('primaryCategory', TodoItem.normCategory(v) ?? '');
    notifyListeners();
  }

  Future<void> setShiftBack(bool v) async {
    await prefs.setBool(kShiftBack, v);
    notifyListeners();
  }

  Future<void> setPullForward(bool v) async {
    await prefs.setBool(kPullForward, v);
    notifyListeners();
  }

  // ---------------------------------------------------------------- 读写

  Future<void> load() async {
    todo = await _readFile(todoFile);
    done = await _readFile(doneFile);
    notifyListeners();
  }

  Future<List<TodoItem>> _readFile(File f) async {
    if (!await f.exists()) return [];
    final text = utf8.decode(await f.readAsBytes(), allowMalformed: true);
    return _parseLines(text);
  }

  List<TodoItem> _parseLines(String text) {
    final t = today;
    return text
        .replaceFirst('\uFEFF', '')
        .split(RegExp(r'\r?\n'))
        .map((l) => TodoItem.parse(l, today: t))
        .whereType<TodoItem>()
        .toList();
  }

  Future<void> _save() async {
    await dir.create(recursive: true);
    await todoFile.writeAsString(_join(todo), encoding: utf8);
    await doneFile.writeAsString(_join(done), encoding: utf8);
    notifyListeners();
  }

  static String _join(List<TodoItem> l) => l.isEmpty ? '' : '${l.map((e) => e.toLine()).join('\n')}\n';

  void _pushUndo() {
    _undo = _Snapshot(todo.map((e) => e.toLine()).toList(), done.map((e) => e.toLine()).toList());
  }

  Future<void> undo() async {
    final u = _undo;
    if (u == null) return;
    todo = u.todo.map((l) => TodoItem.parse(l)!).toList();
    done = u.done.map((l) => TodoItem.parse(l)!).toList();
    _undo = null;
    await _save();
  }

  // ---------------------------------------------------------------- 日切 / 顺延

  /// App 打开 / 回到前台时调用。若日期已变化且开启了“整体顺延”，按规则顺延。
  /// 返回需要提示用户的中文消息（无变化返回 null）。
  Future<String?> checkDayChange() async {
    final t = today;
    final last = lastProcessed;
    if (last == null) {
      await prefs.setString(kLastProcessed, Ymd.fmt(t));
      return null;
    }
    if (!last.isBefore(t)) {
      // 同一天（或系统时间被往回调）：不处理
      if (last.isAfter(t)) await prefs.setString(kLastProcessed, Ymd.fmt(t));
      return null;
    }
    String? msg;
    _pushUndo();
    final moved = Planner.shiftBackByCategory(todo, last, t, enabled: shiftEnabledFor);
    if (moved.isNotEmpty) {
      final parts = moved.entries.map((e) => '${categoryLabel(e.key)} ${e.value} 天').join('、');
      msg = '昨日有未完成任务，后续计划已按类别顺延：$parts';
    } else {
      _undo = null;
    }
    // 无论是否开启，都推进“上次处理日期”，避免之后开启时回溯补偿
    await prefs.setString(kLastProcessed, Ymd.fmt(t));
    await _save();
    return msg;
  }

  // ---------------------------------------------------------------- 增删改

  Future<void> add(String text,
      {String? priority, DateTime? due, DateTime? start, String? category}) async {
    final item = TodoItem.parse(text, today: today);
    if (item == null) return;
    if (category != null) item.setCategory(category);
    item.creationDate ??= today;
    if (priority != null) item.priority = priority;
    if (due != null) item.due = due;
    if (start != null) item.start = start;
    _pushUndo();
    todo.add(item);
    await _save();
  }

  Future<void> update(TodoItem item, String text,
      {String? priority, DateTime? due, DateTime? start, String? category}) async {
    final parsed = TodoItem.parse(text, today: today);
    if (parsed == null) return;
    _pushUndo();
    item.tokens = parsed.tokens;
    // 编辑页里类别单独编辑：正文中不含类别标签，这里把它放回第一个 +标签
    item.setCategory(category);
    item.priority = priority;
    item.due = due;
    item.start = start;
    await _save();
  }

  Future<void> delete(TodoItem item) async {
    _pushUndo();
    todo.remove(item);
    done.remove(item);
    await _save();
  }

  Future<void> clearDone() async {
    _pushUndo();
    done.clear();
    await _save();
  }

  /// 勾选完成：归档到 done.txt。若该任务所属类别的今日任务（今天 + 逾期）已全部完成，
  /// 并且该类别开启了“完成即提前”，则只把该类别的下一批提前。返回提示消息（无则 null）。
  Future<String?> complete(TodoItem item) => completeMany([item]);

  /// 批量完成；每个受影响的类别各自判断一次提前。
  Future<String?> completeMany(Iterable<TodoItem> items) async {
    final list = items.where(todo.contains).toList();
    if (list.isEmpty) return null;
    final t = today;
    _pushUndo();
    final cats = <String?>{};
    for (final item in list) {
      cats.add(item.category);
      item.complete(t);
      todo.remove(item);
      done.insert(0, item);
    }
    final msgs = <String>[];
    for (final c in cats) {
      if (!pullEnabledFor(c)) continue;
      final gap = Planner.pullForwardCategory(todo, t, c);
      if (gap > 0) msgs.add(c == null ? '今日任务已完成，已提前下一批' : '$c 今日任务已完成，已提前下一批');
    }
    await _save();
    return msgs.isEmpty ? null : msgs.join('；');
  }

  /// 在已完成列表里取消完成，回到待办。
  Future<void> reopen(TodoItem item) async {
    if (!done.contains(item)) return;
    _pushUndo();
    item.reopen();
    done.remove(item);
    todo.add(item);
    await _save();
  }

  // ---------------------------------------------------------------- 导入 / 导出

  /// 解析待导入文本：既支持 todo.txt，也支持 .ics 日历（自动拆成一项一条）。
  ImportPreview preview(String text) {
    final isIcs = Ics.looksLikeIcs(text);
    final items = _parseLines(isIcs ? Ics.toTodoLines(text).join('\n') : text);
    return ImportPreview(items.where((e) => !e.done).toList(), items.where((e) => e.done).toList(),
        fromIcs: isIcs, calendarCategory: isIcs ? Ics.categoryOf(text) : null);
  }

  /// 导入。追加模式下跳过与现有任务完全相同的行（避免重复导入造成每天多出一份，
  /// 导致“今日任务”永远清不空）。返回跳过的条数。
  Future<int> applyImport(ImportPreview p, {required bool replace}) async {
    _pushUndo();
    final c = today;
    if (replace) {
      todo = [];
      done = [];
    }
    final seenTodo = todo.map((e) => e.toLine()).toSet();
    final seenDone = done.map((e) => e.toLine()).toSet();
    var skipped = 0;
    for (final i in p.todo) {
      if (seenTodo.add(i.toLine())) {
        todo.add(i);
      } else {
        skipped++;
      }
    }
    for (final i in p.done) {
      if (seenDone.add(i.toLine())) {
        done.add(i);
      } else {
        skipped++;
      }
    }
    // 导入视为一次新的计划，当天不再触发补偿顺延
    await prefs.setString(kLastProcessed, Ymd.fmt(c));
    await _save();
    return skipped;
  }

  /// 手动“提前下一批”：把 [category]（null = 未分类）的下一个日期批次整体提前到今天，
  /// 不受自动开关和“今日是否清空”限制；只移动该类别的任务。
  Future<String> pullNextBatch([String? category]) async {
    final t = today;
    DateTime? next;
    for (final i in todo) {
      final d = i.date;
      if (i.category == category && d != null && d.isAfter(t) && (next == null || d.isBefore(next))) next = d;
    }
    final label = category == null ? '' : '$category ';
    if (next == null) return '$label没有可提前的后续任务';
    _pushUndo();
    final gap = Planner.pullForwardCategory(todo, t, category, force: true);
    await _save();
    return gap > 0 ? '$label已把 ${next.month}月${next.day}日 的任务提前到今天' : '$label没有可提前的后续任务';
  }

  // ---------------------------------------------------------------- 批量管理

  Future<void> deleteMany(Iterable<TodoItem> items) async {
    final set = items.toSet();
    if (set.isEmpty) return;
    _pushUndo();
    todo.removeWhere(set.contains);
    done.removeWhere(set.contains);
    await _save();
  }

  /// 删除全部任务（待办 + 已完成）
  Future<void> deleteAll() async {
    _pushUndo();
    todo = [];
    done = [];
    await _save();
  }

  /// 删除某类别的全部任务（待办 + 已完成）。返回删除条数。
  Future<int> deleteCategory(String? category) async {
    final n = todo.where((t) => t.category == category).length + done.where((t) => t.category == category).length;
    if (n == 0) return 0;
    _pushUndo();
    todo.removeWhere((t) => t.category == category);
    done.removeWhere((t) => t.category == category);
    await _save();
    return n;
  }

  /// 批量更改类别（null = 未分类）
  Future<void> setCategoryMany(Iterable<TodoItem> items, String? category) async {
    final list = items.toList();
    if (list.isEmpty) return;
    _pushUndo();
    for (final i in list) {
      i.replaceCategory(category);
    }
    await _save();
  }

  /// 重命名 / 合并类别：把 [from] 类别的任务全部改为 [to]
  Future<int> renameCategory(String? from, String? to) async {
    final list = [...todo, ...done].where((t) => t.category == from).toList();
    await setCategoryMany(list, to);
    return list.length;
  }

  /// 批量平移日期（due / t 同时 +days；没有日期的任务不动）。返回被移动的条数。
  Future<int> shiftMany(Iterable<TodoItem> items, int days) async {
    final list = items.where((t) => !t.done && t.date != null).toList();
    if (list.isEmpty || days == 0) return 0;
    _pushUndo();
    for (final i in list) {
      i.shift(days);
    }
    await _save();
    return list.length;
  }

  /// 批量取消完成
  Future<void> reopenMany(Iterable<TodoItem> items) async {
    final list = items.where(done.contains).toList();
    if (list.isEmpty) return;
    _pushUndo();
    for (final i in list) {
      i.reopen();
      done.remove(i);
      todo.add(i);
    }
    await _save();
  }

  /// 导出为 .ics（每个有日期的待办一个全日事件）。
  String exportIcs() {
    final tasks = <({String text, String note, DateTime date, String uid})>[];
    for (var i = 0; i < todo.length; i++) {
      final t = todo[i];
      final d = t.date;
      if (d == null) continue;
      final note = t.tokens.where((e) => e.length > 1 && (e.startsWith('+') || e.startsWith('@'))).join(' ');
      tasks.add((
        text: '${t.priority != null ? '(${t.priority}) ' : ''}${t.text}',
        note: note,
        date: d,
        uid: '${Ymd.fmt(d)}-$i-${t.text.hashCode.toUnsigned(32).toRadixString(16)}'
      ));
    }
    return Ics.exportTodo(tasks);
  }

  String exportTodo() => _join(todo);
  String exportDone() => _join(done);
  String exportAll() => _join(todo) + _join(done);
}

class _Snapshot {
  final List<String> todo, done;
  _Snapshot(this.todo, this.done);
}
