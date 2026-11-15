import 'package:daiban/ui/local_wall_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('当前时间取本地系统时刻，每秒更新，跨午夜和手动校时不影响正倒计时', (tester) async {
    var now = DateTime(2026, 11, 15, 23, 59, 59);
    await tester.pumpWidget(MaterialApp(home: LocalWallClock(now: () => now)));
    expect(find.text('当前时间 23:59:59'), findsOneWidget);
    now = DateTime(2026, 11, 16, 0, 0, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('当前时间 00:00:00'), findsOneWidget);
    now = DateTime(2026, 11, 16, 9, 5, 7);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('当前时间 09:05:07'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull); // dispose 取消 timer
  });

  testWidgets('UTC 输入转换成本地时间显示', (tester) async {
    final input = DateTime.utc(2026, 11, 16, 6, 7, 8);
    final t = input.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    await tester.pumpWidget(MaterialApp(home: LocalWallClock(now: () => input)));
    expect(find.text('当前时间 ${two(t.hour)}:${two(t.minute)}:${two(t.second)}'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
