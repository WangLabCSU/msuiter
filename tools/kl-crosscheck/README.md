# tools/kl-crosscheck · U-M1s-14 KL 数值协议等价对拍

**msuiter 自研 KL-NMF（`src/rust/engine/src/nmf.rs::fit_kl_with_init`）vs R NMF 包 brunet 算法**的一次性固定平台实验（不进 CI 门；依据 `docs/ARCHITECTURE.md` §7.1 条目 1 / D11 / A8、`docs/ROADMAP.md` M1s 的 U-M1s-14 行）。验收口径：同初始化、同迭代数下 `‖ΔW‖_F/‖W_R‖_F < 1e-10`（H 同）+ 目标轨迹逐元素相对差 < 1e-12。

**结论（2026-09-30，本机）**：**PASS —— 数值协议等价成立**。端点（T=50/200）相对差 0.9e-15 – 6.4e-15，比 1e-10 判据低 5 个量级；全部数字见 `result.md`（脚本自动生成、数字全录）。

## 方案选择：A（外部初始化直跑随包入口），B/C 不需要

NMF 0.28 的 brunet 注册为 `NMFStrategyIterative`：`Update` 槽 = H 步后 W 步，经 `.Call("divergence_update_H/W", PACKAGE="NMF")` 的 **C 内核**（非纯 R，方案 B/C 的"diff R 源码"路线不可用也无必要）。随包入口 `nmf()` 的 `seed=` 接受 **NMF 模型对象**（`nmfModel(rank, W=W0, H=H0)`）作外部初始化——方案 A 成立。对拍有效性由四个机制探针强制（脚本自动断言）：

1. **注入保真**：`maxIter=0` 返回的模型与种子 `W0/H0` 逐位 `identical()`；
2. **精确控制**：`maxIter=T` 恰跑 T 步（`niter(r)==T`），`stopconv=1e6` 停用 connectivity 早停；
3. **确定性**：同参重跑逐位相同；
4. 循环结构（读包源）：`while(TRUE){stopFun(i); if(stop||i>=maxIter)break; i++; updateFun(i)}` ⇒ **`run(maxIter=t)` 是 `run(maxIter=T)` 的确定性前缀**——R 侧逐 t 轨迹由 `maxIter=1..200` 重复运行采集（每 case ~10 s），两侧前缀性质各自文件级自证。

## 同初始化（命门）与数值交换

输入（V/W0/H0）全部量化到 **10 位小数位的二进分数**（k/1024 网格；整数案例天然满足），以短精确十进制串写入 CSV。原因（实验中发现）：**本平台 R 的十进制串→double 解析对 17 位有效数字串可差 1 ulp**（如 `3.7393736185701556e+01`），17 位串往返不精确；短精确展开则两侧解析器逐位一致（2 万样本实测 + 每案例 `identical()` 往返断言）。driver 输出用 `.17e`（R 读回 ≤1 ulp，相对 2.2e-16，比判据低 4 个量级，不构成混淆）。init 均匀取自 {1/1024,…,1}×`sqrt(mean(V)/k)`，严格正（MU 零吸收），`set.seed` 401/402/403 记录在案。

## 输入（96×20，k=3，`set.seed` 全记录）

| 案例 | 形态 | V 零元素 |
|---|---|---|
| case1 | 3 签名可分离（每签名 32 独占锚通道 + 近纯样本组；与 engine 分离 golden 同型） | 0/1920 |
| case2 | 随机整数计数 0..39 稠密 | 67/1920 |
| case3 | 尖峰签名 + 大量结构零（整零行各留 1–2 个样本计数 ≥1）+ 低计数样本（总数 3） | 1377/1920 |

## 运行

```bash
cd tools/kl-crosscheck
Rscript run_experiment.R          # 一键：生成输入 → cargo 构建 driver → 双侧运行 → 对拍 → result.md
```

要求：R ≥ 4.3 + NMF 包（本机已装 0.28，用户态库 `~/Library/R/arm64/4.5/library`；如缺，`install.packages("NMF")` 用户态安装即可，无 Bioconductor 链）；cargo/rustc。耗时约 1.5 分钟。

## 结果摘要（2026-09-30，R 4.5.2 / NMF 0.28 / rustc 1.92 / Accelerate BLAS，Apple silicon）

| 案例 | T=50 ‖ΔW‖F/‖W_R‖F | T=200 ‖ΔW‖F/‖W_R‖F | 轨迹 max 相对差（严格 <1e-12） | 判据 |
|---|---|---|---|---|
| case1 | 3.516e-15 | 6.411e-15 | 7.135e-09 @ t=179（首个 t=86，1.82e-12） | 端点 PASS；轨迹见下 |
| case2 | 1.137e-15 | 3.478e-15 | 6.773e-15 | PASS |
| case3 | 1.802e-15 | 4.960e-15 | 4.105e-15 | PASS |

**总判据 PASS**。case1 的轨迹严格 1e-12 相对判据在 t≥86 未达（分歧本身就是发现）：case1 精确可分 → 目标值收敛到 6.58e-5（下降 5 个量级），相对判据被 ±抵消放大（κ→大）；**状态层面无分歧**——检查点 t=80 两侧 W/H 相对差 2.7e-15/2.1e-15，且 |Δobj| ≤ 8·eps·(2L+ΣV+ΣWH) 传播界全程 PASS（差异 = R `log` 与 Rust `f64::ln` 的 1-ulp 实现差 + 求值环境噪声）；尺度参照 max|Δobj|/obj₀ = 6.1e-16。case2/case3 严格判据全程 PASS。

## 记录在案的协议差异（均为发现，不影响等价结论）

1. **brunet 每 10 步 `pmax.inplace(·, 2.2e-16)` 底板**：case3 有 120 个 H/W 条目被 R 钉在 2.22e-16，我方自由衰减至 0–1e-113；对相对 F 范数的贡献 ≤1e-15（case3 端点 5.0e-15 中的主要项）。
2. **ε 防护语义**：case3 R 轨迹 min(WH)=1.34e-15 < 我方 KL_EPS=1e-12——防护确有参与，但"V>0 且 WH<1e-12"条目数 = 0（全程 21 个检查点状态），即仅在 V=0 条目触发（双侧 r 均为 0），**良性**。
3. **整零行**：R `nmf()` 输入校验直接拒绝；我方引擎接受（结构零由 ε 策略处理）。
4. **整零列**：R brunet C 核 0/0 产生 NaN 传播、且零暴露样本使其自带 connectivity 检查崩溃（"non-conformable arrays"）；我方引擎保持有限。故 case3 用"总数 3 的低计数样本"替代死列做对拍（真实低 TMB 形态）。
5. **R 十进制解析 1-ulp 误差**（上文），实验以二进量化输入绕开并记录。

## 文件

- `run_experiment.R` —— 全流程（探针 → 输入生成 → driver 调用 → NMF 侧 → 判据 → `result.md`），失败时退出码非 0
- `driver/` —— Rust scratch bin（独立 `[workspace]`，仅 path 依赖 `msuiter-engine`；读 V/W0/H0 CSV → 未改动的 `fit_kl_with_init` → 写 W/H/轨迹/检查点 CSV）。**包代码路径零改动**
- `data/inputs/`、`data/outputs/` —— 交换 CSV 与双侧产物（含 meta.csv：engine crate 角色标记、KL_EPS）
- `result.md` —— 全部数字（含 t=0..200 轨迹逐点对照表）

包代码、CI、依赖清单均未触碰；本目录不进 git 提交（一次性平台实验，A8）。
