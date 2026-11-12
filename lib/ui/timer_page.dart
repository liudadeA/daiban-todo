import 'dart:async';

import 'package:flutter/material.dart';

import '../data/focus_store.dart';
import '../data/store.dart';
import '../logic/focus.dart';
import '../platform/pin.dart';

/// 正向计时全屏页：进入后请求屏幕固定；返回 / 退出先弹窗，确认后中断并记录。
class TimerPage extends StatefulWidget {
  final TodoStore store;
  final FocusStore focus;
  const TimerPage({super.key, required this.store, required this.focus});

  @override
  State<TimerPage> createState() => TimerPageState();
}

class TimerPageState extends State<TimerPage> {
  Timer? _tick;
  VoidCallback? _unpin;
  var _busy = false; // 正在结束，避免系统解除固定时再记一次
  var _dialogOpen = false;

  FocusStore get focus => widget.focus;
  TodoStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted && focus.isRunning) setState(() {});
    });
    _unpin = ScreenPin.listen(_onPinState);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ScreenPin.setKeepScreenOn(true);
      await ScreenPin.start();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _unpin?.call();
    ScreenPin.setKeepScreenOn(false);
    // 若页面被别处弹出且计时已停，确保解除固定
    if (!focus.isRunning) ScreenPin.stop();
    super.dispose();
  }

  void _onPinState(bool pinned) {
    if (pinned || _busy || !focus.isRunning || !mounted) return;
    // 用户用系统手势解除了屏幕固定：中断并记录，然后离开本页
    _finish(interrupted: true, fromSystem: true);
  }

  Future<bool> confirmExit() async {
    if (_dialogOpen) return false;
    _dialogOpen = true;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('退出计时？'),
        content: const Text('将解除屏幕固定，本次计时会被中断并记录。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('继续计时')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('退出并记录')),
        ],
      ),
    );
    _dialogOpen = false;
    return ok == true;
  }

  Future<void> _requestExit() async {
    if (_busy) return;
    if (!await confirmExit()) return;
    await _finish(interrupted: true);
  }

  Future<void> _requestStop() async {
    if (_busy) return;
    await _finish(interrupted: false);
  }

  Future<void> _finish({required bool interrupted, bool fromSystem = false}) async {
    if (_busy) return;
    _busy = true;
    FocusSession? rec;
    try {
      rec = await focus.stop(interrupted: interrupted);
      await ScreenPin.stop();
      await ScreenPin.setKeepScreenOn(false);
    } catch (_) {}
    if (!mounted) return;
    final label = store.categoryLabel(rec?.category ?? focus.runningCategory);
    final dur = rec == null ? '不足 1 秒，未记入统计' : FocusCalc.fmtDuration(rec.seconds);
    final msg = rec == null
        ? dur
        : (interrupted ? '已中断「$label」的计时并记录（$dur）' : '已记录「$label」的专注（$dur）');
    if (fromSystem) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已退出屏幕固定，$msg')));
    }
    Navigator.pop(context, rec);
  }

  @override
  Widget build(BuildContext context) {
    final cat = store.categoryLabel(focus.runningCategory);
    final clock = FocusCalc.fmtClock(focus.elapsedSeconds);
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('timer_exit'),
                    onPressed: _requestExit,
                    icon: const Icon(Icons.close),
                    label: const Text('退出'),
                  ),
                ),
                const Spacer(),
                Text(cat, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('正向计时', style: TextStyle(color: Colors.black45)),
                const SizedBox(height: 24),
                Text(
                  clock,
                  key: const Key('timer_clock'),
                  style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300, fontFeatures: [FontFeature.tabularFigures()], letterSpacing: 2),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('timer_stop'),
                    onPressed: _requestStop,
                    child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('结束并记录', style: TextStyle(fontSize: 18))),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _requestExit,
                  child: const Text('退出并中断'),
                ),
                const SizedBox(height: 24),
                const Text('退出时会先确认，然后解除屏幕固定、中断计时并记入统计。',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black38, fontSize: 12)),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
