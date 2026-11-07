# msuiter 仓库地图（PI 组装专家简报时的精确引用表）

原则：给子代理的必读清单必须精确到"文件 §节"，本表是查找表。路径均相对仓库根。

## 决策与范围
| 问题 | 位置 |
|---|---|
| 项目宪法（16 条决策 D1–D16） | vignettes/articles/architecture.qmd §0 |
| **功能覆盖矩阵（完备性权威检查表，含各能力默认方法与里程碑）** | vignettes/articles/capability-matrix.qmd |
| 当前版本轨道 / 工作单元 / Non-goals | vignettes/articles/roadmap.qmd（v3 双轨：v0.1/v0.2/v1.0；G0–G3 组织门） |
| 历史裁决（评审采纳表） | vignettes/articles/review-00-synthesis.qmd |
| 五专家评审原文（Why 的证据） | vignettes/articles/review-01-computational-biologist.qmd、review-02-rust-r-engineer.qmd、review-03-ml-statistician.qmd、review-04-software-engineer.qmd、review-05-nature-editor.qmd |
| 开发日志（每工作单元一条） | vignettes/articles/devlog-YYYY-MM-DD-<name>.qmd |

## Rust 侧
| 问题 | 位置 |
|---|---|
| FFI 八条硬契约 / workspace 布局 / 依赖预算 / RNG | vignettes/articles/architecture.qmd §2 |
| 引擎语义与更新方程、Cornet/ARD/SUITOR 语义 | vignettes/articles/research-01-extraction-methods.qmd（§1–§13） |
| rust-NMF 实测基准与 bit 等价注意事项 | vignettes/articles/research-01-extraction-methods.qmd §10、vignettes/articles/research-04-source-audit.qmd §14 |
| rust-NMF（GPL 禁复制）/NNLM/RcppML 许可与语义 | vignettes/articles/research-04-source-audit.qmd §14、§19–20 |

## 通道语义（金标准来源）
| 问题 | 位置 |
|---|---|
| SBS/DBS/ID 通道算法（file:line 级） | vignettes/articles/research-04-source-audit.qmd §1（SPMG）、§19（复刻清单） |
| CN48/SV32/RNA-SBS 标签与 per-build 可用性 | vignettes/articles/research-05-standards-data.qmd §2（含 per-build 矩阵表） |
| MNV/complex 路由契约 | vignettes/articles/architecture.qmd §7 条目 2（目录完备性契约） |
| ID89/476（Koh 2025，v1.x） | vignettes/articles/research-07-algorithm-zoo.qmd §1.12 |

## R/S7 侧
| 问题 | 位置 |
|---|---|
| S7 现状/性能实测/引擎注册表蓝图 | vignettes/articles/research-06-s7-class-system.qmd（全篇）；vignettes/articles/architecture.qmd §3 |
| 引擎动物园实现策略表（Rust/R/Adapt/Skip） | vignettes/articles/research-07-algorithm-zoo.qmd §2 |
| API 形态（对象/泛型/错误/生命周期） | vignettes/articles/architecture.qmd §3 |

## 统计与方法
| 问题 | 位置 |
|---|---|
| 拟合算法精确语义（MuSiCal/mSigAct/QP/EM） | vignettes/articles/research-02-fitting-inference.qmd §1 |
| estimand/校准/conformal 纪律 | vignettes/articles/review-00-synthesis.qmd A1/A2；vignettes/articles/architecture.qmd §5 |
| 不确定性方法对比表 | vignettes/articles/research-02-fitting-inference.qmd §2 |
| 损失函数理论 | vignettes/articles/research-02-fitting-inference.qmd §3 |

## 基准与性能
| 问题 | 位置 |
|---|---|
| 指标协议逐位定义（Islam/Jiang/Medo） | vignettes/articles/research-07-algorithm-zoo.qmd §1.20；vignettes/articles/architecture.qmd §8 |
| 场景网格与三层隔离 | vignettes/articles/architecture.qmd §8 |
| 性能预算表 | vignettes/articles/architecture.qmd §8 |
| 公共数据集/生成器 | vignettes/articles/research-05-standards-data.qmd §5、vignettes/articles/research-07-algorithm-zoo.qmd §2(j) |

## 应用工作流
| 问题 | 位置 |
|---|---|
| Top-10 工作流与 PMID | vignettes/articles/research-03-applications.qmd |
| HRD 范围安全契约（WGS-only 等） | vignettes/articles/architecture.qmd §7、vignettes/articles/roadmap.qmd M6s；vignettes/articles/review-01-computational-biologist.qmd #2 |
| RNA 工作流边界 | vignettes/articles/review-01-computational-biologist.qmd #8；vignettes/articles/architecture.qmd §11 |

## 数据与许可
| 问题 | 位置 |
|---|---|
| COSMIC 许可分析与捆绑策略 | vignettes/articles/research-05-standards-data.qmd §1；vignettes/articles/architecture.qmd §0（D3/D4） |
| refdb 治理（precedence/schema/manifest） | vignettes/articles/architecture.qmd §6 条目 2（参考库治理） |
| CRAN Rust 政策引文 | vignettes/articles/research-05-standards-data.qmd §6 |

## 工作记录
| 问题 | 位置 |
|---|---|
| 开发日志（每工作单元一条） | vignettes/articles/devlog-YYYY-MM-DD-<name>.qmd |
| FFI 导出面冻结清单 | vignettes/articles/ffi-surface.qmd（M0 起建立；按需创建，首个 FFI 导出 PR 时建立） |
