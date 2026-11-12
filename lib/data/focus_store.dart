import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/focus.dart';

/// 专注记录：focus.json 持久化已结束的记录；进行中的一次写在 SharedPreferences，杀进程后仍能接着计。
class FocusStore extends ChangeNotifier {
  static const kActive = 'focusActive';
  static const kLockMinutes = 'lockMinutes';
  static const kLockCategory = 'lockCategory';

  /// 锁屏倒计时被系统手势提前解除时，至少计时这么久才记入统计。
  static const minCountdownRecord = Duration(seconds: 10);

  /// 超过这么久还没结束的进行中记录，打开时自动视为中断并落盘。
  static const maxOrphan = Duration(hours: 12);

  final Directory dir;
  final SharedPreferences prefs;
  final DateTime Function() _now;

  List<FocusSession> sessions = [];

  String? runningId;
  String? runningCategory;
  DateTime? runningStart;

  /// 锁屏倒计时：计划结束的时刻（正向计时为 null）
  DateTime? runningTarget;

  /// 打开时自动处理的结果（例如进程被杀期间倒计时已到点），界面取走后清空。
  String? pendingNotice;

  bool get isCountdown => runningTarget != null;

  int get plannedSeconds =>
      runningTarget == null || runningStart == null ? 0 : runningTarget!.difference(runningStart!).inSeconds;

  int get remainingSeconds {
    if (runningTarget == null) return 0;
    final ms = runningTarget!.difference(now).inMilliseconds;
    return ms <= 0 ? 0 : (ms + 999) ~/ 1000;
  }

  /// 上次锁屏用的时长（分钟）与类别
  int get lastLockMinutes => prefs.getInt(kLockMinutes) ?? 25;
  String? get lastLockCategory {
    final v = prefs.getString(kLockCategory);
    return v == null || v.isEmpty ? null : v;
  }

  bool get hasLastLockCategory => prefs.containsKey(kLockCategory);

  FocusStore({required this.dir, required this.prefs, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  DateTime get now => _now();

  File get file => File('${dir.path}/focus.json');

  bool get isRunning => runningStart != null;

  int get elapsedSeconds {
    if (runningStart == null) return 0;
    final n = now.difference(runningStart!).inSeconds;
    return n < 0 ? 0 : n;
  }

  Future<void> load() async {
    sessions = [];
    runningId = null;
    runningCategory = null;
    runningStart = null;
    runningTarget = null;
    if (await file.exists()) {
      try {
        final raw = jsonDecode(utf8.decode(await file.readAsBytes(), allowMalformed: true));
        final list = raw is Map ? raw['sessions'] : raw;
        if (list is List) {
          for (final e in list) {
            if (e is Map<String, dynamic>) {
              final s = FocusSession.fromJson(e);
              if (s != null) sessions.add(s);
            } else if (e is Map) {
              final s = FocusSession.fromJson(Map<String, dynamic>.from(e));
              if (s != null) sessions.add(s);
            }
          }
        }
      } catch (_) {}
    }
    final a = prefs.getString(kActive);
    if (a != null && a.isNotEmpty) {
      try {
        final m = jsonDecode(a) as Map<String, dynamic>;
        final startMs = m['start'];
        if (startMs is int) {
          runningId = m['id']?.toString();
          runningCategory = m['category'] as String?;
          runningStart = DateTime.fromMillisecondsSinceEpoch(startMs);
          final t = m['target'];
          if (t is int) runningTarget = DateTime.fromMillisecondsSinceEpoch(t);
        }
      } catch (_) {}
    }
    // 锁屏倒计时在关闭期间已到点：按完成记录（时长 = 计划时长）
    if (isCountdown && !now.isBefore(runningTarget!)) {
      final cat = runningCategory;
      final rec = await completeCountdown(at: runningTarget);
      if (rec != null) {
        pendingNotice = '「${cat ?? '未分类'}」的锁屏倒计时已结束并记录（${FocusCalc.fmtDuration(rec.seconds)}）';
      }
      return;
    }
    // 残留过久的正向计时：自动中断并记录
    if (isRunning && !isCountdown && now.difference(runningStart!) > maxOrphan) {
      await stop(interrupted: true);
      return;
    }
    notifyListeners();
  }

  void _saveList() {
    dir.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode({'sessions': sessions.map((e) => e.toJson()).toList()}), encoding: utf8);
  }

  Future<void> _saveActive() async {
    if (!isRunning) {
      await prefs.remove(kActive);
    } else {
      await prefs.setString(
          kActive,
          jsonEncode({
            'id': runningId,
            'category': runningCategory,
            'start': runningStart!.millisecondsSinceEpoch,
            if (runningTarget != null) 'target': runningTarget!.millisecondsSinceEpoch,
          }));
    }
  }

  /// 开始某个类别的正向计时。已有进行中的计时则返回 false。
  Future<bool> start(String? category) async {
    if (isRunning) return false;
    runningId = now.microsecondsSinceEpoch.toString();
    runningCategory = category;
    runningStart = now;
    runningTarget = null;
    await _saveActive();
    notifyListeners();
    return true;
  }

  /// 开始锁屏倒计时。已有进行中的计时则返回 false。记住本次的时长与类别。
  Future<bool> startCountdown(String? category, Duration duration) async {
    if (isRunning || duration.inSeconds <= 0) return false;
    runningId = now.microsecondsSinceEpoch.toString();
    runningCategory = category;
    runningStart = now;
    runningTarget = now.add(duration);
    await prefs.setInt(kLockMinutes, duration.inMinutes);
    await prefs.setString(kLockCategory, category ?? '');
    await _saveActive();
    notifyListeners();
    return true;
  }

  /// 倒计时到点：记为完成（非中断）。时长取计划时长；实际超出时取实际时长。
  /// [at] 指定结束时刻（进程被杀后补记用计划结束时刻）。
  Future<FocusSession?> completeCountdown({DateTime? at}) async {
    if (!isCountdown) return null;
    final target = runningTarget!;
    var end = at ?? now;
    if (end.isBefore(target)) end = target;
    return _finish(end: end, interrupted: false, minSeconds: 1);
  }

  /// 倒计时被系统手势提前解除：不足 10 秒不记，否则记为中断。
  Future<FocusSession?> interruptCountdown() async {
    if (!isCountdown) return null;
    return _finish(end: now, interrupted: true, minSeconds: minCountdownRecord.inSeconds);
  }

  Future<FocusSession?> _finish({required DateTime end, required bool interrupted, required int minSeconds}) async {
    final start = runningStart!;
    final cat = runningCategory;
    final kind = isCountdown ? FocusSession.countdown : FocusSession.forward;
    final id = runningId ?? start.microsecondsSinceEpoch.toString();
    runningId = null;
    runningCategory = null;
    runningStart = null;
    runningTarget = null;
    await _saveActive();
    final session = FocusSession(id: id, category: cat, start: start, end: end, interrupted: interrupted, kind: kind);
    if (session.seconds < minSeconds) {
      notifyListeners();
      return null;
    }
    sessions = [...sessions, session];
    _saveList();
    notifyListeners();
    return session;
  }

  /// 结束当前计时并写入记录。[interrupted] 为 true 表示退出 / 解除屏幕固定导致的中断。
  /// 不足 1 秒的不记，只清除进行中状态。返回写入的记录（被丢弃则为 null）。
  Future<FocusSession?> stop({required bool interrupted}) async {
    if (!isRunning) return null;
    if (isCountdown) return interrupted ? interruptCountdown() : completeCountdown();
    return _finish(end: now, interrupted: interrupted, minSeconds: 1);
  }

  /// 测试或导入时直接追加一条已结束的记录。
  Future<void> add(FocusSession s) async {
    sessions = [...sessions, s];
    _saveList();
    notifyListeners();
  }

  Future<void> addAll(Iterable<FocusSession> list) async {
    sessions = [...sessions, ...list];
    _saveList();
    notifyListeners();
  }
}
