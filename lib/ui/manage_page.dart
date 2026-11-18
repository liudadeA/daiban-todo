import 'package:flutter/material.dart';

import '../data/store.dart';
import '../logic/estimator.dart';
import 'category_widgets.dart';

/// 批量管理：删除全部、清空已完成、按类别删除 / 重命名 / 平移日期。
class ManagePage extends StatelessWidget {
  final TodoStore store;
  const ManagePage({super.key, required this.store});

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('确认删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return r == true;
  }

  void _toast(BuildContext context, String msg) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: '撤销', onPressed: () => store.undo())));
  }

  Future<void> _shiftCategory(BuildContext context, String? c) async {
    final dated = store.todo.where((t) => t.category == c && t.date != null).toList();
    if (dated.isEmpty) {
      final m = ScaffoldMessenger.of(context);
      m.clearSnackBars();
      m.showSnackBar(const SnackBar(content: Text('该类别没有可平移日期的待办')));
      return;
    }
    final days = TextEditingController(text: '1');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('平移「${store.categoryLabel(c)}」的日期（${dated.length} 项待办）'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('shift_days_field'),
            controller: days,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: const InputDecoration(
                labelText: '天数',
                helperText: '正数 = 推迟，负数 = 提前；截止日期、开始日期和原计划日期一起移动，已完成不改',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final v in [-7, -1, 1, 7])
              ActionChip(key: Key('shift_days_$v'), label: Text(v > 0 ? '+$v' : '$v'), onPressed: () => days.text = '$v'),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(days.text.trim())), child: const Text('确定')),
        ],
      ),
    );
    if (n == null || n == 0) return;
    final moved = await store.shiftCategory(c, n);
    if (context.mounted) _toast(context, '已把「${store.categoryLabel(c)}」的 $moved 项待办${n > 0 ? '推迟' : '提前'} ${n.abs()} 天');
  }


  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cats = <String?>[...store.categories, if (store.hasUncategorized) null];
        int todoN(String? c) => store.todo.where((t) => t.category == c).length;
        int doneN(String? c) => store.done.where((t) => t.category == c).length;
        return Scaffold(
          appBar: AppBar(title: const Text('批量管理')),
          body: ListView(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('提示：在任务列表里长按任务可进入多选，支持批量完成 / 删除 / 更改类别 / 平移日期。',
                  style: TextStyle(color: Colors.black54)),
            ),
            const _Section('全部'),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('删除全部任务', style: TextStyle(color: Colors.red)),
              subtitle: Text('待办 ${store.todo.length} 项 + 已完成 ${store.done.length} 项'),
              enabled: store.todo.isNotEmpty || store.done.isNotEmpty,
              onTap: () async {
                if (await _confirm(context, '删除全部任务？',
                    '将删除全部 ${store.todo.length} 项待办和 ${store.done.length} 项已完成，此操作可立即撤销。')) {
                  await store.deleteAll();
                  if (context.mounted) _toast(context, '已删除全部任务');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('清空已完成'),
              subtitle: Text('${store.done.length} 项'),
              enabled: store.done.isNotEmpty,
              onTap: () async {
                if (await _confirm(context, '清空已完成？', '将删除 done.txt 中的全部 ${store.done.length} 条记录。')) {
                  await store.clearDone();
                  if (context.mounted) _toast(context, '已清空已完成');
                }
              },
            ),
            const _Section('按类别'),
            if (cats.isEmpty) const ListTile(title: Text('还没有任务')),
            for (final c in cats)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(store.categoryLabel(c)),
                isThreeLine: true,
                subtitle: Text(Estimator.detail(Estimator.forCategory(store.todo, store.done, store.today, c), store.today).join('\n')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    key: Key('manage_shift_${c ?? ''}'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.date_range),
                    tooltip: '平移该类别日期',
                    onPressed: () => _shiftCategory(context, c),
                  ),
                  IconButton(
                    icon: const Icon(Icons.drive_file_rename_outline),
                    tooltip: '重命名 / 合并到其它类别',
                    onPressed: () async {
                      final to = await showCategoryDialog(context, store,
                          title: '重命名「${store.categoryLabel(c)}」',
                          initial: c ?? '',
                          helper: '填写已有类别名即合并到该类别');
                      if (to == null || to == (c ?? '')) return;
                      final n = await store.renameCategory(c, to);
                      if (context.mounted) _toast(context, '已更改 $n 项任务的类别');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: '删除该类别的全部任务',
                    onPressed: () async {
                      if (await _confirm(context, '删除「${store.categoryLabel(c)}」的全部任务？',
                          '将删除该类别的 ${todoN(c)} 项待办和 ${doneN(c)} 项已完成，此操作可立即撤销。')) {
                        final n = await store.deleteCategory(c);
                        if (context.mounted) _toast(context, '已删除 $n 项任务');
                      }
                    },
                  ),
                ]),
              ),
          ]),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      );
}
