import 'dart:io';
import 'dart:ui' as ui;

import 'package:daiban/data/focus_store.dart';
import 'package:daiban/data/store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:daiban/logic/focus.dart';
import 'package:daiban/platform/pin.dart';
import 'package:daiban/ui/stats_export.dart';
import 'package:daiban/ui/stats_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime t(int d, int h, [int m = 0]) => DateTime(2026, 11, d, h, m);

FocusSession fs(String id, String? cat, DateTime a, DateTime b, {bool interrupted = false, bool countdown = false}) =>
    FocusSession(
        id: id,
        category: cat,
        start: a,
        end: b,
        interrupted: interrupted,
        kind: countdown ? FocusSession.countdown : FocusSession.forward);

final sessions = [
  fs('1', '数学', t(12, 9), t(12, 10, 34)),
  fs('2', '专业课', t(12, 14), t(12, 16, 5), interrupted: true, countdown: true),
  fs('3', '英语政治', t(10, 8), t(10, 9)),
];

StatsExportData data(List<FocusSession> list, {String period = '日', DateTime? from, DateTime? to}) {
  final day = Ymd.of(2026, 11, 12);
  final PeriodStats dist;
  final String range;
  switch (period) {
    case '周':
      dist = FocusCalc.forWeek(list, day);
      final r = FocusCalc.weekRange(day);
      range = '${Ymd.fmt(r.$1)} ~ ${Ymd.fmt(r.$2)}';
    case '月':
      dist = FocusCalc.forMonth(list, day);
      range = '2026年11月';
    default:
      dist = FocusCalc.forDay(list, day);
      range = Ymd.fmt(day);
  }
  return StatsExportData(
    generatedOn: day,
    all: FocusCalc.all(list),
    dailyAvgSeconds: FocusCalc.averageDailySeconds(list),
    day: day,
    dayStats: FocusCalc.forDay(list, day),
    periodName: period,
    periodRange: range,
    dist: dist,
    barYear: 2026,
    barMonth: 11,
    hours: FocusCalc.hourDistribution(list, 2026, 11),
    labelOf: (c) => c ?? '未分类',
  );
}

StatsExportPainter painted(StatsExportData d) {
  final p = StatsExportPainter(d);
  final rec = ui.PictureRecorder();
  p.paint(Canvas(rec));
  rec.endRecording().dispose();
  return p;
}

bool isPng(List<int> b) =>
    b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

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

  group('导出图片排版', () {
    test('同一张图里同时有饼图和柱图（饼图在上），以及标题、周期、图例和关键数字', () {
      final p = painted(data(sessions));
      for (final k in ['header', 'summary', 'pie', 'pieChart', 'bar', 'barChart']) {
        expect(p.sections.containsKey(k), isTrue, reason: k);
      }
      expect(p.sections['pie']!.bottom, lessThan(p.sections['bar']!.top));
      expect(p.sections['pieChart']!.height, greaterThan(100));
      expect(p.sections['barChart']!.height, greaterThan(80));
      expect(p.texts, contains('待办 · 专注统计'));
      expect(p.texts, contains('专注时长分布'));
      expect(p.texts, contains('本月专注时段分布'));
      expect(p.texts, contains('按日 · 2026-11-12'));
      expect(p.texts, contains('累计专注'));
      expect(p.texts, contains('当日专注  2026-11-12'));
      expect(p.texts.where((s) => s == '中断次数').length, 2);
      // 图例与屏幕上一致：类别  时长  占比
      expect(p.texts, contains('专业课  2小时5分钟  57.1%'));
      expect(p.texts, contains('数学  1小时34分钟  42.9%'));
      expect(p.texts.any((s) => s.startsWith('2026年11月 · 按 0–23 时累计')), isTrue);
      expect(p.texts.any((s) => s.contains('高峰')), isTrue);
      for (final h in ['0时', '6时', '12时', '18时', '23时']) {
        expect(p.texts, contains(h));
      }
      expect(p.texts, isNot(contains('这段时间还没有专注记录')));
      expect(p.layout(), greaterThan(500));
    });

    test('饼图周期（周 / 月）反映到图片上', () {
      final w = painted(data(sessions, period: '周'));
      expect(w.texts, contains('按周 · 2026-11-09 ~ 2026-11-15'));
      expect(w.texts, contains('总计 4小时39分钟 · 3 次'));
      expect(w.texts.any((s) => s.startsWith('英语政治  1小时')), isTrue);
      final m = painted(data(sessions, period: '月'));
      expect(m.texts, contains('按月 · 2026年11月'));
      final d = painted(data(sessions));
      expect(d.texts, contains('总计 3小时39分钟 · 2 次'));
      expect(d.texts.any((s) => s.startsWith('英语政治')), isFalse);
    });

    test('没有数据也能排版：标题仍在，显示空状态', () {
      final p = painted(data(const []));
      expect(p.texts, contains('专注时长分布'));
      expect(p.texts, contains('本月专注时段分布'));
      expect(p.texts, contains('这段时间还没有专注记录'));
      expect(p.texts, contains('这个月还没有专注记录'));
      expect(p.texts, contains('总计 0分钟'));
      expect(p.sections.containsKey('pieChart'), isTrue);
      expect(p.sections.containsKey('barChart'), isTrue);
    });

    testWidgets('renderStatsPng 生成 PNG（宽 1080px），空数据也不崩', (tester) async {
      await tester.runAsync(() async {
        for (final list in [sessions, <FocusSession>[]]) {
          final png = await renderStatsPng(data(list));
          expect(isPng(png), isTrue);
          final img = await decodeImageFromList(png);
          expect(img.width, 1080);
          expect(img.height, greaterThan(1500));
          img.dispose();
        }
      });
    });
  });

  group('统计页「分享」= 导出图片', () {
    late Directory tmp;
    late DateTime now;
    late List<MethodCall> calls;
    Object? shareError;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('daiban_share');
      SharedPreferences.setMockInitialValues({});
      now = t(12, 20);
      calls = [];
      shareError = null;
      statsShareDir = () async => Directory('${tmp.path}/share');
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ScreenPin.channel, null);
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    Future<(TodoStore, FocusStore)> setup(WidgetTester tester, List<FocusSession> list) async {
      late TodoStore store;
      late FocusStore focus;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ScreenPin.channel, (c) async {
        calls.add(c);
        if (shareError != null) throw shareError!;
        return null;
      });
      await tester.runAsync(() async {
        final prefs = await SharedPreferences.getInstance();
        store = TodoStore(dir: tmp, prefs: prefs, now: () => now);
        focus = FocusStore(dir: tmp, prefs: prefs, now: () => now);
        await store.applyImport(store.preview('甲 +数学 due:2026-11-12\n'), replace: true);
        await focus.load();
        if (list.isNotEmpty) await focus.addAll(list);
      });
      return (store, focus);
    }

    /// 触发「分享」按钮本身的 onPressed（在真实异步区里跑，图片编码和文件读写才会完成）。
    Future<void> tapShare(WidgetTester tester) async {
      final btn = tester.widget<TextButton>(find.byKey(const Key('stats_share')));
      expect(btn.onPressed, isNotNull);
      await tester.runAsync(() async {
        btn.onPressed!();
        try {
          await debugLastStatsShare;
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('点「分享」生成一张 PNG 并交给系统分享（不是文本）；周期跟随当前选择', (tester) async {
      final (store, focus) = await setup(tester, sessions);
      await tester.pumpWidget(app(StatsPage(store: store, focus: focus)));
      await tester.pump();
      await tester.tap(find.text('周'));
      await tester.pump();
      final st = tester.state(find.byType(StatsPage)) as dynamic;
      final StatsExportData d = st.exportData();
      expect(d.periodName, '周');
      expect(d.periodRange, '2026-11-09 ~ 2026-11-15');
      expect(d.dist.seconds, FocusCalc.forWeek(focus.sessions, Ymd.of(2026, 11, 12)).seconds);
      expect(d.barYear, 2026);
      expect(d.barMonth, 11);
      expect(painted(d).texts, contains('按周 · 2026-11-09 ~ 2026-11-15'));

      await tapShare(tester);
      expect(calls.where((c) => c.method == 'share'), isEmpty);
      final share = calls.singleWhere((c) => c.method == 'shareImage');
      final args = Map<String, dynamic>.from(share.arguments as Map);
      expect(args.containsKey('text'), isFalse);
      final path = args['path'] as String;
      expect(path, startsWith('${tmp.path}/share/'));
      expect(path, endsWith('.png'));
      final bytes = File(path).readAsBytesSync();
      expect(isPng(bytes), isTrue);
      expect(find.text('分享'), findsOneWidget); // 按钮恢复
      expect(find.byType(SnackBar), findsNothing);

      // 再分享一次：只保留最新一张
      await tapShare(tester);
      expect(calls.where((c) => c.method == 'shareImage').length, 2);
      expect(Directory('${tmp.path}/share').listSync().whereType<File>().length, 1);
    });

    testWidgets('没有专注记录时也生成图片并分享，不崩溃', (tester) async {
      final (store, focus) = await setup(tester, const []);
      await tester.pumpWidget(app(StatsPage(store: store, focus: focus)));
      await tester.pump();
      await tapShare(tester);
      final share = calls.singleWhere((c) => c.method == 'shareImage');
      expect(isPng(File((share.arguments as Map)['path'] as String).readAsBytesSync()), isTrue);
    });

    testWidgets('系统分享失败时提示，不崩溃', (tester) async {
      final (store, focus) = await setup(tester, sessions);
      shareError = PlatformException(code: 'share_failed');
      await tester.pumpWidget(app(StatsPage(store: store, focus: focus)));
      await tester.pump();
      await tapShare(tester);
      expect(find.text('生成分享图片失败，请重试'), findsOneWidget);
      expect(find.text('分享'), findsOneWidget);
    });
  });
}
