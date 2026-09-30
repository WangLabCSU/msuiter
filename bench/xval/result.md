# M1s 验收门 · sigminer / MutationalPatterns 玩具交叉验证（SBS96）

日期：2026-09-28。执行：计算生物学家（R 侧）。产物全部在本目录；**未修改包代码与既有测试**（仅新增本目录、`tests/testthat/test-xval-sigminer.R`、DESCRIPTION Suggests 追加两条、`bench/xval/README.md`）。

## 结论（先行）

**PASS — 逐格一致。** 在 264 条玩具 SNV、3 样本、真实 hg19 参考窗口上，msuiter 的 SBS96 目录与 sigminer 2.3.1、MutationalPatterns 3.20.1 以及一个纯 R 独立重算（第四方）在 **96 通道 × 3 样本 = 288 格上完全一致（6 组两两对拍全部 IDENTICAL，0 不一致格）**。ROADMAP M1s 金标准夹具行「sigminer/MP 玩具交叉验证」完成；MP 为可选项，本次已安装并纳入对拍。

## 环境与版本（如实记录）

| 件 | 版本 |
|---|---|
| R | 4.5.2 (aarch64, macOS) |
| msuiter | dev（工作树，U-M1s-13 + 会话内并行落地的 `n_threads` FFI 修复；pkgload 加载） |
| sigminer | 2.3.1（CRAN，作者自有包） |
| MutationalPatterns | 3.20.1（Bioconductor；本次会话新装，二进制耗时 < 1 min，远低于 30 min 时间盒） |
| 参考基因组 | BSgenome.Hsapiens.UCSC.hg19（三方共读同一 hg19 序列） |

## 玩具变异集设计（bench/xval/run_xval.R）

- 参考窗口（真实 hg19，ACGT-only 已验证）：chr1:1,000,001–1,200,000、chr7:55,000,001–55,250,000、chr12:10,000,001–10,100,000（合计 550 kb）。三条窗口序列经与 helper-tally.R 同款打包契约（T=0 C=1 A=2 G=3，高位在先）写成 `patch_hg19.2bit`，作为 msuiter 侧参考；sigminer/MP 侧直接读 BSgenome。**同一条 hg19 序列经三条不同读取路径进入三个引擎**——一致即同时交叉验证了 2bit 语境抽取。
- 264 条 SNV：96 条**定向**（COSMIC 96 通道每通道恰好 1 条，样本 S1/S2/S3 轮转 → 每样本 32 条）+ 168 条种子随机（中心碱基限 C/T）。同染色体最小间距 3 bp（跨样本），排除相邻 DBS 合并与 ±1 侧翼污染。每样本 88 条。
- REF 全部取自真实基因组（构造保证），并二次断言。

## 对拍结果

**通道词汇审计**（先集合后逐格——拼写差不允许变成错位假一致）：

| 引擎 | 标签数 | 集合=msuiter | 顺序=msuiter |
|---|---|---|---|
| msuiter | 96 | TRUE | （基准） |
| sigminer 2.3.1 | 96 | TRUE | **TRUE** |
| MutationalPatterns 3.20.1 | 96 | TRUE | FALSE（type-major，88/96 位不同） |
| naiveR（纯 R 重算） | 96 | TRUE | FALSE（与 MP 同为 type-major——其矩阵与 MP 逐字节相同，佐证两者同序） |

**数量审计**：四引擎每样本列和均为 88/88/88（=输入）；六替换类列和均为 44/43/46/44/43/44（C>A/C>G/C>T/T>A/T>C/T>G）。

**逐格（按标签对齐）**：6 组两两比较（msuiter×sigminer、×naiveR、×MP，及三者互相）**全部 IDENTICAL**，合计 0 个不一致格。无「拼写映射问题」需要归因——集合与逐格双双为空差。

**覆盖度（防平庸一致）**：96/96 通道至少 1 条；288 格中 178 格非零（单格最大 4）。一致性建立在全通道被刻意击中的网格上，不是只在热点通道上碰巧相同。

## 「如何确认不是假一致」（方法论）

1. **先比标签集合、再按标签对齐比网格**——通道拼写/顺序差不可能产生幻影一致或幻影噪声（审计表留档 `label_audit.csv`）。
2. **每通道定向放置 1 条变异**：相等性覆盖全部 96×3 格，而非稀疏命中的子集。
3. **第三方独立重算**（naiveR）：从抽出的序列用 ~15 行 base R 直接折叠计数，与两个包都不同源；三方同值 ⇒ 假一致需要三方共谋。
4. **数量双重核对**：每样本列和与 6 类列和都对回输入变异表。
5. **读取路径独立**：msuiter 读自家 2bit，sigminer/MP 读 BSgenome——2bit 打包/解码错一处即破。
6. **敏感性对照（腐蚀记录探针）**：故意放一条 REF 与基因组不符的变异，msuiter 立即跳过而 sigminer/MP 照计（见下）——证明该对拍对语义差异是敏感的，不是橡皮图章。

## REF 不匹配语义探针（问题清单之核心发现）

人工构造：位置 1 REF 正确；位置 2 真实碱基 G 但 MAF 声称 C（alt=G）。

| 引擎 | 计数 | 行为 |
|---|---|---|
| msuiter | 1/2 | 校验 REF vs 基因组，坏记录按 `ref_mismatch` 跳过（SPMG 语义，skip 台账留痕） |
| sigminer 2.3.1 | **2/2** | 不校验；以**声称的 REF** 为中心、基因组只供侧翼 → 坏记录被计入伪通道 C[C>G]G |
| MutationalPatterns 3.20.1 | **2/2** | 同 sigminer（同样把坏记录计入 C[C>G]G） |

判定：**稳健性差异，非 SBS96 网格语义差**——输入干净（REF=基因组）时零分歧。sigminer/MP 的行为会把坏 REF 静默错记通道，msuiter 的 skip 是更安全（也更可解释）的策略；上游如实记录即可，无需改动我方语义。

## 问题清单（全部发现，含非语义项）

1. **通道顺序**：MutationalPatterns 3.20.1 的 96 通道序为 type-major（C>A 块内 5'×3'），与 msuiter/sigminer 的 5'-context-major 在 88/96 个位置上不同。sigminer 2.3.1 与 msuiter **顺序完全相同**（本次实测）。任何与 MP 的按位置对拍都是错的——必须按标签对齐（本对拍即如此）。
2. **REF 校验缺失（上游）**：见上节。sigminer 2.3.1 与 MP 3.20.1 均不校验 REF；作者自有包，照实记录。
3. **sigminer 2.3.1 API 边角**：(a) `keep_only_matrix=TRUE` 直接返回矩阵且为 samples×channels（与 msuiter 的 channels×samples 相转置）；(b) 变异极少时 APOBEC 富集 Fisher 步骤在 `apply()` 上抛 "dim(X) must have a positive length"（< ~10 条 SNV 复现），报错信息不指向根因；(c) `read_maf` 是 `maftools::read.maf` 薄包装。
4. **MutationalPatterns 3.20.1 缺陷**：`GRanges` 的 ALT 用普通 `DNAStringSet` 时 `mut_matrix()` 在 `.find_substitution` 崩溃（`width(unlist(alt))` 对 `DNAString` 无方法，88 条时必现、2 条时偶过）；必须给 VCF 式 `DNAStringSetList`（每记录一元素）。另外 genome 元数据必须置 "hg19"。
5. **会话内瞬态（诚实记录）**：对拍中途工作树出现 FFI 不一致——`extendr-wrappers.R` 已重生成为必传 `n_threads` 而 `.ms_tally_rust` 未同步传参 → `ms_tally()` 报错；由并行会话约 1 分钟内修复，本对拍与测试均在修复后的树上运行。该状态与我方产物无关，但说明 ms_tally 的 FFI 契约变更需要 R/Rust 双侧同步的守护（现有 ffi-surface-drift 测试是正确方向）。
6. **对我方的肯定项**：通道标签拼写、COSMIC 排序、折叠（嘧啶定向）语义、样本对齐、2bit 语境抽取，全部与两个独立上游实现逐格一致；测试 `tests/testthat/test-xval-sigminer.R` 已将 96 通道 ×3 样本网格 + 纯 R 三方 + 顺序审计固化为回归守护（sigminer/BSgenome 缺席时自动 skip，CI 零负担；两者已按任务许可加入 DESCRIPTION Suggests）。

## 产物清单

- `run_xval.R` / `run.log`：可复现脚本与完整运行日志（`Rscript bench/xval/run_xval.R`，~1 min）。
- `variants.csv`：264 条玩具变异（hg19 全局坐标）。
- `patch_hg19.2bit`：msuiter 侧参考补丁基因组。
- `counts_{msuiter,sigminer,naiveR,MP}.csv`：四引擎 96×3 计数矩阵。
- `label_audit.csv`：通道集合/顺序审计表。
- `README.md`：运行说明。
