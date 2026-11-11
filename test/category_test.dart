import 'dart:io';

import 'package:daiban/data/store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:daiban/logic/planner.dart';
import 'package:daiban/logic/todo_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String due(TodoItem i) => Ymd.fmt(i.due!);
List<String> dueOf(TodoStore s, String cat) =>
    s.todo.where((t) => t.category == cat).map(due).toList();

void main() {
  late Directory tmp;
  late DateTime clock;
  late TodoStore store;

  Future<TodoStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    final s = TodoStore(dir: tmp, prefs: prefs, now: () => clock);
    await s.load();
    return s;
  }

  // 408：今天 2 项 + 明天 1 项 + 后天 1 项；数学：今天 1 项 + 明天 1 项
  const plan = '408 A1 +408 due:2026-11-11\n'
      '408 A2 +408 due:2026-11-11\n'
      '408 B +408 due:2026-11-12\n'
      '408 C +408 due:2026-11-13\n'
      '数学 A +数学 due:2026-11-11\n'
      '数学 B +数学 due:2026-11-12\n'
      '杂事 今天 due:2026-11-11\n'
      '杂事 明天 due:2026-11-12\n';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('daiban_cat');
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 11, 11, 9);
    store = await open();
    await store.applyImport(store.preview(plan), replace: true);
  });
  tearDown(() async => tmp.delete(recursive: true));

  TodoItem find(String text) => store.todo.firstWhere((t) => t.text == text);

  group('类别识别', () {
    test('类别 = 第一个 +标签；无标签为未分类', () {
      expect(TodoItem.parse('x +408 +数据结构 a')!.category, '408');
      expect(TodoItem.parse('a @家里')!.category, isNull);
      expect(find('408 A1').category, '408');
      expect(find('杂事 今天').category, isNull);
      expect(store.categories, ['408', '数学']);
      expect(store.hasUncategorized, true);
    });
    test('setCategory：成为第一个标签，保留/清除其它标签', () {
      final a = TodoItem.parse('背书 +数据结构 @家里 due:2026-11-11')!;
      a.setCategory('408');
      expect(a.toLine(), '背书 +408 +数据结构 @家里 due:2026-11-11');
      final b = TodoItem.parse('背书 +数据结构 +408')!..setCategory('408');
      expect(b.toLine(), '背书 +408 +数据结构');
      final c = TodoItem.parse('背书 +数据结构')!..setCategory('408', keepOther: false);
      expect(c.toLine(), '背书 +408');
      final d = TodoItem.parse('背书')!..setCategory(' +数学 ');
      expect(d.toLine(), '背书 +数学');
      final e = TodoItem.parse('背书 +x')!..setCategory('');
      expect(e.toLine(), '背书 +x'); // 空类别 + 保留 = 不改动
    });
    test('replaceCategory：就地替换第一个标签；空 = 未分类', () {
      final a = TodoItem.parse('背书 +408 +数据结构')!..replaceCategory('数学');
      expect(a.toLine(), '背书 +数学 +数据结构');
      a.replaceCategory(null);
      expect(a.toLine(), '背书');
    });
  });

  group('按类别提前 pull-forward', () {
    test('408 今日做完 → 只提前 408 的下一批，数学和未分类原封不动', () async {
      expect(await store.complete(find('408 A1')), isNull); // 还剩 A2
      final msg = await store.complete(find('408 A2'));
      expect(msg, '408 今日任务已完成，已提前下一批');
      expect(dueOf(store, '408'), ['2026-11-11', '2026-11-12']); // B→今天，C→明天
      expect(dueOf(store, '数学'), ['2026-11-11', '2026-11-12']); // 未动
      expect(Ymd.fmt(find('杂事 明天').due!), '2026-11-12');
      expect(Planner.todaySet(store.todo, store.today).where((t) => t.category == '数学').length, 1);
    });

    test('数学今日没做完时，408 做完不影响数学；数学做完只提前数学', () async {
      await store.complete(find('408 A1'));
      await store.complete(find('408 A2'));
      final msg = await store.complete(find('数学 A'));
      expect(msg, '数学 今日任务已完成，已提前下一批');
      expect(dueOf(store, '数学'), ['2026-11-11']);
      expect(dueOf(store, '408'), ['2026-11-11', '2026-11-12']); // 没有被数学的提前再次移动
    });

    test('未分类自成一组', () async {
      final msg = await store.complete(find('杂事 今天'));
      expect(msg, '今日任务已完成，已提前下一批');
      expect(Ymd.fmt(find('杂事 明天').due!), '2026-11-11');
      expect(dueOf(store, '408').first, '2026-11-11');
      expect(dueOf(store, '408').last, '2026-11-13');
    });

    test('单类别开关：408 关 → 不提前；全局关 + 数学开 → 只数学提前', () async {
      await store.setCategoryPull('408', false);
      await store.complete(find('408 A1'));
      expect(await store.complete(find('408 A2')), isNull);
      expect(dueOf(store, '408'), ['2026-11-12', '2026-11-13']);
      await store.setPullForward(false);
      await store.setCategoryPull('数学', true);
      expect(await store.complete(find('杂事 今天')), isNull); // 未分类跟随全局=关
      expect(await store.complete(find('数学 A')), contains('数学'));
    });

    test('手动“提前下一批”按类别，只动该类别', () async {
      final msg = await store.pullNextBatch('数学');
      expect(msg, '数学 已把 11月12日 的任务提前到今天');
      expect(dueOf(store, '数学'), ['2026-11-11', '2026-11-11']);
      expect(dueOf(store, '408'), ['2026-11-11', '2026-11-11', '2026-11-12', '2026-11-13']);
      expect(await store.pullNextBatch('不存在'), '不存在 没有可提前的后续任务');
    });

    test('批量完成：每个类别各自判断', () async {
      final msg = await store.completeMany([find('408 A1'), find('408 A2'), find('数学 A')]);
      expect(msg, contains('408 今日任务已完成'));
      expect(msg, contains('数学 今日任务已完成'));
      expect(dueOf(store, '408'), ['2026-11-11', '2026-11-12']);
      expect(dueOf(store, '数学'), ['2026-11-11']);
    });
  });

  group('按类别顺延 shift-back', () {
    test('只有昨天有未完成的类别被顺延', () async {
      await store.checkDayChange(); // lastProcessed = 11-11
      // 11-11：数学和未分类都做完了（提前功能关掉，避免干扰），408 一项没做
      await store.setPullForward(false);
      await store.complete(find('数学 A'));
      await store.complete(find('杂事 今天'));
      clock = DateTime(2026, 11, 12, 8);
      final msg = await store.checkDayChange();
      expect(msg, '昨日有未完成任务，后续计划已按类别顺延：408 1 天');
      expect(dueOf(store, '408'), ['2026-11-11', '2026-11-11', '2026-11-13', '2026-11-14']);
      expect(dueOf(store, '数学'), ['2026-11-12']); // 未动
      expect(Ymd.fmt(find('杂事 明天').due!), '2026-11-12'); // 未动
    });

    test('单类别顺延开关：408 关 → 不动', () async {
      await store.checkDayChange();
      await store.setCategoryShift('408', false);
      await store.setPullForward(false);
      await store.complete(find('数学 A'));
      clock = DateTime(2026, 11, 12, 8);
      final msg = await store.checkDayChange();
      // 408 关闭顺延 → 不动；数学昨天清空 → 不动；只有未分类（杂事今天没做）被顺延
      expect(msg, '昨日有未完成任务，后续计划已按类别顺延：未分类 1 天');
      expect(Ymd.fmt(find('杂事 明天').due!), '2026-11-13');
      expect(dueOf(store, '408'), ['2026-11-11', '2026-11-11', '2026-11-12', '2026-11-13']);
    }, skip: false);
  });

  group('批量管理', () {
    test('删除全部（待办 + 已完成）可撤销', () async {
      await store.complete(find('数学 A'));
      expect(store.done.length, 1);
      await store.deleteAll();
      expect(store.todo, isEmpty);
      expect(store.done, isEmpty);
      expect(await store.todoFile.readAsString(), '');
      await store.undo();
      expect(store.todo.length, 7);
      expect(store.done.length, 1);
    });
    test('清空已完成', () async {
      await store.complete(find('408 A1'));
      await store.clearDone();
      expect(store.done, isEmpty);
      expect(store.todo.length, 7);
    });
    test('删除某类别的全部任务（待办 + 已完成），其它类别保留', () async {
      await store.setPullForward(false);
      await store.complete(find('408 A1'));
      final n = await store.deleteCategory('408');
      expect(n, 4);
      expect(store.todo.where((t) => t.category == '408'), isEmpty);
      expect(store.done, isEmpty);
      expect(store.todo.length, 4);
      expect(store.categories, ['数学']);
    });
    test('批量删除 / 批量更改类别 / 批量平移 / 重命名合并 / 批量取消完成', () async {
      await store.deleteMany([find('408 A1'), find('408 A2')]);
      expect(store.todo.length, 6);
      await store.setCategoryMany([find('数学 A'), find('数学 B')], '考研数学');
      expect(store.categories, ['408', '考研数学']);
      expect(find('数学 A').toLine(), contains('+考研数学'));
      expect(find('数学 A').toLine(), isNot(contains('+数学')));
      final moved = await store.shiftMany([find('408 B'), find('408 C'), find('杂事 今天')], 2);
      expect(moved, 3);
      expect(due(find('408 B')), '2026-11-14');
      expect(due(find('408 C')), '2026-11-15');
      await store.shiftMany([find('408 B')], -3);
      expect(due(find('408 B')), '2026-11-11');
      expect(await store.renameCategory('考研数学', '408'), 2);
      expect(store.categories, ['408']);
      await store.setPullForward(false);
      await store.completeMany([find('数学 A')]);
      await store.reopenMany(store.done);
      expect(store.done, isEmpty);
      await store.undo();
      expect(store.done.length, 1);
    });
    test('批量平移：没有日期的任务不动', () async {
      await store.add('没日期');
      final n = await store.shiftMany(store.todo.where((t) => t.text == '没日期'), 3);
      expect(n, 0);
    });
  });

  group('导入时设置类别', () {
    test('txt：无标签 → 全部加上 +408；保留 / 清除原有标签', () async {
      var s = await open();
      var p = s.preview('背单词 due:2026-11-11\n做试卷 +数据结构 @家里 due:2026-11-12');
      expect(p.defaultCategory, '数据结构'); // 默认取任务里已有的第一个 +标签
      p.applyCategory('408');
      expect(p.todo.map((e) => e.toLine()).toList(),
          ['背单词 due:2026-11-11 +408', '做试卷 +408 +数据结构 @家里 due:2026-11-12']);
      p = s.preview('做试卷 +数据结构 due:2026-11-12');
      p.applyCategory('408', keepOtherTags: false);
      expect(p.todo.single.toLine(), '做试卷 due:2026-11-12 +408');
      await s.applyImport(p, replace: true);
      expect(s.categories, ['408']);
    });
    test('ics：默认类别 = 日历名第一个词；改成“数学”后科目标签保留为次要标签', () async {
      final ics = File('test/fixtures/plan408.ics').readAsStringSync();
      final p = store.preview(ics);
      expect(p.fromIcs, true);
      expect(p.defaultCategory, '408');
      expect(p.todo.first.toLine(), contains('+408 +数据结构'));
      expect(p.todo.every((t) => t.category == '408'), true);
      p.applyCategory('数学');
      expect(p.todo.first.toLine(), '数据结构 上午 3.4 数组和特殊矩阵压缩存储（p101-108） +数学 +408 +数据结构 due:2026-11-11 t:2026-11-11');
      expect(p.todo.every((t) => t.category == '数学'), true);
      await store.applyImport(p, replace: false);
      expect(store.categories, ['408', '数学']);
      expect(store.todo.where((t) => t.category == '数学').length, 140); // 138 条导入 + 原有 2 条
    });
    test('两份计划分别导入为 408 / 数学：408 做完只提前 408', () async {
      final s = await open();
      final p1 = s.preview('408 一 due:2026-11-11\n408 二 due:2026-11-12');
      p1.applyCategory('408');
      await s.applyImport(p1, replace: true);
      final p2 = s.preview('数学 一 due:2026-11-11\n数学 二 due:2026-11-12');
      p2.applyCategory('数学');
      await s.applyImport(p2, replace: false);
      await s.complete(s.todo.firstWhere((t) => t.text == '408 一'));
      expect(dueOf(s, '408'), ['2026-11-11']);
      expect(dueOf(s, '数学'), ['2026-11-11', '2026-11-12']);
    });
    test('编辑页：更改类别 / 变为未分类', () async {
      final it = find('408 A1');
      await store.update(it, it.editableTextNoCategory, category: '数学');
      expect(it.category, '数学');
      expect(it.toLine(), contains('+数学'));
      await store.update(it, it.editableTextNoCategory, category: '');
      expect(it.category, isNull);
      await store.add('新任务', category: '408', due: Ymd.parse('2026-11-11'));
      expect(store.todo.last.category, '408');
    });
  });
}
