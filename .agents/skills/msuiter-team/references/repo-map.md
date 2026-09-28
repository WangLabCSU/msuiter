# msuiter 仓库地图（PI 组装专家简报时的精确引用表）

原则：给子代理的必读清单必须精确到"文件 §节"，本表是查找表。路径均相对仓库根。

## 决策与范围
| 问题 | 位置 |
|---|---|
| 项目宪法（16 条决策 D1–D16） | docs/ARCHITECTURE.md §0 |
| **功能覆盖矩阵（完备性权威检查表，含各能力默认方法与里程碑）** | docs/CAPABILITY-MATRIX.md |
| 当前版本轨道 / 工作单元 / Non-goals | docs/ROADMAP.md（v3 双轨：v0.1/v0.2/v1.0；G0–G3 组织门） |
| 历史裁决（评审采纳表） | docs/reviews/00-synthesis.md |
| 五专家评审原文（Why 的证据） | docs/reviews/01–05 |
| 开发日志（每工作单元一条） | docs/devlog/YYYY-MM-DD-<work-unit>.md |

## Rust 侧
| 问题 | 位置 |
|---|---|
| FFI 八条硬契约 / workspace 布局 / 依赖预算 / RNG | docs/ARCHITECTURE.md §2 |
| 引擎语义与更新方程、Cornet/ARD/SUITOR 语义 | docs/research/01（§1–§13） |
| rust-NMF 实测基准与 bit 等价注意事项 | docs/research/01 §10、docs/research/04 §14 |
| rust-NMF（GPL 禁复制）/NNLM/RcppML 许可与语义 | docs/research/04 §14、§19–20 |

## 通道语义（金标准来源）
| 问题 | 位置 |
|---|---|
| SBS/DBS/ID 通道算法（file:line 级） | docs/research/04 §1（SPMG）、§19（复刻清单） |
| CN48/SV32/RNA-SBS 标签与 per-build 可用性 | docs/research/05 §2（含 per-build 矩阵表） |
| MNV/complex 路由契约 | docs/ARCHITECTURE.md §7.2 |
| ID89/476（Koh 2025，v1.x） | docs/research/07 §1.12 |

## R/S7 侧
| 问题 | 位置 |
|---|---|
| S7 现状/性能实测/引擎注册表蓝图 | docs/research/06（全篇）；docs/ARCHITECTURE.md §3 |
| 引擎动物园实现策略表（Rust/R/Adapt/Skip） | docs/research/07 §2 |
| API 形态（对象/泛型/错误/生命周期） | docs/ARCHITECTURE.md §3 |

## 统计与方法
| 问题 | 位置 |
|---|---|
| 拟合算法精确语义（MuSiCal/mSigAct/QP/EM） | docs/research/02 §1 |
| estimand/校准/conformal 纪律 | docs/reviews/00-synthesis.md A1/A2；docs/ARCHITECTURE.md §5 |
| 不确定性方法对比表 | docs/research/02 §2 |
| 损失函数理论 | docs/research/02 §3 |

## 基准与性能
| 问题 | 位置 |
|---|---|
| 指标协议逐位定义（Islam/Jiang/Medo） | docs/research/07 §1.20；docs/ARCHITECTURE.md §8 |
| 场景网格与三层隔离 | docs/ARCHITECTURE.md §8 |
| 性能预算表 | docs/ARCHITECTURE.md §8 |
| 公共数据集/生成器 | docs/research/05 §5、07 §2(j) |

## 应用工作流
| 问题 | 位置 |
|---|---|
| Top-10 工作流与 PMID | docs/research/03 |
| HRD 范围安全契约（WGS-only 等） | docs/ARCHITECTURE.md §7/ROADMAP M6s；reviews/01 #2 |
| RNA 工作流边界 | reviews/01 #8；ARCHITECTURE §11 |

## 数据与许可
| 问题 | 位置 |
|---|---|
| COSMIC 许可分析与捆绑策略 | docs/research/05 §1；ADR D3/D4 |
| refdb 治理（precedence/schema/manifest） | docs/ARCHITECTURE.md §6.2 |
| CRAN Rust 政策引文 | docs/research/05 §6 |

## 工作记录
| 问题 | 位置 |
|---|---|
| 开发日志（每工作单元一条） | docs/devlog/YYYY-MM-DD-<work-unit>.md |
| FFI 导出面冻结清单 | docs/ffi-surface.md（M0 起建立） |
