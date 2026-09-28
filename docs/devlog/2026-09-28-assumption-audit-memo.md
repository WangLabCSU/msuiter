# Devlog · 假设审计备忘：Cornet 之后的领域共同假设地图（2026-09-28）

> 触发：G3 事件复核（[Cornet 正式发表](2026-09-28-G3-cornet-event-review.md)）后作者指令——从 mutational signature 的理论与计算/算法假设限制出发，打磨我方理论和方法。Cornet 打掉的是 A1（签名间独立）；本备忘系统枚举领域方法共同依赖的统计/算法假设，逐条标注 (a) 默许处、(b) 已有破坏、(c) 破坏后的下游空白、(d) msuiter 三方法站位，并给出候选延伸命题 P1–P3。
> **声明纪律（D13）**：本文全部命题均为**候选命题 + 四件套草案**，无任何一项已完成验证；阈值均为草案，冻结前可改，冻结后依 G0 条款只允许追加。措辞红线："首个/无损/分布自由"类声明一律限定到可辩护范围。
> 事实基础：docs/research/01/02/07 源码级审计 [V]；G0 协议/现实性两备忘（2026-09-28）；本日经 Crossref 补核 DOI：Wu 2022、Aitchison 1982、Self–Liang 1987。任务简报候选假设映射：①→A2，②→A1+P1，③→A7+P2，④→A6，⑤→A5。

## 1. 审计总表（A1–A8）

| # | 假设 | (a) 默许处 | (b) 已有破坏 | (c) 下游空白 | (d) msuiter 站位 |
|---|---|---|---|---|---|
| A1 | 签名间 exposure 独立/无共暴露 | de novo 全家：SigProfilerExtractor、MutationalPatterns、sigminer、SignatureAnalyzer(ARD)、SUITOR、signeR、mSigHdp 均将 H 视为自由矩阵、无跨签名依赖结构；K 选择稳定性判据隐含零相关；拟合侧手工 connected 组（MuSiCal SIGS_ASSOCIATED、SPA 分组）承认近重复对但将其**先验固定而非估计** | Wu 2022（r≳0.8 基准失效）；Cornet（联合推断，r≈0.98 仍正确；NMF 交叉污染 20–41%）；谱系 Paisley–Blei–Jordan 2014；MvNMF 体积正则为线性世界部分解药 | ①相关结构下**无任何工具输出区间**（Cornet 只报 gauge-fixed 点量）；②K 选择在 r 网格上的 size/power 无系统基准（2023–2026 无新系统性提取基准，research/01 §9）；③presence LRT 在共暴露真值下的经验 size 从未报；④connected 组由手工先验变数据估计——无人做 | Fit：目录 refit 固定 W、逐样本独立似然（刻意简化，见 A3）；χ²₁ 与 bootstrap 均不建模共暴露；相关性引擎=框架组件（v1.x，预注册可证伪声明）。LowCount：逐样本独立+Mondrian；共暴露不破坏样本级交换性，但条件分布偏移需覆盖核查。Infer：DM 把两两相关**结构性钉死为负**（见 P2） |
| A2 | 逐突变 i.i.d. 多项噪声（无过散） | 全部 KL-NMF/多项似然工具；且全部标准生成器共享多项世界观（SigProfilerSimulator、SynSig——G0 现实性备忘 §4） | mSigAct 默认 NB（size=8/50/100）是领域自己的逃逸口；Jiang 2025 协议 NB 通道采样；BayesPowerNMF 幂似然抗误设；TensorSignatures NB | 色散–覆盖率理论曲线不存在（只有模拟）；NB 真值下 LRT 经验 size 的膨胀从未测量；无工具输出色散诊断；NB 下 bootstrap 有效性未知 | Fit：双生成模型已声明（多项+NB Jiang 色散）——领先，但止于模拟；LowCount：NB 原生，坑=size 参数在低 N 不可辨识；Infer：DM 本身即过散多项——结构性吸收该破坏 |
| A3 | 签名矩阵 W 精确已知（条件化假设） | 一切目录 refit（MuSiCal/mSigAct/SPA/FitMS）把 COSMIC 列当真值；de novo→match→refit 管线把 Ŵ 当真值传播 | 无直接破坏者；最近的"承认"= SPA 强制 SBS1+SBS5 背景、BASCULE 残差感知先验、bbaf042 目录更新建议（保留父签名参与拟合） | W 估计误差向 exposure 区间的两层不确定性传播——全领域空白；分层贝叶斯目录先验不存在 | 三方法全部站在该线上；G0 协议显式固定全目录以排除混淆（§4），故 G0 结论须限定 scope="W 已知世界"；四件套失效条件须写明该边界 |
| A4 | 名义 95% 区间 = 95% 频率覆盖 | 全部区间输出者（sigminer/SigsPack/mmsig/STL bootstrap、sigfit/signeR HPD）从未测覆盖；MuSiCal/SPA 无区间（G0 Tier 0 分类证据） | 无外部工作——G0 本身即第一击（现实性备忘 §1：未发现任何已发表覆盖审计）；Medo 2024 明示 open question | 清零/过滤规则作为区间截断的覆盖效应从未归因（G0 已正确列 raw vs 清零两列）；P1/P3 | Fit：headline 即此（"首个……全网格报告"已限定为 exposure 区间覆盖）。**LowCount 声明存在一处 D13 坑**："coverage verified on … retrospective real panel data"——真实 panel 无真值 exposure，coverage 无定义；四件套必须写明代用 estimand（如降采样自洽性），否则措辞不可辩护 |
| A5 | 机会均匀/机会误设无偏（WGS 参考集拟 WES/panel） | MuSiCal 无外显子机会转换（audit [V]，research/02 §4）；大量应用论文以 WGS 归一参考直接拟 WES 目录 | sigfit（似然内机会、支持逐样本）；SPA exome 参考文件；sigminer sig_convert | 偏置幅度从未量化；机会误设下的覆盖审计不存在；panel 级逐样本机会向量（CN segments + callable BED）无生产级实现 | Fit：estimand 须声明机会口径（尚未入 §5 契约——四件套补全项）；LowCount：panel 似然必须逐样本机会；候选命题（备选，本轮未展开） |
| A6 | 低计数体制的渐近有效性 | 领域默认答案=丢弃（mSigAct/bbaf042 丢 <100 SBS；MuSiCal 癌型阈值；SigProfiler 超突变 9600 重标定）；SigMA 是唯一经典例外 | Medo 2024（无普适阈值、难度签名特异、误差 ~1/√N）；SigMA；SigNet（摊销 refit 给预测区间） | χ²₁ 边界渐近在 N≈30–100 的实际 size；bootstrap 在极低 N 的退化（可分辨重采样数有限）；conformal 薄 bin 的宽度行为——全部未测量 | LowCount 整条方法线站在此；Mondrian by N bin 声明已有；坑=sim-to-real 交换性断裂（敏感性曲线已承诺随包发布——四件套"失效条件"的具体化） |
| A7 | exposure 可作普通实数变量（无视成分约束） | 全部应用层 Wilcoxon/Cox on exposures（research/02 §5d"任何地方都无 CoDA/log-ratio 处理 [V 检索]"）；绝对 vs 份额口径混用 | Morrill 2025（DM 混合差丰）；理论源头 Aitchison 1982 | 生存/病例对照/纵向 + 成分约束 + 拟合不确定性传播；闭合效应伪相关校正——全空白 | Infer 全条线（ARCH §5 声明已按 D13 限定："首个"限于覆盖三类设计的统一框架，DM 差丰部分为复现非首创）；Fit estimand ②/③ 已分离绝对与成分口径 |
| A8 | 模型可识别（"重构好=归因对"） | cosine 阈值文化（匹配 0.99/新签名 0.8）；cophenetic 单独使用；单报 RSS | Jiang bbaf042（99/100 谱存在"更优错误归因"，重建指标无信息量）；Wu 2022；Islam 2022（cophenetic 对罕见签名不敏感） | K 选择在相关/过完备目录下的 size/power；presence 检验对近重复对（SBS5 vs SBS40 单独检出）的判别力从未报 | Fit：presence/magnitude/清零三层 estimand 分开测覆盖=直接回应；ARCH §8 以 Hungarian 一对一为主指标、Islam 贪心协议语义逐位保留为对照（research/07 §1.20） |

**对称审计注记**：Cornet 自身完整继承 A2（Poisson 噪声）、A4（无区间输出）、A5（输入 10–40× 重标定是隐含的 exposure 分布"温度"假设，audit research/01 §1.3），并新引入未验证假设（嵌入秩 m≤K、高斯嵌入先验）。故 "correlation-aware × calibrated intervals" 当前是**空集**——这正是 P1 的占位空间。

## 2. 候选延伸命题（P1–P3；均为草案，未验证）

### P1（主推，Framing A 强化叙事）相关性/近重复破坏的不只是点估计，还有区间校准

**语义规范（命题的可检验定义）**：
- 机制 (i)（目录层）：拟合目录含近重复对（SBS5/40，96 通道余弦极高）时，设计矩阵近共线使 exposure 似然沿交换方向近乎平坦 → 点估计系统性偏置（Medo 低估）+ 区间以偏置点为中心 + 清零/过滤截断 → 系统性欠覆盖。
- 机制 (ii)（管线层）：真值 exposure 共变（r≥0.8）只经由**联合估计阶段**进入似然——纯目录 refit 的逐样本似然对共暴露不敏感（可分解）。故"相关性破坏区间"只能发生在 de novo→match→refit 端到端管线（Ŵ 误差随 r 放大并传入 H 区间）。**推论：G0（W 已知 refit）只能探机制 (i)；机制 (ii) 必须 M3b 端到端系统化。**

**四件套草案**：estimand = 端到端管线输出的用户可见 95% exposure 区间对真值绝对 exposure 的频率覆盖，覆盖函数 C(ρ, N, δ)（ρ=真值 exposure 相关，δ=真值签名对余弦距离）；生成模型 = G0 多项主模型 + SynSig 式 exposure 相关注入（r∈{0, 0.5, 0.8, 0.95}，对齐 ARCH §8 相关轴），目录固定；校准协议 = G0 flat 层（SBS5/40，组成 30%/25%）即机制 (i) 探针，零新增成本；M3b 全因子网格并以原版 Cornet 为对拍臂；失效条件 = flat 层 N≥300 覆盖 ĉ≥0.90（G0 判据②已含）**且** M3b 端到端覆盖对 ρ 平坦 → 命题证伪，强化叙事撤回。

**可行性初判：高**。G0 侧零成本；M3b 复用 ms_simulate + SynSig；无竞品环境依赖；占位窗口与 G3 复核"校准车道更空"判断一致。

### P2（MSU-Infer 线）共暴露的正相关结构必须进入关联层生成模型

**语义规范**：Dirichlet 闭式协方差 Cov(π_i,π_j) = −α_iα_j/(α₀²(α₀+1)) < 0 使 DM 的两两成分相关**恒为负**——Cornet 的核心经验发现（共暴露：smoking×ERCC2、SBS4/SBS92 型正相关）在该生成模型下不可表达；用 DM 做组间检验在正相关共暴露下的 size 行为未有人测（research/07 §1.17 确认 Morrill 2025 为唯一形式化前作）。

**四件套草案**：estimand = 签名对 log-ratio 的组间差 + 共暴露参数 ρ_kl；生成模型 = logistic-normal（全协方差，注入正相关）vs DM，含负荷 offset；校准协议 = 先复现 Morrill 2025 基线，再注入 r∈{0.5,0.8,0.95} 共暴露，对比 DM / logistic-normal / naive Wilcoxon 的经验 size 与 power；失效条件 = 正相关低于可检出幅度时 DM 与 LN 无差 → 命题收缩为"先检验共暴露、后分层分析"的诊断流程。

**可行性初判：中**。R 侧；Morrill 复现已是 M3b+ 既有排期，无新增基建；生存/病例对照层需队列合作（G 门）。

### P3（G0 附录升正文的最短路径）过散下的检验/区间联合校准

**语义规范**：多项理想世界的覆盖率乐观（G0 现实性备忘 §4/§6）+ χ²₁ presence LRT 的经验 size 在 NB 真值下的膨胀，二者可共用同一批模拟数据测量；现实性备忘 §7.2 已预留"检验族（名义 α vs 经验 size/power）并列计入 G0 门"裁决点，但协议冻结版未落列。

**四件套草案**：estimand = ①自有 χ²₁ presence LRT 经验 size(α=0.05) 对 NB size 与 N 的函数（Self–Liang 边界渐近为名义参照）；②同网格上 MSU-LowCount conformal（Mondrian by N bin）覆盖；生成模型 = NB(μ=Wh, size∈{8, 50, 100, ∞≡多项})（Jiang 色散校准语义，mSigAct 默认为锚）；校准协议 = G0 NB 敏感性臂（N=1000 单点）扩展为 size×N 短网格，**追加不替换**（符合冻结条款），同一种子流复用；失效条件 = size 膨胀 <2× 且覆盖 ≥0.90 → 降级为附录注记。

**可行性初判：极高**。唯一新增计算 = 自有 LRT 在既有数据上的扫描（纯自有代码，无竞品环境）；同时关掉"多项理想世界"方法学批评。

## 3. 立即动作建议（作者裁决项；均为追加，不动 G0 §2.4 判定规则）

1. **G0**：NB 敏感性臂按 P3 追加**经验 size** 报告列（自有 χ²₁ LRT 进 harness 自校验部分）；flat 层结果按 P1 机制 (i) 单列归因（"近重复目录欠覆盖" vs 噪声）。零范围变更，只加列。
2. **M3b**：预注册 P1 机制 (ii)（exposure 相关注入 × 覆盖率网格 × 端到端管线）为 Cornet 之后 Framing A 强化叙事的第一图候选；并在 MSU-LowCount 四件套落笔前修掉 A4 行指出的 "real panel coverage 无真值" 措辞问题（代用 estimand 须成文）。

## 4. 文献依据

1. Jin H, Geiger B, Glodzik D, Gulhan DC, Park PJ. Cornet. bioRxiv 2026.09.14.751548. doi:10.64898/2026.09.14.751548（Sonata，MIT；research/01 §1 全文审计）
2. Wu Y, Chua EHZ, Ng AWT, Boot A, Rozen SG. Accuracy of mutational signature software on correlated signatures. Sci Rep 12:390 (2022). doi:10.1038/s41598-021-04207-6（本日 Crossref 补核——仓内旧引缺 DOI，建议回填 research/01）
3. Medo M, Ng J, Medová H. Nat Commun 15:9467 (2024). doi:10.1038/s41467-024-53711-6
4. Jiang, Wu & Rozen. Brief Bioinform 26(1):bbaf042 (2025). doi:10.1093/bib/bbaf042
5. Jin et al. MuSiCal. Nat Genet 56:541–552 (2024). doi:10.1038/s41588-024-01659-0
6. Morrill Gavarró L, Couturier DL, Markowetz F. BMC Bioinformatics (2025). doi:10.1186/s12859-025-06055-x
7. Gulhan DC et al. SigMA. Nat Genet 51:912–919 (2019). doi:10.1038/s41588-019-0390-2
8. Islam SMA et al. Cell Genomics 2:100179 (2022). doi:10.1016/j.xgen.2022.100179
9. Aitchison J. The statistical analysis of compositional data. JRSS-B 44(2):139–177 (1982). doi:10.1111/j.2517-6161.1982.tb01195.x（本日核验）
10. Self SG, Liang K-Y. JASA 82:605–610 (1987). doi:10.1080/01621459.1987.10478472（本日核验）
11. Degasperi A et al. Science 376:eabl9283 (2022). doi:10.1126/science.abl9283
12. Rubanova L et al. TrackSig. Nat Commun 11 (2020). doi:10.1038/s41467-020-14352-7
13. Gori K, Baez-Ortega A. sigfit. bioRxiv 372896. doi:10.1101/372896
14. Leplat V, Gillis N, Ang AS. IEEE TSP 68:3400–3410 (2020)；Bergstrom EN et al. BMC Bioinformatics 21:438 (2020)（仓内引，DOI 未核）
