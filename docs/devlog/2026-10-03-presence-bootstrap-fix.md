# Devlog · U-M3a-03 presence P0 + bootstrap CI P1 修复记录（2026-10-03）

## P0：presence 池化零分布（审计 agent_c96cc80b 抓出）
- 问题：跨样本求和配 χ²₁ 参照——H0 下 Σ C(n,m)/2ⁿ·χ²_m（Binomial 混合），n≥2 统计无效（实测 pass_bh 率 n=8:0.545/n=16:0.860）。
- 修复：精确混合零分布 p = Σ_{m≥1} C(n,m)/2ⁿ·P(χ²_m>D)（ln_gamma + 数值不完全 Gamma Q；df=1 路由 erfc——n=1 与 Self–Liang 逐位）；df≥2 级数/连分式（1200 迭代帽）；n≤53 dyadic 权重精确、n>53 ln 空间 e⁻⁷⁰⁰ 下限（跳过质量 <1e-12）。
- 校准矩阵（审核员独立复跑确认）：n=1..16 全落 [0.02,0.08]。R 面孪生 dbinom×pchisq 与 Rust 零偏差。
- ARCH §5 estimand ① 措辞对齐。

## P1：bootstrap CI 与点拟合异尺度（两轮才修对——记录全过程）
1. 第一版修复（乘 totals[j]）：**双重缩放**——boot 拟合本身在 boot counts 尺度（multinomial 恰抽 totals[j] 次，列和恰等），乘法引入 N_j²（CI 覆盖 4 失败：515934 vs 真值 709）。
2. 第二版修复（列归一）：scale = totals[j]/col_sum(boot counts)——**恒等操作**（counts 列和恒等 totals[j]），audit 实测 CI 仍与 rescale 后点估计异尺度。
3. **根因（探针实证）**：rescale_to_totals 的除数是**暴露列和 Σ_a h**，欠拟合字典下 ≠ 样本 totals（字典够不到的通道带无法吸收的质量）——counts 列和与暴露列和是两个不同的量。
4. **正确修复**：boot 每列暴露过与点拟合同一 rescale_to_totals（除数 = boot 暴露列和；零和列 → 0）。欠拟合回归：6/6 点估计入 CI（修复前 0/6）。

## 终审记录
- 批次 A/C 终审（agent_53167f57 + 09353db5/8c79afec 链）：4 golden 修复非驯化确认、混合零分布数学独立重推正确（9 点 χ² 锚 1e-15、R 孪生 1e-14）、spec@seed 契约缺口确认 → registry 警告 + 装配 fallback 落地。
- P2 收口：精确有理数锚 0.754087680658908 (1e-9)、assign.rs 模块头三分支门控、cv.rs 编号、sparse min_iterations=500 与 ard max_iter=2000 vs 上游 2e6 divergence 记录、extending.Rmd sharp-edge 表述、test-extend-contract 警告+默认断言。
