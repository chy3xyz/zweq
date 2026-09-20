#!/usr/bin/env python3
"""分配器归属 lint —— 拦截“用请求 arena 释放非 arena 对象”的一类缺陷。

背景（真实事故）：`ctx.allocator` 是**连接 fiber 的 arena**，Zig 0.17 下
`arena.free()` 是 no-op；而各 store/service 的 `dup*` 用**进程 gpa** 分配行与
字符串。于是 `ctx.allocator.free(store 行)` 会静默泄漏整块（本项目曾一次性
停机报出 631 条 leaked：CSV 导出每次泄漏整页、登录每次泄漏密码哈希）。

为什么必须做成脚本门禁：**单元测试原理上抓不到**——测试里 `ctx.allocator` 与
store 分配器同为 `std.testing.allocator`，两侧同源，不匹配不可见。唯一可行的
判据是静态查“被释放对象的生产者用的是哪个分配器”。

判定（保守，宁可漏报不误报）：
  1. 收集所有 `<X>.free(ctx.allocator)` / `ctx.allocator.free(<X>)` 释放点；
  2. 向上追溯 `<X>` 的生产者（支持一层别名与 `for (...) |x|` 循环绑定）；
  3. 生产者行若出现 `ctx.` / `bindJson` / `allocPrint(ctx` 等“请求作用域或显式
     传入 arena”的痕迹 → 正确，跳过；
  4. 生产者行若是 store/service 取数（`self.store.`/`self.<x>_store.`/`self.svc.`/
     `refs.` / `getUserById` / `listProviders` 之类）且**没有**把 arena 作为实参
     传进去 → 报告；
  5. 其余一律不报（无法判定就不猜）。

用法：
  python3 scripts/check_alloc_owner.py [根目录，默认 src]
退出码 1 表示发现可疑释放点。
"""

import os
import re
import sys

FREE_PATTERNS = [
    # defer x.free(ctx.allocator);   /   x.free(ctx.allocator);
    re.compile(r'\.free\(ctx\.allocator\)'),
    # ctx.allocator.free(x)
    re.compile(r'ctx\.allocator\.free\(\s*([A-Za-z_]\w*)\s*\)'),
]

# 生产者行里出现这些 → 属于请求作用域或显式传入 request arena，视为正确。
ARENA_HINTS = (
    'ctx.allocator', 'ctx.bind', 'ctx.multipart', 'ctx.param',
    'Stringify', 'allocPrint(ctx', 'dupe(ctx',
)

# 生产者行里出现这些 → 来自长期分配器（store/service/安全模块）。
OWNER_HINTS = (
    'self.store.', 'self.svc.', 'refs.', '_store.', '_svc.',
    'getUserById', 'getById', 'getByOpenid', 'getByEmail', 'getPasswordHashById',
    'listProviders', 'listAccounts', 'listOrders', 'listUsers', 'listRolesForUser',
    'listCommissions', 'listKeywords', 'listReplies', 'listBindings', 'listCoupons',
    'listWebhooks', 'listOutlets', 'listArticles', 'listApprovals', 'listRuns',
    'fetchMenu', 'getDatacube', 'miniLogin', 'uploadNews', 'parseConfig',
)

DEF_PAT = re.compile(r'\b(?:var|const)\s+([A-Za-z_]\w*)\s*=\s*(.*)$')
FOR_PAT = re.compile(r'\bfor\s*\(([^)]*)\)\s*\|\s*([A-Za-z_]\w*)\s*(?:,\s*\w+\s*)?\|')


def ident_of_init(init: str) -> str | None:
    """`x = y;` / `x = y orelse ...` / `x = (try f(...)) orelse ...` 里取出被包装的标识符。"""
    m = re.match(r'\(?\s*(?:try\s+)?([A-Za-z_]\w*)\s*\)?\s*(?:orelse|\b)', init)
    return m.group(1) if m else None


def find_origin(lines, idx, var, depth=0):
    """返回 (行号, 该行文本, 来源变量名)；找不到返回 (None, None, var)。"""
    if depth > 3:
        return None, None, var
    for j in range(idx - 1, max(-1, idx - 40), -1):
        m = DEF_PAT.search(lines[j])
        if m and m.group(1) == var:
            init = m.group(2)
            # 单层别名：var x = y;  → 追 y
            if re.fullmatch(r'[A-Za-z_]\w*\s*;?', init) and not init.startswith('try'):
                alias = init.rstrip(';').strip()
                if alias != var:
                    ln, txt, _ = find_origin(lines, j, alias, depth + 1)
                    if ln is not None:
                        return ln, txt, alias
            return j, lines[j].strip(), var
        fm = FOR_PAT.search(lines[j])
        if fm and fm.group(2) == var:
            # for (...) |v| 绑定：追被遍历的集合
            coll = fm.group(1).split(',')[-1].strip()
            return find_origin(lines, j, coll, depth + 1)
    return None, None, var


def check_file(path):
    findings = []
    lines = open(path, encoding='utf-8').read().split('\n')
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith('//'):
            continue
        if not any(p.search(line) for p in FREE_PATTERNS):
            continue
        if '.free(ctx.allocator)' in line:
            m = re.search(r'([A-Za-z_]\w*)\.free\(ctx\.allocator\)', line)
            var = m.group(1) if m else None
            if var is None and '|' in line:  # for (rows) |r| r.free(ctx.allocator)
                fm = re.search(r'\|\s*([A-Za-z_]\w*)\s*\|', line)
                var = fm.group(1) if fm else None
        else:
            m = FREE_PATTERNS[1].search(line)
            var = m.group(1) if m else None
        if not var:
            continue
        ln, txt, _ = find_origin(lines, i, var)
        if ln is None:
            continue
        if any(h in txt for h in ARENA_HINTS):
            continue
        if any(h in txt for h in OWNER_HINTS):
            findings.append((path, i + 1, var, ln + 1, txt))
    return findings


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else 'src'
    all_findings = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            if fn.endswith('.zig'):
                all_findings.extend(check_file(os.path.join(dirpath, fn)))
    if all_findings:
        print("分配器归属 lint 失败：以下释放点用的是请求 arena，但对象由长期分配器生产")
        print("（arena.free 是 no-op → 静默泄漏；请改用拥有者分配器）\n")
        for path, line, var, pline, txt in all_findings:
            print(f"  {path}:{line}  free(ctx.allocator) 的对象 `{var}` 生产于 {path}:{pline}")
            print(f"      {txt}")
        print(f"\n共 {len(all_findings)} 处")
        return 1
    print("✓ 分配器归属 lint 通过（无“arena 释放长期分配器对象”的释放点）")
    return 0


if __name__ == '__main__':
    sys.exit(main())
