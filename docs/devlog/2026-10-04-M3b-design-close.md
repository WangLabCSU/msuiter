# Devlog · M3b 设计备忘 + M3a 关闭确认轮（2026-10-04）

## M3a 关闭确认轮：PASS
- 270d5db P2 修复落地：registry seed 警告降级（硬拒绝降为 msuiter_warning_registry，注册表机械测试恢复 119 PASS）、装配 tryCatch fallback（警告 + seed=1，test-extend-contract 断言双重路径）、ffi-surface ms_fit_bootstrap_rust 后置步注记、sparse/ard validator j/c 全分支（9/9 探针全 msuiter_error_engine）。
- 六单元关闭扫签矩阵：commit+测试证据逐格在位；devlog 遗留清单无孤儿。
- 收口修复：sitrep refdb/ms_fit 过期口径更新（refdb v1 已捆绑、MSU-Fit 校准指向 M3b）+ 测试期望同步 + nodefault 测试 expect_warning 包裹。

## M3b 设计备忘（docs/devlog/2026-10-04-M3b-design-memo.md，草案 v1.0 待裁决确认）
- **核心论证**：BCa 零额外重采样成本（z₀ 来自现有 boot 样本；加速度 a 走固定 active set 解析影响函数，一次 LDLᵀ）；percentile 为退化回退（Hall 1988：percentile O(1/√N) vs BCa O(1/N)）；分层 calibrated-percentile 仅作系统性残差升级臂（Beran 1987 prepivot，非 conformal）。
- 网格：N 对数 11 点（50–10⁵）× Shannon 3 档 × 真值 share 6 点（0.01 清零阈两侧）= 198 cell × 2 臂 × M=2000；判据窗 [0.930,0.970]。
- 双臂：多项主臂（校准声明载体）+ NB 臂（Jiang 协议，κ=8 主锚 + 敏感性扫 {2,8,50,200,Poisson}）；失败阶梯 percentile→BCa→分层→估计器缺陷回修（禁止加宽区间掩盖）。
- 复合清零：share<0.01 ∨ stability<0.95 ∨ ci_lower_share<0.01；复合覆盖率 = 混淆四格 + FPR/FNR 分解。
- sanity：PCAWG 高 TMB 十分位 ≥20 例，永不写成 calibration 证据。
- D13：能声明 "首个（to our knowledge）对 exposure CI 做全网格经验覆盖率测量并报告，双生成模型 + real-data sanity"（Medo 2024 open question，检索快照日期入论文）；不能声明 distribution-free/conformal/first-CI/family-wise。
- 切分：U-M3b-01 NB 采样原语（engine，resample.rs 明示缺口）→ 02 BCa+FFI → 03 校准驱动 → 04 R 面+孪生 → 05 曲线/判据/viz → 06 real-data harness。

## PI 裁决（三分叉）
1. **BCa 默认**：采纳（成本近零；percentile 退化回退；分层表进 v1.0 校正臂）。
2. **NB 原语**：per-channel 独立 NB（匹配 mSigAct/Jiang 似然族）；κ=8 主锚；流字契约放宽为"数据依赖但纯函数"落 U-M3b-01 新单元。
3. **sanity 数据源**：PCAWG WGS 主 + TCGA GDC open WXS 副；容差 ±0.05；WES/panel 轴推迟 M4。
