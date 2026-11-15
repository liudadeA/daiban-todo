import 'dart:async';
import 'package:flutter/material.dart';

/// 独立于专注计时的本地时钟：每秒重读系统时间，切换时区/校时后自然更新。
class LocalWallClock extends StatefulWidget {
  final DateTime Function()? now;
  const LocalWallClock({super.key, this.now});

  @override
  State<LocalWallClock> createState() => _LocalWallClockState();
}

class _LocalWallClockState extends State<LocalWallClock> {
  Timer? _tick;
  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = (widget.now?.call() ?? DateTime.now()).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return Text('当前时间 ${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
        style: const TextStyle(fontSize: 22, fontFeatures: [FontFeature.tabularFigures()]));
  }
}
