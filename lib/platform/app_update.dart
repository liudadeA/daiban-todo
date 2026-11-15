import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/app_edition.dart';
import '../logic/update_check.dart';

const updateChannelName = 'daiban/update';

class UpdateCoordinator {
  final EditionProfile edition;
  final Future<String> Function() fetchReleases;
  final Future<DeviceInfo> Function() deviceInfo;
  final Future<SharedPreferences> Function() prefs;
  final Future<File> Function(GithubAsset asset, {void Function(int received, int? total)? onProgress}) download;
  final Future<String> Function(String path) installApk;

  UpdateCoordinator({
    required this.edition,
    required this.fetchReleases,
    required this.deviceInfo,
    required this.prefs,
    required this.download,
    required this.installApk,
  });

  /// 生产环境协调器。测试请注入假的网络与安装实现，不要访问 GitHub。
  static UpdateCoordinator production({EditionProfile? edition}) {
    final ed = edition ?? AppEdition.profile;
    return UpdateCoordinator(
      edition: ed,
      fetchReleases: fetchGithubReleasesJson,
      deviceInfo: readDeviceInfo,
      prefs: SharedPreferences.getInstance,
      download: downloadApk,
      installApk: requestInstallApk,
    );
  }

  Future<UpdateCheckResult> check({required bool manual}) async {
    try {
      final info = await deviceInfo();
      final releases = parseReleasesJson(await fetchReleases());
      final store = await prefs();
      final dismissed = store.getString(dismissedPrefKey(edition));
      return evaluateUpdate(
        releases: releases,
        edition: edition,
        current: info,
        manual: manual,
        dismissedVersion: dismissed,
      );
    } on UpdateCheckException catch (e) {
      if (!manual) return UpdateCheckResult(UpdateStatus.error, '');
      return UpdateCheckResult(UpdateStatus.error, e.message);
    } catch (_) {
      if (!manual) return const UpdateCheckResult(UpdateStatus.error, '');
      return const UpdateCheckResult(UpdateStatus.error, '网络错误，请稍后重试');
    }
  }

  Future<void> dismiss(EditionUpdate update) async {
    final store = await prefs();
    await store.setString(dismissedPrefKey(edition), update.versionName);
  }

  Future<File> downloadUpdate(EditionUpdate update, {void Function(int received, int? total)? onProgress}) {
    final apk = update.apk;
    if (apk == null) {
      throw const UpdateCheckException('没有适合本机的安装包');
    }
    return download(apk, onProgress: onProgress);
  }
}

Future<DeviceInfo> readDeviceInfo() async {
  try {
    const ch = MethodChannel(updateChannelName);
    final raw = await ch.invokeMapMethod<String, dynamic>('getAppInfo');
    if (raw != null) {
      final code = raw['versionCode'];
      return DeviceInfo(
        versionName: '${raw['versionName'] ?? AppEdition.versionName}',
        versionCode: code is int ? code : int.tryParse('$code'),
        abi: '${raw['abi'] ?? 'unknown'}',
      );
    }
  } catch (_) {}
  return const DeviceInfo(versionName: AppEdition.versionName, abi: 'unknown');
}

Future<String> requestInstallApk(String path) async {
  const ch = MethodChannel(updateChannelName);
  final r = await ch.invokeMethod<String>('installApk', {'path': path});
  return r ?? 'started';
}

Future<String> fetchGithubReleasesJson({HttpClient? client}) async {
  final owned = client == null;
  final c = client ?? HttpClient();
  try {
    final req = await c.getUrl(Uri.parse(githubReleasesListUrl));
    req.headers.set(HttpHeaders.userAgentHeader, 'daiban-todo/${AppEdition.versionName} (${AppEdition.profile.id})');
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw const UpdateCheckException('检查失败，请稍后重试');
    }
    return body;
  } on UpdateCheckException {
    rethrow;
  } on SocketException {
    throw const UpdateCheckException('网络错误，请稍后重试');
  } on HttpException {
    throw const UpdateCheckException('网络错误，请稍后重试');
  } finally {
    if (owned) c.close(force: true);
  }
}

Future<File> downloadApk(GithubAsset asset, {void Function(int received, int? total)? onProgress, HttpClient? client}) async {
  final tmp = await getTemporaryDirectory();
  final dir = Directory('${tmp.path}/updates');
  await dir.create(recursive: true);
  final safe = asset.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final file = File('${dir.path}/$safe');
  if (await file.exists() && asset.size > 0 && await file.length() == asset.size) {
    onProgress?.call(asset.size, asset.size);
    return file;
  }
  final owned = client == null;
  final c = client ?? HttpClient();
  try {
    final req = await c.getUrl(Uri.parse(asset.url));
    req.headers.set(HttpHeaders.userAgentHeader, 'daiban-todo/${AppEdition.versionName} (${AppEdition.profile.id})');
    req.followRedirects = true;
    final res = await req.close();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw const UpdateCheckException('下载失败，请稍后重试');
    }
    final sink = file.openWrite();
    var received = 0;
    final total = res.contentLength >= 0 ? res.contentLength : (asset.size > 0 ? asset.size : null);
    try {
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return file;
  } on UpdateCheckException {
    rethrow;
  } catch (_) {
    throw const UpdateCheckException('下载失败，请稍后重试');
  } finally {
    if (owned) c.close(force: true);
  }
}
