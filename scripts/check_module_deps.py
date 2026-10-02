#!/usr/bin/env python3
"""模块依赖声明 lint —— module.zig 的 .dependencies 必须等于真实 import 图。

背景（审计发现）：31 个业务模块里 28 个 module.zig 声明 `.dependencies = &.{}`，
但静态交叉 import 大量兄弟模块（api 层注入 UserService/AuditService、service 层
互调、跨模块 persistence 直读等）。声明与事实不符导致 zigmodu 的启动校验
（missing/cycle 检测）形同虚设，依赖环无法被验出。

判定：
  1. 扫 `src/modules/<mod>/**/*.zig` 里所有 `@import("...")`；
  2. 相对路径按文件位置归一化后落入 `src/modules/<other>/`（other != mod）
     → 记一条真实依赖；
  3. 解析 module.zig 的 `.dependencies = &.{...}` 得到声明依赖；
  4. 双向 diff：真实存在但未声明 → 报错；声明了但无任何 import 支撑 → 报错。

用法：
  python3 scripts/check_module_deps.py [根目录，默认 src]
退出码 1 表示存在不一致。
"""

import os
import re
import sys

IMPORT_RE = re.compile(r'@import\("([^"]+)"\)')
DECL_RE = re.compile(r"\.dependencies\s*=\s*&\.\{(.*?)\}", re.S)
STRING_RE = re.compile(r'"([^"]+)"')


def real_dependencies(modules_dir: str, mod: str) -> set:
    """扫模块目录内全部 .zig 文件的 @import，归一化后找兄弟模块边。"""
    deps = set()
    mod_dir = os.path.join(modules_dir, mod)
    for dirpath, _dirnames, filenames in os.walk(mod_dir):
        for name in filenames:
            if not name.endswith(".zig"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            for target in IMPORT_RE.findall(text):
                # 只认相对路径 import；包名（zigmodu/zent/zwechat/…）与绝对
                # 模块路径（"modules/…"）不在模块目录文件里出现，出现也跳过。
                if not target.startswith("."):
                    continue
                resolved = os.path.normpath(os.path.join(dirpath, target))
                if not resolved.startswith(modules_dir + os.sep):
                    continue
                rel = os.path.relpath(resolved, modules_dir)
                other = rel.split(os.sep)[0]
                if other != mod:
                    deps.add(other)
    return deps


def declared_dependencies(module_zig: str) -> set:
    with open(module_zig, encoding="utf-8") as f:
        text = f.read()
    m = DECL_RE.search(text)
    if not m:
        return set()
    return set(STRING_RE.findall(m.group(1)))


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "src"
    modules_dir = os.path.join(root, "modules")
    mods = sorted(
        d
        for d in os.listdir(modules_dir)
        if os.path.isdir(os.path.join(modules_dir, d))
        and os.path.isfile(os.path.join(modules_dir, d, "module.zig"))
    )

    problems = 0
    for mod in mods:
        real = real_dependencies(modules_dir, mod)
        declared = declared_dependencies(os.path.join(modules_dir, mod, "module.zig"))
        undeclared = sorted(real - declared)
        unbacked = sorted(declared - real)
        if not undeclared and not unbacked:
            continue
        problems += 1
        print(f"[{mod}] module.zig 声明与真实 import 不一致:")
        for name in undeclared:
            print(f"  未声明: import 了模块 '{name}'，但 .dependencies 未列出")
        for name in unbacked:
            print(f"  无实据: .dependencies 声明了 '{name}'，但模块内无任何 @import")

    total_edges = sum(
        len(real_dependencies(modules_dir, mod)) for mod in mods
    )
    if problems:
        print(f"\n共 {problems} 个模块不一致（{len(mods)} 个模块、真实依赖边 {total_edges} 条）。")
        return 1
    print(f"OK: {len(mods)} 个模块依赖声明与真实 import 一致（真实依赖边 {total_edges} 条）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
