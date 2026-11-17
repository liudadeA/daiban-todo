import 'dart:io';

import 'package:daiban/data/store.dart';
import 'package:daiban/logic/app_edition.dart';
import 'package:daiban/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  late TodoStore store;

  Future<void> load(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(prefs);
      dir = await Directory.systemTemp.createTemp('all_sort_');
      store = TodoStore(
        dir: dir,
        prefs: await SharedPreferences.getInstance(),
        now: () => DateTime(2026, 11, 11, 9),
      );
      await store.applyImport(
        store.preview(
          '甲 +408 due:2026-11-10\n'
          '乙 +数学 due:2026-11-11\n'
          '丙 +408 due:2026-11-11\n'
          '丁 due:2026-11-14\n'
          '戊 +408 due:2026-11-16\n',
        ),
        replace: true,
      );
    });
  }

  Future<void> open(WidgetTester tester, {required String tab}) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pump();
    if (tab != '今日') {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
      await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    }
  }

  int yOf(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy.round();

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  testWidgets('今日与全部都有右上角切换；已完成没有；默认按时间', (tester) async {
    await load(tester);
    await open(tester, tab: '今日');
    expect(find.byKey(const Key('todaySortToggle')), findsOneWidget);
    expect(find.byKey(const Key('allSortToggle')), findsNothing);
    expect(find.text('按时间'), findsOneWidget);
    expect(find.text('408 · 今日剩余 2 项'), findsNothing);
    // 今日按时间：逾期甲在前，当天乙/丙在后；未来的丁、戊不出现
    expect(find.text('甲'), findsOneWidget);
    expect(find.text('乙'), findsOneWidget);
    expect(find.text('丙'), findsOneWidget);
    expect(find.text('丁'), findsNothing);
    expect(find.text('戊'), findsNothing);
    expect(yOf(tester, find.text('甲')), lessThan(yOf(tester, find.text('乙'))));
    expect(yOf(tester, find.text('甲')), lessThan(yOf(tester, find.text('丙'))));

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('全部')));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('allSortToggle')), findsOneWidget);
    expect(find.byKey(const Key('todaySortToggle')), findsNothing);
    expect(find.text('按时间'), findsOneWidget);
    expect(find.text('408 · 3 项'), findsNothing);
    expect(yOf(tester, find.text('甲')), lessThan(yOf(tester, find.text('乙'))));
    expect(yOf(tester, find.text('丙')), lessThan(yOf(tester, find.text('丁'))));
    expect(yOf(tester, find.text('丁')), lessThan(yOf(tester, find.text('戊'))));

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('已完成')));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('todaySortToggle')), findsNothing);
    expect(find.byKey(const Key('allSortToggle')), findsNothing);
  });

  testWidgets('今日按类别：组内按时间，可折叠；仅有未来任务的未分类仍可提前下一批', (tester) async {
    await load(tester);
    await open(tester, tab: '今日');
    await tester.tap(find.byKey(const Key('todaySortToggle')));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('按类别'), findsOneWidget);
    expect(find.text('408 · 今日剩余 2 项'), findsOneWidget);
    expect(find.text('数学 · 今日剩余 1 项'), findsOneWidget);
    expect(find.text('未分类 · 今日已清空'), findsOneWidget);
    expect(yOf(tester, find.text('408 · 今日剩余 2 项')), lessThan(yOf(tester, find.text('数学 · 今日剩余 1 项'))));
    expect(yOf(tester, find.text('数学 · 今日剩余 1 项')), lessThan(yOf(tester, find.text('未分类 · 今日已清空'))));
    expect(yOf(tester, find.text('甲')), lessThan(yOf(tester, find.text('丙'))));
    // 408 有未来的戊、未分类有未来的丁，均可提前下一批（与改前今日页行为一致）
    expect(find.text('提前下一批'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('today_cat_408')));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('甲'), findsNothing);
    expect(find.text('丙'), findsNothing);
    expect(find.text('乙'), findsOneWidget);

    await tester.tap(find.byKey(const Key('today_cat_408')));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('甲'), findsOneWidget);
    expect(find.text('丙'), findsOneWidget);
  });

  testWidgets('全部按类别：组内仍按时间，未分类单独一组，可折叠展开', (tester) async {
    await load(tester);
    await open(tester, tab: '全部');
    await tester.tap(find.byKey(const Key('allSortToggle')));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('按类别'), findsOneWidget);
    expect(find.text('408 · 3 项'), findsOneWidget);
    expect(find.text('数学 · 1 项'), findsOneWidget);
    expect(find.text('未分类 · 1 项'), findsOneWidget);
    expect(yOf(tester, find.text('408 · 3 项')), lessThan(yOf(tester, find.text('数学 · 1 项'))));
    expect(yOf(tester, find.text('数学 · 1 项')), lessThan(yOf(tester, find.text('未分类 · 1 项'))));
    expect(yOf(tester, find.text('甲')), lessThan(yOf(tester, find.text('丙'))));
    expect(yOf(tester, find.text('丙')), lessThan(yOf(tester, find.text('戊'))));

    await tester.tap(find.byKey(const Key('all_cat_408')));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('甲'), findsNothing);
    expect(find.text('丙'), findsNothing);
    expect(find.text('戊'), findsNothing);
    expect(find.text('乙'), findsOneWidget);
    expect(find.text('丁'), findsOneWidget);

    await tester.tap(find.byKey(const Key('all_cat_408')));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('甲'), findsOneWidget);
    expect(find.text('戊'), findsOneWidget);
  });

  testWidgets('今日与全部各自记住排序，默认仍是按时间', (tester) async {
    await load(tester);
    expect(store.prefs.getBool(HomePageState.todaySortPrefKey), isNull);
    expect(store.prefs.getBool(HomePageState.allSortPrefKey), isNull);
    await open(tester, tab: '今日');
    await tester.tap(find.byKey(const Key('todaySortToggle')));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(store.prefs.getBool(HomePageState.todaySortPrefKey), isTrue);
    expect(store.prefs.getBool(HomePageState.allSortPrefKey), isNull);

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('全部')));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('按时间'), findsOneWidget);
    await tester.tap(find.byKey(const Key('allSortToggle')));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(store.prefs.getBool(HomePageState.allSortPrefKey), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: HomePage(store: store)));
    await tester.pump();
    expect(find.byKey(const Key('todaySortToggle')), findsOneWidget);
    expect(find.text('按类别'), findsOneWidget);
    expect(find.text('408 · 今日剩余 2 项'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('全部')));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('按类别'), findsOneWidget);
    expect(find.text('408 · 3 项'), findsOneWidget);
  });

  testWidgets('专注版顶栏去掉「专注版」；基础版顶栏保持「基础版」', (tester) async {
    await load(tester);
    await open(tester, tab: '今日');
    if (AppEdition.profile.isFocus) {
      expect(find.text('待办 · 今日'), findsOneWidget);
      expect(find.text('待办 专注版 · 今日'), findsNothing);
    } else {
      expect(find.text('待办 基础版 · 今日'), findsOneWidget);
    }
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('全部')));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    if (AppEdition.profile.isFocus) {
      expect(find.text('待办 · 全部任务'), findsOneWidget);
      expect(find.text('待办 专注版 · 全部任务'), findsNothing);
      expect(find.textContaining('专注版'), findsNothing);
    } else {
      expect(find.text('待办 基础版 · 全部任务'), findsOneWidget);
    }
  });
}
