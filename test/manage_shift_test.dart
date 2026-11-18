import 'dart:io';

import 'package:daiban/data/store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:daiban/ui/manage_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  late TodoStore store;

  Future<void> load(WidgetTester tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('manage_shift_');
      store = TodoStore(
        dir: dir,
        prefs: await SharedPreferences.getInstance(),
        now: () => DateTime(2026, 11, 11, 9),
      );
      await store.applyImport(
        store.preview(
          '408 A +408 due:2026-11-11\n'
          '408 B +408 due:2026-11-12\n'
          '数学 A +数学 due:2026-11-11\n'
          'x 2026-11-10 旧408已完成 +408 due:2026-11-10\n',
        ),
        replace: true,
      );
    });
  }

  DateTime dueOf(String text) => store.todo.firstWhere((t) => t.text == text).due!;

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  testWidgets('类别管理可为每一类平移日期；对话框可选天数，只改该类别未完成任务', (tester) async {
    await load(tester);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: ManagePage(store: store)));
    await tester.pump();
    expect(find.byKey(const Key('manage_shift_408')), findsOneWidget);
    expect(find.byKey(const Key('manage_shift_数学')), findsOneWidget);

    await tester.tap(find.byKey(const Key('manage_shift_408')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('平移「408」的日期'), findsOneWidget);
    expect(find.byKey(const Key('shift_days_field')), findsOneWidget);
    expect(find.byKey(const Key('shift_days_-7')), findsOneWidget);
    expect(find.byKey(const Key('shift_days_-1')), findsOneWidget);
    expect(find.byKey(const Key('shift_days_1')), findsOneWidget);
    expect(find.byKey(const Key('shift_days_7')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('shift_days_field')), '3');
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(Ymd.fmt(dueOf('408 A')), '2026-11-11');

    // 对话框确认会写文件，在 runAsync 里执行与按钮相同的 store API，再核对界面刷新。
    await tester.runAsync(() async {
      await store.shiftCategory('408', 3);
    });
    await tester.pump();
    expect(Ymd.fmt(dueOf('408 A')), '2026-11-14');
    expect(Ymd.fmt(dueOf('408 B')), '2026-11-15');
    expect(Ymd.fmt(dueOf('数学 A')), '2026-11-11');
    expect(Ymd.fmt(store.done.single.due!), '2026-11-10');
    expect(find.textContaining('计划完成 11月15日'), findsOneWidget);
  });
}
