# G0 容器适配协议（JSON/CSV 进出契约）

> 版本 2026-09-28（随协议冻结）。适用对象：`Dockerfile.sigfit` +
> `run_sigfit.R`、`Dockerfile.stl` + `run_stl.R`、`mock_runner.py`
> （管线自检占位，非竞品测量）。容器内工作目录 `/work`，输入挂
> `/work/in`（只读）、输出挂 `/work/out`（可写）。

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
  `derive_seed(tool, arm, N, rep)`，逐样本驱动的工具——mock、STL 的
  set.seed——用映射；单次 HMC 拟合整批的 sigfit 用批次锚）。HMC/bootstrap
  全部随机性必须由它们驱动（可复现纪律）。
- `nboot`：仅 STL 读，冻结值 200。sigfit 的链数/iter/adapt_delta 一律
  包默认，写入结果 manifest。

## 2. 输出（`/work/out/intervals.csv`，长表）

```csv
sample_id,signature,estimate,lo95,hi95,estimand,zeroed
main__N1000__r0,SBS1,148.3,101.2,201.9,absolute,0
main__N1000__r0,SBS1,148.3,101.2,201.9,raw,0
```
- 每行 = (sample_id × signature × estimand)。
- `estimand` 取值：
  - `absolute`（主 estimand：**用户可见**区间，即已过该工具默认清零/过滤
    规则后的区间）——进覆盖率判定；
  - `raw`（仅 sigfit：未清零后验区间，归因"失准来自后验还是清零规则"）；
  - `fraction`（成分版，次要报告）——可选输出。
- `zeroed`：1 = 该签名的默认清零（sigfit lower<0.01 ⇒ 0）或过滤
  （STL fixedThreshold 5%/Gini）把区间塌缩到 0；0 = 未触发。
  清零/过滤触发率是协议 §5 次要列。
- 被工具拒绝的样本（guardline，如 N=100 端）：**不得中断整批**；该样本
  每个签名写一行 `estimate=lo95=hi95=NaN, zeroed=0`，并把原因写入
  `/work/out/errors.log`。错误率如实进入结果表（协议：拒跑率即部署行为证据）。
- 单位：absolute estimand 的区间端点是 **counts**（与真值 h_j = f_j·N 同单位）。

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

## 5. 已知 API 对账点（W1/D2 smoke 时逐条核对，协议两周计划 D2）

R runner 依据 sigfit（bioRxiv 372896）与 signature.tools.lib 文档撰写；
以下调用点须在首次容器 smoke 时对照实际包版本核对（版本由 Dockerfile
tag 锁定：sigfit v2.2.0、STL v2.5.2）：
1. `run_sigfit.R`：`fit_signatures_counts` 的似然族实参、`retrieve_pars`
   的 `hpd`/`threshold.lower`（默认清零 0.01）实参名与 raw 提取方式；
2. `run_stl.R`：`FitMS` 的 `nboot` 实参名、bootstrap 百分位对象字段名、
   fixedThreshold 过滤后 exposure 的读取方式；
3. 两工具对 96 通道序的假定与 catalog.csv 方向（runner 内已做防御性
   校验，失败即拒）。
