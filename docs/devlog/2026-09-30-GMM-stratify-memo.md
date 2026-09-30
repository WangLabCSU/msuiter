# GMM 超突变分层语义设计备忘（U-M1c-02·先设计后实现）

> 2026-09-30。对象：ROADMAP M1c「GMM 分层器（`ms_stratify_hypermutants` 语义落地）」；ARCHITECTURE §2 `engine/stats.rs`（1-D GMM 分层器）、§5 共识-CV 流水线（「分类+排除 de novo+强制 refit，非"归一化"」）；CAPABILITY-MATRIX L-A（GMM cutoff + 排除 de novo + 强制 refit）。
>
> **证据基线**：SigProfilerExtractor 上游克隆 /tmp/audit-spe/repo。master = `cc6bf5ef`（2026-09-28，"Merge dev for v1.5.0 release"）；最新 tag `v1.5.0` = `a5d636a3`（同日）。行号均指 master `SigProfilerExtractor/subroutines.py`（下称 Sub）与 `sigpro.py`（下称 Sig）。注意：`AlexandrovLab/SigProfiler` 仓库现已是同一 Python 项目的镜像（非 2015 Matlab 原版）；Python 仓全历史最早提交 85dfe32（2018-09-10）至 master 的 "hypermut*" 全史 grep 仅命中归一化注释，**任何可检索版本都不存在「分离-排除-合并」实现**。

---

## 0. 结论速览（源码证据 vs GMM 叙事）

1. **上游确实用 GMM（k=2），但三处流行叙事都不成立，以源码为准**：
   - ① **无 log 变换**：GMM 拟合在**原始每样本突变计数**上（Sub:154/156-157）——"log 空间 GMM"不成立；
   - ② **cutoff 不是后验 0.5 交点、也不看分量均值序**：cutoff = 多数簇迭代剪枝后**保留集的总体 mean + 2σ**，`int` 截断，再被 `100 × 通道数` **下限托底**（Sub:195-200 + Sig:919）——GMM 只供标签，参数不进 cutoff；
   - ③ **上游不做两组单独提取/合并**：超突变样本被**重标定（rescale）压到 cutoff**，全员留在 de novo 提取与全部下游（Sub:474-489）——「分类+排除 de novo+强制 refit」在 SigProfilerExtractor 任何可检索版本中不存在，它是 msuiter ARCH §5 的**有意管线偏离**（原文钉死「非"归一化"」）。
2. 我方实现 = **忠实复刻 cutoff 规则 + 分类谓词**（语义逐位层，D11）；**声明偏离下游用途**（排除+强制 refit 代替 rescale，M2 承接）。GMM 只是上游的工具名，规则按源码逐行翻译。

---

## 1. 上游确切规则（逐问、行号级）

### 1.1 TMB 统计口径

- `col_sums = np.array(np.sum(data, axis=0))`（Sub:154）：**每样本目录列和 = 原始突变计数**。对基因组大小/exome 面积**不做任何归一**（机会归一不在该函数职责内）；对计数**不做 log 变换**——聚类输入即原始计数 `col_sums.reshape(-1, 1)`（Sub:156-157）。

### 1.2 GMM 配置

- `mixture.GaussianMixture(n_components=2, covariance_type="full", random_state=random_state)`（Sub:163-167）：**k=2**；1-D 数据下 "full" 即每分量标量方差；sklearn 默认 `init_params`（kmeans 族、随版本漂移）与 `reg_covar=1e-6`（**加性方差下限**，防退化）随行生效。
- 随机状态：**b71b6cd（2026-09-26，"Seed the GMM used for the normalization cutoff (review issue 4)"，首个发布于 v1.5.0）**之前未播种（不可复现）；自 v1.5.0 起 `random_state = int(SeedSequence(int(seed)).generate_state(1)[0])`（Sig:913-920，根种子派生；注释明言 "so that the cutoff is reproducible from Seeds.txt"）。

### 1.3 Cutoff 判定（多数簇迭代剪枝，Sub:154-200）

```
col_sums = 每样本原始计数
loop:
    fit GMM(k=2) 于当前 col_sums；labels = predict          # try/except 包裹，异常即 break（Sub:190-192）
    unique labels == 1 → break                              # Sub:169-170
    bigger = argmax(簇计数)   # np.argmax 首个最大 → sorted 标签序平局取小标签（Sub:171-172）
    smaller = argmin(簇计数)
    if |mean(bigger) − mean(smaller)| < 4·std(bigger) → break   # 4σ（2·2），总体 std（ddof=0）（Sub:186-192）
    col_sums = bigger 簇成员值；继续                          # 严格收缩 → 必终止（Sub:194）
mean = mean(保留集)；std = std(保留集)                        # 总体口径（Sub:196-197）
cutoff = int(mean + 2·std)                                   # numpy astype(int) 向零截断；正数域 = floor（Sub:195）
if cutoff < manual_cutoff: cutoff = manual_cutoff            # 下限托底（Sub:197-199）
```

- 调用点（Sig:918-919）：`manual_cutoff = 100 × genomes.shape[0]` = **100 × 通道数**（SBS96 → 9600；Sub:149 函数默认同为 9600）。剪枝语义 = 逐轮剥掉离群高尾，直到剩余主体"均质"（均值差 < 4σ 主体标准差）。
- 历史脚注：v1.0.4 时代（7bf11c4，Sub:165/222-223）`manual_cutoff=50000` 且方向**相反**（上限封顶 `if cutoff > manual_cutoff`）→ 现行（v1.1 起可检索）为下限托底。
- 语义要点：**GMM 的均值/方差/后验都不直接进 cutoff**；cutoff 只由保留集的总体统计量决定。剪枝隐含假设超突变者是少数（真实队列 5–10% 成立；若高负荷簇为多数，"bigger" 会选中高簇并剥低尾——失败模式照录，见 §4）。

### 1.4 分层后的行为

- 分类谓词 = `totalMutations > normalization_cutoff`（Sub:236，`normalize_samples` gmm 分支）；动作 = **重标定**：`genomes[:, hyper] = genomes[:, hyper] / totals[hyper] × cutoff`（Sub:474-489），即超突变列被压缩到总数恰为 cutoff，**不排除、不单独提取、无 refit**。注释原文：Sig:913 "get the cutoff for normatization to handle the hypermutators"（sic）、Sub:474 "normalize the samples to handle the hypermutators"。
- `matrix_normalization` 备选："gmm"（默认）/ "100X"（cap = 100×通道数）/ "log2"（各样本缩放到 log2 总数）/ "none" / 手工整数 cutoff（Sig:401；Sub:203、228-270）。
- 「超突变组单独提取 + 非超突变组排除超突变后提取 + refit 合并」的叙事**在本仓全史无实现**；它与 msuiter ARCHITECTURE §5 的流水线裁决（分类+排除 de novo+强制 refit，**非"归一化"**）相对上游 rescale 语义构成**声明的 deliberate divergence**。

---

## 2. 我方实现规格（裁决后）

### 2.1 Rust `engine/stats.rs`（冻结内核）

- `fit_gmm1d(x, master_seed, max_iter, tol)`：k=2 EM，log 空间 E 步（log-sum-exp）；M 步方差 = Σr(x−μ)²/Σr **+ 1e-6**（sklearn `reg_covar` 平价的加性方差下限，防全同值退化）；责任 r0 clamp 进 [0,1]（实现轮修复：rounding 可致 r0>1 若干 ulp，r1<0 驱动塌缩分量方差为负 → NaN——双端逐位镜像的 EM 卫生）；收敛判据 = 平均对数似然增量 < tol（冻结 1e-8，与 sklearn 的 lower-bound tol=1e-3 **声明为自选实现差异**）；上限迭代 200（不收敛返回 `converged=false`，不报错）。
- **播种初始化走 MsRng**：canonical 流布局（`LAYOUT_ID` MSURNGV1），本单元用 `StreamId::ZERO` 单流贯穿整个 cutoff 计算（含剪枝各轮）；init = **播种锚点 + 最远点搭档**（锚下标自种子流抽取，搭档 = 距锚最远的数据点，平局取最早下标）作初始均值（升序规范化，分量 0 = 低均值），权重 0.5/0.5，初始方差 = 全体总体方差 + reg_covar。该 init 与上游 sklearn k-means++ 同为距离感知（孤立极值必获一分量；实现轮曾试双随机点 init， lone-outlier 场景会漏分，已按此修正），同输入同种子**逐位一致**（单线程、固定归约序）。
- 分量/标签规范化：均值升序（0=低）；后验平局取低标号。
- `normalization_cutoff(totals, manual_cutoff, master_seed)`：§1.3 伪代码逐行翻译（总体 mean/σ、argmax 首最大平局、向零截断、下限托底、拟合失败即 break）；返回 cutoff + 保留集统计 + 剪枝轮数。
- `classify_hypermutants(totals, cutoff)`：谓词 `total > cutoff`（严格大于，上游 Sub:236 平权）。

### 2.2 R `R/stratify.R`（本单元无 FFI；协议孪生）

- `ms_stratify_hypermutants(catalog, manual_cutoff = NULL, seed = 1, ...)`：`catalog` 收 MsCatalog（totals = `colSums(counts)`，floor 默认 `100 × nrow`，Sig:919 平权）或命名数值向量（TMB 向量路径，floor 默认 0）。返回 **MsStratification** S7 对象：`cutoff`、`totals`、`hyper` / `nonhyper`（名单）、`n_hyper` / `n_nonhyper`、`gmm`（保留集 mean/sd/剪枝轮数/收敛标记——cutoff 图的钩子）、`policy = "exclude_de_novo_then_refit"`（M2 语义钩子，显式声明与上游 rescale 的分歧）、`seed`。
- 本单元允许文件集不含 FFI 壳 ⇒ R 侧**协议孪生实现**：纯 R EM + 剪枝，参数与 Rust 逐项相同；为跨语言位一致，R 内置 PCG64+SplitMix64 复刻（16-bit limb 双精度精确算术），**KAT 测试直接钉 rng.rs 冻结 golden**（seed 42 / ZERO 流首词 0x0ad917fbf73da447…）。M2 FFI 落地后 R 孪生退役为参考实现。
- 错误纪律：`msuiter_error_input`（非法输入）/ `msuiter_error_stratify`（语义违例）；禁裸 `stop()`。

## 3. 测试计划

- Rust：golden（合成双峰计数 → cutoff/标签逐位）；退化（全同值 / 单样本 / 极端离群剪枝 / 手工 floor）；确定性（同种子两次全等）；坏输入（NaN/负值/n<1）结构化错误。
- R：端到端（合成 catalog 注入 5 个超突变样本 → 名单正确分出）；确定性（两次 `identical()`）；谓词边界（`==` 归非超突变）；PCG64 KAT vs rng.rs golden；错误路径（condition 类断言）。

## 4. D13 声明边界

- **成立**：cutoff 规则与分类谓词对 SigProfilerExtractor master `cc6bf5ef`（含 v1.5.0）协议步骤的语义复刻；标签分配为我方冻结实现（D11 数值协议层——上游自身随 sklearn 版本漂移，不存在可钉的位基准）。
- **声明偏离**：①下游用途（排除+强制 refit ≠ 上游 rescale 归一化）——ARCH §5 既有裁决；②EM 初始化/收敛判据为我方冻结参数（sklearn kmeans init/tol 不跨版本稳定）；③`reg_covar=1e-6` 保留为 sklearn 平价。
- **失效条件**：上游再触 `get_normalization_cutoff`/`normalize_samples`（v1.5.0 后首触即重跑对拍）；sklearn 若改变 predict 语义不影响我方（不依赖 sklearn）。
- **已知失败模式**（照录上游）：超突变簇若为多数，剪枝剥低尾（真实队列不触发）；单样本/全同值输入退化为 cutoff=样本值（sklearn 异常→break 路径的平权）。
