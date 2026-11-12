import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/focus_store.dart';
import '../data/store.dart';
import '../logic/dates.dart';
import '../logic/focus.dart';
import 'stats_export.dart';

/// 统计数据：累计 / 当日 / 时长分布（日周月自定义）/ 本月时段分布。
class StatsPage extends StatefulWidget {
  final TodoStore store;
  final FocusStore focus;
  /// 作为底栏标签页嵌入时只返回内容，不带自己的 Scaffold / AppBar
  final bool embedded;
  const StatsPage({super.key, required this.store, required this.focus, this.embedded = false});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

/// 最近一次分享的 Future（测试用，等待图片生成与分享调用完成）。
@visibleForTesting
Future<String>? debugLastStatsShare;

enum _RangeKind { day, week, month, custom }

class _StatsPageState extends State<StatsPage> {
  TodoStore get store => widget.store;
  FocusStore get focus => widget.focus;

  late DateTime _day; // 当日专注、以及「日」分布的基准
  late DateTime _month; // 本月时段分布
  _RangeKind _kind = _RangeKind.day;
  DateTime? _customFrom, _customTo;

  @override
  void initState() {
    super.initState();
    final t = store.today;
    _day = t;
    _month = t;
  }

  String _label(String? c) => store.categoryLabel(c);

  PeriodStats get _dist {
    switch (_kind) {
      case _RangeKind.day:
        return FocusCalc.forDay(focus.sessions, _day);
      case _RangeKind.week:
        return FocusCalc.forWeek(focus.sessions, _day);
      case _RangeKind.month:
        return FocusCalc.forMonth(focus.sessions, _day);
      case _RangeKind.custom:
        if (_customFrom == null || _customTo == null) return PeriodStats.empty;
        return FocusCalc.forRange(focus.sessions, _customFrom!, _customTo!);
    }
  }

  String get _distTitle {
    switch (_kind) {
      case _RangeKind.day:
        return Ymd.fmt(_day);
      case _RangeKind.week:
        final r = FocusCalc.weekRange(_day);
        return '${Ymd.fmt(r.$1)} ~ ${Ymd.fmt(r.$2)}';
      case _RangeKind.month:
        return '${_day.year}年${_day.month}月';
      case _RangeKind.custom:
        if (_customFrom == null || _customTo == null) return '请选择区间';
        return '${Ymd.fmt(_customFrom!)} ~ ${Ymd.fmt(_customTo!)}';
    }
  }

  void _shiftDist(int step) {
    setState(() {
      switch (_kind) {
        case _RangeKind.day:
          _day = Ymd.add(_day, step);
        case _RangeKind.week:
          _day = Ymd.add(_day, 7 * step);
        case _RangeKind.month:
          _day = DateTime.utc(_day.year, _day.month + step, 1);
        case _RangeKind.custom:
          if (_customFrom != null && _customTo != null) {
            final n = Ymd.diff(_customTo!, _customFrom!) + 1;
            _customFrom = Ymd.add(_customFrom!, n * step);
            _customTo = Ymd.add(_customTo!, n * step);
          }
      }
    });
  }

  Future<void> _pickCustom() async {
    final now = store.today;
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _customFrom != null && _customTo != null
          ? DateTimeRange(start: _customFrom!, end: _customTo!)
          : DateTimeRange(start: _day, end: _day),
      helpText: '选择统计区间',
      locale: const Locale('zh', 'CN'),
    );
    if (r == null) return;
    setState(() {
      _kind = _RangeKind.custom;
      _customFrom = Ymd.fromDateTime(r.start);
      _customTo = Ymd.fromDateTime(r.end);
    });
  }

  bool _sharing = false;

  /// 导出用数据：饼图跟随当前选中的周期（日/周/月/自定义），柱图用当前显示的月份。
  StatsExportData exportData() {
    final name = switch (_kind) {
      _RangeKind.day => '日',
      _RangeKind.week => '周',
      _RangeKind.month => '月',
      _RangeKind.custom => '自定义',
    };
    return StatsExportData(
      generatedOn: store.today,
      all: FocusCalc.all(focus.sessions),
      dailyAvgSeconds: FocusCalc.averageDailySeconds(focus.sessions),
      day: _day,
      dayStats: FocusCalc.forDay(focus.sessions, _day),
      periodName: name,
      periodRange: _distTitle,
      dist: _dist,
      barYear: _month.year,
      barMonth: _month.month,
      hours: FocusCalc.hourDistribution(focus.sessions, _month.year, _month.month),
      labelOf: _label,
    );
  }

  /// 分享：生成一张同时包含饼图和柱图的 PNG，调起系统分享面板。
  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final f = shareStatsImage(exportData());
    debugLastStatsShare = f;
    try {
      await f;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('生成分享图片失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _openRecords() {
    final from = switch (_kind) {
      _RangeKind.day => _day,
      _RangeKind.week => FocusCalc.weekRange(_day).$1,
      _RangeKind.month => FocusCalc.monthRange(_day).$1,
      _RangeKind.custom => _customFrom ?? _day,
    };
    final to = switch (_kind) {
      _RangeKind.day => _day,
      _RangeKind.week => FocusCalc.weekRange(_day).$2,
      _RangeKind.month => FocusCalc.monthRange(_day).$2,
      _RangeKind.custom => _customTo ?? _day,
    };
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => FocusRecordsPage(store: store, focus: focus, from: from, to: to)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, focus]),
      builder: (context, _) {
        final all = FocusCalc.all(focus.sessions);
        final daily = FocusCalc.averageDailySeconds(focus.sessions);
        final today = FocusCalc.forDay(focus.sessions, _day);
        final dist = _dist;
        final hours = FocusCalc.hourDistribution(focus.sessions, _month.year, _month.month);
        final body = SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), child: Column(children: [
            _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('累计专注', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 16),
                Row(children: [
                  _metric('次数', '${all.count}', key: const Key('stats_all_count')),
                  _metric('时长', _splitDur(all.seconds), key: const Key('stats_all_dur')),
                  _metric('日均时长', _splitDur(daily), key: const Key('stats_all_avg')),
                  _metric('中断次数', '${all.interrupted}', key: const Key('stats_all_interrupted')),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text('当日专注  ${Ymd.fmt(_day)}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
                  _arrows(onPrev: () => setState(() => _day = Ymd.add(_day, -1)), onNext: () => setState(() => _day = Ymd.add(_day, 1))),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  _metric('次数', '${today.count}', key: const Key('stats_day_count')),
                  _metric('时长', _splitDur(today.seconds), key: const Key('stats_day_dur')),
                  _metric('中断次数', '${today.interrupted}', key: const Key('stats_day_interrupted')),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(child: Text('专注时长分布', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
                  TextButton(key: const Key('stats_share'), onPressed: _sharing ? null : _share, child: Text(_sharing ? '生成中…' : '分享')),
                  _arrows(onPrev: () => _shiftDist(-1), onNext: () => _shiftDist(1)),
                ]),
                Text(_distTitle, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                SegmentedButton<_RangeKind>(
                  segments: const [
                    ButtonSegment(value: _RangeKind.day, label: Text('日')),
                    ButtonSegment(value: _RangeKind.week, label: Text('周')),
                    ButtonSegment(value: _RangeKind.month, label: Text('月')),
                    ButtonSegment(value: _RangeKind.custom, label: Text('自定义')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) {
                    final k = s.first;
                    if (k == _RangeKind.custom) {
                      _pickCustom();
                    } else {
                      setState(() => _kind = k);
                    }
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 220,
                  child: dist.isEmpty
                      ? const Center(child: Text('这段时间还没有专注记录', style: TextStyle(color: Colors.black45)))
                      : CustomPaint(
                          key: const Key('stats_pie'),
                          painter: FocusPiePainter(dist, _label),
                          child: const SizedBox.expand(),
                        ),
                ),
                const SizedBox(height: 8),
                Center(
                    child: Text('总计 ${FocusCalc.fmtDuration(dist.seconds)}',
                        key: const Key('stats_pie_total'),
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    key: const Key('stats_records'),
                    onPressed: _openRecords,
                    child: const Text('查看专注记录'),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 16, runSpacing: 8, children: [
                  for (final e in dist.slices)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: Color(FocusColors.of(e.category).argb), shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(
                          '${_label(e.category)}  ${FocusCalc.fmtDuration(e.seconds)}  ${(e.shareOf(dist.seconds) * 100).toStringAsFixed(1)}%'),
                    ]),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text('本月专注时段分布  ${_month.year}年${_month.month}月',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
                  _arrows(
                    onPrev: () => setState(() => _month = DateTime.utc(_month.year, _month.month - 1, 1)),
                    onNext: () => setState(() => _month = DateTime.utc(_month.year, _month.month + 1, 1)),
                  ),
                ]),
                const SizedBox(height: 12),
                SizedBox(height: 160, child: _HourBars(hours: hours)),
              ]),
            ),
          ]));
        if (widget.embedded) return body;
        return Scaffold(appBar: AppBar(title: const Text('统计数据')), body: body);
      },
    );
  }

  Widget _card({required Widget child}) => Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );

  Widget _metric(String label, String value, {Key? key}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 4),
          Text(value, key: key, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.2)),
        ]),
      );

  Widget _arrows({required VoidCallback onPrev, required VoidCallback onNext}) => Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev, visualDensity: VisualDensity.compact),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext, visualDensity: VisualDensity.compact),
      ]);

  /// 大数字：把「212小时58分钟」拆成两行更接近参考图；短的保持一行。
  String _splitDur(int seconds) => FocusCalc.fmtDuration(seconds);
}

/// 查看某区间内的专注记录列表。
class FocusRecordsPage extends StatelessWidget {
  final TodoStore store;
  final FocusStore focus;
  final DateTime from, to;
  const FocusRecordsPage({super.key, required this.store, required this.focus, required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final a = Ymd.fromDateTime(from), b = Ymd.fromDateTime(to);
    final list = focus.sessions.where((s) {
      final d = s.startDay;
      return !d.isBefore(a) && !d.isAfter(b);
    }).toList()
      ..sort((x, y) => y.start.compareTo(x.start));
    String hm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: Text(a == b ? '专注记录  ${Ymd.fmt(a)}' : '专注记录  ${Ymd.fmt(a)} ~ ${Ymd.fmt(b)}')),
      body: list.isEmpty
          ? const Center(child: Text('这段时间还没有专注记录', style: TextStyle(color: Colors.black45)))
          : ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = list[i];
                final sameDay = Ymd.fromDateTime(s.start) == Ymd.fromDateTime(s.end);
                final span = sameDay
                    ? '${hm(s.start)}–${hm(s.end)}'
                    : '${Ymd.fmt(s.start)} ${hm(s.start)}–${Ymd.fmt(s.end)} ${hm(s.end)}';
                return ListTile(
                  leading: Icon(s.interrupted ? Icons.pause_circle_outline : Icons.timer_outlined,
                      color: Color(FocusColors.of(s.category).argb)),
                  title: Text(store.categoryLabel(s.category)),
                  subtitle: Text('$span${s.isCountdown ? '  ·  锁屏' : ''}${s.interrupted ? '  ·  已中断' : ''}'),
                  trailing: Text(FocusCalc.fmtDuration(s.seconds)),
                );
              },
            ),
    );
  }
}

class _HourBars extends StatelessWidget {
  final List<int> hours;
  const _HourBars({required this.hours});

  @override
  Widget build(BuildContext context) {
    final max = hours.fold<int>(0, math.max);
    if (max == 0) {
      return const Center(child: Text('这个月还没有专注记录', style: TextStyle(color: Colors.black45)));
    }
    final color = Theme.of(context).colorScheme.primary;
    return Column(children: [
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 24; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: FractionallySizedBox(
                  heightFactor: max == 0 ? 0 : (hours[i] / max).clamp(0, 1),
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: color.withValues(alpha: hours[i] == 0 ? 0.12 : 0.85), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('0时', style: TextStyle(fontSize: 11, color: Colors.black45)),
        Text('6时', style: TextStyle(fontSize: 11, color: Colors.black45)),
        Text('12时', style: TextStyle(fontSize: 11, color: Colors.black45)),
        Text('18时', style: TextStyle(fontSize: 11, color: Colors.black45)),
        Text('23时', style: TextStyle(fontSize: 11, color: Colors.black45)),
      ]),
    ]);
  }
}
