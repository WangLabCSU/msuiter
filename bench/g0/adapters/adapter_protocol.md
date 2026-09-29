# G0 容器适配协议（JSON/CSV 进出契约）

> 版本 2026-09-29（W1/D2 API 对账后修订，取代 2026-09-28 冻结版的相关条目）。
> 适用对象：`Dockerfile.sigfit` + `run_sigfit.R`、`Dockerfile.stl` + `run_stl.R`、
> `mock_runner.py`（管线自检占位，非竞品测量）。容器内工作目录 `/work`，输入挂
> `/work/in`（只读）、输出挂 `/work/out`（可写）。
>
> 两 runner 的公共纪律（上轮烟雾教训固化为契约）：
> - `errors.log` **先行落盘**（进 outdir 第一件事），失败信息追加写入；run_grid
>   的缓存跳过守卫依赖它的存在，失败路径绝不留半截 `intervals.csv`（每次运行
>   先清残留输出，CSV/manifest 只在全部成功后一次性写出，失败 exit 非零）。
> - **显式数值防御**：counts/catalog 中任何非数值列、非有限值、负值、重复/空
>   id 一律拒绝（exit 非零 + errors.log 记因），不做静默转换。
> - 两镜像每步 RUN 带 `|| { echo ...; exit 1; }` 守卫 + 装后 `library()`/版本
>   断言（上轮 STL 静默坏镜像不可重演）。

## 1. 输入（三个文件，均挂 `/work/in/`）

### counts.csv（模拟器产出）
```csv
sample_id,A[C>A]A,A[C>A]C,...,T[T>G]T
main__N1000__r0,3,1,...,0
```
- 通道列 = 96 个，**顺序必须与 `tools/channel-reference/SBS96.txt` 规范序逐项一致**（模拟器与校验器共用该锚）。
- `sample_id` 命名：`{arm}__N{n}__r{rep}`（双下划线分隔；run_grid 据此解码回 cell）。
- 整数计数；每行一个样本（= 一个 replicate）。

### catalog.csv（拟合目录；用户自备，绝不入库）
```csv
channel,SBS1,SBS2,...,<sigK>
A[C>A]A,0.010622,...
```
- 行 = 96 通道（首列 `channel`，标签序同上）；列 = 签名，各列为和 1 的比例（runner 内部再做归一防御）。
- 正式 G0（F3 冻结）= COSMIC v3.6 SBS96 GRCh37 全 101 签名，经环境变量
  `G0_CATALOG_PATH` 指向用户自己的文件、以只读卷挂载进容器；harness
  不复制、不转换、不缓存该文件入 git。`G0_SIGNATURES_PATH`（5×96 真值）
  仅由 provider 校验加载，同样不入库。
- 许可接受是用户动作：运行 docker/mock 之外的真实档前，用户须自行确认
  所持目录文件的许可（harness 在 README 中明示，不做任何变通）。

### params.json（本次调用参数）
```json
{"tool": "sigfit", "seed": 1712345678, "nboot": 200, "notes": "Tier-1 默认参数，照用"}
```
- `seed`：cell 批次锚 = `g0.seeds.derive_seed(tool, arm, N)`（协议 §2.3 的
  逐 (tool, N, replicate) 派生通过 `sample_seeds` 映射落地：每样本
  `derive_seed(tool, arm, N, rep)`，逐样本驱动的工具——STL 的
  `randomSeed=`——用映射；单次 HMC 拟合整批的 sigfit 用批次锚）。
  HMC/bootstrap 全部随机性必须由它们驱动（可复现纪律）。
- `nboot`：仅 STL 读（FitMS `nboot=`），正式冻结 200；smoke 可用 20。
- sigfit 的链数/iter/warmup 一律包默认（rstan `chains=4/iter=2000/warmup=1000`），
  写入结果 manifest；`params.chains/iter/warmup` 三个可选键仅供 smoke 短链，
  正式实验不得设置。

## 2. 输出（`/work/out/intervals.csv`，长表）

```csv
sample_id,signature,estimate,lo95,hi95,estimand,zeroed
main__N1000__r0,SBS1,148.3,101.2,201.9,absolute,0
main__N1000__r0,SBS1,148.3,101.2,201.9,raw,0
```
- 每行 = (sample_id × signature × estimand)。**列覆盖 = catalog.csv 全部签名**：
  工具结果只含选中子集时（STL exposures 会丢弃全零签名列），runner 须映射回
  全目录列，缺席签名如实报 `estimate=lo95=hi95=0, zeroed=1`。
- 单位：absolute estimand 的区间端点是 **counts**（与真值 h_j = f_j·N 同单位）。
  sigfit 的 multinomial exposures 是占比 ⇒ runner 内 **× 样本突变总数还原**，
  并断言（i）每样本占比和 ≈ 1；（ii）还原后逐样本和 = 突变总数。STL 的
  exposures 原生就是 counts，无须换算。
- `estimand` 取值：
  - `absolute`（主 estimand：**用户可见**区间）——进覆盖率判定；
  - `raw`（仅 sigfit：未清零后验区间）。sigfit v2.2.0 **无内建清零参数**
    （无 `threshold.lower`）⇒ raw 与 absolute 数值相同，保留两行以固定 schema
    并与未来版本区分。
- `zeroed`：1 = 该签名触发了工具/协议的清零或过滤，**清零动作本身由
  harness 后处理**（runner 不改写数值，只如实打标志）：
  - sigfit：后处理规则 = absolute `lo95 < 0.01 ⇒ 置 0`（协议默认；包内无
    对应参数）；
  - STL：包内 `fixedThreshold 5%` 过滤把 exposure 置 0 ⇒ runner 直接报
    `estimate=lo95=hi95=0, zeroed=1`（这是工具部署行为，非 runner 加工）。
  清零/过滤触发率是协议 §5 次要列。
- 区间来源：
  - sigfit：`retrieve_pars(fit, par="exposures", hpd_prob=0.95)` 的
    `mean/lower_95/upper_95`（HPD）× 样本总数；
  - STL：点估计 = 包过滤后的 bootstrap 中位数（`res$exposures`，丢弃
    `unassigned` 列后映射回全目录）；区间 = 逐样本
    `res$bootstrap_exposures_samples[[sample]]`（签名 × nboot 的未过滤
    bootstrap 拟合）自算 2.5/97.5 百分位；被过滤签名区间塌缩 [0,0]。
- 被工具拒绝的样本（guardline，如 0 突变）：**不得中断整批**；该样本每个
  签名写一行 `estimate=lo95=hi95=NaN, zeroed=0`，并把原因写入
  `/work/out/errors.log`。错误率如实进入结果表（协议：拒跑率即部署行为证据）。

### manifest.json（两 runner 均写）
- 版本溯源：`version_tag`（v2.2.0 / v2.5.2，全 tag——`packageVersion` 的
  "2.2" 不够）+ `commit`（sigfit 取 `packageDescription()$RemoteSha`；STL 取
  镜像 build 阶段固化在 `/usr/local/share/g0/build_info.json` 的 clone SHA）。
- sigfit 另记：`model`、`hpd_prob`、实际生效的 `chains/iter/warmup`、
  `counts_restoration` 规则、`zero_rule`。
- STL 另记：`nboot`、`method`、`nparallel`、`useBootstrap`、
  `maxRareSigsPerSample`、filter 规则、`catalog_mode`、`channel_order`、
  `interval_source`。

## 3. 容器调用契约（run_grid 生成的命令形）

```bash
docker run --rm \
  -v <cell_dir>/in:/work/in:ro -v <cell_dir>/out:/work/out \
  g0-sigfit Rscript /work/run_sigfit.R \
    --counts /work/in/counts.csv --catalog /work/in/catalog.csv \
    --params /work/in/params.json --outdir /work/out
```
mock 占位同参数：`python3 adapters/mock_runner.py --counts ... --catalog ... --params ... --outdir ...`。

## 4. mock_runner 行为声明

mock 用**同一批模拟数据**做参数自助法（multinomial 重采样 → EM 重拟合 →
2.5/97.5 百分位），检验的是 harness 管线（CSV 往返 / coverage / 判定），
**不是任何竞品行为**。`params.coverage_scale`（默认 1.0）是测试钩子，
用于构造校准/欠覆盖两种情形驱动判定三叉。

## 5. API 对账结论（W1/D2 smoke 已按实测/源码逐条核对并落进 runner）

### 5.1 sigfit v2.2.0（kgori/sigfit，g0-sigfit:2.2.0 容器内实测）
1. 拟合入口是 `fit_signatures(counts, signatures, exp_prior=NULL, model=, opportunities=NULL, ...)`；
   **不存在 `fit_signatures_counts`**。`counts` 行 = 样本 × 96 通道列；
   `signatures` 传 `t(catalog)`（行 = 签名 × 96 通道列）。
2. `seed/chains/iter/warmup` 经 `...` 透传 `rstan::sampling`；缺省 = 包默认
   4/2000/1000（记 manifest）。
3. `retrieve_pars(fit, par="exposures", hpd_prob=0.95)`（**`hpd_prob`**，不是
   `sig_level/CI/hpd`；**没有 `threshold.lower`**）⇒ `mean/lower_95/upper_95`，
   样本 × 签名，**占比**（multinomial），绝对 counts 须 × 样本突变总数。
4. 通道序：sigfit 按位置对齐 counts 列与 signatures 列，两输入同用仓库锚序
   即可（runner 断言标签逐项一致）。

### 5.2 signature.tools.lib v2.5.2（源码逐行核对 + 容器验证）
1. `FitMS(catalogues=, commonSignatures=, rareSignatures=, maxRareSigsPerSample=,
   method=, exposureFilterType=, useBootstrap=, nboot=, nparallel=, randomSeed=)`；
   旧代码的 `signature/counts/parallelisation` 实参不存在。`catalogues` 样本为
   **列**、通道为行；`commonSignatures` 签名为列、通道为行。
2. **`useBootstrap=TRUE` 必须显式开**（默认 FALSE），否则
   `bootstrap_exposures_samples` 静默为 NULL、区间无处可来。区间由 runner 从
   逐样本（签名 × nboot）矩阵自算 2.5/97.5 百分位。
3. **通道序陷阱**：STL 要求经典序 = substitution（C>A,C>G,C>T,T>A,T>C,T>G）
   外层 × 5'（A/C/G/T）× 3'（A/C/G/T）——与仓库锚 SBS96.txt 的字典序不同。
   runner 将 counts/catalog 行同步重排进经典序（暴露量无通道维，无须重排
   回），并用包自带 `getTypeOfMutationsFromChannels` 断言识别为 "subs"。
4. 返回结构：`res$exposures` = 样本(行) × 签名(列) **含 `unassigned` 列**
   （runner 丢弃），且全零签名列被包丢弃（runner 映射回全目录列，缺席签名
   报 [0,0]/zeroed=1）；`res$bootstrap_exposures_samples[[sample]]` = 签名 ×
   nboot 未过滤 bootstrap 拟合；`res$exposures` 点估计 = 包过滤后的 bootstrap
   中位数。
5. **W1 裁决记录（SBS40/organ-T1）**：Breast（及任一器官）RefSig T1 目录不
   含 SBS40 等真值签名，organ 路径与 F3 冻结目录天然冲突。**正式实验 STL 侧
   不走 organ T1**：统一 `commonSignatures=` 喂冻结 v3.6 目录文件
   （`G0_CATALOG_PATH`，作者自备，经 harness 挂成 catalog.csv），
   `rareSignatures=` 置空 + `maxRareSigsPerSample=0`（FitMS 文档口径：退化为
   全目录 common 拟合、无稀有签名搜索）。organ= 仅保留作诊断用途，不入正式档。

## 6. 镜像构建纪律（两 Dockerfile）

- 版本 tag 锁定；GitHub 依赖（NNLM、indelsig.tools.lib、STL 本体）用
  `git clone --branch <tag>` + `R CMD INSTALL`（remotes::install_github 有
  API 限流风险），clone 的 commit SHA 固化进 `/usr/local/share/g0/build_info.json`。
- STL 镜像必装：系统库（libcurl4-openssl-dev libssl-dev libxml2-dev
  libicu-dev libpng-dev libz-dev libbz2-dev liblzma-dev libgmp3-dev cmake
  pkg-config）+ CRAN 链（NMF/factoextra/limSolve/gmp/RCircos/doRNG 等）+
  Bioconductor 链（BiocManager 3.18；VariantAnnotation/GenomicFeatures/
  SummarizedExperiment 等）+ **三个** BSgenome 基因组（hg38 与 hs37d5 是 STL
  的硬 Imports；hg19 是 indelsig.tools.lib 的硬 Imports，而后者是 STL 的硬
  Imports——library() 会加载全部 Imports，缺一即断言失败）。
- 每步 RUN 失败即停（`|| { echo; exit 1; }`），安装后立即
  `requireNamespace`/`library()` 断言；最终验收门 =
  `library(signature.tools.lib)` + `packageVersion()=="2.5.2"` + `FitMS` 导出。
