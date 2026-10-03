# 设计备忘 · M3b MSU-Fit 校准统计（2026-10-04）

> 状态：**草案 v1.0，待 PI 裁决**（裁决项见 §7 三个分叉点；实现等裁决后派单，本备忘不改任何代码）。
> 作者：mutational-signature 方法学专家 agent。
> 输入证据链：ARCHITECTURE.md §5 MSU-Fit 行（L221）/ §7（L245–247）、ROADMAP.md M3b（L80–84）、research/02 §2（L83–94）、research/07（L32/L152）、devlog 2026-10-01/02/03（M3a-01/04–06、bootstrap P1-B、presence P0 校准矩阵）、源码行号见文内。
> 前哨验证：M3a-03 presence 池化零分布 P0 修复后，H0 校准矩阵 n=1..16 全落 [0.02, 0.08]（devlog 2026-10-03；Rust/R 双面）——estimand ① 的校准实证已就位，M3b 把同一纪律推广到 ②③。

---

## 0. 任务一句话

把已就位并被独立校准验证的原语（bootstrap、presence 池化零分布、BH、Fisher SE）**编排成校准统计**：exposure CI 的经验覆盖率测量（BCa/分层 calibrated-percentile）、双生成模型（多项主臂 + NB Jiang 色散 stress 臂）、CI 清零复合覆盖率、高 TMB 降采样 sanity。论文 headline v1.0 的主战场（D14 Framing A）。

---

## 1. Estimand ②：magnitude 落地规格

### 1.1 Estimand 定义（D13 四件套之一）

**支撑条件下的绝对 exposure**：对点拟合支撑 `support=1` 的签名 a，参数为 `h*_a = E[归因于 a 的突变数]`（计数尺度，样本 j 的 rescale=TRUE 总量标度）；CI 的目标事件是 `h*_a ∈ [ci_lo, ci_hi]`，**以真值支撑含 a 为条件**。成分版（`h*_a/Σh*`）并行报告（research/02 §2 行 94 成分数据原则：区间应尊重单纯形几何——v1.0 先以 share 口径另报，log-ratio 变换留 MSU-LowCount/Infer）。真值支撑不含 a 的格子属于 estimand ③ 的复合流程，不进 ② 的边际覆盖率主表（否则"边界参数给区间"的纪律被自己破坏）。

### 1.2 BCa vs 分层 calibrated-percentile：选择判据（分叉点 1）

理论排序（Hall 1988, Ann. Statist. 16(3):927–985, doi:10.1214/aos/1176350930）：percentile 误差 O(1/√N)（一阶精确），BCa O(1/N)（二阶精确）（Efron 1987, JASA 82:171–185, doi:10.1080/01621459.1987.10478410；DiCiccio & Efron 1996, Statist. Sci. 11:189–228, doi:10.1214/ss/1177009928）。**关键成本事实：BCa 不需要新重采样**——bias 校正 z₀ = Φ⁻¹(#{boot < 点估计}/B) 直接来自现有 boot 样本（`bootstrap()` 已产出，src/rust/src/fit.rs:1167）；加速度 a 走**固定 active set 的解析影响函数**（infinitesimal jackknife，非逐突变 leave-out）：支撑 A 上 `h_A = G_A⁻¹ b_A`（interior 解），通道 c 的影响 `u_c = G_A⁻¹ s_A[c]`（k 维向量，权重 = 通道计数），`â = Σ(u_c−ū)³ / (6(Σ(u_c−ū)²)^{3/2})`——每次一个 pivoted LDLᵀ 复用 engine/linalg，成本近零。**推荐默认 = BCa，percentile 只作退化回退**（判据见下），分层 calibrated-percentile 作升级臂。

冻结判据表（阈值进 FFI 常量、协议文档同源）：
| 测量 | 条件 | 动作 |
|---|---|---|
| \|ẑ₀\| < 0.1 ∧ \|â\| < 0.05 ∧ support_stability ≥ 0.95 | 校正量小于 B=1000 时界的 MC 噪声 | percentile 够用（BCa 退化形式 z₀=a=0，type-7 百分位即 `percentile_sorted`，fit.rs:1388） |
| \|ẑ₀\| ≥ 0.1 ∨ \|â\| ≥ 0.05 | 偏度/偏差可见：小 N、真值 share 邻近清零阈 0.01、flat 签名（Medo 2024 doi:10.1038/s41467-024-53711-6 Fig 1c：SBS5/40 型全 N 系统性低估） | BCa |
| 退化：z₀ = ±∞（boot 全侧）∨ \|â\| > 0.2 ∨ stability < 0.9 | active set 不稳、影响函数失效 | 回退 percentile + 显式 flag 列 |
| 多项主臂 BCa 后仍偏窗 | 残差为系统性水平误差（非有限样本阶） | 分层 calibrated-percentile（Beran 1987 prepivot, Biometrika 74:457–468, doi:10.1093/biomet/74.3.457）：按 (N 档 × H* 档) 蒙特卡洛再校准名义水平 ℓ_s，校正表随包发布 + log-N 线性内插规则冻结。**注意：这不是 conformal**（§6） |

### 1.3 N × Shannon 熵网格（格点、格数、判据窗）

- **N 轴（对数 11 点）**：{50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000}——钉住 mSigAct 丢弃线 100（research/02 §1.2 行 44）、社区门槛 50/200（行 110）、Medo 关键区 10²–10⁴（行 111）、PCAWG 高 TMB 5·10⁴+（ARCH §8 场景网格 10²–10⁶ 的可落地上界）。
- **熵轴（归一化 Shannon 熵 3 档）**：`H* = −Σ p_i ln p_i / ln(supp)`（supp = 非零支撑通道数）；peaked < 0.5 / medium 0.5–0.75 / flat > 0.75。真相字典：合成签名库（每档 ≥2 签名，含 Medo 对抗对：1000 SBS3 型 + 少量 flat，research/02 §3 行 102）+ COSMIC v3.6 锚（SBS1 / SBS5）。
- **share 轴（estimand ② 专属 6 点）**：{0.005, 0.01, 0.02, 0.05, 0.10, 0.25}——0.01 清零阈两侧必布。
- **格数**：11 × 3 × 6 = 198 cell × 2 生成模型臂；M = 2000 reps/cell（0.95 名义下 4SE = 4·√(0.95·0.05/2000) ≈ 0.0195 → **判据窗 [0.930, 0.970]**，与 presence 惯例同构造，M3a-03 用 M=1000 时窗 [0.022, 0.078] 报作 [0.02, 0.08]）。边界格（share ≤ 0.02）加跑 M = 4000 复核批。预算核算：字典 Gram 常量跨 reps 复用，NNLS k≤10 每 solve ~10 µs，全网格 ~4×10⁸ boot 拟合 ÷ 16 线程 ≈ 分钟级——Rust 校准使"全网格"买得起（D14 叙事自证）。

---

## 2. 双生成模型校准协议

### 2.1 臂 A（多项，主臂 = 校准声明载体）

`counts[:,j] ~ Multinomial(N_j, p_j)`，`p_j = (W* h*)_j / Σ(W* h*)_j`，直接复用 `engine/resample.rs::multinomial`（累积 CDF 反转、恰 N 个流字）。流布局扩展（须进论文 Methods，PCG64 布局 v1 之上）：`StreamId { replicate: MC_rep, rank: grid_cell_id, fold: 0 }`——与 bootstrap（rank=0）和 CV（fold≥1）流不相交。拟合走**生产面**：`likelihood_bidirectional`（旗舰法，冻结 `FIT_EPS=0.001`/`FIT_MAX_ITER=1000`，fit.rs:1096/1102）+ `zero_threshold=0.01` + `rescale=TRUE` + bootstrap(B=1000) + CI 面。主臂失败 = 我们自己的模型假设下失准，必须修（§2.3）。

### 2.2 臂 B（NB，Jiang 色散 stress 臂）

Jiang 协议语义（bbaf042, Brief Bioinform 26(1):bbaf042；research/07:32："合成谱 = **负二项通道采样**、色散校准到真实重构精度"）：`counts[:,i] ~ NB(μ_i = (W* h*)_i, size = κ)` 逐通道独立——这正是 mSigAct 似然族（`nb_ll`，engine/likelihood.rs:422；size 锚 8/50/100 已冻结 L373–377）。**色散校准规格**：κ 主锚 = 8（SBS96 mSigAct 默认）；真实校准程序 = 用 COSMIC v3.6 拟合真实目录 → 逐通道残差 `E[(x−μ)²] = μ + μ²/κ` 反解 κ（按 TMB 档分箱报告）→ 与 8 对比记录；敏感性扫 κ ∈ {2, 8, 50, 200, Poisson 极限}。

**NB 采样原语缺口（分叉点 2）**：`resample.rs` 模块文档明示 *"Deliberately absent: negative-binomial calibration sampling (Jiang protocol — U-M3a)"*（resample.rs:88–90）——**原语不存在**（任务书说"给 M3a-04 补"，但 M3a-04 已于 2026-10-02 交付 assign+TSB，缺口落 **U-M3b-01 新引擎单元**）。规格：gamma–Poisson 组合采样——γ ~ Gamma(κ)（κ≥1 Marsaglia–Tsang 2000, ACM TOMS 26:363–372, doi:10.1145/358407.358414；κ<1 Ahrens–Dieter 1974）→ Poisson(γ·μ/κ 归一)（大 μ 反转法，Devroye 1986 锚，与 resample.rs 现行引用系一致）；**流字消耗契约必须写明**：拒绝采样字数数据依赖，但仍是流的纯函数（冻结种子可复现），与多项"恰 n 字"契约的差异逐字记录进模块头。备选构造（NB 总数 + 多项分裂，保总量）**不推荐为主臂**：它匹配的不是 mSigAct/Jiang 的逐通道似然族，混入会污染 stress 臂的解释。性质测试：Poisson 极限单调、Var = μ+μ²/κ 经验核对、跨流位级 golden。

### 2.3 覆盖率曲线读法与失败处理

- **读法**：每 (cell × 臂) 一条覆盖率 vs N 曲线、按 H* 档分面；两臂必须分别过窗才可对各自臂措辞（§6）。臂 B 预期欠覆盖（过散未被拟合方差吸收）——曲线形态本身是交付物：欠覆盖随 κ 减小加深的斜率 = MSU-LowCount conformal 的动机定量版（交叉引用，不混谈）。
- **失败处理阶梯**（臂 A 内）：
  1. percentile → **BCa**（z₀/â 修一阶偏差/偏度）；
  2. BCa 仍偏窗 → **分层 calibrated-percentile**（(N×H*) 层内再校准名义水平，Beran prepivot 语义；校正表 = 包数据 + 冻结内插）；
  3. 分层后仍偏窗 → **判定为估计器缺陷而非区间缺陷**（rescale 交互、清零抖动、欠拟合字典质量缺失——M3a-03 P1-B 的教训：boot 与点拟合标度必须同源）→ 回估计器修复，**禁止用加宽区间掩盖**。
- 臂 B 失败不作修复触发，只作 stress 报告 + D13 措辞门（§6）；若 PI 想要"NB 校准版"分层表，须作为独立可选输出，且文档明示它是对 stress 模型校准（防 double-dipping）。

---

## 3. CI 清零复合覆盖率（estimand ③）

挂点：likelihood.rs 模块文档明示 *"the CI-lower-bound face needs intervals (U-M3b) and is deliberately absent"*（likelihood.rs:36–39）；sigfit 锚 `SIGFIT_ZERO_SHARE = 0.01`（L608），三清零锚已审计（L608/612/616）。

**复合决策规则（冻结提案）**——用户最终拿到的清零 = 管线全序合取：
```
final_zero_a = (点拟合 share_a < 0.01)                    # 现行 zeroing_mask_share，L630
             ∨ (support_stability_a < 0.95)               # 新：boot 支撑不稳
             ∨ (ci_lower_share_a < 0.01)                  # 新：CI 下界面（sigfit/Medo 语义）
ci_lower_share_a = ci_lower_abs_a / totals_j
```
（boot 列已过同一 `rescale_to_totals` 对齐 totals_j（P1-B 修复，devlog 2026-10-02/03），故 share 界 = 绝对界除以常量，type-7 插值次序不变。）

**复合覆盖率的精确算法定义**（ARCH §5"③清零 = 决策规则，单独测复合流程覆盖率"）：逐（cell × rep × 签名）记混淆四格：
- 真值 `h*_a = 0`：成功 = `final_zero_a = TRUE`；失败 = false-keep（FPR 方向）；
- 真值 `h*_a > 0`：成功 = `final_zero_a = FALSE ∧ h*_a ∈ CI`；失败 = false-zero（FN 方向）或 kept-but-miss。

`复合覆盖率 = 成功比例`；分解报告 FPR(false-keep)/FNR(false-zero)/kept 条件覆盖三条。真值 share 轴含 {0, 0.005, 0.01, 0.02, 0.05} 使决策规则在 θ=0.01 附近的 ROC 被直接测量。**验收门（提案）**：主门 = 复合覆盖率全格 ≥ 0.93（窗下沿）；诊断门 = share=0 格 FPR ≤ 0.05、share ≥ 0.05 格 FNR ≤ 0.05（报告级，硬化与否随 PI）。默认管线是否把 CI 清零升为 `ms_fit_bootstrap` 默认（vs 仅 `zero_method` 选项 + 报告列）属分叉点 1 的附属裁决；推荐 v1.0 默认仍为点-share 清零，CI 清零为 bootstrap 面属性列 + 选项。

---

## 4. 高 TMB 降采样 sanity 协议

- **数据源（分叉点 3）**：推荐主 = **PCAWG WGS**（consortium, Nature 578:176–184, 2020, doi:10.1038/s41586-020-1962-3；WTSI 公开签名目录矩阵，N 可达 10⁵–10⁶，唯一能从头到尾铺满 N 网格的源）；副 = TCGA GDC open WXS（治理最干净，但 TMB 天花板 ~10⁴ 且须外显子机会归一，只铺 N ≤ 10⁴ 段）。
- **协议**：(1) 取 TMB 顶层十分位样本（`N_full ≥ 5×10⁴`）≥ 20 例；(2) 冻结生产面全量拟合 → 点估计 ĥ 为**声明的 pseudo-truth** + 全量 CI；(3) 降采样 = 同一 bootstrap 原语做稀释：`Multinomial(N, counts/N_full)`（resample.rs 复用，零新采样面）；每 (样本 × N) K = 100 次稀释；(4) 每个稀释目录跑生产面 + CI(B=1000)；(5) **sanity 度量** `S(N)` = 稀释 CI 对 pseudo-truth ĥ（内点、share ≥ 0.05）的覆盖率；验收 = `S(N)` 与合成网格主臂曲线同 N 差 ±0.05 内（或 [0.90, 1.00] 地板，取宽者），且随 N 单调性无系统性反转；(6) 偏差方向与 NB 臂曲线互读（真实过散 → 预期沿臂 B 方向轻欠覆盖——一致性即 sanity 通过的另一证据）。
- **非声明纪律**：pseudo-truth 是估计量（参考值含测量误差），真实数据违反拟合模型（不可辨识、exposure 异质）——本协议是 **sanity/stability，永远不写成 calibration 证据**（ARCH §5 原文措辞"真实数据 sanity"即此意）。

---

## 5. 实现切分与工作单元

Rust 校准驱动**照 bootstrap 模式**（chunk 化独立单元、主线程边界轮询、worker 只见 AtomicBool、chunk 索引定序拼接 → threads∈{1,N} identical()，`run_boots_in_chunks` fit.rs:1325 为模板）；R 做曲线装配与判据。

| 单元 | 面 | 内容 | 依赖 |
|---|---|---|---|
| **U-M3b-01** | engine/resample.rs | NB 采样原语（§2.2 规格；goldens + Poisson 极限 + 方差性质 + 流字契约文档） | 无 |
| **U-M3b-02** | src/rust/src/fit.rs + FFI | BCa 面：解析影响/加速度原语（固定支撑 `u_c = G_A⁻¹ s_A[c]`）+ `bca_interval`（z₀/â + 退化回退规则冻结）+ `ms_fit_bootstrap_rust` 增 `ci_method` 参数 + ffi-surface 行 | 无（可与 01 并行） |
| **U-M3b-03** | bench/（非 ms_* API，D9） | 校准蒙特卡洛驱动：网格模拟两臂 + 生产面 + CI + 复合清零 tally；协议文档 + 固定种子冻结；驱动不随包发布，**结果表（分层校正表、覆盖率曲线数据）进包 data** | 01, 02 |
| **U-M3b-04** | R/fit.R | `ms_fit_bootstrap` 的 `ci_method`/`zero_method` 面、MsFit CI 属性与 tidy 列；纯 R 孪生（percentile/BCa 数学，面间 <1e-8 一致性——M3a-03 惯例） | 02 |
| **U-M3b-05** | R/viz + tests | 曲线装配 + 判据窗检查 + viz/calibration.R 首面；验收窗自动化为 testthat 门 | 03 |
| **U-M3b-06** | tools/ + R | 真实数据 sanity harness（§4；governance 记录入 devlog） | 05；分叉点 3 |

里程碑内嵌：**G2 门（统计学 co-author）须在 M3b 期达成**（ROADMAP L22）——分层 calibrated-percentile 臂与 conformal 边界表述（§6）是 co-author 的第一个审稿任务。验收对照 §7 条目 1 双层：percentile/BCa 算术 = 语义逐位 golden；覆盖率窗 = 数值协议等价（固定种子 + 窗口判定）。

---

## 6. D13 声明边界（措辞清单）

**能声明**（M3b 完成后）：
- ✅ *"To our knowledge, the first exposure-inference layer in mutational signatures whose confidence intervals are validated by empirical coverage measurement, reported over a full grid (mutation burden × signature flatness × true share), under both a multinomial generative model and a negative-binomial overdispersion stress arm, with a retrospective real-data downsampling sanity protocol."* ——检索背书：2026-10-04 WebSearch 无先前 exposure CI 系统性 coverage 测量（Medo 2024 明示 open question = research/02 §2 行 94 空白声明；检索快照日期必须写入论文）。
- ✅ presence 检验校准实证（n=1..16 全落窗，两 faces）；Fisher SE 对 MLE 的 MC SD 验证（`fisher_se_matches_monte_carlo_sd_of_the_mle` 已钉）。
- ✅ 每格覆盖率带 4SE 误差窗报告；分层校正表（若启用）随包发布 + 冻结内插规则。

**不能声明**：
- ❌ "distribution-free" / "finite-sample exact"——bootstrap 区间是渐近的；分层校准只在网格与层内有效，**网格外无保证**（外推须显式 caveat）。
- ❌ "conformal"——分层 calibrated-percentile 是 Beran prepivot 型**模拟校准**，不是 conformal prediction（无 exchangeability 定理、无分布无关覆盖保证；Vovk et al. 2005, doi:10.1007/b106715）；conformal 属 MSU-LowCount（v1.x），措辞不得互相借用。
- ❌ "first CI for exposures"——sigfit HPD（bioRxiv 372896）已存在；firstness 只落在"**经验覆盖率测量并全网格报告**"这个动作上（ARCH §5 措辞原文即如此限定）。
- ❌ "calibrated under all noise models"——只测两臂；NB 臂是 stress 不是校准；real-data 是 sanity 不是校准。
- ❌ 边界参数区间——Fisher SE 内点 only；CI 清零是**决策规则的复合覆盖率**，不是逐格区间保证。
- ❌ family-wise/joint 覆盖——主报告是逐签名**边际**覆盖；联合覆盖若 tally 只作诊断列并如实标注。

---

## 7. 分叉点（PI 复核清单）

1. **BCa vs 分层 calibrated-percentile**：本备忘推荐默认 BCa（零额外重采样成本，§1.2），percentile 仅作退化回退、分层表按需升级。裁决点：(a) 判据阈值（|ẑ₀|<0.1 / |â|<0.05 / stability<0.9）是否冻结；(b) 分层校正表进 v1.0 默认路径还是仅报告；(c) CI 清零是否升为 bootstrap 默认（推荐否，见 §3 末）。
2. **NB 采样原语缺口**：resample.rs:88–90 明示 absent，M3a-04 已闭 → 缺口落 U-M3b-01。裁决点：(a) per-channel 独立 NB（推荐，mSigAct/Jiang 似然族语义）vs NB 总数+多项分裂；(b) 色散主锚（推荐 κ=8 + 真实残差反解对照 + 敏感性扫描）；(c) 流字消耗契约放宽为"数据依赖但纯函数"是否接受。
3. **真实数据 sanity 数据源**：推荐 PCAWG WGS 主 + TCGA GDC open WXS 副（§4）。裁决点：(a) PCAWG 目录获取路径（WTSI 公开矩阵 vs ICGC portal）与 governance 记录位置；(b) sanity 容差（±0.05 vs [0.90,1.00] 地板）取谁；(c) 是否纳入 WES/panel 平台轴（推荐 v1.0 不纳，留 M4 机会归一一等公民之后）。

---

*源码行号对照检索日期 2026-10-04；上游 DOI 均为已核实条目（Hall 1988 经 Project Euclid 检索复核 doi:10.1214/aos/1176350930；其余与 research/02 §8 引用表交叉一致）。*
