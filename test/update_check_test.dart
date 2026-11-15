import 'dart:convert';
import 'dart:io';

import 'package:daiban/logic/app_edition.dart';
import 'package:daiban/logic/update_check.dart';
import 'package:daiban/platform/app_update.dart';
import 'package:daiban/ui/about.dart';
import 'package:daiban/ui/update_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> release({
  required String tag,
  required String title,
  String body = '',
  bool draft = false,
  bool prerelease = false,
  required List<Map<String, dynamic>> assets,
}) =>
    {
      'tag_name': tag,
      'name': title,
      'body': body,
      'draft': draft,
      'prerelease': prerelease,
      'assets': assets,
    };

Map<String, dynamic> apk(String name, {int size = 100, String? url}) => {
      'name': name,
      'size': size,
      'browser_download_url': url ?? 'https://example.test/$name',
    };

String bodyFor({int? arm64, int? v7a, String name = ''}) {
  final parts = <String>[];
  if (name.isNotEmpty) parts.add('版本：$name');
  if (arm64 != null) parts.add('arm64 versionCode $arm64');
  if (v7a != null) parts.add('armeabi-v7a versionCode $v7a');
  return parts.join('，');
}

/// 模拟当前仓库的真实发布形态：Latest 是更新的专注版，同时还有较旧/较新的基础版。
List<Map<String, dynamic>> mixedCatalog() => [
      release(
        tag: 'v1.6.7',
        title: '待办 专注版 v1.6.7',
        body: bodyFor(name: '1.6.7', arm64: 2016, v7a: 1016),
        assets: [
          apk('daiban-focus-arm64-v1.6.7.apk', size: 10),
          apk('daiban-focus-armeabi-v7a-v1.6.7.apk', size: 9),
        ],
      ),
      release(
        tag: 'v1.5.5',
        title: '待办 基础版 v1.5.5',
        body: bodyFor(name: '1.5.5', arm64: 2012, v7a: 1012),
        assets: [
          apk('daiban-basic-arm64-v1.5.5.apk', size: 8),
          apk('daiban-basic-armeabi-v7a-v1.5.5.apk', size: 7),
        ],
      ),
      release(
        tag: 'v1.6.6',
        title: '待办 专注版 v1.6.6',
        body: bodyFor(name: '1.6.6', arm64: 2015, v7a: 1015),
        assets: [
          apk('daiban-focus-arm64-v1.6.6.apk'),
          apk('daiban-focus-armeabi-v7a-v1.6.6.apk'),
        ],
      ),
      release(
        tag: 'v1.5.4',
        title: '待办 基础版 v1.5.4',
        body: bodyFor(name: '1.5.4', arm64: 2011, v7a: 1011),
        assets: [
          apk('daiban-basic-arm64-v1.5.4.apk'),
          apk('daiban-basic-armeabi-v7a-v1.5.4.apk'),
        ],
      ),
    ];

List<GithubRelease> parsed([List<Map<String, dynamic>>? raw]) => parseReleasesJson(jsonEncode(raw ?? mixedCatalog()));

UpdateCoordinator coordinator({
  required EditionProfile edition,
  required DeviceInfo device,
  String Function()? fetch,
  SharedPreferences? prefs,
  Future<File> Function(GithubAsset asset, {void Function(int, int?)? onProgress})? download,
  Future<String> Function(String path)? install,
}) {
  return UpdateCoordinator(
    edition: edition,
    fetchReleases: () async {
      if (fetch != null) return fetch();
      return jsonEncode(mixedCatalog());
    },
    deviceInfo: () async => device,
    prefs: () async => prefs ?? await SharedPreferences.getInstance(),
    download: download ??
        (asset, {onProgress}) async {
          throw const UpdateCheckException('test download not stubbed');
        },
    installApk: install ?? (path) async => 'started',
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('源码只使用 Releases 列表 API，不用 Latest 端点', () {
    final logic = File('lib/logic/update_check.dart').readAsStringSync();
    final plat = File('lib/platform/app_update.dart').readAsStringSync();
    expect(logic, contains('https://api.github.com/repos/liudadeA/daiban-todo/releases?per_page=30'));
    expect(plat, contains('githubReleasesListUrl'));
    expect(logic, isNot(contains('/repos/liudadeA/daiban-todo/releases/latest')));
    expect(plat, isNot(contains('/repos/liudadeA/daiban-todo/releases/latest')));
  });

  test('基础版绝不会把作为 Latest 的专注版发布当成更新', () {
    final releases = parsed();
    final newestFocus = findNewestEditionRelease(releases, EditionProfile.focus, 'arm64-v8a')!;
    final newestBasic = findNewestEditionRelease(releases, EditionProfile.basic, 'arm64-v8a')!;
    expect(newestFocus.versionName, '1.6.7');
    expect(newestFocus.apk!.name, 'daiban-focus-arm64-v1.6.7.apk');
    expect(newestBasic.versionName, '1.5.5');
    expect(newestBasic.apk!.name, 'daiban-basic-arm64-v1.5.5.apk');
    expect(newestBasic.release.title, isNot(contains('专注版')));

    const basicDevice = DeviceInfo(versionName: '1.5.4', versionCode: 2011, abi: 'arm64-v8a');
    final r = evaluateUpdate(
      releases: releases,
      edition: EditionProfile.basic,
      current: basicDevice,
      manual: false,
    );
    expect(r.status, UpdateStatus.available);
    expect(r.update!.versionName, '1.5.5');
    expect(r.update!.apk!.name, startsWith('daiban-basic-'));
    expect(r.update!.versionName, isNot('1.6.7'));
  });

  test('只靠资源文件名也能区分版本；标题写成对方版本则排除', () {
    final byAsset = parsed([
      release(tag: 'v9.9.9', title: '', assets: [apk('daiban-focus-arm64-v9.9.9.apk')]),
      release(tag: 'v8.8.8', title: '', assets: [apk('daiban-basic-arm64-v8.8.8.apk')]),
    ]);
    expect(findNewestEditionRelease(byAsset, EditionProfile.focus, 'arm64-v8a')!.versionName, '9.9.9');
    expect(findNewestEditionRelease(byAsset, EditionProfile.basic, 'arm64-v8a')!.versionName, '8.8.8');

    final mislabeled = parsed([
      release(
        tag: 'v9.9.9',
        title: '待办 基础版 v9.9.9',
        assets: [apk('daiban-focus-arm64-v9.9.9.apk')],
      ),
    ]);
    expect(belongsToEdition(mislabeled.single, EditionProfile.focus), isFalse);
    expect(findNewestEditionRelease(mislabeled, EditionProfile.focus, 'arm64-v8a'), isNull);
  });

  test('优先用同一 ABI 的 versionCode 比较，否则用 versionName；不跨版本比较', () {
    const arm = 'arm64-v8a';
    final higherCodeSameName = toEditionUpdate(
      parsed([
        release(
          tag: 'v1.6.7',
          title: '待办 专注版 v1.6.7',
          body: bodyFor(arm64: 2018, v7a: 1018),
          assets: [apk('daiban-focus-arm64-v1.6.7.apk')],
        ),
      ]).single,
      EditionProfile.focus,
      arm,
    )!;
    expect(isNewerThanCurrent(higherCodeSameName, const DeviceInfo(versionName: '1.6.7', versionCode: 2016, abi: arm)), isTrue);
    expect(isNewerThanCurrent(higherCodeSameName, const DeviceInfo(versionName: '1.6.7', versionCode: 2018, abi: arm)), isFalse);

    final byName = toEditionUpdate(
      parsed([
        release(tag: 'v1.6.8', title: '待办 专注版 v1.6.8', assets: [apk('daiban-focus-arm64-v1.6.8.apk')]),
      ]).single,
      EditionProfile.focus,
      arm,
    )!;
    expect(isNewerThanCurrent(byName, const DeviceInfo(versionName: '1.6.7', abi: arm)), isTrue);
    expect(isNewerThanCurrent(byName, const DeviceInfo(versionName: '1.6.8', abi: arm)), isFalse);
    expect(isNewerThanCurrent(byName, const DeviceInfo(versionName: '1.6.9', abi: arm)), isFalse);

    final v7 = findNewestEditionRelease(parsed(), EditionProfile.focus, 'armeabi-v7a')!;
    expect(v7.versionCode, 1016);
    expect(v7.apk!.name, contains('armeabi-v7a'));
    expect(pickApk(parsed().first, EditionProfile.focus, 'x86_64'), isNull);
  });

  test('草稿、预发布和已是最新时不提示更新', () {
    final list = parsed([
      release(
        tag: 'v1.6.9',
        title: '待办 专注版 v1.6.9',
        prerelease: true,
        assets: [apk('daiban-focus-arm64-v1.6.9.apk')],
      ),
      release(
        tag: 'v1.6.8',
        title: '待办 专注版 v1.6.8',
        draft: true,
        assets: [apk('daiban-focus-arm64-v1.6.8.apk')],
      ),
      release(
        tag: 'v1.6.7',
        title: '待办 专注版 v1.6.7',
        body: bodyFor(arm64: 2016),
        assets: [apk('daiban-focus-arm64-v1.6.7.apk')],
      ),
    ]);
    expect(findNewestEditionRelease(list, EditionProfile.focus, 'arm64-v8a')!.versionName, '1.6.7');
    final latest = evaluateUpdate(
      releases: list,
      edition: EditionProfile.focus,
      current: const DeviceInfo(versionName: '1.6.7', versionCode: 2016, abi: 'arm64-v8a'),
      manual: true,
    );
    expect(latest.status, UpdateStatus.latest);
    expect(latest.message, contains('已是最新版本'));
  });

  test('自动检查：稍后跳过的版本不再弹出；手动检查仍能看到更新', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = coordinator(
      edition: EditionProfile.focus,
      device: const DeviceInfo(versionName: '1.6.6', versionCode: 2015, abi: 'arm64-v8a'),
      prefs: prefs,
    );
    final auto = await c.check(manual: false);
    expect(auto.status, UpdateStatus.available);
    expect(auto.hasInstallableUpdate, isTrue);
    await c.dismiss(auto.update!);
    final skipped = await c.check(manual: false);
    expect(skipped.status, UpdateStatus.dismissed);
    expect(skipped.hasInstallableUpdate, isFalse);
    expect(skipped.update?.apk, isNotNull);
    final manual = await c.check(manual: true);
    expect(manual.status, UpdateStatus.available);
    expect(manual.message, contains('1.6.7'));
  });

  test('网络错误：自动检查保持安静，手动检查给出说明', () async {
    final c = coordinator(
      edition: EditionProfile.focus,
      device: const DeviceInfo(versionName: '1.6.6', versionCode: 2015, abi: 'arm64-v8a'),
      fetch: () => throw const UpdateCheckException('网络错误，请稍后重试'),
    );
    final auto = await c.check(manual: false);
    expect(auto.status, UpdateStatus.error);
    expect(auto.message, isEmpty);
    final manual = await c.check(manual: true);
    expect(manual.status, UpdateStatus.error);
    expect(manual.message, contains('网络错误'));
  });

  test('无效响应与没有匹配 APK 时的说明', () async {
    final bad = coordinator(
      edition: EditionProfile.focus,
      device: const DeviceInfo(versionName: '1.6.6', abi: 'arm64-v8a'),
      fetch: () => '{"message":"not a list"}',
    );
    expect((await bad.check(manual: true)).message, contains('检查失败'));

    final noApk = coordinator(
      edition: EditionProfile.focus,
      device: const DeviceInfo(versionName: '1.6.6', abi: 'x86_64'),
    );
    final auto = await noApk.check(manual: false);
    expect(auto.status, UpdateStatus.noApk);
    expect(auto.message, isEmpty);
    final manual = await noApk.check(manual: true);
    expect(manual.status, UpdateStatus.noApk);
    expect(manual.message, contains('没有适合本机的安装包'));
  });

  testWidgets('启动横幅可点稍后关闭，不挡住继续使用', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = coordinator(
      edition: EditionProfile.focus,
      device: const DeviceInfo(versionName: '1.6.6', versionCode: 2015, abi: 'arm64-v8a'),
      prefs: prefs,
    );
    final r = await c.check(manual: false);
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
      home: const Scaffold(body: Text('首页')),
    ));
    final key = tester.widget<MaterialApp>(find.byType(MaterialApp)).scaffoldMessengerKey!;
    await tester.pump();
    showUpdateBanner(key.currentState!, c, r.update!);
    await tester.pumpAndSettle();
    expect(find.byKey(updateBannerKey), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    await tester.tap(find.byKey(updateLaterKey));
    await tester.pumpAndSettle();
    expect(find.byKey(updateBannerKey), findsNothing);
    expect(find.text('首页'), findsOneWidget);
    expect(prefs.getString(dismissedPrefKey(EditionProfile.focus)), '1.6.7');
  });

  testWidgets('关于页手动检查：已最新 / 有更新 / 网络错误', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});

    Future<void> pump(UpdateCoordinator c) async {
      await tester.pumpWidget(MaterialApp(home: AboutPage(updateCoordinator: c)));
      await tester.pump();
    }

    final latest = coordinator(
      edition: AppEdition.profile,
      device: DeviceInfo(versionName: AppEdition.versionName, versionCode: 3000, abi: 'arm64-v8a'),
    );
    await pump(latest);
    expect(find.byKey(checkUpdateKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(checkUpdateKey));
    await tester.tap(find.byKey(checkUpdateKey));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(updateStatusKey), findsOneWidget);
    expect(find.textContaining('已是最新版本'), findsOneWidget);
    expect(find.byKey(updateAboutInstallKey), findsNothing);

    final newer = coordinator(
      edition: AppEdition.profile,
      device: const DeviceInfo(versionName: '0.0.1', versionCode: 1, abi: 'arm64-v8a'),
    );
    await pump(newer);
    await tester.ensureVisible(find.byKey(checkUpdateKey));
    await tester.tap(find.byKey(checkUpdateKey));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(updateStatusKey)).data, contains('发现新版本'));
    expect(find.byKey(updateAboutInstallKey), findsOneWidget);

    final err = coordinator(
      edition: AppEdition.profile,
      device: const DeviceInfo(versionName: '0.0.1', abi: 'arm64-v8a'),
      fetch: () => throw const UpdateCheckException('网络错误，请稍后重试'),
    );
    await pump(err);
    await tester.ensureVisible(find.byKey(checkUpdateKey));
    await tester.tap(find.byKey(checkUpdateKey));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('网络错误'), findsOneWidget);
  });
}
