import 'dart:io';
import 'package:daiban/data/store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:daiban/logic/planner.dart';
import 'package:daiban/logic/todo_item.dart';
import 'package:daiban/logic/widget_actions.dart';
import 'package:daiban/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  late DateTime now;
  late TodoStore s;
  Future<TodoStore> open() async {
    final store = TodoStore(dir: dir, prefs: await SharedPreferences.getInstance(), now: () => now);
    await store.load();
    return store;
  }
  TodoItem task(String text) => [...s.todo, ...s.done].firstWhere((t) => t.text == text);
  Map<String, String> dates() => {for (final t in [...s.todo, ...s.done]) t.text: '${t.due}/${t.start}/${t.plan}'};
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('early_visibility_');
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 11, 11, 9);
    s = await open();
    await s.applyImport(s.preview('A +408 due:2026-11-11 t:2026-11-10\n'
        'B +408 due:2026-11-14 t:2026-11-13\n'
        'B2 +408 due:2026-11-14 t:2026-11-14\n'
        'C +408 due:2026-11-18 t:2026-11-17\n'
        'M +数学 due:2026-11-12 t:2026-11-12'), replace: true);
  });
  tearDown(() async => dir.delete(recursive: true));

  test('自动提前只显示下一批，due/t/plan 全部不变，后续与其它类别不动', () async {
    final before = dates();
    await s.complete(task('A'));
    expect(dates(), before);
    expect(Planner.todaySet(s.todo, s.today).map((t) => t.text), ['B', 'B2']);
    expect(task('C').pulls, isEmpty);
    final snap = WidgetActions.snapshot(s);
    expect((snap['rows'] as List).where((r) => r['type'] == 'task').map((r) => r['text']), ['B', 'B2']);
    final b = (snap['open'] as List).firstWhere((r) => r['text'] == 'B') as Map;
    expect(b['date'], '2026-11-14');
    expect(b['start'], '2026-11-13');
    expect(b['displayDate'], '2026-11-11');
    expect(s.exportTodo(), contains('due:2026-11-14 t:2026-11-13'));
    expect(s.exportIcs(), contains('DTSTART;VALUE=DATE:20261114'));
  });

  test('手动连续提前跳过已经显示的批次，日期保持，没下一批不重复提前', () async {
    final before = dates();
    await s.pullNextBatch('408'); // 今日原本仍有 A
    expect(Planner.todaySet(s.todo, s.today).map((t) => t.text), ['A', 'B', 'B2']);
    await s.pullNextBatch('408');
    expect(Planner.todaySet(s.todo, s.today).map((t) => t.text), ['A', 'B', 'B2', 'C']);
    expect(await s.pullNextBatch('408'), contains('没有可提前'));
    expect(dates(), before);
  });

  test('提前显示跨日保持且不被当作逾期顺延，重启同样可见', () async {
    await s.complete(task('A'));
    final before = dates();
    now = DateTime(2026, 11, 12, 8);
    expect(await s.checkDayChange(), isNull);
    s = await open();
    expect(dates(), before);
    expect(Planner.inToday(task('B'), s.today), isTrue);
    expect(Planner.visibleOn(task('B'), s.today), isTrue); // t:13 仍未到
    expect(task('C').due, Ymd.of(2026, 11, 18));
  });

  test('连续提前后，取消较早已提前完成的任务只撤回后续显示，不改日期', () async {
    final before = dates();
    await s.complete(task('A'));
    await s.completeMany([task('B'), task('B2')]);
    expect(Planner.inToday(task('C'), s.today), isTrue);
    s = await open();
    await s.reopen(task('B'));
    expect(Planner.todaySet(s.todo, s.today).map((t) => t.text), ['B']);
    expect(task('C').pulls, isEmpty);
    expect(dates(), before);
  });

  test('仅编辑正文保留提前显示；手动重新计划或平移清除显示标记', () async {
    await s.complete(task('A'));
    final b = task('B');
    await s.update(b, 'B edited', category: b.category, due: b.due, start: b.start);
    expect(Planner.inToday(b, s.today), isTrue);
    await s.update(b, 'B edited', category: b.category, due: Ymd.of(2026, 11, 20), start: b.start);
    expect(b.pulls, isEmpty);
    final b2 = task('B2');
    await s.shiftMany([b2], 1);
    expect(b2.pulls, isEmpty);
    expect(b2.due, Ymd.of(2026, 11, 15));
  });

  test('旧 pf 精确恢复 due/t，多次迁移不重复，未来批次不误显示，不猜无记录的历史日期', () async {
    await s.todoFile.writeAsString('X +408 due:2026-11-11 t:2026-11-10 pf:20261111.1.2,20261111.2.1\n'
        'Y +408 due:2026-11-13 t:2026-11-12 pf:20261111.1.2,20261111.2.1\n'
        'Z +408 due:2026-11-11 plan:2026-11-20\n');
    s = await open();
    expect(task('X').due, Ymd.of(2026, 11, 14));
    expect(task('X').start, Ymd.of(2026, 11, 13));
    expect(task('X').plan, Ymd.of(2026, 11, 14));
    expect(Planner.inToday(task('X'), s.today), isTrue);
    expect(task('Y').due, Ymd.of(2026, 11, 16));
    expect(task('Y').pulls, isEmpty);
    expect(Planner.inToday(task('Y'), s.today), isFalse);
    expect(task('Z').due, Ymd.of(2026, 11, 11)); // plan 不是 due，不凭它猜测
    final once = s.exportTodo();
    s = await open();
    expect(s.exportTodo(), once);
    expect(once, isNot(contains('pf:')));
    expect(once, contains('pv:'));
    expect(task('X').text, 'X');
    expect(task('X').editableText, isNot(contains('pv:')));
    expect(task('X').editableTextNoCategory, isNot(contains('pv:')));
  });

  testWidgets('今日显示提前批次，但截止和开始标签仍为原日期，不伪装成今日日期', (tester) async {
    await tester.runAsync(() async => s.complete(task('A')));
    await tester.pumpWidget(MaterialApp(home: HomePage(store: s)));
    await tester.pump();
    expect(find.text('B'), findsOneWidget);
    expect(find.text('提前显示 · 日期不变'), findsWidgets);
    expect(find.text('截止 2026-11-14'), findsWidgets);
    expect(find.text('开始 后天（11-13）'), findsOneWidget);
    expect(task('B').due, Ymd.of(2026, 11, 14));
  });
}
