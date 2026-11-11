import 'dart:io';

import 'package:daiban/data/store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:daiban/logic/planner.dart';
import 'package:daiban/logic/todo_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime d(String s) => Ymd.parse(s)!;
TodoItem p(String l, {DateTime? today}) => TodoItem.parse(l, today: today)!;
List<String> dates(List<TodoItem> l) => l.map((e) => e.date == null ? '-' : Ymd.fmt(e.date!)).toList();

void main() {
  group('解析 / 序列化', () {
    test('中文任务 + due/t/项目/情境', () {
      final t = p('做试卷 1 due:2026-11-11 t:2026-11-10 +考研 @家里');
      expect(t.done, false);
      expect(t.text, '做试卷 1');
      expect(t.due, d('2026-11-11'));
      expect(t.start, d('2026-11-10'));
      expect(t.projects, ['考研']);
      expect(t.contexts, ['家里']);
      expect(t.toLine(), '做试卷 1 due:2026-11-11 t:2026-11-10 +考研 @家里');
    });
    test('优先级与创建日期', () {
      final t = p('(A) 2026-11-01 背单词 due:2026-11-12');
      expect(t.priority, 'A');
      expect(t.creationDate, d('2026-11-01'));
      expect(t.text, '背单词');
      expect(t.toLine(), '(A) 2026-11-01 背单词 due:2026-11-12');
    });
    test('已完成行 x 前缀', () {
      final t = p('x 2026-11-10 2026-11-01 做试卷 due:2026-11-10 pri:B');
      expect(t.done, true);
      expect(t.completionDate, d('2026-11-10'));
      expect(t.creationDate, d('2026-11-01'));
      expect(t.toLine(), 'x 2026-11-10 2026-11-01 做试卷 due:2026-11-10 pri:B');
    });
    test('空行与注释被忽略', () {
      expect(TodoItem.parse('   '), isNull);
      expect(TodoItem.parse('# 注释'), isNull);
    });
    test('非法日期不当作 due', () {
      final t = p('任务 due:2026-02-31');
      expect(t.due, isNull);
      expect(t.date, isNull);
    });
    test('全角冒号 / 括号 规整', () {
      final t = p('（a） 复习 due：2026-11-12 t：2026-11-11');
      expect(t.priority, 'A');
      expect(t.due, d('2026-11-12'));
      expect(t.start, d('2026-11-11'));
    });
    test('相对日期换算', () {
      final today = d('2026-11-11');
      expect(p('a due:明天', today: today).due, d('2026-11-12'));
      expect(p('a due:tomorrow t:today', today: today).start, today);
      expect(p('a due:3d', today: today).due, d('2026-11-14'));
      expect(p('a due:+1w', today: today).due, d('2026-11-18'));
    });
    test('完成: 去掉优先级为 pri: 标签，取消完成可恢复', () {
      final t = p('(B) 任务 due:2026-11-11');
      t.complete(d('2026-11-11'));
      expect(t.toLine(), 'x 2026-11-11 任务 due:2026-11-11 pri:B');
      t.reopen();
      expect(t.toLine(), '(B) 任务 due:2026-11-11');
    });
    test('shift 同时平移 due 与 t，跨月/跨年', () {
      final t = p('a due:2026-12-31 t:2026-12-30');
      t.shift(1);
      expect(t.toLine(), 'a due:2027-01-01 t:2026-12-31');
      t.shift(-2);
      expect(t.toLine(), 'a due:2026-12-30 t:2026-12-29');
    });
  });

  group('今日集合', () {
    final today = d('2026-11-11');
    test('今日 = 到期今天 + 逾期，不含未来、不含 t 未到', () {
      final items = [
        p('逾期 due:2026-11-09'),
        p('今天 due:2026-11-11'),
        p('明天 due:2026-11-12'),
        p('未到开始 due:2026-11-11 t:2026-11-12'),
        p('已开始 due:2026-11-11 t:2026-11-10'),
        p('只有t t:2026-11-11'),
        p('无日期'),
      ];
      final set = Planner.todaySet(items, today).map((e) => e.text).toList();
      expect(set, ['逾期', '今天', '已开始', '只有t']);
      expect(items.where((t) => Planner.undatedVisible(t, today)).map((e) => e.text), ['无日期']);
    });
  });

  group('整体顺延 shiftBack', () {
    test('昨天有未完成 → 之后的任务 +1 天，逾期任务不动', () {
      final items = [
        p('A due:2026-11-10'), // 昨天未完成
        p('B due:2026-11-11'),
        p('C due:2026-11-12 t:2026-11-12'),
        p('D due:2026-11-14'),
        p('无日期'),
      ];
      final n = Planner.shiftBack(items, d('2026-11-10'), d('2026-11-11'));
      expect(n, 1);
      expect(dates(items), ['2026-11-10', '2026-11-12', '2026-11-13', '2026-11-15', '-']);
      expect(items[2].toLine(), 'C due:2026-11-13 t:2026-11-13');
    });
    test('昨天没有未完成 → 不变', () {
      final items = [p('B due:2026-11-11'), p('C due:2026-11-12')];
      expect(Planner.shiftBack(items, d('2026-11-10'), d('2026-11-11')), 0);
      expect(dates(items), ['2026-11-11', '2026-11-12']);
    });
    test('已完成任务不参与', () {
      final items = [p('x 2026-11-10 A due:2026-11-10'), p('B due:2026-11-11')];
      expect(Planner.shiftBack(items, d('2026-11-10'), d('2026-11-11')), 0);
      expect(dates(items), ['2026-11-10', '2026-11-11']);
    });
    test('同一天不处理', () {
      final items = [p('A due:2026-11-10')];
      expect(Planner.shiftBack(items, d('2026-11-11'), d('2026-11-11')), 0);
    });
    test('多天未打开：逐天顺延', () {
      final items = [p('A due:2026-11-10'), p('B due:2026-11-11'), p('C due:2026-11-12')];
      // 11-10 打开过，11-13 再打开：经过 11-10/11/12 三天
      final n = Planner.shiftBack(items, d('2026-11-10'), d('2026-11-13'));
      expect(n, 3);
      expect(dates(items), ['2026-11-10', '2026-11-14', '2026-11-15']);
    });
    test('t 未到的未来任务不算“昨天未完成”', () {
      final items = [p('A due:2026-11-10 t:2026-11-12'), p('B due:2026-11-12')];
      expect(Planner.shiftBack(items, d('2026-11-10'), d('2026-11-11')), 0);
    });
  });

  group('逾期滚动 rollover', () {
    test('昨天没做完的任务第二天仍在今日（逾期）里，且在“顺延关闭”时日期不变', () {
      final items = [p('A due:2026-11-10'), p('B due:2026-11-11')];
      final today = d('2026-11-11');
      expect(Planner.todaySet(items, today).map((e) => e.text), ['A', 'B']);
      expect(Ymd.fmt(items[0].due!), '2026-11-10');
    });
  });

  group('完成即提前 pullForward', () {
    final today = d('2026-11-11');
    test('今日已清空 → 下一批整体提前到今天，间隔保持', () {
      final items = [
        p('x 2026-11-11 今天已做 due:2026-11-11'),
        p('B1 due:2026-11-12'),
        p('B2 due:2026-11-12 t:2026-11-12'),
        p('C due:2026-11-14'),
        p('D due:2026-11-20'),
        p('无日期'),
      ];
      final gap = Planner.pullForward(items, today);
      expect(gap, 1);
      expect(dates(items), ['2026-11-11', '2026-11-11', '2026-11-11', '2026-11-13', '2026-11-19', '-']);
      expect(items[2].toLine(), 'B2 due:2026-11-11 t:2026-11-11 pf:20261111.1.1'); // 隐藏的提前记录，供“取消完成”还原
      expect(items[2].text, 'B2'); // 不出现在显示文字里
    });
    test('下一批隔了几天：提前整个间隔', () {
      final items = [p('B due:2026-11-15'), p('C due:2026-11-17')];
      expect(Planner.pullForward(items, today), 4);
      expect(dates(items), ['2026-11-11', '2026-11-13']);
    });
    test('今日还有未完成（含逾期）→ 不提前', () {
      final items = [p('逾期 due:2026-11-09'), p('B due:2026-11-12')];
      expect(Planner.pullForward(items, today), 0);
      expect(dates(items), ['2026-11-09', '2026-11-12']);
    });
    test('没有后续任务 → 不变', () {
      final items = [p('无日期')];
      expect(Planner.pullForward(items, today), 0);
    });
    test('提前后的批次变成今日任务；完成后可继续提前', () {
      final items = [p('B due:2026-11-12'), p('C due:2026-11-13')];
      Planner.pullForward(items, today);
      expect(Planner.todaySet(items, today).map((e) => e.text), ['B']);
      items.removeAt(0);
      expect(Planner.pullForward(items, today), 1);
      expect(dates(items), ['2026-11-11']);
    });
  });

  group('TodoStore 集成（文件持久化 + 开关 + 不冲突）', () {
    late Directory tmp;
    late DateTime clock;
    late TodoStore store;

    Future<TodoStore> make([Map<String, Object> prefsInit = const {}]) async {
      SharedPreferences.setMockInitialValues(prefsInit);
      final prefs = await SharedPreferences.getInstance();
      final s = TodoStore(dir: tmp, prefs: prefs, now: () => clock);
      await s.load();
      return s;
    }

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('daiban_test');
      clock = DateTime(2026, 11, 10, 9, 30);
      store = await make();
    });
    tearDown(() async => tmp.delete(recursive: true));

    const plan = '做试卷 1 due:2026-11-10 +考研\n'
        '做试卷 2 due:2026-11-10 +考研\n'
        '做试卷 3 due:2026-11-11 +考研\n'
        '做试卷 4 due:2026-11-12 +考研\n'
        'x 2026-11-09 昨天做完的 due:2026-11-09\n';

    test('导入：追加/覆盖，待办与已完成分流，UTF-8 持久化', () async {
      final pv = store.preview(plan);
      expect(pv.todo.length, 4);
      expect(pv.done.length, 1);
      await store.applyImport(pv, replace: true);
      final again = await make();
      expect(again.todo.length, 4);
      expect(again.done.length, 1);
      expect(await store.todoFile.readAsString(), contains('做试卷 1'));
      expect(await store.doneFile.readAsString(), contains('昨天做完的'));
      await store.applyImport(store.preview('再加一条 due:2026-11-13'), replace: false);
      expect(store.todo.length, 5);
      expect(store.exportAll(), contains('x 2026-11-09'));
    });

    test('勾选完成 → 归档到 done.txt；全部完成后触发提前并提示', () async {
      await store.applyImport(store.preview(plan), replace: true);
      await store.checkDayChange(); // 初始化 lastProcessed = 11-10
      var msg = await store.complete(store.todo[0]);
      expect(msg, isNull); // 还剩一套
      msg = await store.complete(store.todo[0]);
      expect(msg, contains('今日任务已完成，已提前下一批'));
      // 原 11-11 批次提前到今天 11-10，11-12 → 11-11
      expect(store.todo.map((e) => Ymd.fmt(e.due!)).toList(), ['2026-11-10', '2026-11-11']);
      expect(store.done.length, 3);
      expect((await store.doneFile.readAsString()).split('\n').where((e) => e.isNotEmpty).length, 3);
      expect((await store.todoFile.readAsString()), contains('做试卷 3 due:2026-11-10'));
    });

    test('关闭“完成即提前”开关 → 不提前', () async {
      await store.applyImport(store.preview(plan), replace: true);
      await store.setPullForward(false);
      await store.complete(store.todo[0]);
      final msg = await store.complete(store.todo[0]);
      expect(msg, isNull);
      expect(store.todo.map((e) => Ymd.fmt(e.due!)).toList(), ['2026-11-11', '2026-11-12']);
    });

    test('今日为空时勾选了未来任务 → 同样触发提前（见 bug2 修复：不再要求被勾选的任务属于今日）', () async {
      await store.applyImport(store.preview('明天的 due:2026-11-11\n后天的 due:2026-11-12'), replace: true);
      final msg = await store.complete(store.todo[0]);
      expect(msg, contains('今日任务已完成，已提前下一批'));
      expect(Ymd.fmt(store.todo[0].due!), '2026-11-10');
    });

    test('今日还有任务时勾选未来任务 → 不触发提前', () async {
      await store.applyImport(
          store.preview('今天的 due:2026-11-10\n明天的 due:2026-11-11\n后天的 due:2026-11-12'), replace: true);
      final msg = await store.complete(store.todo[1]);
      expect(msg, isNull);
      expect(Ymd.fmt(store.todo[1].due!), '2026-11-12');
    });

    test('日切：昨天有未完成 → 整体顺延 +1（默认开）', () async {
      await store.applyImport(store.preview(plan), replace: true); // lastProcessed=11-10
      await store.complete(store.todo[0]); // 只做了 1 套
      clock = DateTime(2026, 11, 11, 8, 0);
      final msg = await store.checkDayChange();
      expect(msg, contains('顺延：考研 1 天'));
      expect(store.todo.map((e) => Ymd.fmt(e.due!)).toList(), ['2026-11-10', '2026-11-12', '2026-11-13']);
      expect(Ymd.fmt(store.lastProcessed!), '2026-11-11');
      // 同一天再次检查（app resume）不会重复顺延
      expect(await store.checkDayChange(), isNull);
      expect(store.todo.map((e) => Ymd.fmt(e.due!)).toList(), ['2026-11-10', '2026-11-12', '2026-11-13']);
      // 逾期任务仍在今日
      expect(Planner.todaySet(store.todo, store.today).map((e) => e.text), ['做试卷 2']);
    });

    test('日切：关闭顺延 → 日期不变但推进 lastProcessed', () async {
      await store.applyImport(store.preview(plan), replace: true);
      await store.setShiftBack(false);
      clock = DateTime(2026, 11, 11, 8, 0);
      expect(await store.checkDayChange(), isNull);
      expect(store.todo.map((e) => Ymd.fmt(e.due!)).toList(),
          ['2026-11-10', '2026-11-10', '2026-11-11', '2026-11-12']);
      expect(Ymd.fmt(store.lastProcessed!), '2026-11-11');
    });

    test('日切：昨天全部完成 → 不顺延', () async {
      await store.applyImport(store.preview('A due:2026-11-10\nB due:2026-11-11'), replace: true);
      await store.setPullForward(false);
      await store.complete(store.todo[0]);
      clock = DateTime(2026, 11, 11, 8, 0);
      expect(await store.checkDayChange(), isNull);
      expect(Ymd.fmt(store.todo[0].due!), '2026-11-11');
    });

    test('冲突检查：提前 → 次日顺延 → 再提前，日期保持一致', () async {
      await store.applyImport(
          store.preview('T1 due:2026-11-10\nT2 due:2026-11-11\nT3 due:2026-11-12'), replace: true);
      // 11-10：做完 T1 → T2 提前到今天
      expect(await store.complete(store.todo[0]), isNotNull);
      expect(store.todo.map((e) => Ymd.fmt(e.due!)).toList(), ['2026-11-10', '2026-11-11']);
      // 11-10 没做 T2 就过夜
      clock = DateTime(2026, 11, 11, 7, 0);
      expect(await store.checkDayChange(), contains('顺延：未分类 1 天'));
      // T2 逾期(11-10)，T3 由 11-11 顺延到 11-12
      expect(store.todo.map((e) => Ymd.fmt(e.due!)).toList(), ['2026-11-10', '2026-11-12']);
      // 11-11 做完 T2（逾期，属今日任务）→ T3 提前到今天
      expect(await store.complete(store.todo[0]), contains('今日任务已完成，已提前下一批'));
      expect(Ymd.fmt(store.todo[0].due!), '2026-11-11');
      // 次日再检查：T3 昨天未做 → 顺延机制只动“之后”的任务，T3 本身逾期
      clock = DateTime(2026, 11, 12, 7, 0);
      expect(await store.checkDayChange(), isNull); // 没有后续任务可顺延
      expect(Ymd.fmt(store.todo[0].due!), '2026-11-11');
    });

    test('撤销：提前之后可恢复', () async {
      await store.applyImport(store.preview('A due:2026-11-10\nB due:2026-11-11'), replace: true);
      await store.complete(store.todo[0]);
      expect(Ymd.fmt(store.todo[0].due!), '2026-11-10');
      await store.undo();
      expect(store.todo.map((e) => e.text).toList(), ['A', 'B']);
      expect(Ymd.fmt(store.todo[1].due!), '2026-11-11');
      expect(store.done, isEmpty);
    });

    test('新增 / 编辑 / 删除 / 取消完成', () async {
      await store.add('(B) 新任务 +考研 due:明天');
      expect(store.todo.length, 1);
      expect(Ymd.fmt(store.todo[0].due!), '2026-11-11');
      expect(store.todo[0].creationDate, d('2026-11-10'));
      await store.update(store.todo[0], '改过的任务 +考研', priority: 'A', due: d('2026-11-15'), start: d('2026-11-14'));
      expect(store.todo[0].toLine(), '(A) 2026-11-10 改过的任务 +考研 due:2026-11-15 t:2026-11-14 plan:2026-11-15');
      await store.update(store.todo[0], '改过的任务', priority: null, due: null, start: null);
      expect(store.todo[0].date, isNull);
      await store.complete(store.todo[0]);
      expect(store.done.length, 1);
      await store.reopen(store.done[0]);
      expect(store.todo.length, 1);
      await store.delete(store.todo[0]);
      expect(store.todo, isEmpty);
    });
  });
}
