# Devlog · G3 事件驱动竞争复核：Cornet 预印本正式发表（2026-09-28）

> 触发：风险登记（ARCH §11）"Cornet 正式发表压制相关性组件"事件发生——Hu, Geiger, Glodzik, Gulhan & Park, *Correlation-aware discovery of co-occurring mutational signatures in cancer*, bioRxiv 2026.09.14.751548（2026-09-21 挂网，Harvard/MIT；一作 Jin Hu 即 MuSiCal 一作）。本复核早于 ~2026-12 季度节点，属事件驱动。
> 论文核心：现有方法假设签名间**相互独立**，现实不成立（共同病因驱动共暴露）→ 强相关下 de novo 提取产生复合/污染签名、检出力下降。Cornet 联合推断签名 + 相关结构；模拟（Wu 2022 网格，r=0.8–0.95）+ TCGA 应用：无监督发现口腔癌 SBS88（colibactin）、膀胱癌 SBS4（此前认为不存在）、EOSCRC 新内源过程、smoking×ERCC2 交互签名。

## 裁决：kill criterion **未触发**，A4 预置策略成立

评审合成 A4 当时的裁决正是为这一刻设计的：相关性引擎已降级为框架组件（v1.x）、以预注册可证伪声明守住位置（Wu 2022 网格 r∈{0.8,0.9,0.95} 上须同时击败 plain KL-NMF / MvNMF / **原版 Cornet** / 相关性感知 refit）。论文发表使该声明的基线 (iii) 从传闻变为**可运行的公开对拍对象**。相关性引擎的范围与排期不变；其价值主张从"方法新颖性"转为 **D15 接口对等**——Cornet 成为注册表中一行可换引擎，benchmark 文化照常运转。

## 对 Framing A 的影响：零冲突，且车道变空

Cornet 改进的是**点估计**（强相关下的签名恢复），完全不触碰**区间校准**——全领域仍然无人验证过 exposure 区间的实际覆盖率（G0 现实性备忘的检索结论维持）。反而：领域注意力被点估计方法吸走后，校准车道更空。注意一个交叉点：**G0 的 flat 层（SBS5/40）本身就是"强相关签名下的区间覆盖"探针**——"相关性不只破坏点估计、还破坏区间"是可检验的新命题，G0 初探 + M3b 系统化，是 Cornet 之后的自然延伸位。

## 威胁面升级（G0 紧迫性的实质理由）

Park 组现在同时持有主流拟合工具（MuSiCal）+ 相关性感知提取（Cornet）。其下一步最可能方向即给 MuSiCal 拟合补不确定性量化——**这正是 kill criterion"竞品发布校准 CI"**。窗口以月计而非年计。结论：**G0 从并行轨道升级为 Framing A 的关键路径**——先发登记"覆盖率从未被验证 + 实测确实失准"这一事实，就是占位。

## 行动项

1. **G0 立即执行**（F1–F4 已于 2026-09-28 冻结，见 [G0 裁决文档](2026-09-28-G0-pi-adjudication.md)）；harness 中与竞品环境无关的部分（模拟生成/覆盖率计算/自校验）即日开建；F5 环境待作者指定。
2. 相关性引擎（v1.x）benchmark 规格补充：Cornet bioRxiv DOI 入引文与对拍清单（U-M2 之后、v1.x 开工前落地）。
3. G3 观察名单（下次季度复核 ~2026-12 前持续跟踪）：MuSiCal 版本动态（尤其 uncertainty 相关 API）、Cornet 期刊接收动态、SigFormer、STL/sigfit 更新。
4. v0.1/v0.2 范围**不变**（本事件不产生任何 M0/M1s/M2/M3a 范围变更）。
