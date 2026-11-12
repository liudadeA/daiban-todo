import 'dart:io';

import 'package:daiban/data/focus_store.dart';
import 'package:daiban/data/store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:daiban/logic/focus.dart';
import 'package:daiban/logic/widget_actions.dart';
import 'package:daiban/platform/pin.dart';
import 'package:daiban/ui/home_page.dart';
import 'package:daiban/ui/stats_page.dart';
import 'package:daiban/ui/timer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

FocusSession s(String id, String? cat, DateTime a, DateTime b, {bool interrupted = false}) =>
    FocusSession(id: id, category: cat, start: a, end: b, interrupted: interrupted);

DateTime t(int d, int h, [int m = 0, int sec = 0]) => DateTime(2026, 11, d, h, m, sec);

Widget app(Widget home) => MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FocusCalc 时长格式', () {
    test('fmtDuration / fmtClock', () {
      expect(FocusCalc.fmtDuration(0), '0分钟');
      expect(FocusCalc.fmtDuration(42), '42秒');
      expect(FocusCalc.fmtDuration(60 * 34), '34分钟');
      expect(FocusCalc.fmtDuration(3600 + 60 * 34), '1小时34分钟');
      expect(FocusCalc.fmtDuration(7200), '2小时');
      expect(FocusCalc.fmtDuration(212 * 3600 + 58 * 60), '212小时58分钟');
      expect(FocusCalc.fmtClock(0), '00:00:00');
      expect(FocusCalc.fmtClock(3725), '01:02:05');
      expect(FocusCalc.fmtClock(100 * 3600 + 1), '100:00:01');
    });
  });

  group('FocusCalc 汇总', () {
    final list = [
      s('1', '数学', t(11, 9), t(11, 10, 34)), // 94 分钟
      s('2', '专业课', t(11, 14), t(11, 16, 5)), // 125 分钟
      s('3', '数学', t(12, 8), t(12, 8, 30), interrupted: true), // 30 分钟（中断也计入）
      s('4', null, t(3, 20), t(3, 21)), // 上周
      s('5', '英语政治', DateTime(2026, 10, 31, 23), DateTime(2026, 11, 1, 1)), // 上月开始，跨月
    ];

    test('累计：次数、时长、日均（按有记录的天数）', () {
      final a = FocusCalc.all(list);
      expect(a.count, 5);
      expect(a.seconds, (94 + 125 + 30 + 60 + 120) * 60);
      // 有记录的天：10-31、11-03、11-11、11-12 → 4 天
      expect(FocusCalc.averageDailySeconds(list), a.seconds ~/ 4);
      expect(FocusCalc.averageDailySeconds([]), 0);
    });

    test('当日：记在开始那一天', () {
      final d = FocusCalc.forDay(list, Ymd.of(2026, 11, 11));
      expect(d.count, 2);
      expect(d.seconds, (94 + 125) * 60);
      expect(FocusCalc.forDay(list, Ymd.of(2026, 11, 13)).isEmpty, isTrue);
      // 跨日记录算在开始的 10-31
      expect(FocusCalc.forDay(list, Ymd.of(2026, 10, 31)).seconds, 120 * 60);
      expect(FocusCalc.forDay(list, Ymd.of(2026, 11, 1)).count, 0);
    });

    test('时长分布：按类别降序、占比；周一到周日；整月；自定义闭区间', () {
      final day = FocusCalc.forDay(list, Ymd.of(2026, 11, 11));
      expect(day.slices.map((e) => e.category), ['专业课', '数学']);
      expect((day.slices[0].shareOf(day.seconds) * 100).toStringAsFixed(1), '57.1');
      expect((day.slices[1].shareOf(day.seconds) * 100).toStringAsFixed(1), '42.9');

      final r = FocusCalc.weekRange(Ymd.of(2026, 11, 11)); // 周三
      expect(Ymd.fmt(r.$1), '2026-11-09');
      expect(Ymd.fmt(r.$2), '2026-11-15');
      final w = FocusCalc.forWeek(list, Ymd.of(2026, 11, 11));
      expect(w.count, 3);
      expect(w.slices.first.category, '专业课');
      expect(w.slices.firstWhere((e) => e.category == '数学').seconds, (94 + 30) * 60);
      expect(w.slices.firstWhere((e) => e.category == '数学').count, 2);

      final m = FocusCalc.forMonth(list, Ymd.of(2026, 11, 20));
      expect(m.count, 4); // 不含 10-31 开始的那条
      final c = FocusCalc.forRange(list, Ymd.of(2026, 11, 3), Ymd.of(2026, 11, 11));
      expect(c.count, 3);
      expect(c.slices.any((e) => e.category == null), isTrue);
    });

    test('本月时段分布：按实际跨越的小时拆分，只算本月', () {
      final h = FocusCalc.hourDistribution(list, 2026, 11);
      expect(h.length, 24);
      expect(h[9], 3600); // 9:00–10:00
      expect(h[10], 34 * 60); // 10:00–10:34
      expect(h[14], 3600);
      expect(h[15], 3600);
      expect(h[16], 5 * 60);
      expect(h[8], 30 * 60);
      expect(h[20], 3600);
      expect(h[23], 0); // 10-31 23 点属于上个月
      expect(h[0], 3600); // 11-01 0:00–1:00 属于本月
      final oct = FocusCalc.hourDistribution(list, 2026, 10);
      expect(oct[23], 3600);
      expect(oct[0], 0);
    });

    test('类别配色稳定', () {
      expect(FocusColors.of('数学').argb, FocusColors.of('数学').argb);
      expect(FocusColors.of(null).argb, FocusColors.uncategorized.argb);
    });
  });

  group('FocusStore 持久化', () {
    late Directory tmp;
    late DateTime now;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('daiban_focus');
      SharedPreferences.setMockInitialValues({});
      now = t(12, 9);
    });
    tearDown(() async => tmp.delete(recursive: true));

    Future<FocusStore> mk() async =>
        FocusStore(dir: tmp, prefs: await SharedPreferences.getInstance(), now: () => now);

    test('开始 → 结束：写入 focus.json；同时只能有一个计时', () async {
      final f = await mk();
      await f.load();
      expect(await f.start('数学'), isTrue);
      expect(await f.start('英语'), isFalse);
      now = now.add(const Duration(minutes: 25, seconds: 3));
      expect(f.elapsedSeconds, 25 * 60 + 3);
      final rec = await f.stop(interrupted: false);
      expect(rec!.seconds, 25 * 60 + 3);
      expect(rec.interrupted, isFalse);
      expect(f.isRunning, isFalse);
      final g = await mk();
      await g.load();
      expect(g.sessions.single.category, '数学');
      expect(g.sessions.single.seconds, 25 * 60 + 3);
    });

    test('进行中的计时在重启后恢复；中断记为 interrupted', () async {
      final f = await mk();
      await f.load();
      await f.start('专业课');
      now = now.add(const Duration(minutes: 10));
      final g = await mk(); // 模拟杀进程后重新打开
      await g.load();
      expect(g.isRunning, isTrue);
      expect(g.runningCategory, '专业课');
      expect(g.elapsedSeconds, 600);
      final rec = await g.stop(interrupted: true);
      expect(rec!.interrupted, isTrue);
      final h = await mk();
      await h.load();
      expect(h.isRunning, isFalse);
      expect(h.sessions.single.interrupted, isTrue);
    });

    test('不足 1 秒不记录；超过 12 小时的残留计时自动中断并记录', () async {
      final f = await mk();
      await f.load();
      await f.start('数学');
      expect(await f.stop(interrupted: true), isNull);
      expect(f.sessions, isEmpty);
      await f.start('数学');
      now = now.add(const Duration(hours: 13));
      final g = await mk();
      await g.load();
      expect(g.isRunning, isFalse);
      expect(g.sessions.single.interrupted, isTrue);
      expect(g.sessions.single.seconds, 13 * 3600);
    });

    test('坏文件不崩溃', () async {
      await File('${tmp.path}/focus.json').writeAsString('{not json');
      final f = await mk();
      await f.load();
      expect(f.sessions, isEmpty);
    });
  });

  group('界面：正向计时与屏幕固定', () {
    late Directory tmp;
    late List<String> calls;
    late DateTime now;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('daiban_focus_ui');
      SharedPreferences.setMockInitialValues({});
      calls = [];
      now = t(12, 9);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ScreenPin.channel, (c) async {
        calls.add(c.method == 'setKeepScreenOn' ? 'keep:${c.arguments}' : c.method);
        if (c.method == 'startPin') return true;
        if (c.method == 'isPinned') return true;
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
        await store.applyImport(store.preview('甲 +数学 due:2026-11-12\n乙 +专业课 due:2026-11-12\n丙 +英语政治 due:2026-11-13\n'), replace: true);
        await focus.load();
      });
      return (store, focus);
    }

    testWidgets('今日页按类别显示「正向计时 / 开始」卡片和统计入口', (tester) async {
      final (store, focus) = await setup(tester);
      await tester.pumpWidget(app(HomePage(store: store, focus: focus)));
      await tester.pump();
      expect(find.byKey(const Key('timer_grid')), findsOneWidget);
      for (final c in ['数学', '专业课', '英语政治']) {
        expect(find.byKey(Key('timer_card_$c')), findsOneWidget);
        expect(find.byKey(Key('timer_start_$c')), findsOneWidget);
      }
      expect(find.text('开始'), findsNWidgets(3));
      expect(find.byKey(const Key('stats_open')), findsNothing); // 统计只在底栏
      expect(find.byType(NavigationDestination), findsNWidgets(5));
    });

    testWidgets('开始 → 请求屏幕固定；返回先弹窗，「继续计时」不中断', (tester) async {
      final (store, focus) = await setup(tester);
      await tester.pumpWidget(app(HomePage(store: store, focus: focus)));
      await tester.pump();
      await tester.runAsync(() async => focus.start('数学'));
      await tester.pumpWidget(app(TimerPage(store: store, focus: focus)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, containsAll(['keep:true', 'startPin']));
      expect(find.text('数学'), findsOneWidget);
      expect(find.byKey(const Key('timer_clock')), findsOneWidget);

      // 系统返回键 → 弹窗
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pump();
      expect(find.text('退出计时？'), findsOneWidget);
      expect(find.textContaining('中断并记录'), findsOneWidget);
      await tester.tap(find.text('继续计时'));
      await tester.pump();
      expect(find.text('退出计时？'), findsNothing);
      expect(focus.isRunning, isTrue);
      expect(calls.contains('stopPin'), isFalse);
      expect(focus.sessions, isEmpty);
    });

    testWidgets('退出 → 确认后解除固定、中断计时并记录', (tester) async {
      final (store, focus) = await setup(tester);
      await tester.runAsync(() async => focus.start('专业课'));
      await tester.pumpWidget(app(Builder(builder: (ctx) {
        return Scaffold(body: Center(child: TextButton(
            onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => TimerPage(store: store, focus: focus))),
            child: const Text('go'))));
      })));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 7, seconds: 30));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('00:07:30'), findsOneWidget);
      await tester.tap(find.byKey(const Key('timer_exit')));
      await tester.pump();
      expect(find.text('退出计时？'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('退出并记录'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(focus.isRunning, isFalse);
      final rec = focus.sessions.single;
      expect(rec.category, '专业课');
      expect(rec.interrupted, isTrue);
      expect(rec.seconds, 450);
      expect(calls, contains('stopPin'));
      expect(calls, contains('keep:false'));
      expect(find.byType(TimerPage), findsNothing);
      expect(find.textContaining('已中断「专业课」的计时并记录（7分钟）'), findsOneWidget);
      // 重新加载仍在
      await tester.runAsync(() async {
        final g = FocusStore(dir: tmp, prefs: await SharedPreferences.getInstance(), now: () => now);
        await g.load();
        expect(g.sessions.single.interrupted, isTrue);
      });
    });

    testWidgets('用系统手势解除屏幕固定 → 立即中断并记录，离开计时页', (tester) async {
      final (store, focus) = await setup(tester);
      await tester.runAsync(() async => focus.start('数学'));
      await tester.pumpWidget(app(Builder(builder: (ctx) {
        return Scaffold(body: Center(child: TextButton(
            onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => TimerPage(store: store, focus: focus))),
            child: const Text('go'))));
      })));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 3));
      await tester.runAsync(() async {
        final msg = const StandardMethodCodec().encodeMethodCall(const MethodCall('onPinState', false));
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(ScreenPin.channelName, msg, (_) {});
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(focus.isRunning, isFalse);
      expect(focus.sessions.single.interrupted, isTrue);
      expect(focus.sessions.single.seconds, 180);
      expect(find.byType(TimerPage), findsNothing);
      expect(find.textContaining('已退出屏幕固定'), findsOneWidget);
    });

    testWidgets('「结束并记录」= 正常完成（非中断）', (tester) async {
      final (store, focus) = await setup(tester);
      await tester.runAsync(() async => focus.start(null));
      await tester.pumpWidget(app(Builder(builder: (ctx) {
        return Scaffold(body: Center(child: TextButton(
            onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => TimerPage(store: store, focus: focus))),
            child: const Text('go'))));
      })));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 45));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('timer_stop')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(focus.sessions.single.interrupted, isFalse);
      expect(focus.sessions.single.seconds, 45 * 60);
      expect(find.textContaining('已记录「未分类」的专注（45分钟）'), findsOneWidget);
    });

    testWidgets('统计页：累计、当日、时长分布（日/周/月）与查看专注记录', (tester) async {
      final (store, focus) = await setup(tester);
      await tester.runAsync(() async {
        await focus.addAll([
          s('1', '数学', t(12, 9), t(12, 10, 34)),
          s('2', '专业课', t(12, 14), t(12, 16, 5)),
          s('3', '英语政治', t(10, 8), t(10, 9), interrupted: true),
        ]);
      });
      await tester.pumpWidget(app(StatsPage(store: store, focus: focus)));
      await tester.pump();
      expect(find.text('累计专注'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('stats_all_count'))).data, '3');
      expect(tester.widget<Text>(find.byKey(const Key('stats_all_dur'))).data, '4小时39分钟');
      // 2 天有记录 → 日均 = 279 ÷ 2 = 139.5 分钟
      expect(tester.widget<Text>(find.byKey(const Key('stats_all_avg'))).data, '2小时19分钟');
      expect(find.textContaining('当日专注  2026-11-12'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('stats_day_count'))).data, '2');
      expect(tester.widget<Text>(find.byKey(const Key('stats_day_dur'))).data, '3小时39分钟');
      expect(find.text('专注时长分布'), findsOneWidget);
      for (final l in ['日', '周', '月', '自定义']) {
        expect(find.text(l), findsOneWidget);
      }
      expect(tester.widget<Text>(find.byKey(const Key('stats_pie_total'))).data, '总计 3小时39分钟');
      expect(find.byKey(const Key('stats_pie')), findsOneWidget);
      expect(find.textContaining('专业课  2小时5分钟  57.1%'), findsOneWidget);
      expect(find.textContaining('数学  1小时34分钟  42.9%'), findsOneWidget);
      await tester.tap(find.text('周'));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('stats_pie_total'))).data, '总计 4小时39分钟');
      await tester.tap(find.text('月'));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('stats_pie_total'))).data, '总计 4小时39分钟');
      // 切回「日」，查看当天的专注记录
      await tester.tap(find.text('日'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('stats_records')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('stats_records')));
      await tester.pumpAndSettle();
      expect(find.textContaining('专注记录  2026-11-12'), findsOneWidget);
      expect(find.text('数学'), findsOneWidget);
      expect(find.text('专业课'), findsOneWidget);
      expect(find.text('英语政治'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.textContaining('本月专注时段分布'), 200);
      expect(find.textContaining('本月专注时段分布  2026年11月'), findsOneWidget);
    });

    testWidgets('统计页空状态', (tester) async {
      final (store, focus) = await setup(tester);
      await tester.pumpWidget(app(StatsPage(store: store, focus: focus)));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('stats_all_count'))).data, '0');
      expect(tester.widget<Text>(find.byKey(const Key('stats_all_dur'))).data, '0分钟');
      expect(find.text('这段时间还没有专注记录'), findsOneWidget);
    });

    test('桌面组件快照不含计时 / 统计字段', () async {
      final store = TodoStore(dir: tmp, prefs: await SharedPreferences.getInstance(), now: () => now);
      await store.applyImport(store.preview('甲 +数学 due:2026-11-12\n'), replace: true);
      final snap = WidgetActions.snapshot(store);
      expect(snap.keys.toSet(), {'date', 'count', 'rows', 'open'});
      final txt = snap.toString();
      for (final w in ['计时', '专注', '统计']) {
        expect(txt, isNot(contains(w)));
      }
    });
  });
}
