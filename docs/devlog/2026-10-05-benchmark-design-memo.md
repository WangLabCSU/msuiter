# M7 前置设计备忘：ms_benchmark() 网格驱动器

日期：2026-10-05 晨（窗口尾批——**设计冻结，实现为 M7 本体**）。范围：CAPABILITY-MATRIX L3 "ms_benchmark() | mlr3 式基准网格；non-certified 引擎显式 warning | M0 骨架/M7 完备"。M0 已交付 MsBenchmark 容器（R/classes-benchmark.R：results/.engine/.scenario/.metric/.estimate + settings）；本备忘冻结 M7 网格驱动器的 API、场景语义与验收锚——**实现开工前须 PI 对两个开放裁决点表态**（§5）。

## §1 API 冻结草案

```r
ms_benchmark(grid, engines = NULL, seed = 1, ...)
```
- `grid`：`ms_benchmark_grid()` 构造的场景网格对象（list-of-scenarios，每 scenario = 生成参数集，§2）。
- `engines`：引擎名字符向量（注册表解析，`match_ms_engine` 语义）；NULL = 全部 certified 引擎。**non-certified 引擎显式 warning 一次**（M0 骨架语义，v0.2 已定：一次性告警 + 继续）。
- 每 (scenario × engine) cell：`ms_extract`/`ms_fit` 端到端 → 评分 → MsBenchmark。
- 每引擎 setup/teardown 钩子（engine 契约的 `required_pkgs` 检查前置，缺席 → cell 标 `skipped` 不中断网格）。
- 评分矩阵经 `ms_compare()` 三协议 + exposure L1/cosine（ARCH §指标）+ 运行时（`ms_extract_fit_time` 语义）。

## §2 场景网格语义（ARCH §8 的机器可读化，分层冻结）

场景 = 命名参数结构，字段全部有冻结默认（CI sanity bound 用小子集；钉硬件 bench 用全网格）：

| 轴 | 取值（冻结默认） | 备注 |
|---|---|---|
| TMB | 10²–10⁶ 对数 5 点 | sanity = {1000, 10000} |
| 签名数 k | 1–20（5 点） | sanity = 3 |
| 相关性 | {0, 0.5, 0.8, 0.95} | 平坦组内 r=0.8 + 稀有共存 = 联合场景字段 |
| purity | {1.0, 0.7, 0.4, 0.2} | 正常 cell 混入 |
| caller | ≥2 SNV + ≥2 indel | 场景生成器的 caller 噪声模型字段 |
| 平台 | WGS/WES/panel | 机会归一经 ms_convert 语义 |
| 参考误设 + 目录外 | 布尔 | 目录外签名 cell = FP 压力 |
| 超突变臂 | 5–10% 样本 100× TMB | APOBEC/POLE cutoff 敏感性 |
| 亚克隆结构 | 布尔 | exposure 分层 |
| 类别计数区间 | SV 10–10³、CN 10–10⁴ | 模态专属 |

**三层生成器隔离**（ARCH §8，协议发表前冻结随包）：校准/模型选择/评估场景分别绑定 `ms_simulate`（计数层，已交付）/SynSig 适配器/PCAWG 锚定混合。第一版交付校准场景驱动器（`ms_simulate` 直驱），后两层为 M7 适配器单元。

## §3 评分契约

- 主指标 = Hungarian 一对一 P/R/F1（`ms_compare(protocol="hungarian")` 主表直读）；Islam 贪心 + 阈值扫 0.80–0.90 附录；Jiang CS（fit-evaluation 场景）。
- exposure L1/cosine：absolute 与 compositional 双口径（与引擎 estimand 对齐——D16 语义注记）。
- 缺席签名误分配 = specificity 面（Jiang）。
- 运行时/内存：`proc_time` + gc峰值（钉硬件口径 CI 只 sanity）。
- results 表 schema = MsBenchmark 现有契约（.engine/.scenario/.metric/.estimate）。

## §4 验收锚（M7 实现时）

- 【整数/逐位】：seed 确定性（同 grid+seed → results 逐位同）；scenario 序稳定；non-certified warning 一次性；skipped cell 不产生 estimate 行。
- 【工程】：网格完整性（cells = scenarios × engines 全笛卡尔）；错误隔离（单 cell 失败 → 该 cell error 行 + 网格继续）；MsBenchmark validator 全绿。
- CI sanity bound：TMB{1000,10000}×k3×2 引擎×多臂 < 5 分钟。

## §5 开放裁决点（实现前须 PI 表态）

1. **评估引擎集合**：v0.2 期自有引擎（NMF/ARD/Sparse）互评，还是含竞品适配器（sigminer 已有；MuSiCal/SigProfilerAssignment 适配器 = M7 独立单元）？建议：先自有互评，竞品容器随 M7。
2. **评分的 exposure 对齐语义**：de novo 提取的签名无 1:1 真值对齐——对齐经 ms_compare Hungarian（一对一）后 L1 只在配对上算，还是最佳贪心？建议：Hungarian 配对 L1（与主指标同源）。

## §6 依赖

ms_simulate（✅ 已交付计数层）、ms_compare 三协议（✅）、引擎注册表（✅ M0）、SynSig/PCAWG 适配器（⏳ M7）、钉硬件访问（⏳ 运维）。
