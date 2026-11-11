/// 把“一天一条”的日历事件（SUMMARY + DESCRIPTION）拆成“一项一条”的学习任务。
/// 纯 Dart，供 ICS 导入、命令行转换脚本和单元测试共用。
///
/// 规则概要：
///  1. SUMMARY 的第一个词当作科目（如“数据结构”“组成原理”“综合练习”），所有任务以科目开头。
///  2. SUMMARY 里的“ + ”分隔多个章节标签；DESCRIPTION 按「；」「;」「。」「上午/下午」切成段，
///     再按「，」「、」切成条目（括号内、数字之间的顿号不切，「重点…」并入前一项）。
///  3. 页码（pXX-YY）和【…重点】标记挂在它所在那一段的每个条目上。
///  4. 如果 SUMMARY 不是章节标签（如“408 真题套卷 1”“模拟卷 2 + 订正”），其名称保留在任务里。
class PlanSplitter {
  static final _pageRe = RegExp(r'[（(]\s*(p[\d]+(?:\s*[-–~]\s*[\d]+)?)\s*[）)]');
  static final _chapterRe = RegExp(r'^(第\s*\d+\s*章|\d{1,2}(\.\d+)*(\s*-\s*\d{1,2}(\.\d+)*)?(\s|$))');
  static const _verbStarts = [
    '做', '重做', '默写', '订正', '限时', '只看', '重看', '整理', '把', '背', '看', '复习', '完成', '刷', '练'
  ];

  /// 返回任务正文列表（不含 +项目 / due / t）。
  static List<String> split(String summary, String description) {
    final sum = _clean(summary);
    final desc = _clean(description);
    final tokens = sum.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (tokens.isEmpty) return [];
    final subject = tokens.first;
    final rest = tokens.skip(1).join(' ');
    final parts = rest.isEmpty
        ? <String>[]
        : rest.split(RegExp(r'\s+\+\s+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final hasChapter = parts.any((p) => _chapterRe.hasMatch(p));

    final items = _splitDescription(desc); // 每项: [label, text]
    List<String> out;
    if (items.isEmpty) {
      out = [rest.isEmpty ? subject : '$subject $rest'];
    } else {
      out = [for (final it in items) _compose(subject, it[0], it[1])];
      if (!hasChapter && parts.isNotEmpty) {
        // 标题本身有辨识度（如“408 真题套卷 1”），保留到任务里
        if (items.length == 1) {
          out = ['$subject ${parts.join(' + ')}：${_compose('', items[0][0], items[0][1]).trim()}'];
        } else {
          final withDigit = parts.where((p) => RegExp(r'\d').hasMatch(p)).toList();
          if (withDigit.isNotEmpty) {
            out[0] = '$subject ${withDigit.join(' + ')}：${_compose('', items[0][0], items[0][1]).trim()}';
          }
        }
      }
    }
    return out;
  }

  static String _compose(String subject, String label, String text) =>
      [subject, label, text].where((e) => e.isNotEmpty).join(' ');

  static String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// 返回 [标签(上午/下午/空), 条目文本(含页码/重点标记)] 列表
  static List<List<String>> _splitDescription(String desc) {
    if (desc.isEmpty) return [];
    // 1) 先按 ； ; 切段
    final segs = _splitTopLevel(desc, ['；', ';']);
    // 2) 每段再按 。 切成句子，【…】并入前一句
    final sentences = <_Sentence>[];
    for (final seg in segs) {
      for (final raw in _splitTopLevel(seg, ['。'])) {
        final s = raw.trim();
        if (s.isEmpty) continue;
        if (s.startsWith('【') && sentences.isNotEmpty) {
          sentences.last.tags.add(s);
        } else {
          sentences.add(_Sentence(s));
        }
      }
    }
    final result = <List<String>>[];
    for (final st in sentences) {
      var text = st.text;
      var label = '';
      final m = RegExp(r'^(上午|下午|晚上)[:：\s]*').firstMatch(text);
      if (m != null) {
        label = m[1]!;
        text = text.substring(m.end);
      }
      // 提取行内【…】标记
      final tags = [...st.tags];
      text = text.replaceAllMapped(RegExp(r'【[^】]*】'), (mm) {
        tags.add(mm[0]!);
        return '';
      });
      // 提取页码
      final pages = <String>[];
      text = text.replaceAllMapped(_pageRe, (mm) {
        pages.add(mm[1]!.replaceAll(RegExp(r'\s'), ''));
        return '';
      }).trim();
      final suffix = [
        if (pages.isNotEmpty) '（${pages.join('、')}）',
        ...tags,
      ].join('');
      for (final piece in _splitItems(text)) {
        result.add([label, piece + suffix]);
      }
    }
    return result;
  }

  /// 在括号外按分隔符切分。
  static List<String> _splitTopLevel(String s, List<String> seps) {
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    final chars = s.runes.map(String.fromCharCode).toList();
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      if ('（([【'.contains(c)) depth++;
      if ('）)]】'.contains(c)) depth = depth > 0 ? depth - 1 : 0;
      if (depth == 0 && seps.contains(c)) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return out.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static bool _startsWithVerb(String s) => _verbStarts.any(s.startsWith);

  /// 一句话 → 若干条目：按 ， 切；不以动词开头的再按 、 切。
  static List<String> _splitItems(String sentence) {
    final commaParts = _splitTopLevel(sentence, ['，', ',']);
    // “重点…”并入前一项
    final merged = <String>[];
    for (final p in commaParts) {
      if (merged.isNotEmpty && RegExp(r'^(重点|其中|即|尤其|特别)').hasMatch(p)) {
        merged[merged.length - 1] = '${merged.last} $p';
      } else {
        merged.add(p);
      }
    }
    final out = <String>[];
    for (final p in merged) {
      if (_startsWithVerb(p)) {
        out.add(p);
        continue;
      }
      final pieces = _splitEnumeration(p);
      out.addAll(pieces);
    }
    return out.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  /// 按 、 切，但数字之间的顿号（第7、8章）不切；过短的碎片并入前一项。
  static List<String> _splitEnumeration(String s) {
    final chars = s.runes.map(String.fromCharCode).toList();
    final pieces = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      if ('（([【'.contains(c)) depth++;
      if ('）)]】'.contains(c)) depth = depth > 0 ? depth - 1 : 0;
      if (c == '、' && depth == 0) {
        final prev = i > 0 ? chars[i - 1] : '';
        final next = i + 1 < chars.length ? chars[i + 1] : '';
        if (RegExp(r'\d').hasMatch(prev) && RegExp(r'\d').hasMatch(next)) {
          buf.write(c);
          continue;
        }
        pieces.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    pieces.add(buf.toString());
    final out = <String>[];
    for (final p in pieces.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      if (out.isNotEmpty && p.runes.length < 2) {
        out[out.length - 1] = '${out.last}、$p';
      } else {
        out.add(p);
      }
    }
    return out;
  }
}

class _Sentence {
  final String text;
  final List<String> tags = [];
  _Sentence(this.text);
}
