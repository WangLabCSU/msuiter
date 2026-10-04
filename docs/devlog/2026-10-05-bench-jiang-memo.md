# bench/jiang 设计备忘：Jiang 2025 拟合协议对标（v0.2 验收门证据）

日期：2026-10-05 凌晨随批。目的：ROADMAP v0.2 验收门最后一项——"Jiang 协议（活性>0 匹配 + Combined Score）对标进入第一梯队合理区间"。**不需要 Islam 口径裁决**（Jiang 活性匹配无双口径歧义）。

## §1 协议（research/07 §1.20 冻结文本）

合成谱 = 负二项通道采样（bbaf042 主协议；多项臂为对照）；真值字典已知；**拟合 = 参考约束 refit**（bbaf042 的 fit-evaluation 设定，非 de novo）；匹配按活性>0；指标 = TP/FP/FN/Specificity/scaled Manhattan/Combined Score（ms_compare(protocol="jiang") U-M4-01 交付面直读）。

## §2 场景设计（对标 bbaf042 的合成实验结构）

- **字典**：COSMIC v3.6 SBS96 参考签名（refdb v1 捆绑 = 已发布物料）取 8 条常见真签名（SBS1/2/4/5/13/17/18/40——覆盖 flat/steep/APOBEC/tobacco/ROS 谱型）。
- **负荷轴**：N ∈ {300, 1000, 3000, 10000}（低负荷端 = Jiang 痛点带）。
- **生成臂**：`multinomial`（恰 N 流字）+ `nb:8`（bbaf042 主协议，色散校准——κ=8 是 M3b 校准驱动的冻结值，注明非 bbaf042 原文逐位）× 各 30 replicate（seed 确定性）。
- **暴露场景**：每 replicate 从字典均匀抽 3 条活跃真签名（Dirichlet(1,1,1) 活性份额），其余 5 条为 decoy（真值活性 0）——FP/FPR 可测。
- **拟合**：`ms_fit(method = "nnls")` 全字典参考约束（bbaf042 设定；likelihood_bidirectional 作对照臂记录）。
- **判定**：活性>0 阈值 = 暴露严格 >0（msuiter 的 share 清零 0.01 语义下报告两口径：raw >0 与 ≥0.01——bbaf042 无清零，raw 口径为主）。

## §3 "第一梯队合理区间"参照

bbaf042 报告了 13 工具的 Combined Score 分布；**我们不逐位复刻其数字**（其合成细节 = 色散校准到真实重构精度，不可从正文完全复原），而是报告我方完整 (N × 臂) 网格的 Precision/Recall/Specificity/scaled Manhattan/Combined Score 曲线，并对照 bbaf042 正文定性结论：(a) 低负荷下所有工具 CS 下降；(b) 平坦签名（SBS5/40 型）系统性低估（Medo 一致）；(c) FP 控制是区分度主轴。**验收判据（PI 可裁）**：N≥1000 时 CS ≥ 2.3（bbaf042 顶工具量级 = CS≈2.5–2.7；我们 3 活跃/5 decoy 场景比其全活跃场景 FP 更难）且 Specificity ≥ 0.9。达标即记"合理区间"证据；不达标 → 记差异并归因（清零语义/色散/负荷）。

## §4 交付物

- `bench/jiang/run_jiang.R`——自包含脚本（pkgload 或 library；离线；refdb 捆绑签名直读）。
- `bench/jiang/result.md`——全网格表 + 曲线叙述 + 验收判据对照。
- 无包内代码改动（纯 bench；`ms_compare`/`ms_fit`/refdb 皆为已审交付面）。
- 失败条件（D13）：任何 arm/fit 组合报错 → 脚本失败即证据（记录到 result.md）。
