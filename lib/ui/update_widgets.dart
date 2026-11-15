import 'package:flutter/material.dart';

import '../logic/app_edition.dart';
import '../logic/update_check.dart';
import '../platform/app_update.dart';

const updateBannerKey = Key('updateBanner');
const checkUpdateKey = Key('checkUpdate');
const updateStatusKey = Key('updateStatus');
const updateNowKey = Key('updateNow');
const updateLaterKey = Key('updateLater');
const updateAboutInstallKey = Key('updateAboutInstall');

/// 关于页里的手动检查。不强制更新。
class UpdateAboutSection extends StatefulWidget {
  final UpdateCoordinator? coordinator;
  const UpdateAboutSection({super.key, this.coordinator});

  @override
  State<UpdateAboutSection> createState() => _UpdateAboutSectionState();
}

class _UpdateAboutSectionState extends State<UpdateAboutSection> {
  UpdateCoordinator? _created;
  UpdateCoordinator get _c => widget.coordinator ?? (_created ??= UpdateCoordinator.production());
  bool _busy = false;
  String? _status;
  EditionUpdate? _update;

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '正在检查…';
      _update = null;
    });
    final r = await _c.check(manual: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = r.message;
      _update = r.hasInstallableUpdate ? r.update : null;
    });
  }

  Future<void> _install() async {
    final u = _update;
    if (u == null || _busy) return;
    await startUpdateFlow(context, _c, u);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('当前版本 ${AppEdition.versionName}'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.tonal(
          key: checkUpdateKey,
          onPressed: _busy ? null : _check,
          child: Text(_busy ? '正在检查…' : '检查更新'),
        ),
        if (_update != null)
          FilledButton(
            key: updateAboutInstallKey,
            onPressed: _busy ? null : _install,
            child: const Text('下载更新'),
          ),
      ]),
      if (_status != null) ...[
        const SizedBox(height: 8),
        Text(_status!, key: updateStatusKey),
      ],
      const SizedBox(height: 4),
      Text(
        '检查只针对本应用（${_c.edition.displayName}），不会把另一个版本当成更新。有更新时不会强制安装，需你点下载，并仍要通过系统安装确认。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ]);
  }
}

/// 下载后调起系统安装确认界面。不能静默安装。
Future<void> startUpdateFlow(BuildContext context, UpdateCoordinator coordinator, EditionUpdate update) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final progress = ValueNotifier<(int, int?)>((0, null));
  var cancelled = false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('下载更新'),
        content: ValueListenableBuilder<(int, int?)>(
          valueListenable: progress,
          builder: (_, value, _) {
            final received = value.$1;
            final total = value.$2;
            final label = total != null && total > 0
                ? '正在下载 ${update.versionName}（${(received / total * 100).clamp(0, 100).toStringAsFixed(0)}%）'
                : '正在下载 ${update.versionName}…';
            return Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(value: total != null && total > 0 ? (received / total).clamp(0, 1) : null),
              const SizedBox(height: 12),
              Text(label),
            ]);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.of(ctx).pop();
            },
            child: const Text('取消'),
          ),
        ],
      );
    },
  );
  try {
    final file = await coordinator.downloadUpdate(update, onProgress: (r, t) {
      progress.value = (r, t);
    });
    if (cancelled) return;
    if (context.mounted) {
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    }
    final r = await coordinator.installApk(file.path);
    if (r == 'needPermission') {
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(
        content: Text('请允许本应用安装应用后，再点「更新」。安装仍需系统确认，不会静默安装。'),
        duration: Duration(seconds: 6),
      ));
    }
  } catch (e) {
    if (context.mounted) {
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    }
    if (!cancelled) {
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(content: Text('$e'), duration: const Duration(seconds: 4)));
    }
  } finally {
    progress.dispose();
  }
}

void showUpdateBanner(ScaffoldMessengerState messenger, UpdateCoordinator coordinator, EditionUpdate update) {
  messenger.hideCurrentMaterialBanner();
  messenger.showMaterialBanner(MaterialBanner(
    key: updateBannerKey,
    content: Text('发现新版本 ${update.versionName}。可以现在更新，也可以稍后，不会强制安装。'),
    actions: [
      TextButton(
        key: updateLaterKey,
        onPressed: () {
          messenger.hideCurrentMaterialBanner();
          coordinator.dismiss(update);
        },
        child: const Text('稍后'),
      ),
      TextButton(
        key: updateNowKey,
        onPressed: () {
          messenger.hideCurrentMaterialBanner();
          startUpdateFlow(messenger.context, coordinator, update);
        },
        child: const Text('更新'),
      ),
    ],
  ));
}
