# 调研报告 06：S7 类系统现状、设计模式与方法框架蓝图
> ℹ️ **文档性质**：本篇为调研快照（archival snapshot，核实日期见文内）。活决策以 [ARCHITECTURE.md](../ARCHITECTURE.md) §0（D1–D16）与 [reviews/00-synthesis.md](../reviews/00-synthesis.md) 为准；文中方法命名（如 MSU-Extract、MSU-Corr）为当时措辞，现行命名见 ARCHITECTURE §5；benchmark 指标以 [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) 与 ARCHITECTURE §8 为准。


> 调研日期：2026-09-28。对照 CRAN、RConsortium/S7 仓库、R base NEWS、官方 vignette、tidymodels/mlr3 源码与本地实测（R 4.5.2 + S7 0.2.2, arm64）核实。**[unverified]** 项已标注。

---

## 1. S7 现状（2026 末）

- 仓库已迁移至 **`RConsortium/S7`**（文档 rconsortium.github.io/S7），活跃（2026-09-26 有提交）。
- CRAN **S7 0.2.2**（2026-04-22），`Depends: R (>= 3.5.0)`。版本史：0.1.0 (2023-08) → 0.2.0 (2024-11，新构造语义、惰性默认值、`prop()` C 重写) → 0.2.1 (2025-11) → 0.2.2 (2026-04)。
- **尚未合入 base R**（R 4.6.1 NEWS 零提及 S7 本体；合入的是"使能钩子"：R 4.3 的 `@` 成为 S3 泛型 + `nameOfClass()`、R 4.4 的 OBJSXP）。RConsortium/S7 issue #542 确认**无合入时间表**（维护者 Michael Lawrence：先要采用率）。
- **依赖策略**：现在依赖 S7 安全（CRAN 已有 104 个包声明），需 `Imports: S7` + `.onLoad()` 中 `methods_register()`；若支持 R ≥ 4.3 则无需 `@` 兼容垫片。**建议地板 R >= 4.3。**

## 2. S7 特性清单（0.2.2 已核实导出）

- 类：`new_class(name, parent, package, properties, validator, constructor)`；**抽象类** `abstract = TRUE`；`new_union(...)` 联合类型；`new_S3_class()` 包装 S3；`S4_register()`（dev 已支持 S7↔S4 双向继承）。S7 对象本质是 S3 对象（class = `c("pkg::Foo", "S7_object")`）——**RDS 往返安全**（dev 处理 `_S7_class` 属性改名与旧序列化回退）。
- 属性：`new_property(class, default(惰性), getter, setter, validator, name)`——**动态/计算属性、只读 setter、惰性默认**；`x@prop` 读写、`set_props(check=)` 批量跳过校验、`prop_names()/prop_exists()`。
- 校验：类级 `validator = function(self) 返回问题字符向量`；构造与属性写入时即校验；`validate()/valid_eventually()/valid_implicitly()` 控制时机。
- 泛型：`new_generic` + `S7_dispatch()`；`method(foo, Class) <- ...` 多重分发；**可对 base/S3/S4 泛型注册方法**（print/plot/summary/`$`/数学组）；`new_external_generic("pkg", "gen", "sig")` 声明对建议包泛型的方法（懒接线）；扩展包经 `zzz.R` 的 `methods_register()`（dev: `S7_on_load/S7_on_unload/S7_on_build`）。
- **无 `class_externalptr`、无 altrep 类**：externalptr 经 `class_any` 属性 + 自定义校验器持有（r-polars 方向确认此为官方意图）；S7 保留 ALTREP 但不制造。
- **性能（本地实测，200k 次）**：单分发 ≈ 6.2 µs（S3 ≈ 2.0）；双分发 ≈ 10.1 µs；属性读 `@` ≈ 1.2 µs、**写 ≈ 17 µs**（写触发全对象重校验）；构造+校验 ≈ 50–85 µs/对象。
- **工程铁律**：S7 只在 API 边界；逐通道/逐样本循环绝不进 R（推入 Rust）；热路径避免 `@<-`（用 `set_props(check=FALSE)` 暂存 + 一次性 `validate()`）；externalptr 不随 RDS 存活 → 需要重连/序列化策略（polars 模式：存输入+参数、按需重建句柄）。

## 3. 生产采用（证据）

- **ggplot2 4.0.3**（2025-09）：NEWS 明言"S3 parts replaced with S7 bits"——最强背书；ggiraph/GGally/ggrepel 等 gg 生态跟进。
- Posit/r-lib：ellmer、marquee、ragnar、shinychat、**filtro**（Max Kuhn，首个 tidymodels 系 S7 注册表，见 §5）、desirability2；Rust/R 混合：**caugi 1.3.0**（extendr + S7，我们的最佳先例，见 §4）；计算：osqp/CVXR/quickr。
- Bioconductor：官方积极但早期——`Bioconductor/S7Examples`（BiocClasses 工作组）、plyxp/anansi；**BioC2026 主题演讲 "S7 for Bioconductor"（Michael Lawrence）**。若未来投 Bioc 需预留 `S4_register()` 互操作。
- 无 r-lib/s7 旧地址（已迁移）；rextendr 0.5.0 **无 S7 codegen**——S7 层自己写（薄，一次性工作）。

## 4. S7 + extendr 集成先例：caugi 模式（我们的模板）

- Rust 状态藏于懒建 **"Session"**：S7 类的 `session` 属性为 `class_any`，**setter 直接报错**（只读，仅经领域动词 `add_nodes()`/`add_edges()` 重建）——Rust 状态写保护。
- **派生属性 = 计算 getter**：`nodes`/`edges` 属性无存储，getter 调 Rust 访问函数返回新鲜 R 数据。*存不透明句柄，按需投影 R 友好视图。*
- `zzz.R` 全舞步：`methods_register()` + S4 钩子 + waldo `compare_proxy`（testthat 比较用）。
- Rust 侧注册表（边类型）以 externalptr 环境单例持有，R 只暴露 `list_/register_/reset_` 动词。

**本项目应用**：extendr 返回的不透明状态（目录句柄、拟合状态）放 `class_any` 只读属性；用户可见物一律 typed+validated 属性；领域动词经 Rust 往返变更；`print/format/plot` 早实现；`compare_proxy` 注册进测试。

## 5. 面向 benchmark 的方法框架设计模式（从源码提取）

| 生态 | 对象系统 | 注册表模式 | 关键 API |
|---|---|---|---|
| **parsnip** (S3) | spec 对象（`model_spec` 子类）+ 命名空间环境注册表（数据而非方法表） | `set_new_model/set_model_engine/set_fit/set_pred/set_dependency`；`translate()` 先解析后执行 | 第三方扩展 = `.onLoad()` 调 `set_*` 写数据行 |
| **yardstick** (S3) | 度量注册 | `new_numeric_metric(fn, direction)` 构造器 + `metric_set()` 组合器 | 结果 tibble 带 `.metric/.estimator/.estimate` |
| **dials** (S3) | 参数空间 | `new_quant_param/new_qual_param`（range/trans/label、`unknown()`） | — |
| **workflows/hardhat** (S3) | 编排 + **提取泛型契约** | `extract_preprocessor/extract_recipe/extract_mold/extract_fit_parsnip/extract_fit_engine/extract_fit_time` | **让所有引擎的产物可统一内省——benchmark 友好的关键，照抄精神** |
| **mlr3** (R6) | 抽象 `Learner`（`$train/$predict` 委托私有 `$.train`）+ Dictionary 注册（`.onLoad` 注册、`register_namespace_callback`） | `mlr_learners` 字典；`benchmark()/benchmark_grid()` Task×Learner×Resampling → `rr$score()` tibble | 基准网格 + 统一评分 |
| **filtro** (S7!) | S7 `class_score`：元数据属性（direction/range/tuning/packages/label/calculating_fn=class_function/results=class_data.frame）+ 每方法子类 + `method(required_pkgs, class_score)` | **最接近我们问题的 S7 模板** | — |

**统一模板**：spec 对象（小、可序列化、元数据丰富）→ 注册表行 (spec 类型, engine, mode) → resolve/translate → fit → 结果对象（内嵌 spec + extract_* 泛型族）→ 扩展 = 载入时写注册表数据。

## 6. 本项目的 S7 蓝图（推荐）

```r
# ---- 数据层 ----
MsVariants  : 变异表 + genome + provenance（输入容器）
MsCatalog   : counts(通道×样本, 尺寸一致性 validator) + channels(注册表快照)
              + samples + provenance —— 通道标签匹配在构造器强制
# ---- 规格层（parsnip/filtro 式 spec）----
MsEngine    : 抽象（name/mode/packages/params(dials 式)/deterministic/label）
  ├─ MsNmf        # KL/EU/HALS 变体经 params 选择
  ├─ MsArd        # 自动 K 分诊
  ├─ MsSparse     # 体积正则（mvNMF 思想的自研实现）
  ├─ MsCorrelated # 相关性感知（自研优化实现）
  ├─ MsLda        # 主题模型
  └─ MsSupervised # SuperSigs 式监督提取
# ---- 结果层 ----
MsSignature : signatures + exposures + stability + K 证据 + engine + seed
              + .state(class_any, setter 报错——caugi 式只读 Rust 句柄)
MsFit       : exposures + support + tests(CI/LRT) + reference + engine
MsRefDb     : 版本化签名库（per-build 可用性元数据）
MsBenchmark : Task×Engine×场景 网格结果（mlr3 式 score tibble）
```

- 自定义泛型（小集合）：`ms_tally()`, `ms_extract()`, `ms_fit()`, `fit_engine()`, `extract_signatures()/extract_exposures()/extract_state()/extract_fit_time()`（hardhat 命名）、`required_pkgs()`（filtro 先例）、`ms_benchmark()`。
- 复用 base/S3 泛型：print/format/plot/summary/knit_print（`new_external_generic("knitr",...)`）。
- **注册表 = 数据不是类爆炸**：薄引擎用注册表行，重不变量的引擎用 S7 子类（混合策略）。
- 互操作：`as.data.frame()/convert()` 到 tibble；ggplot2 4.x 本身 S7，可无缝；RDS 序列化 = 存 spec+inputs，句柄按需重建。
- **S7 未入 base R 的风险对冲**：S7 对象即 S3——语义回退天然安全；地板 R ≥ 4.3。

## 7. 引用/证据

- CRAN S7 0.2.2；RConsortium/S7（docs：rconsortium.github.io/S7）；base R NEWS（4.3/4.4 使能钩子；4.6.1 无 S7）；R Core 博客 "Generalizing Support for Functional OOP in R" (2024-05)
- ggplot2 4.0.0 NEWS #6352；CRAN 依赖扫描（104 包）；BioC2026 日程；Bioconductor/S7Examples
- caugi 1.3.0 源码（session/只读属性/zzz.R 舞步）；extendr crate 0.9.0（ALTREP 警示 + issues #945/#743）
- parsnip `R/aaa_models.R`、yardstick NAMESPACE、dials、workflows/hardhat extract_* 泛型、mlr3 1.8.0 `Learner`/Dictionary/zzz.R、filtro（S7 class_score）
- 本地实测性能数字（R 4.5.2, S7 0.2.2）
