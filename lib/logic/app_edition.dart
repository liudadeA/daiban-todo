/// 当前构建所属的发行版本。两套源码各写一份，避免把专注版 Latest 当成基础版更新。
class EditionProfile {
  final String id;
  final String displayName;
  final String titleMarker;
  final String otherTitleMarker;
  final String assetPrefix;
  final String otherAssetPrefix;

  const EditionProfile({
    required this.id,
    required this.displayName,
    required this.titleMarker,
    required this.otherTitleMarker,
    required this.assetPrefix,
    required this.otherAssetPrefix,
  });

  static const focus = EditionProfile(
    id: 'focus',
    displayName: '待办 专注版',
    titleMarker: '待办 专注版',
    otherTitleMarker: '待办 基础版',
    assetPrefix: 'daiban-focus-',
    otherAssetPrefix: 'daiban-basic-',
  );

  static const basic = EditionProfile(
    id: 'basic',
    displayName: '待办 基础版',
    titleMarker: '待办 基础版',
    otherTitleMarker: '待办 专注版',
    assetPrefix: 'daiban-basic-',
    otherAssetPrefix: 'daiban-focus-',
  );

  bool get isFocus => id == 'focus';
}

/// 本构建的版本身份。版本号须与 pubspec 保持一致。
class AppEdition {
  static const profile = EditionProfile.focus;
  static const versionName = '1.6.7';
  static const pubspecBuild = 16;
}
