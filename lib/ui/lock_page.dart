import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/focus_store.dart';
import '../data/store.dart';
import '../logic/focus.dart';
import '../platform/pin.dart';

/// 等待系统「固定此应用？」确认的最长时间；超时视为固定失败。
const lockPinTimeout = Duration(seconds: 20);

/// 锁屏倒计时的剩余时间：不足 1 小时显示 MM:SS，否则 HH:MM:SS。
String fmtCountdown(int seconds) {
  if (seconds < 0) seconds = 0;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// 请求屏幕固定并等待生效。返回 true = 已固定。
Future<bool> requestPinAndWait({Duration timeout = lockPinTimeout}) async {
  if (!await ScreenPin.start()) return false;
  final until = DateTime.now().add(timeout);
  while (true) {
    if (await ScreenPin.isPinned()) return true;
    if (DateTime.now().isAfter(until)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

/// 固定失败时的说明。
Future<void> showPinHelp(BuildContext context) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('没能固定屏幕'),
        content: const Text('锁屏倒计时需要 Android 的「屏幕固定」（也叫「应用固定」）。\n\n'
            '请到 系统设置 → 安全（或 安全与隐私 / 更多安全设置）→ 屏幕固定，打开后再回来点「开始」；'
            '开始时系统会询问是否固定，请选择「固定」。'),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('知道了'))],
      ),
    );

/// 底栏「锁屏」：选择类别和时长，开始后固定屏幕并倒计时。
class LockTab extends StatefulWidget {
  final TodoStore store;
  final FocusStore focus;
  const LockTab({super.key, required this.store, required this.focus});

  @override
  State<LockTab> createState() => LockTabState();
}

class LockTabState extends State<LockTab> {
  static const presets = [25, 45, 60, 90];

  TodoStore get store => widget.store;
  FocusStore get focus => widget.focus;

  late int _minutes;
  String? _cat;
  var _catChosen = false;
  var _starting = false;

  @override
  void initState() {
    super.initState();
    _minutes = focus.lastLockMinutes;
    if (focus.hasLastLockCategory) {
      _cat = focus.lastLockCategory;
      _catChosen = true;
    }
  }

  /// 任务里的类别 + 已有专注记录的类别，最后是「未分类」
  List<String?> categories() {
    final set = <String>{...store.categories};
    for (final s in focus.sessions) {
      if (s.category != null) set.add(s.category!);
    }
    final list = <String?>[...set.toList()..sort(), null];
    return list;
  }

  Future<void> _custom() async {
    var h = _minutes ~/ 60, m = _minutes % 60;
    final r = await showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('自定义时长'),
          content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            DropdownButton<int>(
              key: const Key('lock_custom_h'),
              value: h,
              items: [for (var i = 0; i <= 12; i++) DropdownMenuItem(value: i, child: Text('$i 小时'))],
              onChanged: (v) => set(() => h = v ?? 0),
            ),
            const SizedBox(width: 16),
            DropdownButton<int>(
              key: const Key('lock_custom_m'),
              value: m,
              items: [
                for (var i = 0; i < 60; i += 5) DropdownMenuItem(value: i, child: Text('$i 分钟')),
                if (m % 5 != 0) DropdownMenuItem(value: m, child: Text('$m 分钟')),
              ],
              onChanged: (v) => set(() => m = v ?? 0),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
                onPressed: h * 60 + m <= 0 ? null : () => Navigator.pop(c, h * 60 + m), child: const Text('确定')),
          ],
        ),
      ),
    );
    if (r != null && r > 0) setState(() => _minutes = r);
  }

  Future<void> start() async {
    if (_starting) return;
    if (focus.isRunning) {
      if (focus.isCountdown) {
        await openLocked();
        return;
      }
      final label = store.categoryLabel(focus.runningCategory);
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('正在正向计时'),
          content: Text('「$label」的正向计时还在进行。同一时间只能有一个计时，要先结束并记录它，再开始锁屏吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('结束并开始锁屏')),
          ],
        ),
      );
      if (ok != true) return;
      await focus.stop(interrupted: false);
      await ScreenPin.stop();
      if (!mounted) return;
    }
    setState(() => _starting = true);
    await ScreenPin.setKeepScreenOn(true);
    final pinned = await requestPinAndWait();
    if (!mounted) return;
    if (!pinned) {
      await ScreenPin.stop();
      await ScreenPin.setKeepScreenOn(false);
      setState(() => _starting = false);
      if (mounted) await showPinHelp(context);
      return;
    }
    await focus.startCountdown(_cat, Duration(minutes: _minutes));
    if (!mounted) return;
    setState(() => _starting = false);
    await openLocked();
  }

  Future<void> openLocked() async {
    await Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, _, _) => LockedPage(store: store, focus: focus),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cats = categories();
    if (!_catChosen || !cats.contains(_cat)) {
      // 默认第一个类别
      _cat = cats.isEmpty ? null : cats.first;
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      const Text('锁屏倒计时', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      const Text('开始后会固定屏幕并倒计时，到点自动结束并记入统计。', style: TextStyle(color: Colors.black54)),
      const SizedBox(height: 20),
      const Text('类别', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in cats)
          ChoiceChip(
            key: Key('lock_cat_${c ?? ''}'),
            label: Text(store.categoryLabel(c)),
            selected: c == _cat,
            onSelected: (_) => setState(() {
              _cat = c;
              _catChosen = true;
            }),
          ),
      ]),
      const SizedBox(height: 20),
      const Text('时长', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in presets)
          ChoiceChip(
            key: Key('lock_min_$m'),
            label: Text('$m分钟'),
            selected: _minutes == m,
            onSelected: (_) => setState(() => _minutes = m),
          ),
        ChoiceChip(
          key: const Key('lock_custom'),
          label: Text(presets.contains(_minutes) ? '自定义' : '自定义 · ${FocusCalc.fmtDuration(_minutes * 60)}'),
          selected: !presets.contains(_minutes),
          onSelected: (_) => _custom(),
        ),
      ]),
      const SizedBox(height: 32),
      Center(
        child: Text(fmtCountdown(_minutes * 60),
            key: const Key('lock_preview'),
            style: TextStyle(fontSize: 48, fontWeight: FontWeight.w300, color: scheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
      const SizedBox(height: 32),
      FilledButton(
        key: const Key('lock_start'),
        onPressed: _starting ? null : start,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_starting ? '正在请求屏幕固定…' : '开始', style: const TextStyle(fontSize: 18)),
        ),
      ),
    ]);
  }
}

/// 固定后的倒计时视图。界面上不提供任何退出方式；到点自动结束，或被系统解除固定时中断并记录。
class LockedPage extends StatefulWidget {
  final TodoStore store;
  final FocusStore focus;
  const LockedPage({super.key, required this.store, required this.focus});

  @override
  State<LockedPage> createState() => _LockedPageState();
}

class _LockedPageState extends State<LockedPage> {
  Timer? _tick;
  VoidCallback? _unlisten;
  var _done = false;

  FocusStore get focus => widget.focus;

  @override
  void initState() {
    super.initState();
    _unlisten = ScreenPin.listen((pinned) {
      if (!pinned) _onSystemUnpin();
    });
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _unlisten?.call();
    super.dispose();
  }

  void _onTick() {
    if (!mounted || _done) return;
    if (!focus.isCountdown) {
      _leave(null);
      return;
    }
    if (focus.remainingSeconds <= 0) {
      _complete();
    } else {
      setState(() {});
    }
  }

  Future<void> _complete() async {
    if (_done) return;
    _done = true;
    final cat = widget.store.categoryLabel(focus.runningCategory);
    final rec = await focus.completeCountdown();
    await ScreenPin.stop();
    await ScreenPin.setKeepScreenOn(false);
    HapticFeedback.heavyImpact();
    _leave(rec == null ? null : '「$cat」锁屏倒计时完成，已记录（${FocusCalc.fmtDuration(rec.seconds)}）');
  }

  Future<void> _onSystemUnpin() async {
    if (_done || !focus.isCountdown) return;
    _done = true;
    final rec = await focus.interruptCountdown();
    await ScreenPin.stop();
    await ScreenPin.setKeepScreenOn(false);
    _leave(rec == null ? '已退出屏幕固定，计时不足 10 秒，未记录' : '已退出屏幕固定，本次已中断并记录');
  }

  void _leave(String? msg) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    if (msg != null) {
      messenger?.clearSnackBars();
      messenger?.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remain = focus.remainingSeconds;
    final total = focus.plannedSeconds;
    final progress = total <= 0 ? 0.0 : (1 - remain / total).clamp(0.0, 1.0);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) {},
      child: Scaffold(
        key: const Key('locked_view'),
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(widget.store.categoryLabel(focus.runningCategory),
                  key: const Key('locked_cat'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('锁屏倒计时', style: TextStyle(color: Colors.black45)),
              const SizedBox(height: 32),
              SizedBox(
                width: 260,
                height: 260,
                child: CustomPaint(
                  painter: _RingPainter(progress, scheme.primary, scheme.primary.withValues(alpha: 0.12)),
                  child: Center(
                    child: Text(fmtCountdown(remain),
                        key: const Key('locked_clock'),
                        style: const TextStyle(
                            fontSize: 52, fontWeight: FontWeight.w300, fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text('共 ${FocusCalc.fmtDuration(total)}', style: const TextStyle(color: Colors.black45)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color fg, bg;
  _RingPainter(this.progress, this.fg, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 8;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = bg;
    canvas.drawCircle(c, r, base);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = fg;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress || old.fg != fg;
}
