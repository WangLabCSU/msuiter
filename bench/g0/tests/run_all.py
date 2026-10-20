#!/usr/bin/env python3
"""Test master entry: python3 -m tests.run_all (pytest not enforced).

5 test groups correspond to the task-book requirements:
  ① test_sim       simulation determinism (same seed same counts) + per-arm moment checks
  ② test_coverage  coverage-calculator correctness (CP analytic anchors + known-σ Gauss nominal 95%)
  ③ test_lrt       LRT size calibration (2000 tests under the multinomial null ≈0.05±noise)
  ④ test_provider  cosmic-file label validation (a wrong order must be rejected)
  ⑤ test_adapter   the round-trip test of the adapter protocol and the mock runner
"""

from __future__ import annotations

import importlib
import sys
import time
import traceback

MODULES = ["test_sim", "test_coverage", "test_lrt", "test_provider", "test_adapter",
           "test_seeds"]


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
