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
msffi_nmf_replicates_probe
msffi_build_info
ms_tally_rust
ms_extract_rust
ms_stratify_rust
```

## 导出明细表

| 导出名 | Rust 签名 | R 包装 | 用途 | 对应契约 | 状态 | since |
|---|---|---|---|---|---|---|
| `msffi_column_major_probe` | `(x: R 双精度矩阵) -> f64` | `.msffi_column_major_probe(x)` | 列主序布局探测器：返回按列主序读取的位置加权校验和（非对称 golden 往返；区分"按列读"与"误按行读"） | 2 | diagnostic | 0.0.0.9000 |
| `msffi_na_probe` | `(x: R 双精度矩阵) -> i32` | `.msffi_na_probe(x)` | NA/NaN 第二层防线：R validator（anyNA，第一层）之后 Rust 侧显式扫描 + `debug_assert`；发现即整调用报错 | 3 | diagnostic | 0.0.0.9000 |
| `msffi_error_probe` | `(i: i32, j: i32) -> f64` | `.msffi_error_probe(i, j)` | 索引越界 → `Err(MsError)` → R condition（class `msuiter_error_rust`，载荷 `message/topic/i/j/c`）的端到端映射；1-based 虚拟 4x3 矩阵 | 4, 5 | diagnostic | 0.0.0.9000 |
| `msffi_interrupt_probe` | `(n_chunks: i32, n_threads: i32) -> i32` | `.msffi_interrupt_probe(n_chunks, threads)` | 中断机制探测器：主线程 chunk 边界轮询 `R_CheckUserInterrupt` + worker 只见 `AtomicBool` + per-call 线程池（`n_threads` 经 `.ms_resolve_threads()` 解析，0 = rayon 默认）；返回完成 chunk 数 | 6, 7 | diagnostic | 0.0.0.9000 |
| `msffi_thread_probe` | `(n_items: i32, seed: i32, n_threads: i32) -> Vec<f64>` | `.msffi_thread_probe(n_items, seed, threads)` | 线程不变性探测器：per-call ThreadPool，每 item 独立 PCG64 流（canonical layout v1），按 chunk 索引定序拼接；threads∈{1,N} 输出 identical | 6 | diagnostic | 0.0.0.9000 |
| `msffi_nmf_replicates_probe` | `(counts: R 双精度矩阵, k: i32, replicates: i32, max_iter: i32, seed: i32, n_threads: i32) -> Vec<f64>` | `.msffi_nmf_replicates_probe(counts, k, replicates, max_iter, seed, threads)` | 真实内核并行驱动（U-M1s-05）：per-call ThreadPool 上并行跑 `replicates` 个独立 KL-NMF 拟合（`engine::nmf::fit_kl_on_stream`），replicate r 的 seeded init 取自 `StreamId{replicate: r, rank: 0, fold: 0}`（canonical layout v1）；单元内单线程（内核循环序不动，A7），按 replicate 索引定序返回每 replicate 最终 KL 目标值——threads∈{1,N} 输出 identical；中断 = 主线程 chunk 边界轮询 `R_CheckUserInterrupt` + worker 只见 `AtomicBool`，任一触发整调用报错无部分结果 | 6, 7 | diagnostic | 0.0.0.9000 |
| `msffi_build_info` | `() -> List` | `.msffi_build_info()` | 编译期工具链信息（rustc 版本/目标平台/包版本；由 `build.rs` 记录），供 `ms_sitrep()` 报告 | 8（构建） | diagnostic | 0.0.0.9000 |
| `ms_tally_rust` | `(genome_path: String, chrom: Vec<String>, pos: Vec<f64>, ref_: Vec<String>, alt: Vec<String>, sample: Vec<String>, strand: Vec<String>, want_sbs96: bool, want_sbs192: bool, want_sbs384: bool, want_sbs1536: bool, want_dbs78: bool, want_id83: bool, n_threads: i32) -> List` | `.ms_tally_rust(genome_path, chrom, pos, ref_, alt, sample, strand, want_sbs96, …, threads)` | 目录 tally 内核（U-M1s-09，首个 kernel 导出）：一次进出——`File::open` + 只读 mmap 2bit 参考基因组（D12 即用即释，`Mmap::map` 为 ffi 壳的 `unsafe` 位）；记录稳定排序 (chrom,sample,pos) → 按 (染色体,样本) 分段逐段 `mnv::route_variants` 路由（SPMG `dinuc_sub==1` 为单样本内检测——跨样本的坐标相邻对永不配成 DBS、各自记 SBS，U-M1s-09 审计修复；拆分-VCF 重连/DBS 候选/skip ledger）→ `genome.rs` context 取 ±2 窗/2×2 dinuc → REF-vs-genome 与 N 检查（SPMG parity：±2 含 N 从所有 SBS 矩阵剔除；dinuc 含 N → n_dinuc；mismatch → ref_mismatch；窗越界 → context_bounds；全匹配失败 → unknown_chrom）→ 计数 SBS96/192/384/1536 + DBS78（channels×samples 列主序扁平缓冲，行序=channels.rs 规范序，列序=样本首现序；禁用表=空；DBS 对从所有 SBS 矩阵剔除；SBS192 无 B/N 通道仅从该表剔除）→ indel 分类（U-M1c ID83 接线）：每个 `RoutedEvent::Indel` 经 `indel83::assign_indel83_genome` 按 SPMG `catalogue_generator_INDEL_single` 语义分类（锚-基因组比对在本层）：有通道 → 目的地 `id83`（`want_id83` 开时计数入 83 通道矩阵，行序=indel83.rs `ID83_CHANNELS` 规范序；U-M1c-01 的 interim `skipped:simple_indel` 映射退役）；`N:Ins:M:x` 微同源插入（SPMG 算键但不写入 ID83，MMG:3738 `iloc[:83]`）→ skip `ins_microhomology_no_channel`；锚碱基 vs 参考基因组失配（含 N 锚，SPMG :1408-1421）→ skip `indel_anchor_mismatch`；游走/MH 窗越染色体端（SPMG 未捕获 IndexError 的结构化硬化，D13）→ skip `context_bounds`；indel 分类同样开关无关地运行（ledger 纯性）；ledger 沿 mnv.rs SkipLedger 渲染（输入顺序，开关无关）；**分区级并行（contract 6/7，U-M1s-11 后续）**：(染色体,样本) 分区为独立单元，per-call ThreadPool 上分 chunk 并行（`n_threads` 经 `.ms_resolve_threads()` 解析，0 = rayon 默认哨兵；worker 各持独立 2bit 解析句柄、分区内部单线程固定记录序；单列分区计数按分区序合并 + 结果按输入索引回写 → **线程数不变性：threads∈{1,4,16} 输出 identical()，Rust/R 双侧钉测**）；单分区或 n_threads==1 退化为顺序主线程路径；中断=主线程 chunk（并行）/分区（顺序）边界轮询 `R_CheckUserInterrupt`，worker 只读 AtomicBool（分区起点 + 每 4096 事件），顺序路径保留每 4096 事件的主线程轮询粒度；**0 哨兵按实际池宽度定波网格（审核 P1 修正：workers=jobs.len() 会把波数塌缩为 1、中断退化为整调用一次）——最坏 Ctrl-C 延迟 ≈ 最长单分区（人类基因组最大染色体为秒级），分区数随样本×染色体增长自动变细**；**interrupt: address-space held until process exit (frozen U-M0-09 limitation)**——用户中断 longjmp 跳过 Rust 析构，本导出的只读 mmap 地址空间保留至进程退出（页缓存背书，D12 无状态性不受影响）；C-trampoline 硬化顺延至 M8/CI；chrom 完全匹配、无 chr 前缀归一化（M1s 从简，本行即文档声明）；返回 `List{ sbs96…dbs78 矩阵, id83 矩阵（registry 标签随 registry 单元落地，暂仅列名）, ledger, n_skipped, n_variants }`。FFI 内部名：用户 API 为 `ms_tally()` 泛型（U-M1s-11 装配） | 1, 2, 3, 4, 5, 7 | kernel | 0.0.0.9000 |
| `ms_extract_rust` | `(counts: R 双精度矩阵 = t(counts)，n_samples×m_channels，k: i32, max_iter: i32, seed: i32, engine: String, n_threads: i32) -> List` | `.ms_extract_rust(counts, k, max_iter, seed, engine, threads)` | 单方法提取内核（U-M1s-12）：恰好一次种子化 NMF 拟合（seeded init，`StreamId::ZERO` 规范零流；`engine` 变体开关 `"kl"`（β=1，D6 默认）/`"eu"`（β=2），其余即 argument 错误；replicates/共识/K 选择属 M2，本导出无）；**布局契约（转置陷阱）**——内核吃行主序 m×n V，R 存储列主序，故 R 侧传 `t(counts)`：n×m 矩阵的列主序扁平缓冲即行主序 V（正确恒等式：`data[i*n+j] == counts[i,j]`，i=通道 0-based、j=样本 0-based——审核修正：对 t(counts) 的 n×m 列主序缓冲，先前所写 data[j*m+i] 不成立），Rust 侧零 marshalling；转置守卫=非对称 golden 纪律（Rust `extract.rs` 与 R 端冒烟均在 96×12（m≠n）可分真值上断言重构 cosine ≥ 0.99，传错方向必红）；校验（契约 4）：k∈[1, min(m,n)]（越界 → argument，i=k、j=min(m,n)）、max_iter/seed/n_threads 非负、engine ∈ {kl, eu}、内核逐格 finite/非负（topic na/argument，1-based i/j）；**interrupt（契约 7，文档化决策）**：单 fit 无 chunk 结构——本导出声明为有界时长、max_iter 内不可中断（备选的逐迭代轮询需把内核循环复制进 ffi 壳或给纯 engine crate 加回调缝，M1s 均更劣；目标规模 96×12×500 迭代 ≪1s；M2 replicates 经既有 chunked driver 恢复轮询）；`n_threads` 仅校验≥0、不建池（单拟合无可并行，A7 平凡线程不变）；返回 RAW 未定标因子 `List{ signatures m×k 列主序, exposures k×n 列主序, objective 长度 max_iter+1, iterations }`——W 列归一是装配层（R/extract.R）的展示约定（H 行同因子缩放保 WH 重构），内核不归一。FFI 内部名：用户 API 为 `ms_extract()` 泛型（U-M1s-12 装配，MsSignature + catalog_summary 快照） | 1, 2, 3, 4, 5 | kernel | 0.0.0.9000 |
| `ms_stratify_rust` | `(counts: R 双精度矩阵 列主序 m×n（通道×样本，不转置）, manual_cutoff: f64, seed: f64, n_threads: i32) -> List` | `.ms_stratify_rust(counts, manual_cutoff, seed, threads)`（R/stratify.R，internal） | GMM 超突变分层内核（M2 计划位提前执行 = U-M1c-02 的 FFI 接线）：`engine::stats::normalization_cutoff` + `classify_hypermutants` 语义零改动调用（冻结 SigProfiler 规则：k=2 GMM 多数簇剪枝 → trunc(mean+2σ)、`manual_cutoff` 托底、严格大于谓词；MsRng `StreamId::ZERO` 单流贯穿全部剪枝迭代）。**布局契约**——R 侧传 m×n counts 原样（列主序，不转置，与 extract.rs 的 t(counts) 相反）：列 j 的连续切片即样本 j，每样本 totals = 列内升序逐通道 f64 累加（整数值计数下任意累加序精确 ⇒ 与 R `colSums` 逐位一致）；转置守卫 = 非对称 golden 纪律（同一 cohort 过 1×n 参考与 4×n 矩阵（m≠1≠n）逐位相等，误读轴向必红，Rust 侧 `column_major_layout_guard_multichannel_matches_1row` 钉测）。**counts 值域（契约 4）**——R 包装第一层（matrix/REALSXP/anyNA）之后，Rust 侧逐格扫描第二层：finite（topic `na`）+ 非负 + 整数值（topic `argument`，载荷 1-based (i,j) 列主序坐标）；n=0 → argument；缓冲长度≠m·n → bounds。**线格式（0-based 决策，本文档即声明）**——`hypermutant_idx: Vec<i32>` 为 0-based 升序样本下标（Rust 原生约定，R 包装 +1 后索引样本名）；`cutoff` 以整数值 double 过界（u64 域，R double 精确至 2^53）；`cluster_stats = List{ retained_mean, retained_sd, retained_n, n_fits, converged }` 即保留集诊断（cutoff 图钩子）。`manual_cutoff`/`seed` 为 [0, 2^53] 整数值 double（Rust 侧复检）——较任务最小签名 (counts, n_threads) 显式扩参：cutoff 推导与播种在 kernel 内，seed/manual_cutoff 不跨界则孪生 parity 无从谈起（R API `manual_cutoff`/`seed` 语义冻结所需）。**threads/中断（契约 6/7，文档化决策）**：单次 cutoff 规则 = n 个标量上的定序计算（EM ≤200 迭代、剪枝 ≤n 轮，亚毫秒级）——无可并行（A7 平凡线程不变）、无 chunk 结构可轮询，声明为有界时长不可中断（同 `ms_extract_rust` 决策）；`n_threads` 仅校验 ≥0 不建池。FFI 内部名：用户 API 为 `ms_stratify_hypermutants()`（R/stratify.R 主路径切 FFI，纯 R 协议孪生保留为 `msuiter_stratify_twin()` 参考实现 + 测试） | 1, 2, 3, 4, 5 | kernel | 0.0.0.9000 |

约定：

* **状态** 只有两档：`diagnostic`（本单元的契约探测器/元信息，无领域算法）与 `kernel`（真实算法内核导出，M1s 起进入）。M0 里程碑内不存在 `kernel` 导出——这是刻意的（U-M0-09 禁止实现任何真实算法内核）。
* **since** = 导出首次出现的包版本；一经发布不再改写。
* 错误协议：所有 `msffi_*` 的 `Err(MsError)` 在 ffi 边界统一转为 class `c("msuiter_error_rust", "error", "condition")` 的 condition 对象（载荷 `message`、`topic`、`i`、`j`、`c`），由 R 包装以 `stop()` 重发；R 侧 validator 的 abort class 为 `msuiter_error_input` / `msuiter_error_na` / `msuiter_error_option`（ARCHITECTURE §3.5 的 `msuiter_error_<topic>` 规范）。
  **helper 统一已完成（2026-09-28，U-M1s 收尾清账小单元）**：全部 R 侧 abort（`.ms_tally_rust` 六处、`.ms_validate_matrix/_count/_switch`、`.ms_resolve_threads` 及 `.ms_extract_rust` 三处）已统一经共享 `msuiter_abort()`（R/classes-utils.R）发出，先前的临时 `rlang::abort(context=)` 形态不复存在。字面 `context` 字段与 anyNA 的整数 i/j 坐标按 ffi 契约保留为 condition 顶层字段——经 `msuiter_abort(data=)` 兼容参数注入（rlang 保留 `c` 承载子条件，故不直接用 `c=`），规范的 i/j/c 三段 bullet 载于 `cnd$msuiter_error`；测试钉死的 `err$i`/`err$j`/`err$context` 断言保持原样通过。
* 无状态（契约 1）适用于全部导出：无句柄注册表、无 `.state`、无静默重算；per-call 线程池随调用建毁。

## 冻结协议

1. **任何**对本清单的变更（新增导出、删除、改签名、改错误协议）必须：
   - 同步更新 §"导出清单" 与 §"导出明细表"（含 `since` 与 `状态`）；
   - `devtools::test()` 中漂移守卫测试保持绿（清单 ↔ 生成 wrappers 集合一致）；
   - PR 描述勾选 FFI-surface 检查项——检查项由 U-M0-08 的 PR 模板落地（见 ROADMAP M0 治理文件条目），模板就位前以 PR 描述显式声明 "ffi-surface 变更" 代替；
   - 涉及 `ms_*_rust` 内核导出（M1s+）时，同步刷新对应 golden/fixture（PR 模板第二检查项，同上承接）。
2. `msffi_*` 属 diagnostic 层：允许随评审增删；`ms_*_rust` 属 kernel 层：一经发布冻结（语义变更 = 新导出名 + 旧名 deprecate 走 `lifecycle::deprecate_warn`）。
3. 本文件随每个 release 评审一次（per-release 评审工件，ARCHITECTURE §3.5）；评审记录进当期 devlog。
