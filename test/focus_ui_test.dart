import 'dart:io';

import 'package:daiban/data/focus_store.dart';
import 'package:daiban/data/store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:daiban/logic/focus.dart';
import 'package:daiban/logic/widget_actions.dart';
import 'package:daiban/ui/home_page.dart';
import 'package:daiban/ui/stats_page.dart';
import 'package:daiban/ui/timer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

FocusSession sess(String? cat, String start, String end, {bool interrupted = false}) {
  DateTime p(String t) => DateTime.parse(t.contains('T') ? t : t.replaceFirst(' ', 'T'));
  return FocusSession(id: start, category: cat, start: p(start), end: p(end), interrupted: interrupted);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('daiban/pin'),
      (c) async {
        calls.add(c.method);
        if (c.method == 'startPin' || c.method == 'isPinned') return true;
        return null;
      },
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('daiban/pin'),
      null,
    );
  });

  late Directory dir;
  late TodoStore todos;
  late FocusStore focus;
  var now = DateTime(2026, 11, 12, 8, 0, 0);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('daiban_fui');
    now = DateTime(2026, 11, 12, 8, 0, 0);
    final prefs = await SharedPreferences.getInstance();
    todos = TodoStore(dir: dir, prefs: prefs, now: () => now);
    focus = FocusStore(dir: dir, prefs: prefs, now: () => now);
  });
  tearDown(() async => dir.delete(recursive: true));

  test('桌面组件快照不含正向计时 / 专注统计', () async {
    await todos.applyImport(todos.preview('甲 +408 due:2026-11-12\n'), replace: true);
    await focus.add(sess('408', '2026-11-12 07:00:00', '2026-11-12 08:00:00'));
    final snap = WidgetActions.snapshot(todos);
    expect(snap.keys.toSet(), {'date', 'count', 'rows', 'open'});
    final text = snap.toString();
    expect(text, isNot(contains('预计')));
    expect(text, isNot(contains('正向计时')));
    expect(text, isNot(contains('专注')));
    expect(text, isNot(contains('开始')));
  });

  testWidgets('今日页类别卡片：正向计时 / 开始；统计入口', (tester) async {
    await tester.runAsync(() async {
      await todos.applyImport(todos.preview('甲 +408 due:2026-11-12\n乙 +数学 due:2026-11-12\n'), replace: true);
    });
    await tester.pumpWidget(MaterialApp(home: HomePage(store: todos, focus: focus)));
    await tester.pump();
    expect(find.byKey(const Key('timer_grid')), findsOneWidget);
    expect(find.byKey(const Key('timer_card_408')), findsOneWidget);
    expect(find.byKey(const Key('timer_start_408')), findsOneWidget);
    expect(find.byKey(const Key('timer_start_数学')), findsOneWidget);
    expect(find.text('正向计时'), findsWidgets);
    expect(find.text('开始'), findsWidgets);
    expect(find.byKey(const Key('stats_open')), findsNothing); // 统计只在底栏
      expect(find.byType(NavigationDestination), findsNWidgets(5));
  });

  testWidgets('开始进入全屏秒表并请求屏幕固定；结束并记录为正常完成', (tester) async {
    await tester.runAsync(() async {
      await todos.applyImport(todos.preview('甲 +408 due:2026-11-12\n'), replace: true);
    });
    await tester.pumpWidget(MaterialApp(home: HomePage(store: todos, focus: focus)));
    await tester.pump();
    await tester.tap(find.byKey(const Key('timer_start_408')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(TimerPage), findsOneWidget);
    expect(find.byKey(const Key('timer_clock')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('timer_clock'))).data, '00:00:00');
    expect(find.text('正向计时'), findsWidgets);
    expect(calls, contains('startPin'));
    expect(calls, contains('setKeepScreenOn'));

    now = now.add(const Duration(minutes: 2, seconds: 5));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.widget<Text>(find.byKey(const Key('timer_clock'))).data, '00:02:05');

    await tester.tap(find.byKey(const Key('timer_stop')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TimerPage), findsNothing);
    expect(focus.sessions, hasLength(1));
    expect(focus.sessions.single.interrupted, isFalse);
    expect(focus.sessions.single.category, '408');
    expect(focus.sessions.single.seconds, 2 * 60 + 5);
    expect(calls, contains('stopPin'));
  });

  testWidgets('退出先弹出确认：取消继续计时，确认则中断并记录', (tester) async {
    await tester.runAsync(() async {
      await todos.applyImport(todos.preview('甲 +408 due:2026-11-12\n'), replace: true);
      await focus.start('408');
    });
    await tester.pumpWidget(MaterialApp(home: TimerPage(store: todos, focus: focus)));
    await tester.pump();
    now = now.add(const Duration(minutes: 3));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byKey(const Key('timer_exit')));
    await tester.pump();
    expect(find.text('退出计时？'), findsOneWidget);
    expect(find.textContaining('中断并记录'), findsWidgets);

    await tester.tap(find.text('继续计时'));
    await tester.pump();
    expect(find.byType(TimerPage), findsOneWidget);
    expect(focus.isRunning, isTrue);
    expect(focus.sessions, isEmpty);

    await tester.tap(find.byKey(const Key('timer_exit')));
    await tester.pump();
    await tester.tap(find.text('退出并记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TimerPage), findsNothing);
    expect(focus.isRunning, isFalse);
    expect(focus.sessions, hasLength(1));
    expect(focus.sessions.single.interrupted, isTrue);
    expect(focus.sessions.single.seconds, 3 * 60);
  });

  testWidgets('系统解除屏幕固定：自动中断并记录', (tester) async {
    await tester.runAsync(() async {
      await todos.applyImport(todos.preview('甲 +408 due:2026-11-12\n'), replace: true);
      await focus.start('408');
    });
    await tester.pumpWidget(MaterialApp(scaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(), home: TimerPage(store: todos, focus: focus)));
    await tester.pump();
    now = now.add(const Duration(minutes: 4));

    await tester.runAsync(() async {
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'daiban/pin',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('onPinState', false)),
        (_) {},
      );
    });
    await tester.pump();
    expect(focus.isRunning, isFalse);
    expect(focus.sessions, hasLength(1));
    expect(focus.sessions.single.interrupted, isTrue);
    expect(focus.sessions.single.seconds, 4 * 60);
  });

  testWidgets('正在计时其它类别时不能再开始', (tester) async {
    await tester.runAsync(() async {
      await todos.applyImport(todos.preview('甲 +408 due:2026-11-12\n乙 +数学 due:2026-11-12\n'), replace: true);
      await focus.start('408');
    });
    await tester.pumpWidget(MaterialApp(home: HomePage(store: todos, focus: focus)));
    await tester.pump();
    await tester.tap(find.byKey(const Key('timer_start_数学')));
    await tester.pump();
    expect(find.textContaining('正在计时'), findsOneWidget);
    expect(find.byType(TimerPage), findsNothing);
    expect(focus.runningCategory, '408');
  });

  testWidgets('统计页：累计、当日、饼图、记录列表（含已中断）', (tester) async {
    await tester.runAsync(() async {
      await focus.addAll([
        sess('数学', '2026-11-11 09:00:00', '2026-11-11 10:34:00'),
        sess('专业课', '2026-11-11 14:00:00', '2026-11-11 16:05:00'),
        sess('数学', '2026-11-12 07:00:00', '2026-11-12 07:20:00', interrupted: true),
      ]);
    });
    // 打开统计时「当日」默认是 store.today = 2026-11-12
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: todos, focus: focus)));
    await tester.pump();
    expect(find.text('累计专注'), findsOneWidget);
    expect(find.text('当日专注  2026-11-12'), findsOneWidget);
    expect(find.text('专注时长分布'), findsOneWidget);
    expect(find.text('查看专注记录'), findsOneWidget);
    expect(find.textContaining('本月专注时段分布'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('stats_all_count'))).data, '3');
    expect(tester.widget<Text>(find.byKey(const Key('stats_all_dur'))).data, '3小时59分钟'); // 94+125+20
    expect(tester.widget<Text>(find.byKey(const Key('stats_day_count'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const Key('stats_day_dur'))).data, '20分钟');

    // 当日分布翻到 11-11
    await tester.tap(find.byIcon(Icons.chevron_left).first);
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('stats_day_count'))).data, '2');
    expect(tester.widget<Text>(find.byKey(const Key('stats_day_dur'))).data, '3小时39分钟');

    // 分布默认也是 11-12（上面只翻了当日卡片的第一组箭头… 分布有自己的箭头）
    // 切到 11-11 的「日」分布：点分布卡片的左箭头（第二个 chevron_left）
    await tester.tap(find.byIcon(Icons.chevron_left).at(2));
    await tester.pump();
    expect(find.text('2026-11-11'), findsOneWidget);
    expect(find.textContaining('3小时39分钟'), findsWidgets);
    expect(find.textContaining('57.1%'), findsOneWidget);
    expect(find.textContaining('42.9%'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('stats_records')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('stats_records')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FocusRecordsPage), findsOneWidget);
    expect(find.text('专业课'), findsWidgets);
    expect(find.text('数学'), findsWidgets);
  });

  testWidgets('记录列表对中断项标注已中断', (tester) async {
    await tester.runAsync(() async {
      await focus.addAll([
        sess('数学', '2026-11-12 07:00:00', '2026-11-12 07:20:00', interrupted: true),
        sess('专业课', '2026-11-12 08:00:00', '2026-11-12 08:10:00'),
      ]);
    });
    await tester.pumpWidget(MaterialApp(
        home: FocusRecordsPage(store: todos, focus: focus, from: Ymd.of(2026, 11, 12), to: Ymd.of(2026, 11, 12))));
    await tester.pump();
    expect(find.textContaining('已中断'), findsOneWidget);
    expect(find.text('数学'), findsOneWidget);
    expect(find.text('专业课'), findsOneWidget);
    expect(find.text('20分钟'), findsOneWidget);
    expect(find.text('10分钟'), findsOneWidget);
  });
}
