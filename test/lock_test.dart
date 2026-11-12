import 'dart:io';

import 'package:daiban/data/focus_store.dart';
import 'package:daiban/data/store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:daiban/logic/focus.dart';
import 'package:daiban/platform/pin.dart';
import 'package:daiban/ui/home_page.dart';
import 'package:daiban/ui/lock_page.dart';
import 'package:daiban/ui/stats_page.dart';
import 'package:daiban/ui/timer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime t(int d, int h, [int m = 0, int s = 0]) => DateTime(2026, 11, d, h, m, s);

FocusSession fs(String id, String? cat, DateTime a, DateTime b, {bool interrupted = false, bool countdown = false}) =>
    FocusSession(
        id: id,
        category: cat,
        start: a,
        end: b,
        interrupted: interrupted,
        kind: countdown ? FocusSession.countdown : FocusSession.forward);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('中断次数只统计锁屏倒计时', () {
    final list = [
      fs('1', '数学', t(12, 8), t(12, 8, 30), interrupted: true), // 正向计时退出：不算
      fs('2', '数学', t(12, 9), t(12, 9, 20), interrupted: true, countdown: true), // 锁屏中断：算
      fs('3', '专业课', t(12, 10), t(12, 10, 45), countdown: true), // 锁屏完成
      fs('4', '专业课', t(11, 10), t(11, 10, 5), interrupted: true, countdown: true), // 前一天
      fs('5', null, t(11, 20), t(11, 21)),
    ];

    test('累计与当日', () {
      final all = FocusCalc.all(list);
      expect(all.count, 5); // 正向计时的中断仍计入次数
      expect(all.seconds, (30 + 20 + 45 + 5 + 60) * 60); // 也计入时长
      expect(all.interrupted, 2);
      expect(FocusCalc.forDay(list, Ymd.of(2026, 11, 12)).interrupted, 1);
      expect(FocusCalc.forDay(list, Ymd.of(2026, 11, 11)).interrupted, 1);
      expect(FocusCalc.forDay(list, Ymd.of(2026, 11, 13)).interrupted, 0);
    });

    test('只有正向计时中断时为 0', () {
      final only = [fs('a', '数学', t(12, 8), t(12, 9), interrupted: true)];
      expect(FocusCalc.all(only).interrupted, 0);
      expect(FocusCalc.forDay(only, Ymd.of(2026, 11, 12)).interrupted, 0);
      expect(FocusCalc.all(only).count, 1);
    });

    test('kind 持久化；旧记录默认为正向计时', () {
      final j = fs('x', '数学', t(12, 8), t(12, 9), countdown: true).toJson();
      expect(j['kind'], 'countdown');
      expect(FocusSession.fromJson(j)!.isCountdown, isTrue);
      final old = Map<String, dynamic>.from(j)..remove('kind');
      expect(FocusSession.fromJson(old)!.isCountdown, isFalse);
    });
  });

  test('倒计时显示：不足 1 小时 MM:SS，否则 HH:MM:SS', () {
    expect(fmtCountdown(25 * 60), '25:00');
    expect(fmtCountdown(59), '00:59');
    expect(fmtCountdown(90 * 60), '01:30:00');
    expect(fmtCountdown(-3), '00:00');
  });

  group('FocusStore 锁屏倒计时', () {
    late Directory tmp;
    late DateTime now;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('daiban_lock');
      SharedPreferences.setMockInitialValues({});
      now = t(12, 9);
    });
    tearDown(() async => tmp.delete(recursive: true));
    Future<FocusStore> mk() async => FocusStore(dir: tmp, prefs: await SharedPreferences.getInstance(), now: () => now);

    test('开始 → 到点：记为完成，时长 = 计划时长；记住时长与类别', () async {
      final f = await mk();
      await f.load();
      expect(f.lastLockMinutes, 25);
      expect(await f.startCountdown('数学', const Duration(minutes: 45)), isTrue);
      expect(f.isCountdown, isTrue);
      expect(await f.start('英语'), isFalse); // 同一时间只能一个计时
      now = now.add(const Duration(minutes: 10));
      expect(f.remainingSeconds, 35 * 60);
      expect(f.plannedSeconds, 45 * 60);
      now = now.add(const Duration(minutes: 35));
      final rec = await f.completeCountdown();
      expect(rec!.interrupted, isFalse);
      expect(rec.isCountdown, isTrue);
      expect(rec.seconds, 45 * 60);
      expect(f.isRunning, isFalse);
      expect(f.lastLockMinutes, 45);
      expect(f.lastLockCategory, '数学');
      final g = await mk();
      await g.load();
      expect(g.sessions.single.isCountdown, isTrue);
    });

    test('提前解除：不足 10 秒不记；否则记为中断', () async {
      final f = await mk();
      await f.load();
      await f.startCountdown(null, const Duration(minutes: 25));
      now = now.add(const Duration(seconds: 9));
      expect(await f.interruptCountdown(), isNull);
      expect(f.sessions, isEmpty);
      expect(f.isRunning, isFalse);
      await f.startCountdown(null, const Duration(minutes: 25));
      now = now.add(const Duration(minutes: 3));
      final rec = await f.interruptCountdown();
      expect(rec!.interrupted, isTrue);
      expect(rec.isCountdown, isTrue);
      expect(rec.seconds, 180);
      expect(FocusCalc.all(f.sessions).interrupted, 1);
    });

    test('进程被杀：未到点则恢复；已过点则按计划时长记为完成并给出提示', () async {
      final f = await mk();
      await f.load();
      await f.startCountdown('专业课', const Duration(minutes: 25));
      now = now.add(const Duration(minutes: 5));
      final g = await mk();
      await g.load();
      expect(g.isCountdown, isTrue);
      expect(g.remainingSeconds, 20 * 60);
      expect(g.runningCategory, '专业课');
      now = now.add(const Duration(hours: 2));
      final h = await mk();
      await h.load();
      expect(h.isRunning, isFalse);
      expect(h.sessions.single.interrupted, isFalse);
      expect(h.sessions.single.seconds, 25 * 60);
      expect(h.pendingNotice, contains('已结束并记录'));
    });
  });

  group('界面', () {
    late Directory tmp;
    late List<String> calls;
    late DateTime now;
    late bool pinOk;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('daiban_lock_ui');
      SharedPreferences.setMockInitialValues({});
      calls = [];
      now = t(12, 9);
      pinOk = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ScreenPin.channel, (c) async {
        calls.add(c.method == 'setKeepScreenOn' ? 'keep:${c.arguments}' : c.method);
        if (c.method == 'startPin') return pinOk;
        if (c.method == 'isPinned') return pinOk;
        return null;
      });
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ScreenPin.channel, null);
      await tmp.delete(recursive: true);
    });

    Future<(TodoStore, FocusStore)> setup(WidgetTester tester) async {
      late TodoStore store;
      late FocusStore focus;
      await tester.runAsync(() async {
        final prefs = await SharedPreferences.getInstance();
        store = TodoStore(dir: tmp, prefs: prefs, now: () => now);
        focus = FocusStore(dir: tmp, prefs: prefs, now: () => now);
        await store.applyImport(store.preview('甲 +数学 due:2026-11-12\n乙 +专业课 due:2026-11-12\n'), replace: true);
        await focus.load();
      });
      return (store, focus);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    void sendUnpin() {
      final msg = const StandardMethodCodec().encodeMethodCall(const MethodCall('onPinState', false));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(ScreenPin.channelName, msg, (_) {});
    }

    testWidgets('底栏：今日、全部、已完成、锁屏、统计；标题跟随；统计无 FAB 也无顶栏图表入口', (tester) async {
      final (store, focus) = await setup(tester);
      await tester.pumpWidget(MaterialApp(home: HomePage(store: store, focus: focus)));
      await tester.pump();
      final labels = tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).map((d) => d.label).toList();
      expect(labels, ['今日', '全部', '已完成', '锁屏', '统计']);
      expect(find.byKey(const Key('stats_open')), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.text('统计'));
      await tester.pumpAndSettle();
      expect(find.text('待办 · 统计数据'), findsOneWidget);
      expect(find.text('累计专注'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(find.text('锁屏'));
      await tester.pumpAndSettle();
      expect(find.text('待办 · 锁屏'), findsOneWidget);
      expect(find.byKey(const Key('lock_start')), findsOneWidget);
      for (final m in [25, 45, 60, 90]) {
        expect(find.byKey(Key('lock_min_$m')), findsOneWidget);
      }
      expect(find.byKey(const Key('lock_custom')), findsOneWidget);
      expect(find.byKey(const Key('lock_cat_数学')), findsOneWidget);
      expect(find.byKey(const Key('lock_cat_')), findsOneWidget); // 未分类
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('锁屏：开始 → 固定 → 无任何退出控件，返回键无效 → 到点自动完成并记录', (tester) async {
      final (store, focus) = await setup(tester);
      await tester.pumpWidget(MaterialApp(home: HomePage(store: store, focus: focus)));
      await tester.tap(find.text('锁屏'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('lock_cat_专业课')));
      await tester.tap(find.byKey(const Key('lock_min_45')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('lock_start')));
      await settle(tester);
      expect(calls, containsAll(['keep:true', 'startPin', 'isPinned']));
      expect(focus.isCountdown, isTrue);
      expect(find.byKey(const Key('locked_view')), findsOneWidget);
      expect(find.byKey(const Key('locked_cat')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('locked_clock'))).data, '45:00');

      // 锁定视图里没有任何按钮 / 退出文字 / 关闭图标
      final locked = find.byKey(const Key('locked_view'));
      for (final type in [TextButton, FilledButton, ElevatedButton, OutlinedButton, IconButton, BackButton, CloseButton]) {
        expect(find.descendant(of: locked, matching: find.byType(type)), findsNothing, reason: '$type');
      }
      for (final w in ['退出', '结束', '中断', '解除', '取消固定']) {
        expect(find.descendant(of: locked, matching: find.textContaining(w)), findsNothing, reason: w);
      }
      expect(find.descendant(of: locked, matching: find.byIcon(Icons.close)), findsNothing);
      expect(calls.where((c) => c == 'stopPin'), isEmpty);

      // 返回键：不弹出、不弹窗
      final dynamic app = tester.state(find.byType(WidgetsApp));
      await app.didPopRoute();
      await tester.pump();
      expect(find.byKey(const Key('locked_view')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      now = now.add(const Duration(minutes: 20));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Text>(find.byKey(const Key('locked_clock'))).data, '25:00');

      now = now.add(const Duration(minutes: 25));
      await settle(tester);
      expect(focus.isRunning, isFalse);
      final rec = focus.sessions.single;
      expect(rec.isCountdown, isTrue);
      expect(rec.interrupted, isFalse);
      expect(rec.category, '专业课');
      expect(rec.seconds, 45 * 60);
      expect(calls, contains('stopPin'));
      expect(calls, contains('keep:false'));
      expect(find.byKey(const Key('locked_view')), findsNothing);
      expect(find.textContaining('锁屏倒计时完成，已记录（45分钟）'), findsOneWidget);
      expect(FocusCalc.all(focus.sessions).interrupted, 0);
    });

    testWidgets('锁屏：系统手势解除固定 → 中断并记录，中断次数 +1', (tester) async {
      final (store, focus) = await setup(tester);
      await tester.pumpWidget(MaterialApp(home: HomePage(store: store, focus: focus)));
      await tester.tap(find.text('锁屏'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('lock_start')));
      await settle(tester);
      expect(find.byKey(const Key('locked_view')), findsOneWidget);
      now = now.add(const Duration(minutes: 4));
      sendUnpin();
      await settle(tester);
      expect(focus.isRunning, isFalse);
      expect(focus.sessions.single.interrupted, isTrue);
      expect(focus.sessions.single.isCountdown, isTrue);
      expect(focus.sessions.single.seconds, 240);
      expect(find.byKey(const Key('locked_view')), findsNothing);
      expect(find.text('已退出屏幕固定，本次已中断并记录'), findsOneWidget);
      await tester.tap(find.text('统计'));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('stats_all_interrupted'))).data, '1');
      expect(tester.widget<Text>(find.byKey(const Key('stats_day_interrupted'))).data, '1');
    });

    testWidgets('锁屏：固定失败 → 说明如何开启，不进入锁定状态', (tester) async {
      final (store, focus) = await setup(tester);
      pinOk = false;
      await tester.pumpWidget(MaterialApp(home: HomePage(store: store, focus: focus)));
      await tester.tap(find.text('锁屏'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('lock_start')));
      await settle(tester);
      expect(find.text('没能固定屏幕'), findsOneWidget);
      expect(find.textContaining('屏幕固定'), findsWidgets);
      expect(find.byKey(const Key('locked_view')), findsNothing);
      expect(focus.isRunning, isFalse);
      expect(calls, contains('keep:false'));
    });

    testWidgets('正向计时进行中时开始锁屏：先确认结束并记录（正常，不算中断）', (tester) async {
      final (store, focus) = await setup(tester);
      await tester.runAsync(() async => focus.start('数学'));
      await tester.pumpWidget(MaterialApp(home: HomePage(store: store, focus: focus)));
      await tester.tap(find.text('锁屏'));
      await tester.pump();
      now = now.add(const Duration(minutes: 12));
      await tester.tap(find.byKey(const Key('lock_start')));
      await tester.pump();
      expect(find.text('正在正向计时'), findsOneWidget);
      await tester.tap(find.text('结束并开始锁屏'));
      await settle(tester);
      expect(focus.sessions.single.isCountdown, isFalse);
      expect(focus.sessions.single.interrupted, isFalse);
      expect(focus.sessions.single.seconds, 12 * 60);
      expect(focus.isCountdown, isTrue);
      expect(find.byKey(const Key('locked_view')), findsOneWidget);
    });

    testWidgets('正向计时页只有一个「退出」，没有「退出并中断」；正向退出不计中断次数', (tester) async {
      final (store, focus) = await setup(tester);
      await tester.runAsync(() async => focus.start('数学'));
      await tester.pumpWidget(MaterialApp(home: Builder(
          builder: (ctx) => Scaffold(
              body: TextButton(
                  onPressed: () =>
                      Navigator.push(ctx, MaterialPageRoute(builder: (_) => TimerPage(store: store, focus: focus))),
                  child: const Text('go'))))));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('退出'), findsOneWidget);
      expect(find.text('退出并中断'), findsNothing);
      expect(find.textContaining('两'), findsNothing);
      expect(find.text('结束并记录'), findsOneWidget);
      now = now.add(const Duration(minutes: 5));
      await tester.tap(find.byKey(const Key('timer_exit')));
      await tester.pump();
      expect(find.text('退出计时？'), findsOneWidget);
      await tester.tap(find.text('退出并记录'));
      await settle(tester);
      expect(focus.sessions.single.interrupted, isTrue);
      expect(focus.sessions.single.isCountdown, isFalse);
      expect(FocusCalc.all(focus.sessions).interrupted, 0);
      await tester.pumpWidget(MaterialApp(home: StatsPage(store: store, focus: focus)));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('stats_all_count'))).data, '1');
      expect(tester.widget<Text>(find.byKey(const Key('stats_all_interrupted'))).data, '0');
      expect(tester.widget<Text>(find.byKey(const Key('stats_day_interrupted'))).data, '0');
    });

    testWidgets('统计页：中断次数（累计 / 当日）只算锁屏', (tester) async {
      final (store, focus) = await setup(tester);
      await tester.runAsync(() async {
        await focus.addAll([
          fs('1', '数学', t(12, 7), t(12, 7, 30), interrupted: true), // 正向
          fs('2', '数学', t(12, 8), t(12, 8, 10), interrupted: true, countdown: true),
          fs('3', '专业课', t(11, 8), t(11, 8, 10), interrupted: true, countdown: true),
          fs('4', '专业课', t(11, 9), t(11, 9, 25), countdown: true),
        ]);
      });
      await tester.pumpWidget(MaterialApp(home: StatsPage(store: store, focus: focus)));
      await tester.pump();
      expect(find.text('中断次数'), findsNWidgets(2));
      expect(tester.widget<Text>(find.byKey(const Key('stats_all_count'))).data, '4');
      expect(tester.widget<Text>(find.byKey(const Key('stats_all_interrupted'))).data, '2');
      expect(tester.widget<Text>(find.byKey(const Key('stats_day_count'))).data, '2');
      expect(tester.widget<Text>(find.byKey(const Key('stats_day_interrupted'))).data, '1');
      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('stats_day_interrupted'))).data, '1');
      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('stats_day_interrupted'))).data, '0');
      // 记录列表：锁屏 / 已中断 标记
      await tester.pumpWidget(MaterialApp(
          home: FocusRecordsPage(store: store, focus: focus, from: Ymd.of(2026, 11, 12), to: Ymd.of(2026, 11, 12))));
      await tester.pump();
      expect(find.textContaining('已中断'), findsNWidgets(2));
      expect(find.textContaining('锁屏'), findsOneWidget);
    });
  });
}
