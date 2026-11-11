import 'dart:io';

import 'package:daiban/data/store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:daiban/logic/planner.dart';
import 'package:daiban/logic/todo_item.dart';
import 'package:daiban/logic/widget_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String due(TodoItem i) => Ymd.fmt(i.due!);

void main() {
  late Directory tmp;
  late DateTime clock;

  Future<TodoStore> open() async {
    final s = TodoStore(dir: tmp, prefs: await SharedPreferences.getInstance(), now: () => clock);
    await s.load();
    return s;
  }

  TodoItem byText(TodoStore s, String t) => [...s.todo, ...s.done].firstWhere((e) => e.text == t);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('daiban_pb');
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 11, 11, 20);
  });
  tearDown(() async => tmp.delete(recursive: true));

  const plan = '''
今日甲 +408 due:2026-11-11 t:2026-11-11
今日乙 +408 due:2026-11-11 t:2026-11-11
次批一 +408 due:2026-11-12 t:2026-11-12
次批二 +408 due:2026-11-12 t:2026-11-12
再后一 +408 due:2026-11-13 t:2026-11-13
再后二 +408 due:2026-11-15 t:2026-11-15
数学今日 +数学 due:2026-11-11
数学次日 +数学 due:2026-11-12
''';

  group('提前后的任务就是今日任务', () {
    test('日期被改写为今天（due 和 t），相对标签是“今日”，后续整体前移', () async {
      final s = await open();
      await s.applyImport(s.preview(plan), replace: true);
      await s.complete(byText(s, '今日甲'));
      final msg = await s.complete(byText(s, '今日乙'));
      expect(msg, contains('408 今日任务已完成，已提前下一批'));
      for (final n in ['次批一', '次批二']) {
        final i = byText(s, n);
        expect(due(i), '2026-11-11');
        expect(Ymd.fmt(i.start!), '2026-11-11');
        expect(Ymd.relative(i.due!, s.today), '今日');
        expect(Ymd.chipLabel(i.due!, s.today), '今日（11-11）');
        expect(Planner.inToday(i, s.today), isTrue);
        expect(i.pulledOn(s.today), isTrue);
        expect(i.text, n); // 隐藏标签不出现在显示文字里
      }
      expect(due(byText(s, '再后一')), '2026-11-12'); // 后续同步前移 1 天
      expect(Ymd.relative(byText(s, '再后一').due!, s.today), '明日');
      expect(due(byText(s, '再后二')), '2026-11-14');
      expect(due(byText(s, '数学次日')), '2026-11-12'); // 其它类别不受影响
      // 快照（桌面组件）里也是今日任务
      final rows = (WidgetActions.snapshot(s)['rows'] as List).cast<Map>();
      final names = rows.where((r) => r['type'] == 'task').map((r) => r['text']).toList();
      expect(names, containsAll(['次批一', '次批二']));
      expect(names, isNot(contains('再后一')));
    });

    test('相对日期标签现算：昨日 / 逾期 / 远期显示完整日期', () {
      final t = Ymd.of(2026, 11, 11);
      expect(Ymd.relative(Ymd.of(2026, 11, 12), t), '明日');
      expect(Ymd.relative(Ymd.of(2026, 11, 13), t), '后天');
      expect(Ymd.relative(Ymd.of(2026, 11, 10), t), '昨日');
      expect(Ymd.relative(Ymd.of(2026, 11, 8), t), '逾期 3 天');
      expect(Ymd.chipLabel(Ymd.of(2026, 11, 20), t), '2026-11-20');
    });
  });

  group('取消完成 → 还原提前', () {
    test('取消完成今天原本的任务：被提前的一批回到原日期，后续也还原；只显示今天的', () async {
      final s = await open();
      await s.applyImport(s.preview(plan), replace: true);
      await s.complete(byText(s, '今日甲'));
      await s.complete(byText(s, '今日乙'));
      expect(due(byText(s, '次批一')), '2026-11-11');
      final msg = await s.reopen(s.done.firstWhere((e) => e.text == '今日乙'));
      expect(msg, contains('408 已还原刚才提前的任务'));
      expect(due(byText(s, '次批一')), '2026-11-12');
      expect(Ymd.fmt(byText(s, '次批二').start!), '2026-11-12');
      expect(due(byText(s, '再后一')), '2026-11-13');
      expect(due(byText(s, '再后二')), '2026-11-15');
      expect(byText(s, '次批一').pulls, isEmpty);
      expect(byText(s, '次批一').toLine(), '次批一 +408 due:2026-11-12 t:2026-11-12 plan:2026-11-12');
      final todays = s.todo.where((t) => t.category == '408' && Planner.inToday(t, s.today)).map((t) => t.text).toList();
      expect(todays, ['今日乙']);
      // 其它类别不受影响
      expect(due(byText(s, '数学次日')), '2026-11-12');
    });

    test('重启后仍能还原（记录写在 todo.txt 里）；组件勾选的提前同样可还原', () async {
      var s = await open();
      await s.applyImport(s.preview(plan), replace: true);
      await s.complete(byText(s, '今日甲'));
      // 第二项通过桌面组件的后台回调完成
      final b = byText(s, '今日乙');
      await WidgetActions.handle(s, WidgetActions.completeUri(WidgetActions.idOf(b)));
      expect(due(byText(s, '次批一')), '2026-11-11');
      expect(File('${tmp.path}/todo.txt').readAsStringSync(), contains('pf:20261111.1.1'));
      s = await open(); // 模拟 App 重启
      expect(byText(s, '次批一').pulledOn(s.today), isTrue);
      await s.reopen(s.done.firstWhere((e) => e.text == '今日甲'));
      expect(due(byText(s, '次批一')), '2026-11-12');
      expect(due(byText(s, '再后二')), '2026-11-15');
      expect(File('${tmp.path}/todo.txt').readAsStringSync(), isNot(contains('pf:')));
    });

    test('连续提前多次：取消完成最早的任务，最近几批依次还原，直到今天没有被提前的任务', () async {
      final s = await open();
      await s.applyImport(s.preview(plan), replace: true);
      await s.complete(byText(s, '今日甲'));
      await s.complete(byText(s, '今日乙')); // 提前一：次批一/二 → 今日
      await s.complete(byText(s, '次批一'));
      await s.complete(byText(s, '次批二')); // 提前二：再后一 → 今日
      expect(due(byText(s, '再后一')), '2026-11-11');
      expect(due(byText(s, '再后二')), '2026-11-13');
      await s.reopen(s.done.firstWhere((e) => e.text == '今日甲'));
      // 最近一批（再后一/再后二）已还原到“提前一”之后的位置（11-12 / 11-14）；
      // 次批一/二已经做完，第一次提前的前移保留（明天的活今天做完了，后续本来就该前移一天）
      expect(due(byText(s, '再后一')), '2026-11-12');
      expect(due(byText(s, '再后二')), '2026-11-14');
      expect(Ymd.relative(byText(s, '再后一').due!, s.today), '明日');
      final todays = s.todo.where((t) => t.category == '408' && Planner.inToday(t, s.today)).map((t) => t.text).toList();
      expect(todays, ['今日甲']);
    });

    test('取消完成一个被提前过又完成的任务，也算今天的原任务 → 只还原最近一批', () async {
      final s = await open();
      await s.applyImport(s.preview(plan), replace: true);
      await s.complete(byText(s, '今日甲'));
      await s.complete(byText(s, '今日乙')); // 提前一
      await s.complete(byText(s, '次批一'));
      await s.complete(byText(s, '次批二')); // 提前二
      await s.reopen(s.done.firstWhere((e) => e.text == '次批一'));
      expect(due(byText(s, '再后一')), '2026-11-12'); // 提前二还原（回到提前一之后的位置）
      final todays = s.todo.where((t) => t.category == '408' && Planner.inToday(t, s.today)).map((t) => t.text).toList();
      expect(todays, ['次批一']);
    });

    test('取消完成的任务不在今日（提前完成的未来任务）→ 不还原', () async {
      final s = await open();
      await s.applyImport(s.preview(plan), replace: true);
      await s.complete(byText(s, '今日甲'));
      await s.complete(byText(s, '今日乙')); // 次批 → 今日
      await s.complete(byText(s, '再后二')); // 提前完成一个未来任务（今日还有次批，不触发提前）
      final msg = await s.reopen(s.done.firstWhere((e) => e.text == '再后二'));
      expect(msg, isNull); // 它是未来任务，不是今天的“原任务”
      expect(due(byText(s, '次批一')), '2026-11-11');
    });

    test('隔天后提前记录被清理，不再还原', () async {
      final s = await open();
      await s.applyImport(s.preview(plan), replace: true);
      await s.complete(byText(s, '今日甲'));
      await s.complete(byText(s, '今日乙'));
      await s.complete(byText(s, '次批一'));
      expect(File('${tmp.path}/todo.txt').readAsStringSync(), contains('pf:'));
      clock = DateTime(2026, 11, 12, 8);
      await s.checkDayChange();
      expect(File('${tmp.path}/todo.txt').readAsStringSync(), isNot(contains('pf:')));
      // 昨天的原任务现在取消完成：不会把昨天提前的任务再推回去
      final before = byText(s, '次批二').toLine();
      await s.reopen(s.done.firstWhere((e) => e.text == '今日甲'));
      expect(byText(s, '次批二').toLine(), before);
    });

    test('撤销（一步）仍然可用：提前 + 记录一起恢复', () async {
      final s = await open();
      await s.applyImport(s.preview(plan), replace: true);
      await s.complete(byText(s, '今日甲'));
      await s.complete(byText(s, '今日乙'));
      await s.undo();
      expect(due(byText(s, '次批一')), '2026-11-12');
      expect(byText(s, '次批一').pulls, isEmpty);
    });
  });

  test('pf 标签不影响显示 / 编辑文字，完成时清除', () {
    final i = TodoItem.parse('读书 +408 due:2026-11-11 pf:20261111.1.2,20261111.2.1')!;
    expect(i.text, '读书');
    expect(i.editableText, contains('+408'));
    expect(i.editableText, isNot(contains('pf:')));
    expect(i.editableTextNoCategory, isNot(contains('pf:')));
    expect(i.pulls.map((e) => e.gap), [2, 1]);
    i.complete(Ymd.of(2026, 11, 11));
    expect(i.toLine(), isNot(contains('pf:')));
  });
}
