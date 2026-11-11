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

/// 带原计划日期的任务：[plan] 为原计划日，[cur] 为当前 due/t（可能已被提前 / 顺延改写）。
TodoItem open(String plan, {String? cur, String cat = '408', String name = '任务'}) =>
    p('$name +$cat due:${cur ?? plan} t:${cur ?? plan} plan:$plan');
TodoItem fin(String plan, {String? cur, String cat = '408', String name = '完成'}) =>
    p('x 2026-11-10 $name +$cat due:${cur ?? plan} t:${cur ?? plan} plan:$plan');

void main() {
  group('Estimator 规则（按原计划的“量”）', () {
    test('没有提前也没有落后 → 预计 = 计划，持平', () {
      final todo = [open('2026-11-11'), open('2026-11-12'), open('2026-11-14')];
      final e = Estimator.forCategory(todo, [], today, '408');
      expect(f(e.planDate), '2026-11-14');
      expect(f(e.estDate), '2026-11-14');
      expect(e.aheadDays, 0);
      expect(Estimator.compact(e, today), '进度 0/3 · 计划 11月14日 · 预计 11月14日（与计划持平）');
    });

    test('提前完成一整天的量 → 预计完成日期减 1；每多一整天再减 1', () {
      // 计划 11-11、11-12、11-13、11-14 各一条；11-12 和 11-13 的已提前完成
      final todo = [open('2026-11-11'), open('2026-11-14')];
      final done = [fin('2026-11-12'), fin('2026-11-13')];
      final e = Estimator.forCategory(todo, done, today, '408');
      expect(e.earlyDays, 2);
      expect(e.lateDays, 0);
      expect(f(e.planDate), '2026-11-14');
      expect(f(e.estDate), '2026-11-12');
      expect(e.aheadDays, 2);
      expect(Estimator.compact(e, today), '进度 2/4 · 计划 11月14日 · 预计 11月12日（提前 2 天）');
      // 只提前一天
      final e1 = Estimator.forCategory([...todo, open('2026-11-13')], [fin('2026-11-12')], today, '408');
      expect(e1.earlyDays, 1);
      expect(f(e1.estDate), '2026-11-13');
    });

    test('只完成一天的一部分不算：整天的量没做完就不减', () {
      final todo = [open('2026-11-12', name: '甲'), open('2026-11-14')];
      final done = [fin('2026-11-12', name: '乙')]; // 11-12 有两条，只做了一条
      final e = Estimator.forCategory(todo, done, today, '408');
      expect(e.earlyDays, 0);
      expect(f(e.estDate), '2026-11-14');
      expect(Estimator.compact(e, today), contains('与计划持平'));
    });

    test('一天里有多条任务：全部完成才算一天', () {
      final todo = [open('2026-11-15')];
      final done = [fin('2026-11-13', name: '甲'), fin('2026-11-13', name: '乙'), fin('2026-11-13', name: '丙')];
      final e = Estimator.forCategory(todo, done, today, '408');
      expect(e.earlyDays, 1); // 三条合起来只是一天的量
      expect(f(e.estDate), '2026-11-14');
    });

    test('落后：计划日已过但没做完的天数，预计 = 计划 + 落后天数', () {
      // 11-09、11-10 的任务没做完（各落后一天）；11-11 是今天，不算落后
      final todo = [open('2026-11-09', cur: '2026-11-11'), open('2026-11-10', cur: '2026-11-11'), open('2026-11-11', cur: '2026-11-12'), open('2026-11-14', cur: '2026-11-15')];
      final e = Estimator.forCategory(todo, [], today, '408');
      expect(e.lateDays, 2);
      expect(e.earlyDays, 0);
      expect(f(e.planDate), '2026-11-14'); // 用原计划日，而不是被顺延后的 11-15
      expect(f(e.estDate), '2026-11-16');
      expect(e.aheadDays, -2);
      expect(Estimator.compact(e, today), '进度 0/4 · 计划 11月14日 · 预计 11月16日（落后 2 天）');
    });

    test('落后一部分：过去那天只完成了一半，仍算落后', () {
      final todo = [open('2026-11-10', cur: '2026-11-11', name: '甲'), open('2026-11-13')];
      final done = [fin('2026-11-10', cur: '2026-11-10', name: '乙')];
      final e = Estimator.forCategory(todo, done, today, '408');
      expect(e.lateDays, 1);
      expect(f(e.estDate), '2026-11-14');
    });

    test('过去的计划日已全部完成：不落后、也不算提前', () {
      final todo = [open('2026-11-13')];
      final done = [fin('2026-11-09'), fin('2026-11-10')];
      final e = Estimator.forCategory(todo, done, today, '408');
      expect(e.earlyDays, 0);
      expect(e.lateDays, 0);
      expect(f(e.estDate), '2026-11-13');
    });

    test('提前与落后同时存在：净提前 = 提前天数 − 落后天数', () {
      final todo = [open('2026-11-09', cur: '2026-11-11'), open('2026-11-20')];
      final done = [fin('2026-11-12'), fin('2026-11-13'), fin('2026-11-14')];
      final e = Estimator.forCategory(todo, done, today, '408');
      expect(e.earlyDays, 3);
      expect(e.lateDays, 1);
      expect(e.aheadDays, 2);
      expect(f(e.estDate), '2026-11-18');
    });

    test('今天的计划日：做完也不算提前，没做完也不算落后', () {
      final a = Estimator.forCategory([open('2026-11-11'), open('2026-11-13')], [], today, '408');
      expect(a.earlyDays + a.lateDays, 0);
      final b = Estimator.forCategory([open('2026-11-13')], [fin('2026-11-11')], today, '408');
      expect(b.earlyDays + b.lateDays, 0);
      expect(f(b.estDate), '2026-11-13');
    });

    test('永远有预计：没有任何完成记录也给出日期，不再有“数据不足”', () {
      final e = Estimator.forCategory([open('2026-11-20')], [], today, '408');
      expect(e.hasEstimate, isTrue);
      expect(Estimator.compact(e, today), isNot(contains('数据不足')));
      expect(Estimator.detail(e, today).join(), isNot(contains('数据不足')));
    });

    test('其它类别不参与；无日期任务只计进度，不构成计划日', () {
      final todo = [open('2026-11-14'), open('2026-12-30', cat: '数学'), p('无日期 +408')];
      final e = Estimator.forCategory(todo, [], today, '408');
      expect(f(e.planDate), '2026-11-14');
      expect(e.open, 2);
      final und = Estimator.forCategory([p('无日期 +408')], [], today, '408');
      expect(und.planDate, isNull);
      expect(und.estDate, isNull);
      expect(Estimator.compact(und, today), '进度 0/1');
    });

    test('老数据没有 plan: 标签：用当前日期 + 未过期的提前记录推算原计划日', () {
      final it = p('甲 +408 due:2026-11-11 t:2026-11-11 pf:20261111.1.3');
      expect(f(it.planOrDate), '2026-11-14');
      expect(it.plan, isNull);
      expect(it.ensurePlan(), isTrue);
      expect(f(it.plan), '2026-11-14');
      expect(it.ensurePlan(), isFalse);
      final e = Estimator.forCategory([it], [], today, '408');
      expect(f(e.planDate), '2026-11-14');
    });

    test('已全部完成', () {
      final e = Estimator.forCategory([], [fin('2026-11-10'), fin('2026-11-11')], today, '408');
      expect(e.finished, isTrue);
      expect(e.progress, 1);
      expect(Estimator.compact(e, today), '已全部完成 2/2');
    });

    test('进度与未分类', () {
      final todo = [p('a'), p('b +408 due:2026-11-12 plan:2026-11-12')];
      final done = [p('x 2026-11-10 c'), p('x 2026-11-10 d +408')];
      final m = Estimator.all(todo, done, today);
      expect(m.keys.toSet(), {null, '408'});
      expect(m[null]!.done, 1);
      expect(m['408']!.total, 2);
      expect(m['408']!.progress, 0.5);
      expect(Estimator.compact(m['408']!, today), startsWith('进度 1/2 · 计划 11月12日'));
    });

    test('详细说明', () {
      final todo = [open('2026-11-11'), open('2026-11-14')];
      final done = [fin('2026-11-12'), fin('2026-11-13')];
      final d = Estimator.detail(Estimator.forCategory(todo, done, today, '408'), today);
      expect(d.first, '待办 2 · 已完成 2 · 进度 50%');
      expect(d.join('\n'), contains('计划完成 11月14日'));
      expect(d.join('\n'), contains('预计完成 11月12日（明日），提前 2 天（已提前完成 2 天的量）'));
    });
  });

  group('plan: 标签的写入与保留', () {
    late Directory tmp;
    late TodoStore s;
    DateTime now = DateTime(2026, 11, 11, 9);
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('daiban_plan');
      SharedPreferences.setMockInitialValues({});
      now = DateTime(2026, 11, 11, 9);
      s = TodoStore(dir: tmp, prefs: await SharedPreferences.getInstance(), now: () => now);
    });
    tearDown(() async => tmp.delete(recursive: true));

    String? planOf(String name) => [...s.todo, ...s.done].firstWhere((t) => t.text == name).plan == null
        ? null
        : f([...s.todo, ...s.done].firstWhere((t) => t.text == name).plan);

    test('导入时给每个有日期的任务写入 plan:，无日期的不写，界面 / 编辑文本里看不到', () async {
      await s.applyImport(s.preview('甲 +408 due:2026-11-11\n乙 +408 t:2026-11-12\n丙 +408\n'), replace: true);
      expect(planOf('甲'), '2026-11-11');
      expect(planOf('乙'), '2026-11-12');
      expect(planOf('丙'), isNull);
      final a = s.todo.firstWhere((t) => t.text == '甲');
      expect(a.text, '甲');
      expect(a.editableText, '甲 +408');
      expect(await s.todoFile.readAsString(), contains('plan:2026-11-11'));
    });

    test('重复导入同一份文本仍会去重（plan: 不影响比较）', () async {
      await s.applyImport(s.preview('甲 +408 due:2026-11-11\n乙 +408 due:2026-11-12\n'), replace: true);
      final skipped = await s.applyImport(s.preview('甲 +408 due:2026-11-11\n乙 +408 due:2026-11-12\n'), replace: false);
      expect(skipped, 2);
      expect(s.todo.length, 2);
    });

    test('完成即提前改写 due/t，plan: 不变；预计 = 按原计划的量', () async {
      await s.applyImport(
          s.preview('甲 +408 due:2026-11-11\n乙 +408 due:2026-11-12\n丙 +408 due:2026-11-14\n'),
          replace: true);
      await s.complete(s.todo.firstWhere((t) => t.text == '甲'));
      final b = s.todo.firstWhere((t) => t.text == '乙');
      final c = s.todo.firstWhere((t) => t.text == '丙');
      expect(f(b.date), '2026-11-11'); // 被提前到今天
      expect(f(c.date), '2026-11-13');
      expect(planOf('乙'), '2026-11-12'); // 原计划不变
      expect(planOf('丙'), '2026-11-14');
      var e = Estimator.forCategory(s.todo, s.done, s.today, '408');
      expect(f(e.planDate), '2026-11-14');
      expect(e.earlyDays, 0); // 乙还没做完
      expect(Estimator.compact(e, s.today), contains('与计划持平'));
      // 做完乙：11-12 的量提前完成 → 预计 11-13
      await s.complete(b);
      e = Estimator.forCategory(s.todo, s.done, s.today, '408');
      expect(e.earlyDays, 1);
      expect(f(e.estDate), '2026-11-13');
      expect(Estimator.compact(e, s.today), contains('预计 11月13日（提前 1 天）'));
      // 完成后 done.txt 里仍保留 plan:
      expect(await s.doneFile.readAsString(), contains('plan:2026-11-12'));
    });

    test('整体顺延改写 due/t，plan: 不变；落后天数按原计划算', () async {
      await s.applyImport(
          s.preview('甲 +408 due:2026-11-11\n乙 +408 due:2026-11-12\n丙 +408 due:2026-11-14\n'),
          replace: true);
      now = DateTime(2026, 11, 12, 9); // 甲没做，隔天
      await s.checkDayChange();
      expect(f(s.todo.firstWhere((t) => t.text == '乙').date), '2026-11-13'); // 顺延
      expect(planOf('乙'), '2026-11-12');
      expect(planOf('丙'), '2026-11-14');
      final e = Estimator.forCategory(s.todo, s.done, s.today, '408');
      expect(e.lateDays, 1); // 11-11 的量没完成
      expect(f(e.planDate), '2026-11-14');
      expect(f(e.estDate), '2026-11-15');
      expect(Estimator.compact(e, s.today), contains('落后 1 天'));
    });

    test('取消完成还原提前后，plan: 仍是原计划日', () async {
      await s.applyImport(s.preview('甲 +408 due:2026-11-11\n乙 +408 due:2026-11-12\n'), replace: true);
      final a = s.todo.firstWhere((t) => t.text == '甲');
      await s.complete(a);
      await s.reopen(s.done.firstWhere((t) => t.text == '甲'));
      expect(f(s.todo.firstWhere((t) => t.text == '乙').date), '2026-11-12');
      expect(planOf('乙'), '2026-11-12');
      expect(planOf('甲'), '2026-11-11');
    });

    test('编辑任务：日期没改保留原计划日；手动改了日期则按新日期重新计划', () async {
      await s.applyImport(s.preview('甲 +408 due:2026-11-11\n乙 +408 due:2026-11-12\n'), replace: true);
      final a = s.todo.firstWhere((t) => t.text == '甲');
      await s.complete(a); // 乙被提前到今天，plan 仍是 11-12
      final b = s.todo.firstWhere((t) => t.text == '乙');
      await s.update(b, '乙改名 +408', due: b.due, start: b.start, category: '408');
      expect(planOf('乙改名'), '2026-11-12');
      await s.update(b, '乙改名 +408', due: DateTime(2026, 11, 20), start: null, category: '408');
      expect(planOf('乙改名'), '2026-11-20');
    });

    test('批量平移是手动重新计划：plan: 跟着平移', () async {
      await s.applyImport(s.preview('甲 +408 due:2026-11-12\n乙 +408 due:2026-11-14\n'), replace: true);
      await s.shiftMany(s.todo, 2);
      expect(planOf('甲'), '2026-11-14');
      expect(planOf('乙'), '2026-11-16');
    });

    test('老数据（文件里没有 plan:）加载时补写：当前日期，或用 pf: 还原出原计划日', () async {
      await s.todoFile.writeAsString('甲 +408 due:2026-11-12\n乙 +408 due:2026-11-11 t:2026-11-11 pf:20261111.1.3\n');
      await s.doneFile.writeAsString('x 2026-11-10 丙 +408 due:2026-11-10\n');
      await s.load();
      expect(planOf('甲'), '2026-11-12');
      expect(planOf('乙'), '2026-11-14');
      expect(planOf('丙'), '2026-11-10');
      final raw = await s.todoFile.readAsString();
      expect(raw, contains('plan:2026-11-14'));
      expect(await s.doneFile.readAsString(), contains('plan:2026-11-10'));
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
            store.preview('甲 +408 due:2026-11-11\n乙 +408 due:2026-11-14\nx 2026-11-10 丙 +408 due:2026-11-12\nx 2026-11-10 丁 +408 due:2026-11-13\n数学题 +数学 due:2026-11-11\n'),
            replace: true);
      });
      await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
      await tester.pump();
      final t408 = tester.widget<Text>(find.byKey(const Key('est_408'))).data!;
      expect(t408, contains('进度 2/4'));
      expect(t408, contains('计划 11月14日'));
      expect(t408, contains('预计 11月12日')); // 11-12、11-13 两天的量已提前完成
      expect(t408, contains('提前 2 天'));
      final math = tester.widget<Text>(find.byKey(const Key('est_数学'))).data!;
      expect(math, contains('预计 11月11日（与计划持平）'));
      expect(math, isNot(contains('数据不足')));
    });
  });
}
