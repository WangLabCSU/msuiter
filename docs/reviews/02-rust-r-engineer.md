# 评审 02：Rust/R 系统开发专家（独立评审，2026-09-28）

> 评审人设定：extendr 系 R 包 CRAN 维护者，深谙 R C API、跨平台打包、cargo vendoring。关键主张经 upstream 一手复核（extendr-macros wrapper 源码、crates.io extendr-api 0.9.0、docs.rs rand/twobit、CRAN Using Rust 页）。
> **总裁决：有条件通过（conditional go）。** R/算法/许可层契约密度罕见地高，但 **Rust 运行时层契约（随机数、并发、panic、FFI 边界、分发预算）几乎整体缺席**——这是"数量级加速 + 可复现"叙事的地基。

## P0

### 1.【P0】复现性契约建在流沙上：`rand` 的输出跨版本不保证一致
- docs.rs 原文：`SmallRng` **"Non-portable: any future library version may replace the algorithm"**，复现请用 `rand_pcg/rand_xoshiro`；rand 0.9 是破坏性大版本且 crates 已滚到 0.10.x——审稿期内一次 `cargo update`，"种子全链路可复现"静默失效。
- **修改**：不碰 rand 的 RNG 面。自写 PCG64（~60 行）+ 自写 multinomial/Dirichlet（rand_distr 本就没有 multinomial）；种子协议 = 用户 seed → SplitMix64 → per-(replicate, rank, fold) 计数器流，流布局写进论文 Methods；Cargo.lock + vendor 钉死；CI 跨版本 golden 测试。

## P1

### 2.【P1】CRAN 2 线程合规与 fork 安全机制未落地，各有一个 set-once 陷阱
- rayon 全局池 lazy set-once：`RAYON_NUM_THREADS` 只在首次并行调用读一次；常驻池被 `mcfork`（Bioc 生态常用）fork 后成尸体；CRAN 要求安装期 cargo 限 `-j 1/2`，rextendr 默认 Makevars 不做。
- **修改**：**放弃全局池**——每个顶层 FFI 调用内 `ThreadPoolBuilder::new().num_threads(n).build()` + scoped `install()`（~100µs 可忽略）；n 来自 R 端 `getOption("msuiter.threads")`（`_R_CHECK_LIMIT_CORES_` 下默认 2）；Makevars.in 显式 `CARGO_BUILD_JOBS=2`；文档写 BiocParallel `threads=1` 兼容。

### 3.【P1】FP 决定论缺口：线程数不能改变数值结果
- 并行归约顺序随线程数变 → 2 线程（检查）与 16 线程（用户）产出 bit 级不同结果——复现性声明被戳穿。
- **修改**：并行只存在于独立单元之间（replicate/样本/bootstrap），单元内 kernel 单线程固定归约顺序；CI 硬测试：同 seed 在 threads∈{1,4} 输出 `identical()`。

### 4.【P1】句柄注册表 + `.state` 是为不存在的能力付的复杂度：把 FFI 改成无状态
- `MsSignature` 是拟合**最终产物**——全是现成矩阵，Rust 侧无状态可驻留；基因组 mmap+解析是微秒级。句柄的代价：externalptr 不进 RDS → 用户 load 后一碰 `.state` 触发**静默重拟合**；泄漏；fork 风险；破坏 waldo 比较。
- **修改**：v1 FFI 全部无状态（`ms_tally_rust(2bit_path, ...)` 进程内 mmap 算完释放；`ms_extract_rust(counts, params, seeds)` 一次进出）；**从 S7 类删除 `.state`**；caugi 模式只保留"只读属性"美学；未来需可续算再引入句柄 + `reg.finalizer` + 显式 `ms_close()` + 重连报错（绝不静默重算）。

### 5.【P1】手写 randomized SVD/Cholesky 恰好在最难的 benchmark 场景退化
- NNDSVD 需要的前导奇异三元组在 Wu 2022 r=0.8–0.95（旗舰场景）下奇异间隙塌缩，power iterations 不足则误差放大；签名近共线（SBS1/5）时 `G=PᵀP` 病态，无 pivot Cholesky 会负开方；KL 分母零通道 ε 放置直接决定 NaN 是否出厂。
- **修改**：randomized SVD 固定 q≥3 power iterations + oversampling ≥16 + "exact Gram-SVD 对照" property test（1536² Gram 完全可行）；NNLS Gram 用 **pivot 化 LDLᵀ** + `ε·‖G‖` ridge + KKT 残差断言；KL 分母 `max(·,ε)`、`log(ε+·)`，ε 值进文档与 TDD。

### 6.【P1】Ctrl-C：长跑 Rust 调用不可中断
- `R_CheckUserInterrupt` 只允许主线程调用（rayon worker 里是 UB）。
- **修改**：主线程在并行 chunk 边界轮询 `R_CheckUserInterrupt`；worker 内只查 `AtomicBool` 取消标志；导出契约：可中断且中断后无残留（与无状态设计协同自动成立）。

### 7.【P1】分发预算没有数字：vendor 体积、MSRV、安装期行为排在 M8 才"审计"
- 估算：vendor 展开 ~15–25MB、xz 后 ~4–8MB，叠加后易顶破 CRAN 10MB 指导线需 waiver；**好消息：extendr-api 0.9.0 官方 MSRV = 1.71**（符合 CRAN 两年 cargo 要求）；rust-toolchain.toml 绝不能进 tarball。
- **修改**：体积/MSRV 审计**提前到 M0 spike**（一周出真实 vendor + xz 字节数 + rustc 1.71 构建证明）；`extendr-api default-features=false` 只留 ndarray；按 P0-1 砍 rand 树；Makevars 按 string2path 模式（vendor.tar.xz + cargo_vendor_config.toml + CARGO_NET_OFFLINE + -j2 + cleanup）；DESCRIPTION `SystemRequirements: cargo, rustc (>= 1.71)`。

## P2

### 8.【P2】"与 R NMF brunet bit 级对齐"是做不到的验收标准
- R brunet 走平台 BLAS（Accelerate/OpenBLAS/参考），乘加顺序随厂商变——3 OS CI 上天然 flaky。
- **修改**：两级验收——对拍 R NMF 用相对容差（`‖ΔW‖/‖W‖ < 1e-10`，同 seed 收敛点）；bit 级 golden 只锁**自己实现的历史版本**。

### 9.【P2】FFI 边界缺硬契约：memory order、NA/NaN、i32 边界
- R column-major vs ndarray row-major——**96×96 方形矩阵会静默转置**；`NA_integer_`=INT_MIN 会被 `as usize` 变合法大数；"非负"校验不配 `anyNA()` 就漏。
- **修改**：①过界矩阵统一显式 column-major 视图 + 方形转置探测器单测（非对称 golden 往返）；②NA 契约 = R validator 强制 `anyNA()` 拒绝，Rust 端 `debug_assert!` 且不产出 NaN；③索引 i32→usize + bounds check，越界返回 R error。

### 10.【P2】panic 策略应写进文档
- 已核实 extendr-macros wrapper 用 `catch_unwind(AssertUnwindSafe(...))` 把 panic 转 R error——不打穿 FFI。但错误路径 `throw_r_error → Rf_error → longjmp` **跳过 Rust 栈析构**：kernel 深处调 throwing helper 会漏堆缓冲；rayon worker panic 传播回调用线程再被接住，但"部分完成输出"状态需定义。
- **修改**："kernel 返回 `Result<_, MsError>`，只在 ffi crate 边界转 R error；禁止 kernel 内调 throwing API；任何 panic → 整调用报错、无部分结果"。R 侧测试错误路径得到 condition 且会话可继续。

### 11.【P2】twobit crate 定位自相矛盾
- twobit 0.2.2 是 `Read + Seek` 泛型 reader：`open()` 带缓冲普通读（百万变体随机访问=百万级小读）、`open_and_read()` 整文件进 RAM（hg38 ~800MB）——**自己不做 mmap**；byte-swap（大端）文件支持未见说明。
- **修改**：二选一进 ADR：(a) `TwoBitFile` over `Cursor<Mmap>`（memmap2 + Cursor 组合），按染色体排序分批、每个 4bit 字只解一次，vendor 钉死 =0.2.2；(b) 自研 ~300 行 reader + 对拍 `rtracklayer::import`。任一方案先验证 byte-swap/重复 chrom/N/softmask 语义。

### 12.【P2】workspace 三 crate 划分方向对，缺两条护栏
- **修改**：依赖方向单一（ffi→catalog→engine，禁反向）；engine/catalog `#![forbid(unsafe_code)]`，unsafe 限定在 ffi crate 并逐条 SAFETY 注释；cargo deny 加 ban 规则禁止 engine/catalog 依赖 extendr-api。

## 总体裁决与亮点
- **Conditional go**。Rust 运行时层条款（RNG 版本契约、并发/fork/中断、panic/longjmp、FFI 硬契约、分发预算数字）必须 M0 写进 ADR，不是 M8 交学费。
- **三件做得好**：FFI 三面收敛（索引不回字符串/边界一次规范化/小导出面）；Rust/R 工程事实调研准确可执行（无"上 CRAN 很容易"幻觉）；S7 成本模型实测成纪律（6µs/17µs → API 边界铁律）——"在我审过的 extendr+S7 提案里第一次见到"。
- Sources: docs.rs SmallRng；CRAN Using Rust；crates.io extendr-api 0.9.0（MSRV 1.71）；extendr-macros wrappers.rs；docs.rs twobit。
