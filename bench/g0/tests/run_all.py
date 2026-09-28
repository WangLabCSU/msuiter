#!/usr/bin/env python3
"""测试总入口：python3 -m tests.run_all（不强制 pytest）。

5 组测试对应任务书要求：
  ① test_sim       模拟确定性（同 seed 同 counts）+ 各臂矩校验
  ② test_coverage  覆盖率计算器正确性（CP 解析锚点 + 已知 σ 高斯名义 95%）
  ③ test_lrt       LRT size 校准（多项零假设下 2000 次检验 ≈0.05±噪声）
  ④ test_provider  cosmic-file 标签校验（错序必须拒）
  ⑤ test_adapter   adapter 协议与 mock runner 的往返测试
"""

from __future__ import annotations

import importlib
import sys
import time
import traceback

MODULES = ["test_sim", "test_coverage", "test_lrt", "test_provider", "test_adapter"]


def main() -> int:
    failures = []
    for mod_name in MODULES:
        mod = importlib.import_module(f"tests.{mod_name}" if not mod_name.startswith("tests")
                                      else mod_name)
        fns = sorted((n, f) for n, f in vars(mod).items()
                     if n.startswith("test_") and callable(f))
        for name, fn in fns:
            t0 = time.time()
            try:
                fn()
                print(f"PASS  {mod_name}.{name}  ({time.time() - t0:.1f}s)")
            except Exception:
                failures.append(f"{mod_name}.{name}")
                print(f"FAIL  {mod_name}.{name}  ({time.time() - t0:.1f}s)")
                traceback.print_exc()
    total = sum(len([n for n, f in vars(importlib.import_module(f"tests.{m}")).items()
                     if n.startswith("test_") and callable(f)]) for m in MODULES)
    print(f"\n{total - len(failures)}/{total} tests passed.")
    if failures:
        print("FAILED:", ", ".join(failures))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
