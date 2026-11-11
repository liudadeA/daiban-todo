import 'dart:io';

import 'package:daiban/data/store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 校验仓库 plans/ 下的计划文件能被导入解析器正确读取。
void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('daiban_plans');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async => tmp.delete(recursive: true));

  Future<TodoStore> open() async {
    final s = TodoStore(dir: tmp, prefs: await SharedPreferences.getInstance(), now: () => DateTime(2026, 11, 11, 9));
    await s.load();
    return s;
  }

  test('数据结构细化计划：每行都能解析，类别/日期/页码正确', () async {
    final text = File('plans/数据结构_串起_细化到页.txt').readAsStringSync();
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final s = await open();
    final p = s.preview(text);
    expect(p.todo.length, lines.length);
    expect(p.done, isEmpty);
    final lo = Ymd.parse('2026-11-11')!, hi = Ymd.parse('2026-11-21')!;
    for (final it in p.todo) {
      expect(it.category, '408'); // 首个 +标签
      expect(it.projects, containsAll(['408', '数据结构']));
      expect(it.due, isNotNull);
      expect(it.start, it.due);
      expect(it.due!.isBefore(lo) || it.due!.isAfter(hi), isFalse);
      expect(it.text, matches(RegExp(r'p\d+(-\d+)?')));
      expect(it.text, isNot(contains('（续）')));
      expect(it.toLine(), it.toLine().trim());
    }
    final days = p.todo.map((e) => e.due).toSet();
    expect(days.length, 11);
  });

  test('完整计划 v2：能导入，数据结构外的科目条目与原计划一致', () async {
    final v2 = File('plans/408复习计划_v2.txt').readAsStringSync();
    final old = File('plans/408复习计划.txt').readAsStringSync();
    final s = await open();
    final p2 = s.preview(v2), p1 = s.preview(old);
    final other2 = p2.todo.where((e) => !e.projects.contains('数据结构')).map((e) => e.toLine()).toList()..sort();
    final other1 = p1.todo.where((e) => !e.projects.contains('数据结构')).map((e) => e.toLine()).toList()..sort();
    expect(other2, other1);
    await s.applyImport(p2, replace: true);
    expect(s.todo.length, p2.todo.length);
    // 重新读取后仍然一致
    final s2 = await open();
    expect(s2.todo.length, p2.todo.length);
  });
}
