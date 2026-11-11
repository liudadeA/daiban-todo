import 'dart:io';

import 'package:daiban/data/store.dart';
import 'package:daiban/logic/dates.dart';
import 'package:daiban/logic/ics.dart';
import 'package:daiban/logic/plan_splitter.dart';
import 'package:daiban/logic/planner.dart';
import 'package:daiban/logic/todo_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime d(String s) => Ymd.parse(s)!;
String due(dynamic i) => Ymd.fmt(i.due!);

void main() {
  late Directory tmp;
  late DateTime clock;

  Future<TodoStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    final s = TodoStore(dir: tmp, prefs: prefs, now: () => clock);
    await s.load(); // 模拟 App 重启：从 todo.txt / done.txt 重新读取
    return s;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('daiban_reg');
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 11, 11, 9, 0);
  });
  tearDown(() async => tmp.delete(recursive: true));

  final perDay = File('test/fixtures/plan408_perday.txt').readAsStringSync();
  final icsText = File('test/fixtures/plan408.ics').readAsStringSync();

  group('回归：完成今日任务后后续任务必须提前（用户的真实计划数据）', () {
    test('一天一条的旧格式：完成今天唯一任务 → 明天提前到今天（经过 导入/落盘/重启/勾选）', () async {
      var s = await open();
      await s.checkDayChange();
      await s.applyImport(s.preview(perDay), replace: true);
      s = await open(); // 重启
      expect(Planner.todaySet(s.todo, s.today).length, 1);
      final msg = await s.complete(s.todo.first);
      expect(msg, contains('今日任务已完成，已提前下一批'));
      s = await open(); // 重启后日期仍是提前后的
      expect(due(s.todo.first), '2026-11-11');
      expect(Planner.todaySet(s.todo, s.today).length, 1);
      expect(s.todo.first.text, contains('5.1-5.3 二叉树'));
    });

    test('前一天装好并导入，第二天打开后完成 → 正常提前', () async {
      clock = DateTime(2026, 11, 10, 22, 0);
      var s = await open();
      await s.checkDayChange();
      await s.applyImport(s.preview(perDay), replace: true);
      clock = DateTime(2026, 11, 11, 8, 0);
      s = await open();
      expect(await s.checkDayChange(), isNull); // 昨天没有任务，不顺延
      expect(due(s.todo.first), '2026-11-11');
      expect(await s.complete(s.todo.first), isNotNull);
      expect(due(s.todo.first), '2026-11-11');
    });

    test('在“全部”页勾选、或设备日期早于计划日期（今日为空）时也会提前', () async {
      clock = DateTime(2026, 11, 10, 9, 0); // 设备日期比计划早一天
      final s = await open();
      await s.applyImport(s.preview(perDay), replace: true);
      expect(Planner.todaySet(s.todo, s.today), isEmpty);
      final msg = await s.complete(s.todo.first); // 勾掉 11-11 的任务
      expect(msg, contains('今日任务已完成，已提前下一批'));
      expect(due(s.todo.first), '2026-11-10'); // 11-12 的任务被提前到今天
    });

    test('重复“追加”导入同一份计划：自动跳过重复（否则每天多一份，今日永远清不空）', () async {
      final s = await open();
      await s.applyImport(s.preview(perDay), replace: true);
      final skipped = await s.applyImport(s.preview(perDay), replace: false);
      expect(skipped, 37);
      expect(s.todo.length, 37);
      expect(await s.complete(s.todo.first), isNotNull);
    });

    test('手动“提前下一批”：今日还没做完也能提前；没有后续任务时给出提示', () async {
      final s = await open();
      await s.applyImport(s.preview('A due:2026-11-11\nB due:2026-11-12\nC due:2026-11-13'), replace: true);
      expect(await s.pullNextBatch(), '已把 11月12日 的任务提前到今天');
      expect(s.todo.map(due).toList(), ['2026-11-11', '2026-11-11', '2026-11-12']);
      await s.undo();
      expect(s.todo.map(due).toList(), ['2026-11-11', '2026-11-12', '2026-11-13']);
      final s2 = await open();
      await s2.applyImport(s2.preview('只有今天 due:2026-11-11'), replace: true);
      expect(await s2.pullNextBatch(), '没有可提前的后续任务');
    });

    test('一天多项：今日全部勾完 → 第二天整批（多项）一起提前到今天', () async {
      var s = await open();
      await s.applyImport(s.preview(icsText), replace: true);
      final todayItems = Planner.todaySet(s.todo, s.today);
      expect(todayItems.length, 3);
      expect(await s.complete(todayItems[0]), isNull);
      expect(await s.complete(todayItems[1]), isNull);
      final msg = await s.complete(todayItems[2]);
      expect(msg, contains('今日任务已完成，已提前下一批'));
      s = await open();
      final now = Planner.todaySet(s.todo, s.today);
      expect(now.length, 6); // 11-12 的 6 项整批到了今天
      expect(now.every((e) => e.text.startsWith('数据结构')), true);
      expect(s.todo.where((e) => e.due == d('2026-11-12')).length, 4); // 原 11-13 的 4 项
      // 日历中 11-12 之后的间隔保持（原 11-14 → 11-13）
      expect(s.todo.any((e) => e.due == d('2026-11-13')), true);
    });
  });

  group('ICS 解析', () {
    test('行展开 / 转义 / DATE / 多日事件 / DTEND 不含', () {
      const ics = 'BEGIN:VCALENDAR\r\nX-WR-CALNAME:408 复习计划\r\n'
          'BEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20261217\r\nDTEND;VALUE=DATE:20261219\r\n'
          'SUMMARY:考前回\r\n 顾\r\nDESCRIPTION:第一行\\n第二\\, 行\\; 末\\\\尾\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';
      final cal = Ics.parse(ics);
      expect(cal.name, '408 复习计划');
      final e = cal.events.single;
      expect(e.summary, '考前回顾');
      expect(e.description, '第一行\n第二, 行; 末\\尾');
      expect(Ymd.fmt(e.start), '2026-12-17');
      expect(Ymd.fmt(e.end), '2026-12-18'); // 不含 12-19
    });
    test('DATE-TIME：本地时间、UTC(Z) 换算、结束于 00:00 视为不含', () {
      const ics = 'BEGIN:VCALENDAR\nBEGIN:VEVENT\nDTSTART:20261111T090000\nDTEND:20261111T100000\nSUMMARY:甲\nEND:VEVENT\n'
          'BEGIN:VEVENT\nDTSTART:20261111T170000Z\nDTEND:20261111T180000Z\nSUMMARY:乙\nEND:VEVENT\n'
          'BEGIN:VEVENT\nDTSTART:20261111T200000\nDTEND:20261113T000000\nSUMMARY:丙\nEND:VEVENT\nEND:VCALENDAR';
      final cal = Ics.parse(ics, localOffset: const Duration(hours: 9));
      expect(cal.events.map((e) => '${Ymd.fmt(e.start)}~${Ymd.fmt(e.end)}').toList(),
          ['2026-11-11~2026-11-11', '2026-11-12~2026-11-12', '2026-11-11~2026-11-12']);
    });
    test('没有 DTEND 视为单日；缺少 DTSTART 的事件被忽略', () {
      const ics = 'BEGIN:VCALENDAR\nBEGIN:VEVENT\nDTSTART;VALUE=DATE:20261111\nSUMMARY:x\nEND:VEVENT\n'
          'BEGIN:VEVENT\nSUMMARY:无日期\nEND:VEVENT\nEND:VCALENDAR';
      expect(Ics.parse(ics).events.length, 1);
    });
    test('用户的 408 日历：37 个事件，其中 12-17~12-18 跨两天，共 138 条任务', () {
      expect(Ics.looksLikeIcs(icsText), true);
      final cal = Ics.parse(icsText);
      expect(cal.events.length, 37);
      final lines = Ics.toTodoLines(icsText);
      expect(lines.length, 138);
      expect(lines.first, '数据结构 上午 3.4 数组和特殊矩阵压缩存储（p101-108） +408 +数据结构 due:2026-11-11 t:2026-11-11');
      expect(lines.where((l) => l.contains('考前回顾')).map((l) => RegExp(r'due:(\S+)').firstMatch(l)![1]).toSet(),
          {'2026-12-17', '2026-12-18'});
      // 每一行都能被 todo.txt 解析器识别且有 due 与 t
      final s = TodoStoreProbe.parse(lines);
      expect(s.length, 138);
      // 日期不降序
      final ds = s.map((e) => Ymd.fmt(e.due!)).toList();
      expect([...ds]..sort(), ds);
    });
    test('导出 .ics 再导入：任务一一对应，不会被再次拆分', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await open();
      await s.applyImport(s.preview('(A) 背单词，每天 30 个；含逗号 +考研 @家里 due:2026-11-12 t:2026-11-12\n无日期任务'),
          replace: true);
      final ics = s.exportIcs();
      expect(ics.contains('\r\n'), true);
      expect(RegExp('BEGIN:VEVENT').allMatches(ics).length, 1);
      for (final line in ics.split('\r\n')) {
        expect(line.codeUnits.length < 100 && _utf8Len(line) <= 75, true, reason: line);
      }
      final s2 = await open();
      final pv = s2.preview(ics);
      expect(pv.todo.length, 1);
      expect(pv.todo.single.priority, 'A');
      expect(pv.todo.single.text, '背单词，每天 30 个；含逗号');
      expect(pv.todo.single.projects, ['考研']);
      expect(due(pv.todo.single), '2026-11-12');
    });
  });

  group('任务拆分 PlanSplitter', () {
    test('上午/下午 + 页码保持在各自条目上', () {
      final r = PlanSplitter.split('数据结构 3.4 数组 + 第4章 串',
          '上午 3.4 数组和特殊矩阵压缩存储（p101-108）；下午 第4章 串，重点 KMP、手算 next/nextval（p109-124）。');
      expect(r, [
        '数据结构 上午 3.4 数组和特殊矩阵压缩存储（p101-108）',
        '数据结构 下午 第4章 串 重点 KMP（p109-124）',
        '数据结构 下午 手算 next/nextval（p109-124）',
      ]);
    });
    test('括号内、数字间的顿号不切；动词开头的句子不按顿号切', () {
      expect(PlanSplitter.split('组成原理 第1章 概论', '性能指标（CPI、MIPS 计算）；进制转换、原反补移码。'),
          ['组成原理 性能指标（CPI、MIPS 计算）', '组成原理 进制转换', '组成原理 原反补移码']);
      expect(PlanSplitter.split('数据结构 错题', '重做第7、8章错题，整理成一页纸。'),
          ['数据结构 重做第7、8章错题', '数据结构 整理成一页纸']);
      expect(PlanSplitter.split('综合练习 订正 + 补漏', '只看错题本、公式页、复杂度表和各科总结。').length, 1);
    });
    test('【重点】标记跟随所在段落；SUMMARY 的标题含编号时保留', () {
      final r = PlanSplitter.split('数据结构 7.1 查找', 'ASL 计算、折半查找（p264-286）。【查找重点】');
      expect(r, ['数据结构 ASL 计算（p264-286）【查找重点】', '数据结构 折半查找（p264-286）【查找重点】']);
      expect(PlanSplitter.split('综合练习 408 真题套卷 1', '限时 3 小时做一整套 408 真题。'),
          ['综合练习 408 真题套卷 1：限时 3 小时做一整套 408 真题']);
    });
    test('没有描述时直接用标题；空输入不报错', () {
      expect(PlanSplitter.split('背单词', ''), ['背单词']);
      expect(PlanSplitter.split('', ''), isEmpty);
    });
  });
}

int _utf8Len(String s) => s.runes.fold(0, (n, r) => n + (r < 0x80 ? 1 : r < 0x800 ? 2 : r < 0x10000 ? 3 : 4));

class TodoStoreProbe {
  static List<TodoItem> parse(List<String> lines) {
    final out = <TodoItem>[];
    for (final l in lines) {
      final i = TodoItem.parse(l);
      if (i != null) out.add(i);
    }
    return out;
  }
}
