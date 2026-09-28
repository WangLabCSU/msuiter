# Devlog · G0 先导覆盖实验——PI 裁决与待冻结项（2026-09-28）

> 输入：[2026-09-28-G0-protocol-memo.md](2026-09-28-G0-protocol-memo.md)（方法学草案）+ [2026-09-28-G0-realism-memo.md](2026-09-28-G0-realism-memo.md)（现实性审查，独立撰写）。两备忘结论一致性高，PI 裁决合并如下。**G0 执行权在作者本人（ROADMAP 组织行动门）；"待作者冻结"项落定前不开跑。**

## PI 已裁决（采纳）

1. **工具解读**（协议备忘 Q1）：ROADMAP"2 个竞品工具"= 2 个**带区间输出**的工具作覆盖裁定对——**Tier-1 = sigfit v2.2.0**（后验派最强竞品假设；HPD + 清零规则照用，另报 raw 列归因失准来源）+ **signature.tools.lib v2.5.2**（bootstrap 派主流，nboot=200）。MuSiCal / SigProfilerAssignment / mSigAct 归 **Tier-0 分类证据**（"领域最主流两工具根本不输出 exposure 区间"本身是 Figure-1 素材），不进覆盖矩阵、不触发判定。
2. **estimand**（Q2）：绝对 exposure 覆盖为主、成分为辅（对齐 ARCH §5 estimand ②）；sigfit HPD 的"名义 95% 非频率保证"解释性差异在报告中单列。
3. **场景升级**（现实性备忘全采）：TMB 网格 N≈30–10⁶ 几何网格、**10²–10⁴ 覆盖率悬崖区 ≥6 点加密**（协议原 {100…10000} 上调）；**NB 过散臂由"敏感性"升级为必选**（nbinom.size=8 语义）；增加 clock 混入臂（purity≈0.4 等效）；真值组合 ≥6 组（clock-only / +APOBEC / +MMR / POLE 超突变 / 平坦三联 SBS1-5-40 / 强签名+平坦背景）；**caller 轴固定排除出 G0**（两备忘一致；区间覆盖率问题不应与目录生成噪声混淆）；指标以**区间覆盖率**为中心，禁跨签名平均掩盖 flat 层。
4. **先例核查结论**（现实性备忘）：未发现已发表的同位覆盖评估（最接近的 Medo 2024 明示 CI 覆盖率为 open question）→ **G0 叙事未被抢跑**；kill criterion"竞品发布校准 CI"的近似形态已现（SigFormer bioRxiv 2026），**协议冻结必须带时间戳**。
5. **判定规则框架**（协议备忘，D13 纪律）：支持 A = 任一 Tier-1 工具任一 cell ĉ ≤ 0.85（binomial CI 上界 < 0.90）或 flat 层全 N≥300 cell ≤ 0.90；kill→B = 两工具全 N≥300 cell ≥ 0.90 且无单调恶化；gray = borderline cell 加倍 reps 至 400 重判，仍 gray 默认走 B（风险不对称）。
6. **两周核算**：40–52 人工时；关键路径 = sigfit/rstan 编装（Day 3 止损换 signeR）；W1 先做 signature.tools.lib 的 RefSig 兼容检查（ Breast RefSig T1 须含全部真值签名）。

## 待作者冻结（G0 开跑前置，缺一不开跑）

- [ ] **F1 阈值数字定稿**：支持 A −10pp / kill→B −5pp（按功效核算拟定；冻结后不可回调——预注册纪律）。
- [ ] **F2 工具对解读确认**（上述第 1 条；如作者希望换工具对，Tier-0 证据集不变）。
- [ ] **F3 真值与目录预注册**：5 签名固定 SBS1/SBS2/SBS13/SBS5/SBS40（15/15/15/30/25%）+ 拟合目录 COSMIC v3.6 SBS96 GRCh37 全 101 签名。
- [ ] **F4 协议时间戳冻结**（本裁决文档 + 两备忘随 commit 定版），随后才开跑模拟。
- [ ] **F5 执行环境落实**：作者机器 Python/R 环境（sigfit 依赖 rstan；Day 3 止损路径 = signeR）。

## 与 ROADMAP 的关系

- G0 结果决定论文 Framing A/B（ARCH §10 / D14），是 U-M7-03 论文写作的前置条件；与代码轨道（M0/M1s）完全并行，互不阻塞。
- G0 属组织行动门，团队可代办的部分（协议起草、场景审查）已完成；执行与判定阈值拍板在作者。
