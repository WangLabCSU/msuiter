# 五专家评审综合裁决（Synthesis，2026-09-28）

> 五份独立评审见本目录 01–05。本文档是主编的采纳裁决——每条评审意见归入 **采纳（立即改文档）/ 采纳（排期进路线图）/ 部分采纳 / 不采纳（记录理由）**。评审原文保留不改，本文档是唯一生效口径；与评审冲突处以本文档为准。

## 1. 五份评审的一句话结论

| 评审 | 结论 |
|---|---|
| 01 计算生物学家 | **有条件信任**——科学层三个主角声明（MSU-Fit 覆盖率、MSU-Corr、多证据 K）会被一页纸击穿；HRD/RNA 工作流按现状属临床危险与不诚实；M0–M8 时间线不现实 |
| 02 Rust/R 专家 | **Conditional go**——Rust 运行时层契约（RNG 版本、并发/fork、panic、FFI 边界、分发预算）几乎整体缺席，必须在 M0 成文 |
| 03 ML/统计学家 | **Major revision**——统计声明普遍比协议强 1–2 级；把"校准过/分布自由/无损/首个"降级到协议实际支撑的水平 |
| 04 软件开发专家 | **有条件通过**——"论文愿望清单"不是交付计划；无 v1 切线、逐位验收与 clean-room 对撞、并行化与确定性冲突 |
| 05 Nature 编辑 | **当前定位 = Genome Biology/NC，不是 Nature Methods**——唯一够顶刊的统计贡献是"exposure 推断的校准统计学"；8 个 MSU-* 砍到 2–3 个；三段式需重排 |

## 2. 交叉印证（≥2 位评审独立指出 = 必须改）

1. **CI/校准声明缺 estimand**（01#1、03#2、05#2/5/7）
2. **Conformal"分布自由"在 N 异质下数学不成立**（01#11d、03#1）
3. **MSU-Corr 会被读作 Cornet 衍生**：gauge 不可辨识、缺 baseline、缺 ablation、m 协议缺失（01#7、03#3、05#2/风险1）
4. **确定性声明缺线程数不变性**（02#3、04#3）
5. **"逐位"混淆离散语义与浮点内核，且与 clean-room 策略对撞**（02#8、04#2）
6. **时间线低估 ~3×、无最小 v1**（01 附注、04#1、05 风险3）
7. **句柄/.state 是为不存在的能力付的复杂度**（02#4、04#11）
8. **K 选择缺默认仲裁规则**（01#9、03#4）
9. **"首个/无损/分布自由"过度声明**（01#11、03 全文）
10. **8 个 MSU-* 稀释贡献**（04 隐含、05#2 明确）

## 3. 采纳裁决（立即改文档）

| # | 裁决 | 采纳内容 | 落点 |
|---|---|---|---|
| A1 | 采纳 | **统计契约**：estimand 三层（presence=LRT χ²₁；magnitude=support-conditional 绝对 exposure；清零=决策规则单独测复合覆盖率）；多项与 NB 双生成模型校准；coverage 随 N×Shannon 曲线；Fisher 区间 interior-only；"boundary parameters get tests, not intervals" | ARCH §7 |
| A2 | 采纳 | **Conformal 降维**：Mondrian by TMB bin + studentized score；声明改写为 per-stratum empirical coverage；quantile 表随包发布 | ARCH §5/§7 |
| A3 | 采纳 | **方法命名收缩**：只保留 **MSU-Fit / MSU-LowCount / MSU-Infer** 三个命名方法（headline 簇）；提取流水线/相关性引擎/损伤节奏/张量/目录 IR 全部降为**框架组件**（去 MSU- 前缀） | ARCH §5 |
| A4 | 采纳 | **相关性引擎降级**：预注册可证伪声明（r∈{0.8,0.9,0.95} 上同时击败 MvNMF+correlated refit 与原版 Cornet）；gauge-fixed 报告（禁解读嵌入向量）；m<K 经 held-out；体积正则与嵌入分离 ablation；五模态降为 SBS+DBS 演示 | ARCH §5/ROADMAP v1.x（推迟项） |
| A5 | 采纳 | **无状态 FFI**：删除句柄注册表与 `.state` 属性；S7 内嵌对象改为**快照摘要**（维度+通道表哈希+refdb 版本）；caugi 模式只留只读美学 | ARCH §2/§3 |
| A6 | 采纳 | **自研 RNG**：PCG64 + SplitMix64 流布局（写进论文 Methods），不依赖 rand 的 RNG 面（跨版本不保证）；跨版本 golden 测试 | ARCH §2 |
| A7 | 采纳 | **并发契约**：并行只在独立单元间；单元内固定归约顺序；线程数不变性 identical() 测试；per-call ThreadPool（弃全局池）；`msuiter.threads` option（检查期 2）；Makevars -j2；R_CheckUserInterrupt 主线程 chunk 边界 + worker AtomicBool | ARCH §2/§9 |
| A8 | 采纳 | **双层验收术语**：**语义逐位**（通道算术/协议步骤/平局规则/默认参数——整数与标签 golden，硬验收）vs **数值协议等价**（浮点内核——固定种子+容差）；R NMF brunet 对拍 = 固定平台一次性实验，不进 CI 门 | ARCH §7/ROADMAP |
| A9 | 采纳 | **基准升级**：加 purity/caller/类别专属计数区间（SV 10–10³、CN 10–10⁴）/超突变臂/联合对抗 cell/目录外签名 cell；校准-选择-评估三层场景隔离（不同生成器）；**主指标 = Hungarian 一对一**（贪心+阈扫为附录，分裂惩罚）；协议冻结随包发布 | ARCH §8 |
| A10 | 采纳 | **K 仲裁规则**：层级决策（SUITOR argmin → 稳定性 veto → Wilcoxon 降诊断）；Hungarian unmatched 的 split/merge 语义；meta-rule 全网格评估 | ARCH §7 |
| A11 | 采纳 | **目录完备性契约**：MNV 2–5/>5、complex/double indel 路由表 + skip ledger；拆分 VCF 的 DBS 重连算法；MNV golden fixtures；complex 事件显式路由 | ARCH §7/ROADMAP M1s/M1c |
| A12 | 采纳 | **工作流范围安全**：HRDetect 系数模式 **WGS-only** + allele-specific CN caller 白名单 + WES 标 experimental；RNA 工作流最小 caller 要求 + 伪影面板 + matched-DNA 验证 estimand + research-use 标注 | ARCH §7/ROADMAP M6s |
| A13 | 采纳 | **refdb 治理**：precedence（默认 bundled 优先、provenance 钉版本）；schema_version 前向拒绝；更新钉 commit SHA + manifest 烧录 + fail-closed；更新测试 fixture 化；**v1 只捆绑人类 SBS/DBS/ID**；缺失 build = `build_independent: true` 声明（relabel 而非 derived）+ 查询时如实提示 | ARCH §6 |
| A14 | 采纳 | **API 定型**：`method = ms_nmf(...)` S7 对象一等公民 + 字符串糖；自定义泛型一律 `ms_` 前缀（hardhat 命名仅文档概念）；新增 §3.5 Error & lifecycle（rlang class/i-j-c/禁裸 stop/lifecycle 政策/ffi-surface.md 冻结流程） | ARCH §3 |
| A15 | 采纳 | **CI 补全**：矩阵加 R 4.3（至少 Linux）+ devel（允许失败）；valgrind/ASAN scheduled job；CI 基准门降为 sanity bound（<5s），加速比验收移入钉硬件 bench；dependabot + cargo audit；codecov（R≥85%，Rust 报告不设门）；fixture 刷新脚本 + PR 模板检查项；rhub/--as-cran 预提交 | ARCH §9 |
| A16 | 采纳 | **路线图双轨**：v0.1（~6 周：SBS96/192/384/1536+DBS78、KL-NMF+NNLS、单方法、CI、r-universe）→ v0.2（~12 周：+ID83、K 选择、拟合三法、bootstrap CI、refdb v1、viz 6 图）→ v1.0（~5–6 月：MSU-Fit 校准、HRD 报告、pkgdown）；**ID89/Infer/Tempo/Tensor/Lda/Supervised/CN-SV 拟合/RNA/therapy 推迟 v1.x**；M8 拆 M8a/M8b | ROADMAP v3 |
| A17 | 采纳 | **治理**：registry 加 engine_version/contract_version/certified 三态；non-certified 引擎 benchmark 告警 + 信任边界声明；月度反向依赖矩阵；CONTRIBUTING/CoC/模板 | ARCH §3.4 |
| A18 | 采纳 | **超突变者正名**：`ms_stratify_hypermutants()`（分类+排除+强制 refit，非"归一化"）；common/rare 升格为 atlas 工作流；Cornet 10–40× 重标定降为相关性引擎内部超参（sweep 验证 + de-rescale + 禁用于 NMF 路径） | ARCH §5/§7 |
| A19 | 采纳 | **论文重定位**：headline = **"Calibrated inference of mutational signature exposures"**（Framing A）+ 生态支撑（B）；**两周先导覆盖实验（2 工具 × TMB 网格）作为 kill-criterion gate 前置于任何叙事写作**；案例升级三路径（治疗记录/RNA-only/低计数 panel）需队列合作；kill criteria 七条全收 | ARCH §10/ROADMAP G 门 |
| A20 | 采纳 | 其余：β=1 默认即多项 MLE（删"三噪声"宣传或给协议）；零伪计数政策；SUITOR fold/填补语义逐位复刻（语义层）；DM 加 hurdle/结构零；twobit over `Cursor<Mmap>` ADR；column-major+NA FFI 硬契约；panic=Result+边界转 error；workspace 依赖方向断言 + `forbid(unsafe_code)`；MSU↔函数映射表 + `ms_sitrep()`；docs-sync CI；ADR 独立成目录 | 各处 |

## 4. 部分采纳 / 不采纳

| 评审意见 | 裁决 | 理由 |
|---|---|---|
| 04#1 建议把 SUITOR CV 推迟到 v0.2 可选 | **部分采纳** | MSU-Fit headline 依赖校准叙事但 K 选择规则依赖 CV——v0.1 不含 CV，v0.2 作为开关加入（与 04 一致）；但 K 仲裁规则文档化在 v0.2 一次写全 |
| 05"只命名 MSU-Fit/LowCount/Infer" | **采纳但保留组件名** | 组件仍需工程名（extraction pipeline 等），只是不再以"方法"身份出现在论文 abstract |
| 01#3 把 MNV 修提出 M1 | **采纳** | MNV 路由是语义正确性问题（不修则 DBS/SBS 目录系统性失真），不属于可推迟功能；落点为 M1s（见 A11） |
| 05"MSU-Tensor 砍出 abstract" | **采纳 + 保留探索位** | TensorSignatures 生物学动机真实；降为 exploratory（held-out likelihood 选 K + Kruskal 检查），v1.x 排期 |
| 04#9 ADR 独立目录 | **采纳（轻量）** | 建立 docs/adr/，先把 D1–D16 迁入（裁决落地时已有 16 条，含 D15/D16）；研究文档加 archival 声明 |
| 02#11 twobit 自研 ~300 行 reader | **部分采纳** | M0 spike 两条路都试（crate over Cursor\<Mmap\> vs 自研），以 byte-swap/大端验证结果定 ADR；默认倾向 crate |

## 5. 编辑建议的组织行动项（需要作者本人决策/推进，非文档可解决）

1. **两周先导覆盖实验**（G0 门）：2 个竞品工具 × TMB 网格的名义 vs 实际覆盖率——验证"竞品 CI 失准"叙事地基，先于一切论文写作。
2. **统计学 co-author**（conformal/CoDA 理论部分）+ **临床/队列合作者**（治疗记录 / RNA-only / FFPE panel 三选一）——M3 前锁定，否则案例注定装饰性（编辑 kill criterion #4）。
3. **co-maintainer**：M1s 前找到（bus factor + CRAN + 审稿三重需要；即 G1 门）。
4. 每季度复核竞争格局（Cornet/MuSiCal/SPA 的发表动态），触发 ROADMAP 的 kill criteria 重估。

## 6. 文档生效

- ARCHITECTURE.md **v2.2**（本文档裁决的落地版）
- ROADMAP.md **v3**（双轨 + G 门）
- 评审原文 01–05 保留为证据与论文 rebuttal 素材
