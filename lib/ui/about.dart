import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const repoUrl = 'https://github.com/liudadeA/daiban-todo';

/// 示例任务行（可复制）。
const exampleLine = '数据结构 4.2 模式匹配：简单匹配+KMP p111-119 +408 +数据结构 due:2026-11-11 t:2026-11-11';

const importFormatText = '''每行一个任务，格式兼容 todo.txt / topydo；也可以直接导入 .ics 日历。

示例（可点“复制”或长按选择文字）：''';

const importFormatExplain = '''各部分含义：
• 数据结构 4.2 模式匹配：简单匹配+KMP p111-119 —— 任务描述（想写什么都行，页码等也写在这里）
• +408 +数据结构 —— 项目标签；第一个 +标签 就是这条任务的“类别”（这里是 408），提前 / 顺延都按类别分别计算；没有 +标签 的归入“未分类”
• due:2026-11-11 —— 截止日期（YYYY-MM-DD），也支持 due:明天、due:3d 等相对日期
• t:2026-11-11 —— 开始日期；没到这天不会出现在“今日”里
• (A) —— 可选的优先级，写在行首，例如：(A) 背单词 +英语 due:2026-11-12
• x 2026-11-11 … —— 以 x 加完成日期开头，表示已完成
• @情境 —— 可选的情境标签
• .ics 日历文件也可以导入：每天的事件会自动拆成“一项一条”的任务，导出时也能生成 .ics''';

const introText = '''待办 基础版 是一款兼容 todo.txt 格式的安卓待办清单：按类别自动顺延未完成的任务、做完后自动提前后续任务。

本作是为了借助 AI 更高效地做计划：把学习资料、目录或需求交给 AI，让它按本应用的导入格式生成计划，再一键导入（支持 txt / ics）。导入之后，应用负责按日期展示，未完成的任务自动顺延，完成后同一类别的后续任务自动提前。

小提示：可以直接把上方格式说明复制给 AI。''';

const licenseText = '''本应用借鉴 topydo 的 todo.txt 格式与排序 / 到期日语义，并同样以 GNU GPL-3.0 许可发布，源代码与 LICENSE 全文见本仓库。

本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证（第 3 版，或你选择的更新版本）重新分发和 / 或修改它。本程序的发布是希望它有用，但没有任何担保；甚至没有适销性或特定用途适用性的默示担保。''';

Future<void> _copy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 2)));
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final mono = th.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', height: 1.4);
    Widget h(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(t, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('关于 待办 基础版')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            // 1. 导入格式（置顶）
            h('导入格式'),
            const SelectableText(importFormatText),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: th.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SelectableText(exampleLine, key: const Key('exampleLine'), style: mono),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const Key('copyExample'),
                    onPressed: () => _copy(context, exampleLine),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('复制示例'),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            const SelectableText(importFormatExplain, key: Key('formatExplain'), style: TextStyle(height: 1.5)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('copyFormat'),
                onPressed: () => _copy(context, '$exampleLine\n\n$importFormatExplain'),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('复制格式说明'),
              ),
            ),
            // 2. 简介
            h('简介'),
            const SelectableText(introText, key: Key('introText'), style: TextStyle(height: 1.5)),
            // 3. 协议（置于最后，只保留本仓库链接）
            h('开源协议'),
            const SelectableText(licenseText, key: Key('licenseText'), style: TextStyle(height: 1.5)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: SelectableText(repoUrl, key: const Key('repoUrl'), style: TextStyle(color: th.colorScheme.primary))),
              IconButton(
                key: const Key('copyRepo'),
                tooltip: '复制链接',
                onPressed: () => _copy(context, repoUrl),
                icon: const Icon(Icons.copy, size: 18),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

void showAbout(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage()));
}
