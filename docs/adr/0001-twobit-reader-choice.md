# ADR 0001：2bit 读取器选型——采用 `twobit` crate（over `Cursor<Mmap>`）

- 状态：accepted（2026-09-28）
- 裁决单元：U-M0-02 M0 spike（W1 硬截止）
- 上游依据：ARCHITECTURE.md §0 D7、§2（catalog/genome.rs 条目）；reviews/00-synthesis.md §4 末条（02#11：两案都试，以 byte-swap/大端验证结果定案，默认倾向 crate）
- 解锁：workspace 依赖预算中 `twobit` 的预留位（D7）；`catalog/genome.rs`（U-M1s-08）

## 1. 背景

`ms_tally()` 的 Rust 快路径需要按染色体随机访问 2bit 参考基因组（进程内 mmap 即用即释，D12 无状态）。D7 预留两案，本 ADR 以实验证据裁决：

- **方案 A（crate）**：第三方 `twobit` crate 包裹内存映射缓冲（`Cursor<Mmap>` 形态）。
- **方案 B（自研）**：244 行自研 reader（零新增依赖）。

## 2. 实验设置（可复现）

实验 crate 位于 `tools/spike/twobit-spike/`（随本 ADR 入库作可复现证据；独立 `Cargo.toml` + `[workspace]` 隔离，非包 workspace 成员，R 包 tarball 经 `.Rbuildignore` 排除），三个组件：

1. **夹具生成器**（`src/fixture.rs`）：从逻辑内容确定性生成完整 2bit 文件（magic 0x1A412743、version 0、多染色体索引、4-bit 打包碱基 T=0/C=1/A=2/G=3 首碱基居高位、N block、mask block、reserved），同时产出**大端布局变体**（全部 u32 字段字节序翻转）与逐位真值（序列含 N 替换、soft-mask 小写变体、block 坐标、chrom 尺寸）。夹具覆盖：尺寸非 4 倍数（chr1=1003、chrM=17、chr2=4000）；N block 在位置 0、中部、跨文件尾、相邻两块；soft block 与 N block 重叠（N 优先，与 crate 的后处理次序一致）。
2. **两案 reader**：A = `twobit::TwoBitFile::from_buf(...)`（含 `Cursor<&Mmap>` 实测）；B = 自研原型（`src/own.rs`，244 行，同为 `AsRef<[u8]>` 零拷贝解析 + 按染色体偏移随机访问）。
3. **测试矩阵**（`tests/spike.rs`，7 条）：{小端, 大端} × {crate, 自研} 全量真值逐位比对（全序列 + 8 个窗口/染色体 + N/soft block 坐标 + chrom 尺寸 + softmask 开关）＋ 双 reader 互检 ＋ `Cursor<&Mmap>` 形态（真实文件 mmap）＋ 坏 magic 拒绝。

**byte-swap/大端验证口径**：同一逻辑内容的小端与大端文件必须被 reader 正确解析且输出逐位一致（大端主机正确性的可检验代理）。`twobit` crate 通过 magic 及其反序值（0x4327411A）自动检测并翻转全部 u32 字段。

## 3. 实验结果

| 测试 | rustc 1.97.1（stable） | rustc 1.71.0（MSRV） |
|---|---|---|
| crate × 小端 = 真值 | pass | pass |
| crate × 大端 = 真值 | pass | pass |
| 自研 × 小端 = 真值 | pass | pass |
| 自研 × 大端 = 真值 | pass | pass |
| crate ≡ 自研（双布局，序列+block 坐标） | pass | pass |
| crate over `Cursor<&Mmap>`（双布局，真实文件 mmap） | pass | pass |
| 双 reader 拒绝坏 magic | pass | pass |

`cargo test` 7/7 全绿（两套工具链各跑一遍）。过程中发现并修复的口径问题：索引记录 `nameSize` 按 UCSC 规范为 **1 字节**（非 u32）——crate 实现正确，夹具初版有误已修正，两者在该语义上一致。

## 4. 裁决维度

| 维度 | 方案 A：twobit 0.2.2 | 方案 B：自研 |
|---|---|---|
| License（D1） | **MIT**（Bethune & Smirnov），非 GPL ✓ | 无 |
| 运行时依赖 | **0 个** | 0 个 |
| MSRV | 无声明；**实测 1.71.0 编译+测试通过**（随行 libc 0.2.189、memmap2 0.9.11 亦通过） | 实测 1.71 通过 |
| API 契合（Cursor<Mmap> 流式 + 按染色体随机访问） | `TwoBitFile::from_buf(&mmap)`（`Cursor<&Mmap>: Read+Seek`，零拷贝）；header/index 一次解析，序列按偏移随机访问；`read_sequence(range)`/`chrom_names/sizes`/`hard_masked_blocks`/`soft_masked_blocks`/`base_counts`/`enable_softmask` | 同等能力已原型验证，但全部自担维护 |
| 大端/byte-swap | 内建检测，实验逐位通过 | 自实现，实验逐位通过 |
| 维护活跃度 | 0.2.2 发布于 **2026-03-27**（一年内更新，修复大端读等）；2020 年起 5 个版本；repo github.com/jbethune/rust-twobit；crates.io 下载 ~14.8k | 生命周期成本全部自担 |
| 体积/影响面 | 24.7 KB 源码，1554 行，vendor 增量 ~0.09 MB 未压缩（xz 后 +0.017 MB，见 ADR 0002） | 0 |
| 注意点 | crate 内部含 `unsafe { String::from_utf8_unchecked }`（ASCII 可证安全）；仅存在于依赖内部，engine/catalog 仍 `#![forbid(unsafe_code)]`；错误走 `Result`（坏 magic 实测干净拒绝，不 panic） | 无 |

## 5. 决策

**采用方案 A：`twobit` crate（version 0.2.2，`twobit = "0.2.2"`）**。默认倾向 crate 的先验被证据确认：license 干净、零运行时依赖、MSRV 实测达标、API 与 ARCH §2 的 `Cursor<Mmap>` 形态逐字吻合、维护活跃。

依赖解锁记录（D7 预留位）：
- `src/rust/Cargo.toml` `[workspace.dependencies]` 新增 `twobit = "0.2.2"`；
- `src/rust/catalog/Cargo.toml` 声明 `twobit = { workspace = true }`（genome.rs 实现属 U-M1s-08，本单元不动其余部分）；
- `deny.toml`：审核修正后全量 `cargo deny check` 绿——licenses 白名单补 `Unicode-3.0`（unicode-ident 的 `(MIT OR Apache-2.0) AND Unicode-3.0`）、三个 crate manifest 补 `license = "Apache-2.0"`（消除 unlicensed）、advisories 采 `unmaintained = "workspace"` 策略（paste RUSTSEC-2024-0421 经 extendr-api 0.9 传递、我方不可修，不阻断；升级 extendr-api 时复查全量 check，清单进 U-M0-08 CONTRIBUTING）；ban 规则不受影响。

**回退条款**：依赖随 vendor 钉死（ADR 0002），供应链风险有界。若上游停止维护且阻塞升级，方案 B 的自研原型（244 行 + 本 ADR 接口契约，`tools/spike/twobit-spike/src/own.rs`）为已验证的回退路径，切换只影响 `catalog/genome.rs`。

## 6. U-M1s-08 接口契约（自研回退或封装时遵守）

- 输入：`AsRef<[u8]>` 缓冲（mmap 即用即释，D12 无状态）；header/index 一次解析，序列按 `(offset, i/4)` 随机访问。
- 字节序：magic==0x1A412743 → 原样；magic==0x4327411A → 全部 u32 字段 swap；索引 `nameSize` 为 1 字节。
- 解码：2 bit/碱基，字节内首碱基居高位，T=0/C=1/A=2/G=3；N block 解码后置 'N'，soft block 再小写化（次序固定）；N block 的打包位为 don't-care。
- 错误：`Result<_, E>`，格式错误不 panic；版本 ≠0 拒绝。

## 7. 残留

- 本实验仅 macOS arm64（R 4.5.2，xz 5.6.4，rustc 1.71.0/1.97.1）；Linux/Windows 上的大端无关性由同一测试矩阵在 U-M0-07 CI 矩阵承接（测试可移植，实验 crate 已随本 ADR 入库，`tools/spike/twobit-spike/` 内 `cargo test` 直接复跑）。
- 实验 crate 发布 tarball 不含（`/tools/spike` 已入 `.Rbuildignore`）；`tests/spike.rs` 的比对口径在 U-M1s-08 落地为 `catalog/genome.rs` 的正式测试（与 BSgenome 对拍另计）。
