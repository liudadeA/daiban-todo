#!/usr/bin/env python3
"""《2027年数据结构考研复习指导》第4章(p109) ~ 第8章(p390) 细化到页的学习计划生成器。

用法: python3 tool/gen_ds_plan.py 408复习计划.txt 输出目录
  - 数据结构_串起_细化到页.txt   单独的数据结构细化计划
  - 408复习计划_v2.txt           用细化计划替换原计划里“串”之后的数据结构条目，其余科目不变

规则：
  * 窗口 = 原计划里数据结构从“第4章 串”(2026-11-11 下午) 到 2026-11-21 的 21 个半天(上午/下午)。
  * 每个半天分到的“学习量”相同；页数按权重折算：正文/试题/归纳/思维拓展每页 1.0，答案与解析每页 0.8。
  * 页范围按累计权重切到各半天，一个小节被切开时后半段标“（续）”。
  * 同一起始页的相邻小节合并为一条任务。
"""
import re, sys, datetime, os

# (名称, 起始页, 类型)  类型: t 正文, q 试题, a 答案, s 归纳/思维拓展
LEAVES = [
 ("第4章 串 引言 + 4.1 串的定义和实现", 109, 't'),
 ("4.1.1 串的定义", 110, 't'), ("4.1.2 串的基本操作", 110, 't'), ("4.1.3 串的存储结构", 111, 't'),
 ("4.2.1 简单的模式匹配算法", 112, 't'), ("4.2.2 KMP算法", 117, 't'), ("4.2.3 KMP算法的进一步优化", 118, 't'),
 ("4.2.4 本节试题精选", 119, 'q'), ("4.2.5 答案与解析", 123, 'a'), ("第4章 归纳总结和重难点", 123, 's'),
 ("第4章 思维拓展", 124, 's'),
 ("5.1.1 树的定义", 124, 't'), ("5.1.2 基本术语", 125, 't'), ("5.1.3 树的性质", 126, 't'),
 ("5.1.4 本节试题精选", 126, 'q'), ("5.1.5 答案与解析", 127, 'a'),
 ("5.2.1 二叉树的定义及其主要特性", 129, 't'), ("5.2.2 二叉树的存储结构", 131, 't'),
 ("5.2.3 本节试题精选", 133, 'q'), ("5.2.4 答案与解析", 135, 'a'),
 ("5.3.1 二叉树的遍历", 140, 't'), ("5.3.2 线索二叉树", 143, 't'),
 ("5.3.3 本节试题精选", 146, 'q'), ("5.3.4 答案与解析", 152, 'a'),
 ("5.4.1 树的存储结构", 168, 't'), ("5.4.2 树、森林与二叉树的转换", 170, 't'), ("5.4.3 树和森林的遍历", 171, 't'),
 ("5.4.4 本节试题精选", 172, 'q'), ("5.4.5 答案与解析", 175, 'a'),
 ("5.5.1 哈夫曼树和哈夫曼编码", 180, 't'), ("5.5.2 并查集", 183, 't'),
 ("5.5.3 本节试题精选", 185, 'q'), ("5.5.4 答案与解析", 187, 'a'),
 ("第5章 归纳总结和重难点", 192, 's'), ("第5章 思维拓展", 193, 's'),
 ("6.1.1 图的定义", 194, 't'), ("6.1.2 本节试题精选", 197, 'q'), ("6.1.3 答案与解析", 199, 'a'),
 ("6.2.1 邻接矩阵法", 201, 't'), ("6.2.2 邻接表法", 203, 't'), ("6.2.3 十字链表", 204, 't'),
 ("6.2.4 邻接多重表", 205, 't'), ("6.2.5 图的基本操作", 206, 't'),
 ("6.2.6 本节试题精选", 206, 'q'), ("6.2.7 答案与解析", 210, 'a'),
 ("6.3.1 广度优先搜索(BFS)", 214, 't'), ("6.3.2 深度优先搜索(DFS)", 217, 't'), ("6.3.3 图的遍历与图的连通性", 218, 't'),
 ("6.3.4 本节试题精选", 219, 'q'), ("6.3.5 答案与解析", 220, 'a'),
 ("6.4.1 最小生成树(Prim、Kruskal)", 221, 't'), ("6.4.2 最短路径(Dijkstra、Floyd)", 226, 't'),
 ("6.4.3 有向无环图描述表达式", 228, 't'), ("6.4.4 拓扑排序", 228, 't'), ("6.4.5 关键路径", 232, 't'),
 ("6.4.6 本节试题精选", 234, 'q'), ("6.4.7 答案与解析", 237, 'a'),
 ("第6章 归纳总结和重难点 + 思维拓展", 262, 's'),
 ("第7章 查找 引言", 263, 't'),
 ("7.1 查找的基本概念 + 7.2.1 顺序查找", 264, 't'), ("7.2.2 折半查找", 265, 't'), ("7.2.3 分块查找", 267, 't'),
 ("7.2.4 本节试题精选", 268, 'q'), ("7.2.5 答案与解析", 269, 'a'),
 ("7.3.1 二叉排序树(BST)", 272, 't'), ("7.3.2 平衡二叉树(AVL)", 278, 't'), ("7.3.3 红黑树", 286, 't'),
 ("7.3.4 本节试题精选", 291, 'q'), ("7.3.5 答案与解析", 295, 'a'),
 ("7.4 B树和B+树 引言", 304, 't'), ("7.4.1 B树及其基本操作", 305, 't'), ("7.4.2 B+树的基本概念", 308, 't'),
 ("7.4.3 本节试题精选", 309, 'q'), ("7.4.4 答案与解析", 311, 'a'),
 ("7.5 散列表 引言", 317, 't'), ("7.5.1 散列表的基本概念", 318, 't'), ("7.5.2 散列函数的构造方法", 318, 't'),
 ("7.5.3 处理冲突的方法", 320, 't'), ("7.5.4 散列查找及性能分析", 321, 't'),
 ("7.5.5 本节试题精选", 324, 'q'), ("7.5.6 答案与解析", 330, 'a'), ("第7章 归纳总结和重难点", 330, 's'),
 ("第7章 思维拓展 + 第8章 排序 引言", 331, 's'),
 ("8.1.1 排序的基本概念", 332, 't'), ("8.1.2 本节试题精选", 333, 'q'), ("8.1.3 答案与解析", 333, 'a'),
 ("8.2.1 直接插入排序", 334, 't'), ("8.2.2 折半插入排序", 335, 't'), ("8.2.3 希尔排序", 336, 't'),
 ("8.2.4 本节试题精选", 338, 'q'), ("8.2.5 答案与解析", 340, 'a'),
 ("8.3.1 冒泡排序", 341, 't'), ("8.3.2 快速排序", 344, 't'),
 ("8.3.3 本节试题精选", 346, 'q'), ("8.3.4 答案与解析", 351, 'a'),
 ("8.4.1 简单选择排序", 351, 't'), ("8.4.2 堆排序", 354, 't'),
 ("8.4.3 本节试题精选", 357, 'q'), ("8.4.4 答案与解析", 363, 'a'),
 ("8.5.1 归并排序", 363, 't'), ("8.5.2 基数排序", 365, 't'), ("8.5.3 计数排序", 366, 't'),
 ("8.5.4 本节试题精选", 367, 'q'), ("8.5.5 答案与解析", 370, 'a'),
 ("8.6.1 各种内部排序算法的比较", 373, 't'), ("8.6.2 内部排序算法的应用", 374, 't'),
 ("8.6.3 本节试题精选", 374, 'q'), ("8.6.4 答案与解析", 377, 'a'),
 ("8.7.1 外部排序的基本概念", 380, 't'), ("8.7.2 外部排序的方法", 381, 't'),
 ("8.7.3 多路平衡归并与败者树", 382, 't'), ("8.7.4 置换-选择排序", 383, 't'), ("8.7.5 最佳归并树", 384, 't'),
 ("8.7.6 本节试题精选", 385, 'q'), ("8.7.7 答案与解析", 386, 'a'), ("第8章 归纳总结和重难点", 386, 's'),
 ("第8章 思维拓展", 390, 's'),
]
END_PAGE = 390          # 391 为参考文献，不安排
FIRST, LAST_DAY = datetime.date(2026, 11, 11), datetime.date(2026, 11, 21)
WEIGHT = {'t': 1.0, 'q': 1.0, 'a': 0.8, 's': 1.0}


def groups():
    """同起始页的相邻小节合并；返回 [(名称, 起页, 止页, 单页权重)]"""
    out, i = [], 0
    while i < len(LEAVES):
        j = i
        while j + 1 < len(LEAVES) and LEAVES[j + 1][1] == LEAVES[i][1]:
            j += 1
        names = []
        for n, _, _ in LEAVES[i:j + 1]:
            names.append(n)
        w = max(WEIGHT[k] for _, _, k in LEAVES[i:j + 1])
        nxt = LEAVES[j + 1][1] if j + 1 < len(LEAVES) else END_PAGE + 1
        out.append((' + '.join(names), LEAVES[i][1], nxt - 1, w))
        i = j + 1
    return out


def build():
    gs = groups()
    pages = []  # (page, group_idx, weight)
    for gi, (_, a, b, w) in enumerate(gs):
        for p in range(a, b + 1):
            pages.append((p, gi, w))
    total = sum(w for _, _, w in pages)
    days = [FIRST + datetime.timedelta(d) for d in range((LAST_DAY - FIRST).days + 1)]
    slots = [(d, h) for d in days for h in ('上午', '下午')][1:]  # 11-11 上午 已被 3.4 数组 占用
    n = len(slots)
    acc, assign = 0.0, {}
    for p, gi, w in pages:
        mid = acc + w / 2
        acc += w
        assign[p] = min(n - 1, int(mid / total * n))
    tasks = []
    for si, (d, h) in enumerate(slots):
        for gi, (name, a, b, _) in enumerate(gs):
            ps = [p for p in range(a, b + 1) if assign[p] == si]
            if not ps:
                continue
            first_part = ps[0] == a
            rng = f"p{ps[0]}" if ps[0] == ps[-1] else f"p{ps[0]}-{ps[-1]}"
            nm = name if first_part else name + "（续）"
            tasks.append((d, si, h, nm, rng, sum(WEIGHT_OF[p] for p in ps)))
    return tasks, slots, total


WEIGHT_OF = {}
for _gi, (_n, _a, _b, _w) in enumerate(groups()):
    for _p in range(_a, _b + 1):
        WEIGHT_OF[_p] = _w


def line(d, h, nm, rng):
    ds = d.isoformat()
    return f"数据结构 {h} {nm} {rng} +408 +数据结构 due:{ds} t:{ds}"


def main():
    src, outdir = sys.argv[1], sys.argv[2]
    tasks, slots, total = build()
    new = [(t[0], t[1], line(t[0], t[2], t[3], t[4])) for t in tasks]
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, '数据结构_串起_细化到页.txt'), 'w', encoding='utf8') as f:
        f.write('\n'.join(l for _, _, l in new) + '\n')
    old = [l for l in open(src, encoding='utf8').read().split('\n') if l.strip()]
    keep, removed = [], 0
    for l in old:
        m = re.search(r'due:(\d{4}-\d{2}-\d{2})', l)
        d = datetime.date.fromisoformat(m.group(1)) if m else None
        if ' +数据结构 ' in l and d and FIRST <= d <= LAST_DAY and '3.4 数组' not in l:
            removed += 1
            continue
        keep.append(l)
    rows = [(datetime.date.fromisoformat(re.search(r'due:(\S+)', l).group(1)), -1, l) for l in keep]
    rows += new
    rows.sort(key=lambda r: (r[0], r[1]))  # 稳定排序：同一天旧条目(-1)在前，新条目按半天顺序
    with open(os.path.join(outdir, '408复习计划_v2.txt'), 'w', encoding='utf8') as f:
        f.write('\n'.join(r[2] for r in rows) + '\n')
    pages = END_PAGE - 109 + 1
    print(f"tasks={len(new)} removed_old={removed} kept_old={len(keep)} total_lines={len(rows)} pages={pages} weighted={total:.1f} slots={len(slots)} per_slot={total/len(slots):.1f}")


if __name__ == '__main__':
    main()
