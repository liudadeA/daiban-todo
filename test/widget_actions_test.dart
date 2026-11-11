import 'dart:io';

import 'package:daiban/data/store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:daiban/logic/widget_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  late DateTime clock;
  late TodoStore store;

  Future<TodoStore> open({bool pull = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!pull) await prefs.setBool(TodoStore.kPullForward, false);
    final s = TodoStore(dir: tmp, prefs: prefs, now: () => clock);
    await s.load();
    return s;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('daiban_wa');
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 11, 11, 9);
    store = await open();
  });
  tearDown(() async => tmp.delete(recursive: true));

  test('快照按类别分组，与今日集合一致；id 稳定且可找回', () async {
    await store.applyImport(
        store.preview(
            '数据结构 KMP +408 +数据结构 due:2026-11-11 t:2026-11-11\n'
            '线性代数 习题 +数学 due:2026-11-11\n'
            '明天才开始 +408 due:2026-11-12 t:2026-11-12\n'
            '无日期备忘 +408\n'),
        replace: true);
    final snap = WidgetActions.snapshot(store);
    expect(snap['date'], '2026-11-11');
    expect(snap['count'], 3); // 两条今日 + 一条无日期；明天的不算
    final rows = (snap['rows'] as List).cast<Map>();
    final types = rows.map((r) => r['type']).toList();
    expect(types, ['header', 'task', 'task', 'header', 'task']);
    // 408 在前（与数学都有今日任务时按名称：408 < 数学）还是按拼音？ "408".compareTo("数学") is negative (digit < CJK)
    expect(rows[0]['text'], '408');
    expect(rows[1]['text'], '数据结构 KMP');
    expect(rows[2]['text'], '无日期备忘');
    expect(rows[3]['text'], '数学');
    expect(rows[4]['text'], '线性代数 习题');
    final id = rows[1]['id'] as String;
    expect(id, isNotEmpty);
    expect(id, WidgetActions.idOf(store.todo.firstWhere((t) => t.text == '数据结构 KMP')));
    expect(id, isNot(WidgetActions.idOf(store.todo.firstWhere((t) => t.text == '线性代数 习题'))));
  });

  test('组件勾选走同一套 complete：归档并按类别提前', () async {
    await store.applyImport(
        store.preview(
            '今日卷 1 +408 due:2026-11-11\n'
            '今日卷 2 +408 due:2026-11-11\n'
            '下一批 +408 due:2026-11-13 t:2026-11-13\n'
            '数学今日 +数学 due:2026-11-11\n'
            '数学以后 +数学 due:2026-11-13 t:2026-11-13\n'),
        replace: true);
    final a = store.todo.firstWhere((t) => t.text == '今日卷 1');
    final b = store.todo.firstWhere((t) => t.text == '今日卷 2');
    final msg1 = await WidgetActions.handle(store, WidgetActions.completeUri(WidgetActions.idOf(a)));
    expect(msg1, isNull); // 该类别今日还没清空
    expect(store.done.any((t) => t.text == '今日卷 1'), isTrue);
    final msg2 = await WidgetActions.handle(store, WidgetActions.completeUri(WidgetActions.idOf(b)));
    expect(msg2, contains('408 今日任务已完成，已提前下一批'));
    final next = store.todo.firstWhere((t) => t.text == '下一批');
    expect(Ymd.fmt(next.due!), '2026-11-11');
    // 数学未完成，不能被 408 的提前带走
    final mathLater = store.todo.firstWhere((t) => t.text == '数学以后');
    expect(Ymd.fmt(mathLater.due!), '2026-11-13');
  });

  test('未知 id 不改数据；refresh 只做跨日检查', () async {
    await store.applyImport(store.preview('今日任务 +408 due:2026-11-11'), replace: true);
    final before = store.todo.first.toLine();
    expect(await WidgetActions.handle(store, WidgetActions.completeUri('deadbeef')), isNull);
    expect(store.todo.single.toLine(), before);
    expect(await WidgetActions.handle(store, WidgetActions.refreshUri), isNull);
    expect(store.todo, hasLength(1));
  });

  test('refresh 在跨日后会按类别顺延', () async {
    await store.applyImport(
        store.preview('未完成 +408 due:2026-11-11\n后续 +408 due:2026-11-12 t:2026-11-12\n'),
        replace: true);
    // 把“上次处理日”设为 11 日，时钟拨到 12 日
    await store.prefs.setString(TodoStore.kLastProcessed, '2026-11-11');
    clock = DateTime(2026, 11, 12, 0, 10);
    store = await open();
    await WidgetActions.handle(store, WidgetActions.refreshUri);
    final later = store.todo.firstWhere((t) => t.text == '后续');
    expect(Ymd.fmt(later.due!), '2026-11-13');
  });
}
