import 'dart:io';

import 'package:daiban/data/store.dart';
import 'package:daiban/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('今日页渲染、勾选完成触发“已提前”提示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late TodoStore store;
    await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      final dir = await Directory.systemTemp.createTemp('daiban_w');
      store = TodoStore(dir: dir, prefs: prefs, now: () => DateTime(2026, 11, 11, 9));
      await store.applyImport(
          store.preview('做试卷 1 due:2026-11-11 +考研\n做试卷 2 due:2026-11-12 +考研\n x 2026-11-10 旧任务'),
          replace: true);
    });
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pump();
    expect(find.text('做试卷 1'), findsOneWidget);
    expect(find.text('做试卷 2'), findsNothing); // 明天的不在今日
    expect(find.byType(Checkbox), findsOneWidget);
    // 文件 IO 需在真实事件循环中执行，因此直接调用与勾选相同的 store.complete
    String? msg;
    await tester.runAsync(() async => msg = await store.complete(store.todo.first));
    expect(msg, contains('今日任务已完成，已提前下一批'));
    await tester.pump();
    expect(find.text('做试卷 2'), findsOneWidget);
    await tester.tap(find.text('全部'));
    await tester.pump();
    expect(find.textContaining('今天'), findsWidgets);
    await tester.tap(find.text('已完成'));
    await tester.pump();
    expect(find.text('做试卷 1'), findsOneWidget);
    expect(find.text('旧任务'), findsOneWidget);
  });

  testWidgets('今日按类别分组，每组有“提前下一批”；长按进入多选', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late TodoStore store;
    await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      final dir = await Directory.systemTemp.createTemp('daiban_w2');
      store = TodoStore(dir: dir, prefs: prefs, now: () => DateTime(2026, 11, 11, 9));
      await store.applyImport(
          store.preview('甲 +408 due:2026-11-11\n乙 +408 due:2026-11-12\n丙 +数学 due:2026-11-11'),
          replace: true);
    });
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pump();
    expect(find.textContaining('408 · 今日剩余 1 项'), findsOneWidget);
    expect(find.textContaining('数学 · 今日剩余 1 项'), findsOneWidget);
    expect(find.text('提前下一批'), findsOneWidget); // 只有 408 有后续任务
    await tester.longPress(find.text('甲'));
    await tester.pump();
    expect(find.text('已选 1 项'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump();
    expect(find.text('已选 2 项'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('已选 2 项'), findsNothing);
  });
}
