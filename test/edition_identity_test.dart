import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daiban/logic/app_edition.dart';
import 'package:daiban/ui/about.dart';

void main() {
  test('版本与 Android 应用标识正确，保留 Kotlin namespace', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('applicationId = "cn.daiban.daiban.basic"'));
    expect(gradle, contains('namespace = "cn.daiban.daiban"'));
    expect(File('pubspec.yaml').readAsStringSync(), contains('version: 1.5.5+12'));
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:label="待办 基础版"'));
    expect(File('lib/main.dart').readAsStringSync(), contains("title: '待办 基础版'"));
    expect(AppEdition.profile, EditionProfile.basic);
    expect(AppEdition.versionName, '1.5.5');
    expect(AppEdition.pubspecBuild, 12);
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
    expect(manifest, contains(r'${applicationId}.shareprovider'));
    expect(File('android/app/src/main/res/xml/share_paths.xml').readAsStringSync(), contains('updates/'));
  });

  test('桌面组件动作与 URI 使用本版独立标识', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final provider = File('android/app/src/main/kotlin/cn/daiban/daiban/TodayWidgetProvider.kt').readAsStringSync();
    for (final action in ['cn.daiban.daiban.basic.widget.COMPLETE', 'cn.daiban.daiban.basic.widget.MIDNIGHT']) {
      expect(manifest, contains(action));
      expect(provider, contains(action));
    }
    expect(provider, contains('daiban-basic://refresh'));
    expect(File('lib/logic/widget_actions.dart').readAsStringSync(), contains("scheme = 'daiban-basic'"));
    expect(provider, contains('daiban-basic://complete'));
    expect(File('android/app/src/main/res/values/strings.xml').readAsStringSync(), contains('待办 基础版 · 今日'));
  });

  testWidgets('关于页展示本版应用名', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    expect(find.text('关于 待办 基础版'), findsOneWidget);
    expect(introText, startsWith('待办 基础版 是一款'));
  });
}
