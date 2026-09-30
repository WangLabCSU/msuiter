# Devlog · U-M1c-02 GMM 超突变分层器（2026-09-30）

## 交付
- **设计备忘先行**：`docs/devlog/2026-09-30-GMM-stratify-memo.md` —— SigProfilerExtractor（master `cc6bf5ef` = v1.5.0 merge；行号级源码考古）超突变处理 = **原始计数上的 k=2 GMM（无 log 变换）+ 多数簇迭代剪枝（4σ 停止）+ 保留集 mean+2σ 截断 + 100×通道数下限**；上游分层后行为是 **rescale 归一化，不是排除+refit**（全史 grep 证实任何版本无分离-合并实现）——ARCH §5「分类+排除 de novo+强制 refit，非归一化」为我方 deliberate divergence，cutoff 规则与谓词忠实复刻、下游用途声明偏离。D13 裁决记录在案。
- **engine `stats.rs`**（新模块）：`fit_gmm1d`（k=2 EM；log-sum-exp E 步；M 步 sklearn 序 = 先均值后方差；加性 `GMM_VAR_REG=1e-6` 方差地板 = reg_covar 平价；tol 1e-8 / max_iter 200，不收敛返回 flag 不报错；分量均值升序规范化）+ `normalization_cutoff`（§1.3 剪枝逐行翻译：总体 mean/σ、argmax 首最大平局、向零截断、下限托底、拟合失败 break = 上游 try/except 平权）+ `classify_hypermutants`（严格大于）。播种初始化走 MsRng canonical 流布局（`StreamId::ZERO` 单流贯穿整个 cutoff 计算）：**播种锚点 + 最远点搭档**（距离感知 = sklearn kmeans++ 的确定性等价物；双随机点 init 在 lone-outlier 场景实测漏分，已废弃）。
- **R `R/stratify.R`**：`ms_stratify_hypermutants(catalog, manual_cutoff = NULL, seed = 1)` —— MsCatalog 路径（totals = colSums，floor 默认 100×nrow = 上游调用点约定）与命名 TMB 向量路径；返回 **MsStratification** S7 对象（cutoff / totals / hyper / nonhyper / 两组 counts / gmm 诊断（cutoff 图钩子）/ `policy = "exclude_de_novo_then_refit"`（M2 语义钩子）/ seed）；print/format 一行式；错误纪律 `msuiter_error_input` / `msuiter_error_stratify`。
- **R 内置 MsRng 位精确复刻**（16-bit limb 双精度算术，全程 < 2^53 精确）：PCG64 + SplitMix64 + canonical 流布局 v1。本单元文件集冻结不含 FFI 壳 ⇒ R 为**协议孪生**（同一 EM/剪枝/谓词），KAT 测试直接钉 rng.rs 冻结 golden；M2 FFI 落地后退役为参考实现。

## 测试
- Rust `stats` 内联 11 测：golden（双峰 cohort cutoff=13804/retained 44/labels、模型参数 1e-6 相对容差；lone-outlier 剪枝 cutoff=6375）+ seed 1..8 稳健性 + 退化（全同值/单样本/双样本平局取低标号）+ floor 语义 + 谓词严格大于 + 确定性逐位 + 结构化 argument 错误。
- testthat 10 块 73 断言：PCG64 KAT vs rng.rs 冻结 golden（位级）；R golden 与 Rust 同 fixture 同值（13804/6375/7000/12345/20000 跨语言整数级一致）；MsCatalog 端到端（注入 6 超突变样本被完整分出）；`identical()` 确定性；谓词边界；format；validator 篡改拒绝；5 条错误路径。
- `devtools::test()` 全绿（1433 PASS / 0 FAIL）；R CMD check 0 e / 0 w / **1 NOTE（License，既有，与本单元无关）**（--no-manual：环境无 pdflatex）；cargo test --workspace 15 套件绿；clippy --all-targets 0；deny 绿；`+1.71.0` stats 绿；release profile build 绿（P0-2 先例门）；Cargo.lock 零变化；docs-sync 绿；ffi-surface 漂移守卫绿（零 FFI 改动）。

## 实现轮修复的三个真 bug（记录备查）
1. **EM 责任越界 → 方差为负 → NaN**（Rust 与 R 同病）：rounding 可使责任 >1 若干 ulp，`r1 = 1 − r0 < 0` 驱动塌缩分量方差 <0，`log(var)` 产 NaN。修复 = 责任 clamp 进 [0,1]，双端逐位镜像（EM 卫生，进 memo §2.1）。触发器：3 点小样本塌缩路径；既有 golden 因方差大而未暴露。
2. **R PCG64 状态不推进**：R 传值语义下函数内 `rng$state <- …` 改的是局部副本——生成器每调用复位。修复 = 生成器迁入 environment（引用语义，镜像 Rust `&mut MsRng`）。
3. **inc 移位丢进位**：`(initseq << 1) | 1` 的 bit-63 进位须落 bit-64（Rust u128 语义）；R 初版在 64 位字上移位。修复 = 零扩展到 128 位再移位。KAT（seed 42 ZERO / offset 流 / seed 0 offset）三者全过即钉死。

## 边界与遗留
- FFI 接线（`ms_stratify_rust`）与排除 de novo + 强制 refit 流水线 = M2；本单元 R 侧协议孪生在那之后退役。
- 跨语言位一致**只承诺 PCG64 整数流**（KAT）；EM 浮点参数在 tol 球内随 libm 漂移（Rust golden 钉位、R 断言放宽到 1e-4 相对），cutoff 为整数故跨语言钉死——D11 双层验收的对应落实。
- 已知失败模式（照录上游，memo §4）：超突变簇为多数时剪枝剥低尾；n 极小（<10）时 EM 塌缩使 cutoff 被离群值抬高（如 3 样本冒烟案例）——真实队列域不触发。
- 并行单元提示：工作树中 catalog crate 的 cn48/sv32 为其他单元产物，本单元零接触。
