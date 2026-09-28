# FFI 导出面（ffi-surface）评审工件

> 状态依据：`docs/ARCHITECTURE.md` §2（FFI 硬契约 1–8）、§3.5（`docs/ffi-surface.md` 为 per-release 评审工件）；建立于 U-M0-09。
> 适用范围：根 crate（FFI 壳）的全部 `#[extendr]` 导出（`msffi_*`，经 `R/extendr-wrappers.R` 的 `wrap__*` 注册进 `msuiter` 动态库）。engine/catalog crate 无 FFI 面，不在本表。
> **本文件是冻结工件**：仓库守卫测试（`tests/testthat/test-ffi-surface-drift.R`）解析 §"导出清单" 中的机器可读清单，与 rextendr 生成 wrappers 的实际导出集合逐项比对，任何漂移（新增/删除/改名）即测试红。

## 导出清单（机器可读；漂移守卫以此为唯一事实来源）

```msuiter-ffi-surface
msffi_column_major_probe
msffi_na_probe
msffi_error_probe
msffi_interrupt_probe
msffi_thread_probe
msffi_build_info
```

## 导出明细表

| 导出名 | Rust 签名 | R 包装 | 用途 | 对应契约 | 状态 | since |
|---|---|---|---|---|---|---|
| `msffi_column_major_probe` | `(x: R 双精度矩阵) -> f64` | `.msffi_column_major_probe(x)` | 列主序布局探测器：返回按列主序读取的位置加权校验和（非对称 golden 往返；区分"按列读"与"误按行读"） | 2 | diagnostic | 0.0.0.9000 |
| `msffi_na_probe` | `(x: R 双精度矩阵) -> i32` | `.msffi_na_probe(x)` | NA/NaN 第二层防线：R validator（anyNA，第一层）之后 Rust 侧显式扫描 + `debug_assert`；发现即整调用报错 | 3 | diagnostic | 0.0.0.9000 |
| `msffi_error_probe` | `(i: i32, j: i32) -> f64` | `.msffi_error_probe(i, j)` | 索引越界 → `Err(MsError)` → R condition（class `msuiter_error_rust`，载荷 `message/topic/i/j/c`）的端到端映射；1-based 虚拟 4x3 矩阵 | 4, 5 | diagnostic | 0.0.0.9000 |
| `msffi_interrupt_probe` | `(n_chunks: i32, n_threads: i32) -> i32` | `.msffi_interrupt_probe(n_chunks, threads)` | 中断机制探测器：主线程 chunk 边界轮询 `R_CheckUserInterrupt` + worker 只见 `AtomicBool` + per-call 线程池（`n_threads` 经 `.ms_resolve_threads()` 解析，0 = rayon 默认）；返回完成 chunk 数 | 6, 7 | diagnostic | 0.0.0.9000 |
| `msffi_thread_probe` | `(n_items: i32, seed: i32, n_threads: i32) -> Vec<f64>` | `.msffi_thread_probe(n_items, seed, threads)` | 线程不变性探测器：per-call ThreadPool，每 item 独立 PCG64 流（canonical layout v1），按 chunk 索引定序拼接；threads∈{1,N} 输出 identical | 6 | diagnostic | 0.0.0.9000 |
| `msffi_build_info` | `() -> List` | `.msffi_build_info()` | 编译期工具链信息（rustc 版本/目标平台/包版本；由 `build.rs` 记录），供 `ms_sitrep()` 报告 | 8（构建） | diagnostic | 0.0.0.9000 |

约定：

* **状态** 只有两档：`diagnostic`（本单元的契约探测器/元信息，无领域算法）与 `kernel`（真实算法内核导出，M1s 起进入）。M0 里程碑内不存在 `kernel` 导出——这是刻意的（U-M0-09 禁止实现任何真实算法内核）。
* **since** = 导出首次出现的包版本；一经发布不再改写。
* 错误协议：所有 `msffi_*` 的 `Err(MsError)` 在 ffi 边界统一转为 class `c("msuiter_error_rust", "error", "condition")` 的 condition 对象（载荷 `message`、`topic`、`i`、`j`、`c`），由 R 包装以 `stop()` 重发；R 侧 validator 的 abort class 为 `msuiter_error_input` / `msuiter_error_na` / `msuiter_error_option`（ARCHITECTURE §3.5 的 `msuiter_error_<topic>` 规范）。
  **已知形态偏离（2026-09-28 记录）**：R 侧 `rlang::abort` 的上下文字段名为 `context` 而非字面 `c`（rlang 保留 `c` 承载子 condition，字面 `c=` 会被 call 求值劫持），i/j 为顶层字段且无 `msuiter_error` 列——与 U-M0-03 `msuiter_abort` 的 `cnd$msuiter_error` 载荷形态并存。M1s 内核进场前统一为共享 helper（U-M1s-09 承接），届时同步本注记。
* 无状态（契约 1）适用于全部导出：无句柄注册表、无 `.state`、无静默重算；per-call 线程池随调用建毁。

## 冻结协议

1. **任何**对本清单的变更（新增导出、删除、改签名、改错误协议）必须：
   - 同步更新 §"导出清单" 与 §"导出明细表"（含 `since` 与 `状态`）；
   - `devtools::test()` 中漂移守卫测试保持绿（清单 ↔ 生成 wrappers 集合一致）；
   - PR 描述勾选 FFI-surface 检查项——检查项由 U-M0-08 的 PR 模板落地（见 ROADMAP M0 治理文件条目），模板就位前以 PR 描述显式声明 "ffi-surface 变更" 代替；
   - 涉及 `ms_*_rust` 内核导出（M1s+）时，同步刷新对应 golden/fixture（PR 模板第二检查项，同上承接）。
2. `msffi_*` 属 diagnostic 层：允许随评审增删；`ms_*_rust` 属 kernel 层：一经发布冻结（语义变更 = 新导出名 + 旧名 deprecate 走 `lifecycle::deprecate_warn`）。
3. 本文件随每个 release 评审一次（per-release 评审工件，ARCHITECTURE §3.5）；评审记录进当期 devlog。
