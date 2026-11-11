import 'package:flutter/material.dart';

import '../data/store.dart';
import '../logic/dates.dart';

class SettingsPage extends StatefulWidget {
  final TodoStore store;
  const SettingsPage({super.key, required this.store});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _primary;
  TodoStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _primary = TextEditingController(text: store.primaryCategory ?? '');
  }

  @override
  void dispose() {
    _primary.dispose();
    super.dispose();
  }

  /// 三态：继承全局 / 开 / 关
  Widget _tri(String label, bool? value, bool global, ValueChanged<bool?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(child: Text(label)),
        DropdownButton<int>(
          value: value == null ? 0 : (value ? 1 : 2),
          items: [
            DropdownMenuItem(value: 0, child: Text('跟随全局（${global ? '开' : '关'}）')),
            const DropdownMenuItem(value: 1, child: Text('开')),
            const DropdownMenuItem(value: 2, child: Text('关')),
          ],
          onChanged: (v) => onChanged(v == 0 ? null : v == 1),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final last = store.lastProcessed;
        final cats = <String?>[...store.categories, if (store.hasUncategorized) null];
        return Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: ListView(children: [
            SwitchListTile(
              title: const Text('未完成则整体顺延（全局默认）'),
              subtitle: const Text('跨天后，某类别昨天还有未完成的任务，则只把该类别之后的未完成任务 due / t 各推迟 1 天（跨多天则逐天推迟）。'),
              value: store.shiftBackEnabled,
              onChanged: store.setShiftBack,
            ),
            SwitchListTile(
              title: const Text('完成即提前（全局默认）'),
              subtitle: const Text('某类别今日任务（含逾期）全部完成后，只把该类别下一批日期的未完成任务整体提前到今天。'),
              value: store.pullForwardEnabled,
              onChanged: store.setPullForward,
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('类别', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _primary,
                decoration: const InputDecoration(
                  labelText: '主类别（新建任务时的默认类别）',
                  helperText: '类别 = 任务的第一个 +标签，例如 408、数学；留空 = 不预设',
                  border: OutlineInputBorder(),
                  prefixText: '+',
                ),
                onChanged: (v) => store.setPrimaryCategory(v),
              ),
            ),
            if (cats.isEmpty)
              const ListTile(title: Text('还没有任务，导入或新建后这里会列出各类别')),
            for (final c in cats)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text(
                          '${store.categoryLabel(c)}　待办 ${store.todo.where((t) => t.category == c).length} 项',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    _tri('完成即提前', store.categoryPullSetting(c), store.pullForwardEnabled,
                        (v) => store.setCategoryPull(c, v)),
                    _tri('整体顺延', store.categoryShiftSetting(c), store.shiftBackEnabled,
                        (v) => store.setCategoryShift(c, v)),
                  ]),
                ),
              ),
            const Divider(),
            ListTile(
              title: const Text('上次日切检查日期'),
              subtitle: Text(last == null ? '尚未检查' : Ymd.fmt(last)),
            ),
            const ListTile(
              title: Text('说明'),
              subtitle: Text('各类别互相独立：408 做完只会提前 408 的下一批，数学的计划不动；顺延同理。'
                  '逾期未完成的任务不会消失，会一直显示在「今日」对应类别的分组里。'
                  '日切检查只在打开 / 切回 App 时执行，同一天内不会重复顺延。'),
            ),
          ]),
        );
      },
    );
  }
}
