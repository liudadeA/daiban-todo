import 'dart:io';

import 'package:daiban/data/store.dart';
import 'package:daiban/logic/todo_item.dart';
import 'package:daiban/logic/widget_actions.dart';
import 'package:daiban/ui/category_widgets.dart';
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

  String textOf(TodoItem t) => t.text;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('import_replace_');
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 11, 16, 9);
    s = await open();
    await s.applyImport(
        s.preview('旧408待办 +408 due:2026-11-16\n'
            'x 2026-11-15 旧408已完成 +408 due:2026-11-15\n'
            '旧数学待办 +数学 due:2026-11-16\n'
            'x 2026-11-15 旧数学已完成 +数学 due:2026-11-15\n'
            '旧未分类 due:2026-11-16\n'
            'x 2026-11-15 旧未分类已完成 due:2026-11-15\n'),
        replace: true);
  });
  tearDown(() async => dir.delete(recursive: true));

  test('覆盖只替换导入中出现的类别，其它类别的待办和已完成都保留', () async {
    final p = s.preview('新408 +408 due:2026-11-16\nx 2026-11-16 新408已完成 +408 due:2026-11-16');
    final skipped = await s.applyImport(p, replace: true);
    expect(skipped, 0);
    expect(s.todo.map(textOf), ['旧数学待办', '旧未分类', '新408']);
    expect(s.done.map(textOf), ['旧408已完成', '旧数学已完成', '旧未分类已完成', '新408已完成']);
    expect(s.todo.any((t) => t.text == '旧408待办'), isFalse);
    expect(s.done.any((t) => t.text == '旧408已完成'), isTrue);
    s = await open();
    expect(s.todo.map(textOf), ['旧数学待办', '旧未分类', '新408']);
    expect(s.done.map(textOf), ['旧408已完成', '旧数学已完成', '旧未分类已完成', '新408已完成']);
    final names = (WidgetActions.snapshot(s)['rows'] as List).where((r) => r['type'] == 'task').map((r) => r['text']);
    expect(names, containsAll(['新408', '旧数学待办', '旧未分类']));
    expect(names, isNot(contains('旧408待办')));
  });

  test('一份文件含多个类别时，只覆盖这些类别', () async {
    final p = s.preview('新408 +408 due:2026-11-17\n新数学 +数学 due:2026-11-18');
    await s.applyImport(p, replace: true);
    expect(s.todo.map(textOf), ['旧未分类', '新408', '新数学']);
    expect(s.done.map(textOf), ['旧408已完成', '旧数学已完成', '旧未分类已完成']);
  });

  test('只导入未分类时，仅替换未分类，已有类别不动', () async {
    final p = s.preview('新未分类 due:2026-11-18');
    await s.applyImport(p, replace: true);
    expect(s.todo.map(textOf), ['旧408待办', '旧数学待办', '新未分类']);
    expect(s.done.map(textOf), ['旧408已完成', '旧数学已完成', '旧未分类已完成']);
  });

  test('对话框设定类别后再覆盖：只替换设定后的那一个类别', () async {
    final p = s.preview('来自日历 +408 due:2026-11-17\n另一条 +数据结构 due:2026-11-18');
    p.applyCategory('数学');
    expect(p.importCategories(), {'数学'});
    await s.applyImport(p, replace: true);
    expect(s.todo.where((t) => t.category == '数学').map(textOf), ['来自日历', '另一条']);
    expect(s.todo.where((t) => t.category == '408').map(textOf), ['旧408待办']);
    expect(s.done.where((t) => t.category == '408').map(textOf), ['旧408已完成']);
    expect(s.done.where((t) => t.category == '数学').map(textOf), ['旧数学已完成']);
    expect(s.todo.any((t) => t.text == '旧数学待办'), isFalse);
  });

  test('追加仍然保留全部现有任务，并跳过完全相同的行', () async {
    final skipped = await s.applyImport(
        s.preview('旧408待办 +408 due:2026-11-16\n额外408 +408 due:2026-11-20'),
        replace: false);
    expect(skipped, 1);
    expect(s.todo.map(textOf), containsAll(['旧408待办', '旧数学待办', '旧未分类', '额外408']));
    expect(s.done.length, 3);
  });

  test('ICS 覆盖只替换该日历设定的类别', () async {
    final ics = File('test/fixtures/plan408.ics').readAsStringSync();
    final p = s.preview(ics);
    expect(p.fromIcs, isTrue);
    p.applyCategory('408');
    await s.applyImport(p, replace: true);
    expect(s.todo.any((t) => t.category == '408' && t.text == '旧408待办'), isFalse);
    expect(s.todo.where((t) => t.category == '408').length, p.todo.length);
    expect(s.todo.map(textOf), containsAll(['旧数学待办', '旧未分类']));
    expect(s.done.map(textOf), containsAll(['旧408已完成', '旧数学已完成', '旧未分类已完成']));
    expect(s.done.where((t) => t.category == '408').map(textOf), ['旧408已完成']);
  });

  test('覆盖后可一步撤销，恢复被替换类别及其它任务', () async {
    await s.applyImport(s.preview('新408 +408 due:2026-11-17'), replace: true);
    await s.undo();
    expect(s.todo.map(textOf), ['旧408待办', '旧数学待办', '旧未分类']);
    expect(s.done.map(textOf), ['旧408已完成', '旧数学已完成', '旧未分类已完成']);
  });


  test('覆盖时已有已完成完全相同则跳过，不会重复追加', () async {
    final skipped = await s.applyImport(
        s.preview('新408 +408 due:2026-11-16\n'
            'x 2026-11-15 旧408已完成 +408 due:2026-11-15\n'),
        replace: true);
    expect(skipped, 1);
    expect(s.done.where((t) => t.text == '旧408已完成').length, 1);
    expect(s.todo.map(textOf), contains('新408'));
    expect(s.todo.any((t) => t.text == '旧408待办'), isFalse);
  });

  testWidgets('导入对话框不再暗示清空全部，提示随类别输入变化', (tester) async {
    final p = s.preview('新408 +408 due:2026-11-17\n新数学 +数学 due:2026-11-18');
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final future = showImportDialog(ctx, s, p);
    await tester.pumpAndSettle();
    final hint = tester.widget<Text>(find.byKey(const Key('import_overwrite_hint')));
    expect(hint.data, contains('只替换「408」这一类别'));
    expect(hint.data, contains('已完成保留'));
    expect(hint.data, isNot(contains('会先清空现有待办和已完成')));
    expect(hint.data, isNot(contains('现有待办和已完成')));
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('import_overwrite_hint'))).data, contains('只替换「408、数学」'));
    expect(tester.widget<Text>(find.byKey(const Key('import_overwrite_hint'))).data, contains('已完成保留'));
    await tester.tap(find.text('保留任务原有的其它 +标签'));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('import_overwrite_hint'))).data, contains('只替换未分类'));
    expect(tester.widget<Text>(find.byKey(const Key('import_overwrite_hint'))).data, contains('已完成保留'));
    await tester.tap(find.text('取消'));
    expect(await future, isNull);
  });
}
