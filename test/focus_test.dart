import 'dart:io';

import 'package:daiban/data/focus_store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:daiban/logic/focus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

FocusSession s(String? cat, String start, String end, {bool interrupted = false, String? id}) {
  DateTime p(String t) => DateTime.parse(t.contains('T') ? t : t.replaceFirst(' ', 'T'));
  return FocusSession(id: id ?? start, category: cat, start: p(start), end: p(end), interrupted: interrupted);
}

void main() {
  group('文案', () {
    test('时长', () {
      expect(FocusCalc.fmtDuration(0), '0分钟');
      expect(FocusCalc.fmtDuration(45), '45秒');
      expect(FocusCalc.fmtDuration(58), '58秒');
      expect(FocusCalc.fmtDuration(60), '1分钟');
      expect(FocusCalc.fmtDuration(58 * 60), '58分钟');
      expect(FocusCalc.fmtDuration(2 * 3600), '2小时');
      expect(FocusCalc.fmtDuration(2 * 3600 + 50 * 60), '2小时50分钟');
      expect(FocusCalc.fmtDuration(212 * 3600 + 58 * 60), '212小时58分钟');
    });

    test('秒表', () {
      expect(FocusCalc.fmtClock(0), '00:00:00');
      expect(FocusCalc.fmtClock(65), '00:01:05');
      expect(FocusCalc.fmtClock(2 * 3600 + 5 * 60 + 7), '02:05:07');
      expect(FocusCalc.fmtClock(10 * 3600), '10:00:00');
    });
  });

  group('统计规则', () {
    final math = s('数学', '2026-11-11 09:00:00', '2026-11-11 10:34:00'); // 1h34m
    final major = s('专业课', '2026-11-11 14:00:00', '2026-11-11 16:05:00'); // 2h5m
    final later = s('数学', '2026-11-12 08:00:00', '2026-11-12 08:30:00'); // 30m
    final interrupted = s('英语', '2026-11-10 20:00:00', '2026-11-10 20:40:00', interrupted: true);

    test('累计：次数、时长、日均 = 总时长 ÷ 有记录的天数', () {
      final all = FocusCalc.all([math, major, later, interrupted]);
      expect(all.count, 4);
      expect(all.seconds, 94 * 60 + 125 * 60 + 30 * 60 + 40 * 60); // 289 分钟
      // 有记录的日子：11-10、11-11、11-12 共 3 天
      expect(FocusCalc.averageDailySeconds([math, major, later, interrupted]), (289 * 60) ~/ 3);
      expect(FocusCalc.averageDailySeconds([]), 0);
    });

    test('次数和时长记在开始的那一天；跨日也算开始那天', () {
      final night = s('数学', '2026-11-11 23:30:00', '2026-11-12 00:30:00'); // 60m
      expect(FocusCalc.forDay([night], Ymd.of(2026, 11, 11)).count, 1);
      expect(FocusCalc.forDay([night], Ymd.of(2026, 11, 11)).seconds, 3600);
      expect(FocusCalc.forDay([night], Ymd.of(2026, 11, 12)).isEmpty, isTrue);
    });

    test('日 / 周 / 月 / 自定义 区间', () {
      final list = [math, major, later, interrupted];
      final day = FocusCalc.forDay(list, Ymd.of(2026, 11, 11));
      expect(day.count, 2);
      expect(day.seconds, (94 + 125) * 60);
      expect(day.slices.map((e) => e.category).toList(), ['专业课', '数学']);
      expect((day.slices[0].shareOf(day.seconds) * 1000).round(), 571); // 125/219 ≈ 57.1%
      expect((day.slices[1].shareOf(day.seconds) * 1000).round(), 429);

      // 2026-11-11 是周三；那一周周一是 11-09，周日 11-15，含 11-10、11-11、11-12
      final week = FocusCalc.forWeek(list, Ymd.of(2026, 11, 11));
      expect(FocusCalc.weekRange(Ymd.of(2026, 11, 11)).$1, Ymd.of(2026, 11, 9));
      expect(FocusCalc.weekRange(Ymd.of(2026, 11, 11)).$2, Ymd.of(2026, 11, 15));
      expect(week.count, 4);

      final month = FocusCalc.forMonth(list, Ymd.of(2026, 11, 11));
      expect(month.count, 4);
      expect(FocusCalc.forMonth(list, Ymd.of(2026, 12, 1)).isEmpty, isTrue);

      final custom = FocusCalc.forRange(list, Ymd.of(2026, 11, 11), Ymd.of(2026, 11, 12));
      expect(custom.count, 3); // 不含 11-10
    });

    test('中断的记录同样计入', () {
      final p = FocusCalc.forDay([interrupted], Ymd.of(2026, 11, 10));
      expect(p.count, 1);
      expect(p.seconds, 40 * 60);
    });

    test('时段分布按小时拆分，跨日只记本月的部分', () {
      final a = s('数学', '2026-11-11 10:30:00', '2026-11-11 12:00:00'); // 10 时 30m，11 时 60m
      final hours = FocusCalc.hourDistribution([a], 2026, 11);
      expect(hours[10], 30 * 60);
      expect(hours[11], 60 * 60);
      expect(hours[12], 0);

      final night = s('数学', '2026-11-30 23:30:00', '2026-12-01 00:30:00');
      final nov = FocusCalc.hourDistribution([night], 2026, 11);
      expect(nov[23], 30 * 60);
      expect(nov[0], 0);
      final dec = FocusCalc.hourDistribution([night], 2026, 12);
      expect(dec[0], 30 * 60);
      expect(dec[23], 0);
    });
  });

  group('FocusStore 持久化', () {
    late Directory dir;
    late FocusStore store;
    var now = DateTime(2026, 11, 12, 8, 0, 0);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('daiban_focus');
      now = DateTime(2026, 11, 12, 8, 0, 0);
      store = FocusStore(dir: dir, prefs: await SharedPreferences.getInstance(), now: () => now);
    });
    tearDown(() async => dir.delete(recursive: true));

    test('开始、结束（正常 / 中断）、不足 1 秒不记、同时只能有一个', () async {
      expect(await store.start('数学'), isTrue);
      expect(store.isRunning, isTrue);
      expect(await store.start('英语'), isFalse);
      expect(store.runningCategory, '数学');
      now = now.add(const Duration(minutes: 25));
      final rec = await store.stop(interrupted: false);
      expect(rec, isNotNull);
      expect(rec!.interrupted, isFalse);
      expect(rec.seconds, 25 * 60);
      expect(store.isRunning, isFalse);
      expect(store.sessions, hasLength(1));

      expect(await store.start('英语'), isTrue);
      now = now.add(const Duration(seconds: 40));
      final mid = await store.stop(interrupted: true);
      expect(mid!.interrupted, isTrue);
      expect(mid.seconds, 40);
      expect(store.sessions, hasLength(2));

      expect(await store.start('专业课'), isTrue);
      now = now.add(const Duration(milliseconds: 400));
      expect(await store.stop(interrupted: true), isNull);
      expect(store.sessions, hasLength(2));
    });

    test('杀进程后进行中的计时能恢复；超过 12 小时自动中断并记录', () async {
      await store.start('数学');
      now = now.add(const Duration(minutes: 10));
      final again = FocusStore(dir: dir, prefs: await SharedPreferences.getInstance(), now: () => now);
      await again.load();
      expect(again.isRunning, isTrue);
      expect(again.runningCategory, '数学');
      expect(again.elapsedSeconds, 10 * 60);
      expect(again.sessions, isEmpty);

      now = now.add(const Duration(hours: 13));
      final stale = FocusStore(dir: dir, prefs: await SharedPreferences.getInstance(), now: () => now);
      await stale.load();
      expect(stale.isRunning, isFalse);
      expect(stale.sessions, hasLength(1));
      expect(stale.sessions.single.interrupted, isTrue);
      expect(stale.sessions.single.category, '数学');
    });

    test('已结束的记录写入 focus.json，再 load 能读回来', () async {
      await store.add(s('数学', '2026-11-11 09:00:00', '2026-11-11 10:00:00', interrupted: true));
      expect(await store.file.exists(), isTrue);
      final again = FocusStore(dir: dir, prefs: await SharedPreferences.getInstance(), now: () => now);
      await again.load();
      expect(again.sessions, hasLength(1));
      expect(again.sessions.single.category, '数学');
      expect(again.sessions.single.interrupted, isTrue);
      expect(again.sessions.single.seconds, 3600);
    });
  });
}
