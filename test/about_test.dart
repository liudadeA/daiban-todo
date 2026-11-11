import 'package:daiban/logic/todo_item.dart';
import 'package:daiban/ui/about.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('示例行能被解析：类别 408、due/t 正确', () {
    final it = TodoItem.parse(exampleLine)!;
    expect(it.category, '408');
    expect(it.projects, ['408', '数据结构']);
    expect(it.due, DateTime.utc(2026, 11, 11));
    expect(it.start, DateTime.utc(2026, 11, 11));
  });

  testWidgets('关于页：导入格式在最上、协议在最后且只有本仓库链接；可复制', (tester) async {
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String?;
      return null;
    });
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    final yFormat = tester.getTopLeft(find.text('导入格式')).dy;
    final yLicense = tester.getTopLeft(find.text('开源协议')).dy;
    expect(yFormat, lessThan(yLicense));
    expect(tester.getTopLeft(find.byKey(const Key('exampleLine'))).dy, lessThan(yLicense));
    expect(find.byType(SelectableText), findsWidgets);
    // 页面上不应出现除本仓库之外的链接
    final texts = tester.widgetList<SelectableText>(find.byType(SelectableText)).map((w) => w.data ?? '').join('\n');
    expect(texts, contains(repoUrl));
    expect(texts, isNot(contains('topydo/topydo')));
    expect(texts, isNot(contains('gnu.org')));
    expect(RegExp(r'https?://[^\s]+').allMatches(texts).map((m) => m.group(0)).toSet(), {repoUrl});
    expect(texts, contains('GPL-3.0'));
    expect(texts, contains('due:'));
    expect(find.textContaining('待办'), findsWidgets);
    expect(find.textContaining('代办'), findsNothing);
    await tester.tap(find.byKey(const Key('copyExample')));
    await tester.pump();
    expect(clip, exampleLine);
    expect(find.text('已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byKey(const Key('copyRepo')));
    await tester.pump();
    expect(clip, repoUrl);
  });
}
