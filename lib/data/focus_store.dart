import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/focus.dart';

/// 专注记录：focus.json 持久化已结束的记录；进行中的一次写在 SharedPreferences，杀进程后仍能接着计。
class FocusStore extends ChangeNotifier {
  static const kActive = 'focusActive';

  /// 超过这么久还没结束的进行中记录，打开时自动视为中断并落盘。
  static const maxOrphan = Duration(hours: 12);

  final Directory dir;
  final SharedPreferences prefs;
  final DateTime Function() _now;

  List<FocusSession> sessions = [];

  String? runningId;
  String? runningCategory;
  DateTime? runningStart;

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
        }
      } catch (_) {}
    }
    // 残留过久的计时：自动中断并记录
    if (isRunning && now.difference(runningStart!) > maxOrphan) {
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
          }));
    }
  }

  /// 开始某个类别的正向计时。已有进行中的计时则返回 false。
  Future<bool> start(String? category) async {
    if (isRunning) return false;
    runningId = now.microsecondsSinceEpoch.toString();
    runningCategory = category;
    runningStart = now;
    await _saveActive();
    notifyListeners();
    return true;
  }

  /// 结束当前计时并写入记录。[interrupted] 为 true 表示退出 / 解除屏幕固定导致的中断。
  /// 不足 1 秒的不记，只清除进行中状态。返回写入的记录（被丢弃则为 null）。
  Future<FocusSession?> stop({required bool interrupted}) async {
    if (!isRunning) return null;
    final start = runningStart!;
    final cat = runningCategory;
    final id = runningId ?? start.microsecondsSinceEpoch.toString();
    runningId = null;
    runningCategory = null;
    runningStart = null;
    await _saveActive();
    final end = now;
    final session = FocusSession(id: id, category: cat, start: start, end: end, interrupted: interrupted);
    if (session.seconds < 1) {
      notifyListeners();
      return null;
    }
    sessions = [...sessions, session];
    _saveList();
    notifyListeners();
    return session;
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
