# M2 验收门 · sigminer 提取层玩具交叉验证（三方互证：msuiter vs sigminer vs 已知真值）

日期：2026-09-30。执行：计算生物学家（R 侧）。产物全部在本目录；**未修改包代码与既有测试**（新增本目录与 `tests/testthat/test-xval-m2-extract.R`）。

## 结论（先行）

**PASS。** 同一合成 counts 矩阵（96 通道 × 12 样本，3 个可分真值签名）分别进入 msuiter 默认流水线（`ms_extract(k=3)`，D16 consensus-CV）与 sigminer 2.3.1 NMF 提取（`sig_extract`，brunet/KL 默认 + 补充 `sig_auto_extract` L1KL 自动定 K）：

- 双方对真值恢复 cosine：msuiter = 0.99999 / 0.99998 / 0.99992，sigminer = 0.99999 / 0.99999 / 0.99992（判据 >0.90）；
- 双方互相 best-match cosine：0.9999991 / 0.9999999 / 0.9999962（判据 >0.95），暴露份额 cosine 同为 0.99999+；
- sigminer 自动定 K（L1KL，无 k 参数）三次独立运行均选中真值 **K=3**；
- 双方均不置换输入通道序：输出行序与输入完全一致；msuiter SBS96 注册表序 == sigminer 参考 DB 行序（复验 M1s）。

三方互证成立：同一数据、两条独立实现、一个已知真值，收敛到同一组签名。全套关键产物两次整跑**字节级一致**（确定性复核通过）。

## 环境与版本

| 件 | 版本 |
|---|---|
| R | 4.5.2 (aarch64, macOS) |
| msuiter | dev（工作树，pkgload 加载） |
| sigminer | 2.3.1（用户态库，M1s 同版本） |
| 运行成本 | msuiter 流水线 7.3 s；sig_extract 1.3 s；sig_auto_extract 0.4 s（96×12 规模） |

## 设计（bench/xval-m2/run_xval.R）

- **通道身份**：真实 COSMIC SBS96 标签，msuiter 注册表序为基准（`channel_tables[["SBS96"]]$labels`，5'-flank-major）。**序审计复验**：该序与 sigminer 自带 COSMIC v3.1 参考 DB 行序（`get_sig_db("SBS")`）逐位相同（96/96）——与 M1s「sigminer 与 msuiter 同序」结论一致，且本次把参照系从 sig_tally 输出扩到了 sigminer 的参考签名 DB。
- **真值**：3 签名 × 96 通道——每签名 27 条**独占**锚通道（不相交主导支撑，权重 0.5+U(0,1)）+ 15 条**共享**背景通道（权重 0.04，每签名背景质量占比 0.021–0.023），列归一；12 样本分 4 组×3：组 1–3 近纯（主签名暴露 800+400·U，交叉暴露 ≤30），组 4 全混合（三签名均 800+400·U）——同 helper-extract.R 的可辨识结构。counts = round(W·H)，整数，总计 18,695，每样本中位 1,056。
- **同数据进双引擎**（提取层单变量对照；tally 层 M1s 已证逐格一致，此处直接 `ms_catalog()` 构造——与 test-m2-e2e.R 同路径）：
  - msuiter：`ms_catalog(counts, channels=SBS96 registry) → ms_extract(k=3)`（默认流水线：8 初始化 KL-NMF 系综 → Hungarian 共识 → NNLS 重拟合 → SUITOR CV；engine = "nmf-pipeline"，avg stability = 1.000）；
  - sigminer：`t(counts)`（行=样本，列=通道）→ `sig_extract(n_sig=3, method="brunet", nrun=10, seed=123456)`（全部包默认）→ `$Signature.norm`；补充 `sig_auto_extract(method="L1KL", nrun=10)`（无 k 参数，自动定 K）。
- **对拍**：先各自对真值贪心最优配对求恢复 cosine；再 msuiter×sigminer 3×3 余弦网格贪心 1-1 配对；暴露份额（列归一后的 H）对配对签名逐样本余弦；判据按任务：恢复 >0.9 且互相 best-match >0.95。

## 数字全录

**恢复 vs 真值**（贪心最优配对；truth T1/T2/T3 为植入签名 1/2/3）：

| 引擎 | 配对 | cosine |
|---|---|---|
| msuiter | T1 ~ Sig1 | 0.9999900 |
| msuiter | T2 ~ Sig3 | 0.9999837 |
| msuiter | T3 ~ Sig2 | 0.9999239 |
| sigminer | T2 ~ Sig1 | 0.9999897 |
| sigminer | T1 ~ Sig2 | 0.9999896 |
| sigminer | T3 ~ Sig3 | 0.9999240 |
| sig-autoKL | T1~Sig2, T2~Sig1, T3~Sig3 | 0.99999 / 0.99999 / 0.99992（与 sigminer brunet 同配对） |

（双方把 T2 提为各自输出的第 3/1 列——NMF 列序无意义，配对按余弦贪心，属预期。）

**msuiter vs sigminer 3×3 余弦网格**（行=msuiter Sig1–3，列=sigminer Sig1–3）：

| | Sig1 | Sig2 | Sig3 |
|---|---|---|---|
| Sig1 | 0.0016 | **0.999999** | 0.0119 |
| Sig2 | 0.0007 | 0.0119 | **1.000000** |
| Sig3 | **0.999996** | 0.0040 | 0.0008 |

非对角元 ≤0.012（真值可分性传导到双方输出）。

**贪心配对 + 暴露份额**：

| msuiter | sigminer | 签名 cosine | 暴露份额 cosine |
|---|---|---|---|
| Sig2 | Sig3 | 0.9999999 | 0.9999955 |
| Sig1 | Sig2 | 0.9999991 | 0.9999938 |
| Sig3 | Sig1 | 0.9999962 | 0.9999981 |

**补充臂**：`sig_auto_extract(L1KL)`（PCAWG 式自动定 K，无 k 参数）三次独立运行均选 **K=3**；其输出与 msuiter 的贪心 best-match cosine = 1.0000 / 1.0000 / 1.0000。

**确定性复核**：真值由 SEED=20260930 生成；msuiter 流水线 seed=1（冻结）、sigminer brunet seed=123456；L1KL 无种子参数但 K 选择稳定。整脚本重跑，`cosine_msuiter_vs_sigminer.csv` 与两份 recovery CSV **字节级一致**。

## 方法评注（对拍的价值所在）

- 两者在该玩具上**不分伯仲**：恢复 cosine 差异在第 5 位小数（≤8e-6）。这是设计使然——3 签名强可分、样本近纯组钉死射线，任何正确的 KL-NMF 都应解到同一顶点；验收的意义在于**任何一方掉链子即现形**（参照 test-m2-e2e.R 注释：布局转置一类错误会把恢复 cosine 打到 ~0.35）。交叉项 ≤0.012 证明双方都停在真值顶点，没有分裂或合并成分。
- 流水线附加物按预期工作：avg stability = 1.000（8 个初始化复制全部归簇）；k_evidence 1 行（提取秩的 CV 记录）。

## 问题清单（全部发现，含非语义项）

1. **API 命名纠偏（任务简报 vs sigminer 2.3.1 现实）**：任务写 `sig_auto_extract(sig_input, k=...)`（NMF-based，brunet/kl 默认）。实测：sigminer 2.3.1 中定 k 的 NMF 提取是 **`sig_extract(nmf_matrix, n_sig, method="brunet", nrun=10, seed=123456)`**（brunet=KL，默认）；`sig_auto_extract` **没有 k 参数**（PCAWG 式自动定 K，方法 L1W.L2H/L1KL/L2KL）。本对拍以 `sig_extract` 为指定臂、`sig_auto_extract(L1KL)` 为补充臂，两条都跑。
2. **sigminer 输入/输出约定**（复验+固化）：输入为**样本×通道**（与 msuiter 的通道×样本相反）；`$Signature` 为原始尺度（列和非 1），**`$Signature.norm` 才是列归一**，`$Exposure` 行和与原始 Signature 列和一致（`Signature %*% Exposure` 可重构 counts）——归一约定与 msuiter 的显示归一（W 列和 1）同构，无需换算。输出行序**保持输入列序**（含故意乱序探针实测），不发生隐藏置换。
3. **「COSMIC 规范序」一词有两义**（文档层风险）：sigminer 的**参考 DB 行序**（legacy 与 v3.1 相同）与 msuiter 注册表序都是 5'-flank-major（A[C>A]A, A[C>A]C, A[C>A]G, A[C>A]T, A[C>G]A…，两者逐位相同）；但 bench/xval/run_xval.R 里 M1s 脚本本地构造的 CANON 循环（type→5'→3'）是 **type-major**，与真序在 88/96 位不同——M1s 对拍靠标签对齐未受影响，但其脚本注释「COSMIC order: 3' fastest, 5' second, type major」对 msuiter 实际注册表序的描述是**错的**（序审计是真序=5'-flank-major）。建议后续把 M1s 脚本的 CANON 构造改为读注册表（不影响已固化测试 test-xval-sigminer.R：其断言全部按标签对齐 + expect_equal(labs_ms, labs_sg)，真序无关）。**非包代码语义差，无需改动我方。**
4. **sig_auto_extract 无种子参数**：K 选择在 3 次重跑中稳定为 3（本数据上无碍），但严格可复现性依赖数据充分可分；对拍判据不依赖该臂，仅作补充。
5. **对我方的肯定项**：D16 默认流水线（系综→共识→NNLS→CV）在 96×12 上 7.3 s 完成，签名矩阵、暴露矩阵、标签装配（rownames=注册表序、Sig1..k）、列归一约定全部与 sigminer 独立实现收敛；`ms_extract` 对 ms_catalog 直构目录（name="SBS96"+真实标签）无隐藏校验障碍，测试路径可直接复用。

## 产物清单

- `run_xval.R` / `run.log`：可复现脚本与完整运行日志（`Rscript bench/xval-m2/run_xval.R`，<15 s）。
- `truth_signatures.csv` / `truth_exposures.csv` / `truth.rds`：真值设计（种子 20260930）。
- `counts_input.csv`：喂给双引擎的同一整数 counts 矩阵（96×12）。
- `cosine_msuiter_vs_sigminer.csv`：3×3 余弦网格；`pairing_msuiter_sigminer.csv`：贪心配对 + 暴露份额 cosine。
- `recovery_msuiter.csv` / `recovery_sigminer.csv`：各自对真值的恢复余弦。
- `cosine_msuiter_vs_autoKL.csv`：补充臂（L1KL 自动定 K）对拍网格。
- `sigminer-auto/`：sig_auto_extract 的结果文件（destdir）。
- `tests/testthat/test-xval-m2-extract.R`：固化回归（skip_if_not_installed("sigminer")，断言恢复 >0.9 + 互相 best-match >0.95 + 通道序不置换）。
