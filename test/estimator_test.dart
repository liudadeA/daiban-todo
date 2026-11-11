import 'dart:io';

import 'package:daiban/data/store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:daiban/logic/estimator.dart';
import 'package:daiban/logic/todo_item.dart';
import 'package:daiban/logic/widget_actions.dart';
import 'package:daiban/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TodoItem p(String l) => TodoItem.parse(l)!;
final today = Ymd.of(2026, 11, 11);
String f(DateTime? d) => d == null ? '-' : Ymd.fmt(d);

List<TodoItem> openN(int n, String due, {String cat = '408'}) =>
    [for (var i = 0; i < n; i++) p('任务$i +$cat due:$due t:$due')];
TodoItem doneOn(String date, {String cat = '408'}) => p('x $date 完成 +$cat');

void main() {
  group('Estimator 规则', () {
    test('计划完成 = 未完成任务里最晚的日期（due 优先，其次 t）；其它类别不参与', () {
      final todo = [p('a +408 due:2026-11-12'), p('b +408 t:2026-11-20'), p('c +408 due:2026-11-15 t:2026-11-25'), p('d +数学 due:2026-12-30'), p('e +408')];
      final e = Estimator.forCategory(todo, [], today, '408');
      expect(f(e.planDate), '2026-11-20'); // c 的 date = due = 11-15
      expect(e.open, 4);
      expect(Estimator.forCategory(todo, [], today, '数学').planDate, Ymd.of(2026, 12, 30));
    });

    test('近 7 天平均速度推算预计完成日：剩余 ÷ 日均，向上取整（今天算第 1 天）', () {
      // 11-09、11-10、11-11 三天共完成 6 项 → span = 3 天，日均 2 项
      final done = [doneOn('2026-11-09'), doneOn('2026-11-09'), doneOn('2026-11-10'), doneOn('2026-11-10'), doneOn('2026-11-11'), doneOn('2026-11-11')];
      final todo = openN(10, '2026-11-20');
      final e = Estimator.forCategory(todo, done, today, '408');
      expect(e.rate, closeTo(2.0, 1e-9));
      expect(f(e.estDate), '2026-11-15'); // 需要 5 天：11、12、13、14、15
      expect(e.aheadDays, 5); // 计划 11-20，预计 11-15 → 提前 5 天
      expect(Estimator.aheadText(e.aheadDays), '提前 5 天');
    });

    test('落后：预计晚于计划', () {
      final done = [doneOn('2026-11-10'), doneOn('2026-11-11')]; // 2 天 2 项 → 日均 1
      final todo = openN(9, '2026-11-14');
      final e = Estimator.forCategory(todo, done, today, '408');
      expect(f(e.estDate), '2026-11-19'); // 9 天：11 → 19
      expect(e.aheadDays, -5);
      expect(Estimator.aheadText(e.aheadDays), '落后 5 天');
    });

    test('持平', () {
      final done = [doneOn('2026-11-10'), doneOn('2026-11-11')];
      final e = Estimator.forCategory(openN(4, '2026-11-14'), done, today, '408');
      expect(f(e.estDate), '2026-11-14');
      expect(e.aheadDays, 0);
      expect(Estimator.aheadText(0), '与计划持平');
    });

    test('数据不足：不到 2 个不同日期 / 没有记录 / 记录在 7 天之外 → 没有预计，只保留计划', () {
      final todo = openN(5, '2026-11-20');
      for (final done in [
        <TodoItem>[],
        [doneOn('2026-11-11'), doneOn('2026-11-11'), doneOn('2026-11-11')], // 同一天
        [doneOn('2026-11-01'), doneOn('2026-11-02')], // 窗口之外
        [p('x 日期缺失的旧记录 +408')], // 没有完成日期
      ]) {
        final e = Estimator.forCategory(todo, done, today, '408');
        expect(e.estDate, isNull);
        expect(e.rate, isNull);
        expect(e.aheadDays, isNull);
        expect(e.hasEstimate, isFalse);
        expect(f(e.planDate), '2026-11-20');
        expect(Estimator.compact(e, today), contains('预计 数据不足'));
      }
    });

    test('窗口只算最近 7 天（含今天）：11-05 算窗口内，11-04 不算', () {
      final todo = openN(6, '2026-11-30');
      final inWin = Estimator.forCategory(todo, [doneOn('2026-11-05'), doneOn('2026-11-11')], today, '408');
      expect(inWin.rate, closeTo(2 / 7, 1e-9));
      final out = Estimator.forCategory(todo, [doneOn('2026-11-04'), doneOn('2026-11-11')], today, '408');
      expect(out.estDate, isNull); // 11-04 在窗口外，只剩一天记录
    });

    test('已全部完成 / 没有日期的类别', () {
      final e = Estimator.forCategory([], [doneOn('2026-11-10'), doneOn('2026-11-11')], today, '408');
      expect(e.finished, isTrue);
      expect(e.progress, 1);
      expect(Estimator.compact(e, today), '已全部完成 2/2');
      final und = Estimator.forCategory([p('无日期 +408')], [doneOn('2026-11-10'), doneOn('2026-11-11')], today, '408');
      expect(und.planDate, isNull);
      expect(und.estDate, isNotNull);
      expect(und.aheadDays, isNull); // 没有计划日期就不比较提前/落后
      expect(Estimator.compact(und, today), isNot(contains('提前')));
      expect(Estimator.compact(und, today), isNot(contains('落后')));
    });

    test('速度太慢（超过一年）→ 不给具体日期', () {
      final done = [doneOn('2026-11-05'), doneOn('2026-11-11')];
      final e = Estimator.forCategory(openN(400, '2027-01-01'), done, today, '408');
      expect(e.tooFar, isTrue);
      expect(e.estDate, isNull);
      expect(Estimator.compact(e, today), contains('预计 一年以上'));
    });

    test('进度与未分类', () {
      final todo = [p('a'), p('b +408 due:2026-11-12')];
      final done = [p('x 2026-11-10 c'), p('x 2026-11-10 d +408')];
      final m = Estimator.all(todo, done, today);
      expect(m.keys.toSet(), {null, '408'});
      expect(m[null]!.done, 1);
      expect(m[null]!.open, 1);
      expect(m['408']!.total, 2);
      expect(m['408']!.progress, 0.5);
      expect(Estimator.compact(m['408']!, today), startsWith('进度 1/2 · 计划 11月12日'));
    });

    test('文案：紧凑行与详细说明', () {
      final done = [doneOn('2026-11-10'), doneOn('2026-11-11')];
      final e = Estimator.forCategory(openN(4, '2026-11-14'), done, today, '408');
      expect(Estimator.compact(e, today), '进度 2/6 · 计划 11月14日 · 预计 11月14日（与计划持平）');
      final d = Estimator.detail(e, today);
      expect(d.first, '待办 4 · 已完成 2 · 进度 33%');
      expect(d.join('\n'), contains('计划完成 11月14日'));
      expect(d.join('\n'), contains('预计完成 11月14日'));
      expect(d.join('\n'), contains('近 7 天平均每天完成 1.0 项'));
    });
  });

  group('界面与组件', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('daiban_est');
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() async => tmp.delete(recursive: true));

    test('桌面组件快照不含任何预计 / 进度字段', () async {
      final s = TodoStore(dir: tmp, prefs: await SharedPreferences.getInstance(), now: () => DateTime(2026, 11, 11, 9));
      await s.applyImport(
          s.preview('甲 +408 due:2026-11-11\n乙 +408 due:2026-11-20\nx 2026-11-10 丙 +408\nx 2026-11-11 丁 +408\n'),
          replace: true);
      final snap = WidgetActions.snapshot(s);
      expect(snap.keys.toSet(), {'date', 'count', 'rows', 'open'});
      final text = snap.toString();
      expect(text, isNot(contains('预计')));
      expect(text, isNot(contains('进度')));
      expect(text, isNot(contains('计划')));
      for (final r in (snap['rows'] as List).cast<Map>()) {
        expect(r.keys.toSet().difference({'type', 'id', 'text', 'category'}), isEmpty);
      }
    });

    testWidgets('今日页类别标题下显示进度 / 计划 / 预计', (tester) async {
      late TodoStore store;
      await tester.runAsync(() async {
        store = TodoStore(dir: tmp, prefs: await SharedPreferences.getInstance(), now: () => DateTime(2026, 11, 11, 9));
        await store.applyImport(
            store.preview('甲 +408 due:2026-11-11\n乙 +408 due:2026-11-14\nx 2026-11-10 丙 +408\nx 2026-11-11 丁 +408\n数学题 +数学 due:2026-11-11\n'),
            replace: true);
      });
      await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
      await tester.pump();
      final t408 = tester.widget<Text>(find.byKey(const Key('est_408'))).data!;
      expect(t408, contains('进度 2/4'));
      expect(t408, contains('计划 11月14日'));
      expect(t408, contains('预计 11月12日')); // 2 天 2 项 → 日均 1，剩 2 项：11-11、11-12
      expect(t408, contains('提前 2 天'));
      final math = tester.widget<Text>(find.byKey(const Key('est_数学'))).data!;
      expect(math, contains('预计 数据不足'));
    });
  });
}
