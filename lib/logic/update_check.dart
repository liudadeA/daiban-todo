import 'dart:convert';

import 'app_edition.dart';

/// 一次检查更新的结果（不会自动安装）。
enum UpdateStatus { latest, available, dismissed, noApk, error }

class UpdateCheckException implements Exception {
  final String message;
  const UpdateCheckException(this.message);
  @override
  String toString() => message;
}

class GithubAsset {
  final String name;
  final String url;
  final int size;
  const GithubAsset({required this.name, required this.url, required this.size});
}

class GithubRelease {
  final String tag;
  final String title;
  final String body;
  final bool draft;
  final bool prerelease;
  final List<GithubAsset> assets;
  const GithubRelease({
    required this.tag,
    required this.title,
    required this.body,
    required this.draft,
    required this.prerelease,
    required this.assets,
  });
}

class DeviceInfo {
  final String versionName;
  final int? versionCode;
  final String abi;
  const DeviceInfo({required this.versionName, this.versionCode, required this.abi});
}

class EditionUpdate {
  final GithubRelease release;
  final String versionName;
  final int? versionCode;
  final GithubAsset? apk;
  const EditionUpdate({
    required this.release,
    required this.versionName,
    this.versionCode,
    this.apk,
  });
}

class UpdateCheckResult {
  final UpdateStatus status;
  final EditionUpdate? update;
  final String message;
  const UpdateCheckResult(this.status, this.message, {this.update});

  bool get hasInstallableUpdate => status == UpdateStatus.available && update?.apk != null;
}

/// GitHub Releases *列表* API（不要请求 /releases/latest：该仓库的 Latest 是专注版）。
const githubReleasesListUrl =
    'https://api.github.com/repos/liudadeA/daiban-todo/releases?per_page=30';

/// 解析 GitHub Releases 列表 JSON。
List<GithubRelease> parseReleasesJson(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! List) {
    throw const UpdateCheckException('检查失败，请稍后重试');
  }
  return [
    for (final raw in decoded)
      if (raw is Map)
        GithubRelease(
          tag: '${raw['tag_name'] ?? ''}',
          title: '${raw['name'] ?? ''}',
          body: '${raw['body'] ?? ''}',
          draft: raw['draft'] == true,
          prerelease: raw['prerelease'] == true,
          assets: [
            for (final a in (raw['assets'] as List? ?? const []))
              if (a is Map)
                GithubAsset(
                  name: '${a['name'] ?? ''}',
                  url: '${a['browser_download_url'] ?? ''}',
                  size: a['size'] is int ? a['size'] as int : int.tryParse('${a['size']}') ?? 0,
                ),
          ],
        ),
  ];
}

/// 这份 Release 是否属于指定版本（专注版 / 基础版）。
///
/// 只看标题（「待办 专注版」/「待办 基础版」）和资源文件名（`daiban-focus-*` /
/// `daiban-basic-*`）。绝不把 GitHub Latest 或列表第一项当作“我的更新”。
bool belongsToEdition(GithubRelease release, EditionProfile edition) {
  final title = release.title;
  final titledMine = title.contains(edition.titleMarker);
  final titledOther = title.contains(edition.otherTitleMarker);
  if (titledOther && !titledMine) return false;
  if (titledMine && !titledOther) return true;

  final names = release.assets.map((a) => a.name);
  final hasMine = names.any((n) => n.startsWith(edition.assetPrefix));
  final hasOther = names.any((n) => n.startsWith(edition.otherAssetPrefix));
  if (hasOther && !hasMine) return false;
  return hasMine;
}

String? parseVersionName({required String tag, required String title}) {
  final fromTag = RegExp(r'^v?(\d+\.\d+\.\d+)\b').firstMatch(tag.trim());
  if (fromTag != null) return fromTag.group(1);
  final fromTitle = RegExp(r'v?(\d+\.\d+\.\d+)\s*$').firstMatch(title.trim());
  return fromTitle?.group(1);
}

/// 从发布说明里读取当前 ABI 的 versionCode（若有）。
int? parseVersionCode(String body, String abi) {
  if (_isArm64(abi)) {
    final m = RegExp(r'arm64(?:-v8a)?\s+versionCode\s+(\d+)', caseSensitive: false).firstMatch(body);
    if (m != null) return int.parse(m.group(1)!);
  }
  if (_isArmV7(abi)) {
    final m = RegExp(r'(?:armeabi-v7a|v7a)\s+versionCode\s+(\d+)', caseSensitive: false).firstMatch(body);
    if (m != null) return int.parse(m.group(1)!);
  }
  return null;
}

bool _isArm64(String abi) => abi.contains('arm64');
bool _isArmV7(String abi) => abi.contains('armeabi-v7a') || (abi.contains('v7a') && !abi.contains('arm64'));

/// 选择与本机 ABI、本版本前缀匹配的 APK。不跨版本取包。
GithubAsset? pickApk(GithubRelease release, EditionProfile edition, String abi) {
  bool matchesAbi(String name) {
    if (_isArm64(abi)) return name.contains('arm64') && !name.contains('v7a');
    if (_isArmV7(abi)) return name.contains('armeabi-v7a') || (name.contains('v7a') && !name.contains('arm64'));
    return false;
  }

  for (final a in release.assets) {
    if (a.name.startsWith(edition.assetPrefix) && a.name.endsWith('.apk') && matchesAbi(a.name) && a.url.isNotEmpty) {
      return a;
    }
  }
  return null;
}

int compareVersionName(String a, String b) {
  List<int> parts(String v) =>
      v.split('.').map((p) => int.tryParse(RegExp(r'^\d+').stringMatch(p) ?? '') ?? 0).toList();
  final pa = parts(a);
  final pb = parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final da = i < pa.length ? pa[i] : 0;
    final db = i < pb.length ? pb[i] : 0;
    if (da != db) return da.compareTo(db);
  }
  return 0;
}

/// 是否比当前安装的版本新。优先比较同一 ABI 的 versionCode，否则比较 versionName。
bool isNewerThanCurrent(EditionUpdate remote, DeviceInfo current) {
  if (remote.versionCode != null && current.versionCode != null) {
    return remote.versionCode! > current.versionCode!;
  }
  return compareVersionName(remote.versionName, current.versionName) > 0;
}

bool isNewerRelease(EditionUpdate a, EditionUpdate b, String abi) {
  if (a.versionCode != null && b.versionCode != null) return a.versionCode! > b.versionCode!;
  return compareVersionName(a.versionName, b.versionName) > 0;
}

EditionUpdate? toEditionUpdate(GithubRelease release, EditionProfile edition, String abi) {
  final name = parseVersionName(tag: release.tag, title: release.title);
  if (name == null) return null;
  return EditionUpdate(
    release: release,
    versionName: name,
    versionCode: parseVersionCode(release.body, abi),
    apk: pickApk(release, edition, abi),
  );
}

/// 在列表里找出该版本（专注或基础）可用的最新正式发布。
EditionUpdate? findNewestEditionRelease(
  List<GithubRelease> releases,
  EditionProfile edition,
  String abi,
) {
  EditionUpdate? best;
  for (final r in releases) {
    if (r.draft || r.prerelease) continue;
    if (!belongsToEdition(r, edition)) continue;
    final u = toEditionUpdate(r, edition, abi);
    if (u == null) continue;
    if (best == null || isNewerRelease(u, best, abi)) best = u;
  }
  return best;
}

/// [manual] 为 false 时，网络错误或没有匹配 APK 都保持安静，不打扰用户。
UpdateCheckResult evaluateUpdate({
  required List<GithubRelease> releases,
  required EditionProfile edition,
  required DeviceInfo current,
  required bool manual,
  String? dismissedVersion,
}) {
  final newest = findNewestEditionRelease(releases, edition, current.abi);
  if (newest == null || !isNewerThanCurrent(newest, current)) {
    return UpdateCheckResult(UpdateStatus.latest, '已是最新版本（${current.versionName}）');
  }
  if (newest.apk == null) {
    if (!manual) return const UpdateCheckResult(UpdateStatus.noApk, '');
    return UpdateCheckResult(
      UpdateStatus.noApk,
      '发现新版本 ${newest.versionName}，但没有适合本机的安装包',
      update: newest,
    );
  }
  if (!manual && dismissedVersion != null && dismissedVersion == newest.versionName) {
    return UpdateCheckResult(UpdateStatus.dismissed, '发现新版本 ${newest.versionName}', update: newest);
  }
  return UpdateCheckResult(UpdateStatus.available, '发现新版本 ${newest.versionName}', update: newest);
}

String dismissedPrefKey(EditionProfile edition) => 'update.dismissed.${edition.id}';
