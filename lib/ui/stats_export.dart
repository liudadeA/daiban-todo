import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../logic/dates.dart';
import '../logic/focus.dart';
import '../platform/pin.dart';

/// 分享用的统计图片：把「专注时长分布」饼图（当前所选周期）和「本月专注时段分布」柱图
/// 画在同一张 PNG 里（外加累计 / 当日的关键数字），不依赖屏幕上是否滚动到可见。
class StatsExportData {
  /// 生成日期（显示在页眉）
  final DateTime generatedOn;
  final PeriodStats all;
  final int dailyAvgSeconds;
  final DateTime day;
  final PeriodStats dayStats;

  /// 饼图周期：日 / 周 / 月 / 自定义
  final String periodName;

  /// 饼图周期的日期范围文字，例如 2026-11-09 ~ 2026-11-15
  final String periodRange;
  final PeriodStats dist;
  final int barYear, barMonth;
  final List<int> hours; // 24 个小时的累计秒数
  final String Function(String?) labelOf;

  const StatsExportData({
    required this.generatedOn,
    required this.all,
    required this.dailyAvgSeconds,
    required this.day,
    required this.dayStats,
    required this.periodName,
    required this.periodRange,
    required this.dist,
    required this.barYear,
    required this.barMonth,
    required this.hours,
    required this.labelOf,
  });
}

/// 图片排版 + 绘制。先 [layout] 得到逻辑尺寸，再 [paint]。
/// [sections] 记录各区块位置，[texts] 记录画出的所有文字（便于测试与排查）。
class StatsExportPainter {
  static const double width = 360;
  static const double pad = 16;
  static const seed = Color(0xFF2E7D6B);

  final StatsExportData d;
  final ColorScheme cs = ColorScheme.fromSeed(seedColor: seed);
  final Map<String, Rect> sections = {};
  final List<String> texts = [];
  StatsExportPainter(this.d);

  static const _ink = Color(0xDD000000);
  static const _muted = Color(0x8A000000);
  static const _faint = Color(0x73000000);

  /// 逻辑高度（宽度固定 [width]）。
  double layout() => _run(null);

  /// 先量一遍得到各卡片位置并画背景，再画内容（两遍排版完全一致）。
  double paint(Canvas c) {
    sections.clear();
    texts.clear();
    final h = _run(null);
    c.drawRect(Rect.fromLTWH(0, 0, width, h), Paint()..color = cs.surfaceContainerLow);
    c.drawRect(sections['header']!, Paint()..color = cs.primary);
    for (final k in const ['summary', 'pie', 'bar']) {
      _cardBg(c, sections[k]!);
    }
    _run(c);
    return h;
  }

  // ------------------------------------------------------------------ 绘制

  TextPainter _tp(String s, double size, {Color color = _ink, FontWeight w = FontWeight.normal, double maxW = width, TextAlign align = TextAlign.left}) {
    return TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: w, height: 1.25)),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxW);
  }

  /// 画一行文字，返回高度
  double _text(Canvas? c, String s, double x, double y, double size,
      {Color color = _ink, FontWeight w = FontWeight.normal, double? maxW, bool center = false}) {
    final mw = maxW ?? width - x - pad;
    final tp = _tp(s, size, color: color, w: w, maxW: mw, align: center ? TextAlign.center : TextAlign.left);
    if (c != null) {
      texts.add(s);
      final dx = center ? x + (mw - tp.width) / 2 : x;
      tp.paint(c, Offset(dx, y));
    }
    return tp.height;
  }

  double _card(String key, double y, double Function(double top) body) {
    const inner = 14.0;
    final h = body(y + inner) + inner * 2;
    final r = Rect.fromLTWH(pad, y, width - pad * 2, h);
    sections[key] = r;
    return h;
  }

  void _cardBg(Canvas c, Rect r) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(16));
    c.drawRRect(rr, Paint()..color = Colors.white);
    c.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x10000000));
  }

  double _metrics(Canvas? c, double y, List<(String, String)> items) {
    const x0 = pad + 14;
    final w = (width - x0 * 2) / items.length;
    var h = 0.0;
    for (var i = 0; i < items.length; i++) {
      final x = x0 + w * i;
      final lh = _text(c, items[i].$1, x, y, 11, color: _muted, maxW: w - 4);
      final vh = _text(c, items[i].$2, x, y + lh + 2, 14, w: FontWeight.w700, maxW: w - 4);
      h = math.max(h, lh + 2 + vh);
    }
    return h;
  }

  /// 两遍共用：c == null 只量高度。
  double _run(Canvas? c) {
    const x0 = pad + 14;
    const innerW = width - pad * 2 - 28;
    var y = 0.0;

    // 页眉
    const headH = 72.0;
    sections['header'] = const Rect.fromLTWH(0, 0, width, headH);
    _text(c, '待办 专注版 · 专注统计', pad, 16, 20, color: cs.onPrimary, w: FontWeight.w700);
    _text(c, '生成于 ${Ymd.fmt(d.generatedOn)}', pad, 44, 12, color: cs.onPrimary.withValues(alpha: 0.85));
    y = headH + 12;

    // 关键数字
    final sh = _card('summary', y, (top) {
      var yy = top;
      yy += _text(c, '累计专注', x0, yy, 14, w: FontWeight.w600) + 8;
      yy += _metrics(c, yy, [
        ('次数', '${d.all.count}'),
        ('时长', FocusCalc.fmtDuration(d.all.seconds)),
        ('日均时长', FocusCalc.fmtDuration(d.dailyAvgSeconds)),
        ('中断次数', '${d.all.interrupted}'),
      ]);
      yy += 14;
      yy += _text(c, '当日专注  ${Ymd.fmt(d.day)}', x0, yy, 14, w: FontWeight.w600) + 8;
      yy += _metrics(c, yy, [
        ('次数', '${d.dayStats.count}'),
        ('时长', FocusCalc.fmtDuration(d.dayStats.seconds)),
        ('中断次数', '${d.dayStats.interrupted}'),
      ]);
      return yy - top;
    });
    y += sh + 12;

    // 饼图
    const pieH = 220.0;
    final ph = _card('pie', y, (top) {
      var yy = top;
      yy += _text(c, '专注时长分布', x0, yy, 16, w: FontWeight.w700) + 2;
      yy += _text(c, '按${d.periodName} · ${d.periodRange}', x0, yy, 12, color: _muted) + 8;
      final area = Rect.fromLTWH(x0, yy, innerW, pieH);
      sections['pieChart'] = area;
      if (d.dist.isEmpty) {
        _text(c, '这段时间还没有专注记录', x0, yy + pieH / 2 - 10, 13, color: _faint, maxW: innerW, center: true);
      } else if (c != null) {
        c.save();
        c.translate(area.left, area.top);
        FocusPiePainter(d.dist, d.labelOf).paint(c, area.size);
        c.restore();
      }
      yy += pieH + 4;
      final cnt = d.dist.count > 0 ? ' · ${d.dist.count} 次' : '';
      yy += _text(c, '总计 ${FocusCalc.fmtDuration(d.dist.seconds)}$cnt', x0, yy, 14,
              w: FontWeight.w600, maxW: innerW, center: true) +
          8;
      for (final e in d.dist.slices) {
        final line = '${d.labelOf(e.category)}  ${FocusCalc.fmtDuration(e.seconds)}  ${(e.shareOf(d.dist.seconds) * 100).toStringAsFixed(1)}%';
        if (c != null) {
          c.drawCircle(Offset(x0 + 5, yy + 8), 5, Paint()..color = Color(FocusColors.of(e.category).argb));
        }
        yy += _text(c, line, x0 + 16, yy, 12, maxW: innerW - 16) + 4;
      }
      return yy - top;
    });
    y += ph + 12;

    // 柱图
    const barH = 130.0;
    final bh = _card('bar', y, (top) {
      var yy = top;
      yy += _text(c, '本月专注时段分布', x0, yy, 16, w: FontWeight.w700) + 2;
      final total = d.hours.fold<int>(0, (a, b) => a + b);
      final max = d.hours.fold<int>(0, math.max);
      final peak = max == 0 ? null : d.hours.indexOf(max);
      final sub = '${d.barYear}年${d.barMonth}月 · 按 0–23 时累计'
          '${total > 0 ? ' · 合计 ${FocusCalc.fmtDuration(total)}' : ''}'
          '${peak != null ? ' · 高峰 $peak时' : ''}';
      yy += _text(c, sub, x0, yy, 12, color: _muted, maxW: innerW) + 10;
      final area = Rect.fromLTWH(x0, yy, innerW, barH);
      sections['barChart'] = area;
      if (max == 0) {
        _text(c, '这个月还没有专注记录', x0, yy + barH / 2 - 10, 13, color: _faint, maxW: innerW, center: true);
      } else if (c != null) {
        final bw = innerW / 24;
        for (var i = 0; i < 24; i++) {
          final v = d.hours[i];
          final h = math.max(2.0, barH * v / max);
          final r = RRect.fromRectAndRadius(
              Rect.fromLTWH(area.left + bw * i + 1, area.bottom - h, bw - 2, h), const Radius.circular(2));
          c.drawRRect(r, Paint()..color = cs.primary.withValues(alpha: v == 0 ? 0.12 : 0.85));
        }
      }
      yy += barH + 4;
      // 刻度：0 / 6 / 12 / 18 / 23 时
      final bw = innerW / 24;
      var th = 0.0;
      for (final hr in const [0, 6, 12, 18, 23]) {
        final label = '$hr时';
        final tp = _tp(label, 10, color: _faint);
        final cx = x0 + bw * hr + bw / 2 - tp.width / 2;
        th = math.max(th, _text(c, label, cx.clamp(x0, x0 + innerW - tp.width), yy, 10, color: _faint, maxW: 40));
      }
      yy += th;
      return yy - top;
    });
    y += bh + 12;

    final fh = _text(c, '来自「待办」· 次数和时长记在开始那天；中断次数只算锁屏倒计时', pad, y, 10,
        color: _faint, maxW: width - pad * 2, center: true);
    y += fh + 16;

    return y;
  }
}

/// 饼图（屏幕上和导出图片共用，颜色与图例一致）。
class FocusPiePainter extends CustomPainter {
  final PeriodStats stats;
  final String Function(String?) labelOf;
  FocusPiePainter(this.stats, this.labelOf);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) * 0.32;
    var start = -math.pi / 2;
    final total = stats.seconds;
    if (total <= 0) return;
    for (final e in stats.slices) {
      final sweep = e.shareOf(total) * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = Color(FocusColors.of(e.category).argb);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, true, paint);
      // 标签放在弧中点外侧
      if (sweep > 0.12) {
        final mid = start + sweep / 2;
        final tp = TextPainter(
            text: TextSpan(
                text: '${FocusCalc.fmtDuration(e.seconds)}\n${labelOf(e.category)}',
                style: const TextStyle(color: Colors.black87, fontSize: 11, height: 1.2)),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center)
          ..layout();
        final pos = Offset(c.dx + math.cos(mid) * (r + 28) - tp.width / 2, c.dy + math.sin(mid) * (r + 28) - tp.height / 2);
        final line = Paint()
          ..color = Colors.black38
          ..strokeWidth = 1;
        canvas.drawLine(Offset(c.dx + math.cos(mid) * r, c.dy + math.sin(mid) * r),
            Offset(c.dx + math.cos(mid) * (r + 16), c.dy + math.sin(mid) * (r + 16)), line);
        tp.paint(canvas, pos);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant FocusPiePainter old) => old.stats != stats;
}

/// 把统计图片渲染成 PNG（默认 3 倍像素，宽 1080px）。
Future<Uint8List> renderStatsPng(StatsExportData data, {double pixelRatio = 3}) async {
  final painter = StatsExportPainter(data);
  final h = painter.layout();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.scale(pixelRatio);
  painter.paint(canvas);
  final pic = rec.endRecording();
  final img = await pic.toImage((StatsExportPainter.width * pixelRatio).round(), (h * pixelRatio).round());
  try {
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('PNG 编码失败');
    return bytes.buffer.asUint8List();
  } finally {
    img.dispose();
    pic.dispose();
  }
}

/// 分享图片存放目录（应用缓存目录下的 share/，FileProvider 只开放这一处）。测试可替换。
@visibleForTesting
Future<Directory> Function() statsShareDir = () async => Directory('${(await getTemporaryDirectory()).path}/share');

/// 生成统计图片并调起系统分享。返回写出的文件路径。
Future<String> shareStatsImage(StatsExportData data) async {
  final png = await renderStatsPng(data);
  final dir = await statsShareDir();
  if (!dir.existsSync()) dir.createSync(recursive: true);
  // 只保留最新一张，避免缓存越积越多
  for (final f in dir.listSync()) {
    if (f is File && f.path.endsWith('.png')) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }
  final d = data.generatedOn;
  final name = 'daiban-stats-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}-'
      '${DateTime.now().millisecondsSinceEpoch}.png';
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(png, flush: true);
  await ScreenPin.shareImage(file.path, title: '分享统计图片');
  return file.path;
}
