# G0 先导覆盖实验 harness（自有部分）

> 竞品环境无关的全部自有组件：模拟生成、种子纪律、覆盖率计算、自有 presence
> LRT、网格配置、容器适配层与编排器。协议已于 2026-09-28 冻结
> （[pi-adjudication](../../docs/devlog/2026-09-28-G0-pi-adjudication.md)
> F1–F4）；本 harness 是冻结协议的可运行实现，**不改动任何冻结参数**。
>
> 状态：harness 开建完成并通过独立审核修复（2026-09-28：NB 分支 EM 数学
> 错误 P0-1、敏感性臂泄漏 P0-2、冻结空间缩水 P0-3 及 P1/P2 批全部落改）；
> 自校验测试 36/36 通过；正式 G0 执行
> （primary/degraded × docker × cosmic-file）**未开跑**，等 F5 执行环境落实。

## 1. 冻结协议要点（本 harness 的实现依据）

| 冻结项 | 内容 | 实现位置 |
|---|---|---|
| 可证伪命题 | 竞品 95% exposure 区间的经验覆盖率显著低于名义 0.95（低 TMB 与平坦签名格点尤甚）；若基本校准 → 接受 Framing B | 判定语义在 `g0/coverage.py::judge` |
| F1 判定阈值 | 支持 A ①任一 Tier-1 工具任一 cell ĉ≤0.85 且 CP 95% 上界<0.90，或 ②flat 层（SBS5/40）N≥300 全部 cell ĉ≤0.90；kill→B 两工具全部 N≥300 cell ĉ≥0.90 且随 N 无单调恶化；gray → borderline cells 加倍 reps 至 400 重判，仍 gray 默认走 B | `g0/coverage.py`（`judge`、`clopper_pearson`）；阈值常量在 `g0/grid.py` |
| F2 工具对 | Tier-1 = sigfit v2.2.0（HPD + 默认清零 lower<0.01⇒0，另报 raw 列）+ signature.tools.lib v2.5.2（bootstrap nboot=200 + 默认过滤）；Tier-0（MuSiCal/SPA/mSigAct）不进覆盖矩阵 | `adapters/`（runner + Dockerfile 按 tag 锁定） |
| F3 真值与目录 | 5 真值签名 SBS1/2/13/5/40 @ 15/15/15/30/25%（=组合轴 master，清单 ②"+APOBEC"）；拟合目录 = COSMIC v3.6 SBS96 GRCh37 全 101 签名（用户自备文件，绝不入库） | `g0/grid.py::MASTER_TRUTH_COMPOSITION`；`g0/providers.py::CosmicFileProvider` |
| 网格 | 几何网格 30→10⁶ 共 19 点（裁决第 3 条上调）；10²–10⁴ 悬崖区 9 点（≥6 加密达标） | `g0/grid.py::PRIMARY_GRID` |
| 真值组合轴 | ≥6 组（裁决第 3 条）：master / clock-only / +MMR 群 / POLE 超突变（高 N 档）/ 平坦三联小 exposure / 强签名+平坦背景；占比取现实锚点（Alexandrov 2020；Campbell 2017），文献依据逐条内注 | `g0/grid.py::COMPOSITIONS` |
| 重复数 | 200/工具/签名/格点（功效：−10pp ≈6σ、−5pp ≈3.3σ）；降级档 3 点 {100,1000,10000} × 100 reps（裁决明示保留） | `g0/grid.py::REPS_*`、`arms_for_profile` |
| 种子纪律 | master seed = 20260928；逐 (arm,N,rep) SplitMix64 计数器流派生（与 ARCH §2 rng.rs 同构）；全部种子落盘 Seeds.txt（manifest 记录运行时 commit SHA） | `g0/seeds.py`；`run_grid.py::git_sha` |
| 生成模型 | 主臂多项 X~Mult(N,Σf_k·S_k)（f 遍历冻结组合轴）；NB 过散臂必选（size=8，Gamma-Poisson 构造）；clock 混入臂（purity 0.4 等效）；稀疏臂（SBS13→2% @ N=1000） | `g0/sim.py` |
| 判定输入契约 | 敏感性臂（nb/clock/sparse）只细化不推翻判定（冻结增补条款 b）——只有 main 模型臂进 `judge`；全部判定子句按 Tier-1 工具过滤，kill 要求两工具在场；borderline 无 N≥300 限定（§2.4 原文） | `run_grid.py`（judge_arms）；`g0/coverage.py::judge` |
| 增补诊断列（不动判定规则） | ①NB 臂追加自有 χ²₁ presence LRT 经验 size/power（P3，Self–Liang 边界 p = ½·erfc(√(stat/2))；NB 分支用单调 MM 更新 h←h·Wᵀ(x/μ)/Wᵀ((x+s)/(μ+s))，2026-09-28 修复）；②flat 层按 P1 机制 (i) 单列归因 | `g0/lrt.py`；coverage 表 `p1_mechanism_i` 列；`run_grid.py --with-lrt-diagnostic` |

纪律：逐签名逐格点报告，**禁止跨签名平均掩盖 flat 层**；主 estimand =
绝对 exposure（用户可见区间），成分版与 raw 列次要不进判定；每 rep 只重抽
计数不重抽组成（条件覆盖）。

## 2. 目录结构

```
bench/g0/
├── README.md               本文件
├── run_grid.py             编排器（生成→adapter→解析→coverage→判定→落盘）
├── g0/
│   ├── seeds.py            master seed + 确定性派生 + Seeds.txt manifest
│   ├── grid.py             冻结网格/真值组合轴/重复数/阈值常量 + 臂配置（primary/degraded/smoke）
│   ├── providers.py        synthetic（默认）/cosmic-file（SBS96.txt 序强校验）
│   ├── sim.py              四臂模拟生成器（多项/NB/clock 混入/稀疏）
│   ├── lrt.py              自有 χ²₁ presence LRT（Poisson+NB 语义 EM，零 scipy）
│   └── coverage.py         CP 精确区间（自实现不完全 beta）+ 逐 cell 覆盖率 + 冻结判定
├── adapters/
│   ├── adapter_protocol.md 进出契约（counts/catalog/params → intervals.csv）
│   ├── mock_runner.py      参数自助法占位 runner（只验管线，非竞品测量）
│   ├── run_sigfit.R        sigfit 容器 runner（HPD + 清零 + raw 列）
│   ├── run_stl.R           STL 容器 runner（bootstrap nboot=200 + 过滤）
│   ├── Dockerfile.sigfit   r-ver 4.3.3 + rstan + sigfit@v2.2.0
│   └── Dockerfile.stl      r-ver 4.3.3 + signature.tools.lib@v2.5.2
├── tests/                  python3 -m tests.run_all（36 项，不强制 pytest）
├── results/                入 git：Seeds.txt、coverage_*.csv、judgment_*.md、
│                           timings_*.csv、diagnostic_lrt_nb.csv
└── cache/                  gitignored：counts、truth、cell 输入/输出中间产物
```

## 3. 许可声明（宪法级红线）

- **COSMIC 签名矩阵绝不入库**（D3 保守姿态，同 `tools/channel-reference`
  的处理逻辑）。仓库内不存在、不嵌入、不派生任何 COSMIC 数值。
- 双 provider 设计：
  - `synthetic`（默认）：Dirichlet 合成签名（构造公式文档化于
    `g0/providers.py`，slot 标签沿用 SBS1/2/13/5/40 但数值非 COSMIC），
    测试与开发全用这档；
  - `cosmic-file`：从环境变量 `G0_SIGNATURES_PATH`（5×96 真值矩阵）与
    `G0_CATALOG_PATH`（拟合目录，F3 = COSMIC v3.6 全 101）读取**用户自行
    获取的文件**，加载时对照 `tools/channel-reference/SBS96.txt` 规范序
    逐项校验（顺序敏感，错序/缺签名/通道数错一律拒绝）。数据获取与许可
    接受是用户动作；文件以只读方式引用/挂载，永不复制入库。
- 结果表（`results/`）只含覆盖率与判定统计，不含签名矩阵本体。

## 4. 运行方式

```bash
cd bench/g0

# ① 自校验（约 15 s；36 项测试全过为 harness 可用条件）
python3 -m tests.run_all

# ② 管线 smoke（mock adapter + synthetic provider；只验证 harness 自身）
python3 run_grid.py --profile smoke --adapter mock --provider synthetic --with-lrt-diagnostic

# ③ 正式档 dry-run（只落盘 Seeds.txt + counts/truth，供 F5 环境核对）
python3 run_grid.py --profile primary --adapter docker --provider cosmic-file --dry-run

# ④ 降级档（协议 §6/§7-R7：3 点网格 × 100 reps；降级自动记入 judgment 表头）
python3 run_grid.py --profile degraded --adapter docker --provider cosmic-file

# ⑤ 正式 G0（须 harness 审核通过 + F5 落实后由作者执行）
python3 run_grid.py --profile primary --adapter docker --provider cosmic-file \
    --tools sigfit,stl --with-lrt-diagnostic

# gray 重判（协议 §2.4）：对 borderline cells 加倍重复
python3 run_grid.py --profile primary --adapter docker --provider cosmic-file --reps 400

# 重建全部中间产物（忽略 cache 复用）
#   追加 --force-rerun
```

前置条件（正式档）：Docker daemon 运行且 `g0-sigfit`/`g0-stl` 镜像已构建
（`docker build -f adapters/Dockerfile.sigfit -t g0-sigfit adapters/`）；
环境变量 `G0_SIGNATURES_PATH`、`G0_CATALOG_PATH` 指向用户自备矩阵文件。
mock 档无任何外部依赖（numpy 之外零依赖）。

## 5. 与 msuiter 包的关系

本目录是 **bench 对照物，永不进包**（D9）：`g0/`、`adapters/`、`tests/`
不 import 包代码（`R/`、`src/`），包代码也不依赖本目录。G0 结论
（Framing A/B）通过 devlog 与 ARCH §10/D14 进入主线，而非代码耦合。
自有 presence LRT（`g0/lrt.py`）是 P3 增补列的参考实现，若未来进包
须按包纪律重写并独立测试，不直接搬移。

## 6. 已知边界（诚实注记，D13）

- R runner 按 sigfit/STL 文档语义撰写，**API 级对账点**列于
  `adapters/adapter_protocol.md` §5（W1/D2 smoke 任务：首次容器运行时
  逐条核对实参名与返回对象字段名，版本由 Dockerfile tag 锁定）。
  STL runner 的 errors.log 先行落盘（失败信息追加写入），run_grid 的
  缓存跳过守卫对 STL 生效。
- W1 兼容性检查未做：STL 仅支持器官 RefSig 目录，正式跑前须验证
  Breast RefSig T1 含全部 5 个真值签名（协议 §3，缺失则按降级路径处理）。
- **NB 臂 LRT 诊断（2026-09-28 修复后口径）**：修复前 NB 分支把
  Gamma-Poisson 分层 E 步权重当乘法更新，NB 对数似然迭代内单调下降
  （40 rep 批量实测 ll −1.3×10⁵ → −4.7×10⁵，100% h 钉在防御性 h_cap
  假收敛），committed 诊断显示 nb 臂 power=0.04。修复为审核员验证的
  单调 MM 更新 `h ← h·Wᵀ(x/μ)/Wᵀ((x+s)/(μ+s))` 后，同一数据 ll =
  −1.0×10⁴ 且单调上升。重新生成的 `results/diagnostic_lrt_nb.csv`
  （N=1000，200 reps，每率 1000 次检验）：NB 语义经验 size = 0.015、
  在场签名合并 power = 0.613；Poisson 误设语义 size = 0.065（膨胀方向
  与 P3 预期一致）。逐签名分解（400 rep 核验）：easy 层（SBS1/2/13 @
  15% 份额）power = 1.0；平坦近重复对（SBS5/40 @ 30/25%）逐签名 power
  ≈ 0.05/0.01——3% 谱差被 NB 过散方差淹没，是可辨识性极限的诚实注记
  （G0 对平坦签名的被测量是区间覆盖率，非 presence power）；power 合理
  性底线（easy 逐签名 ≥0.5、合并 ≥0.5）已入 tests/test_lrt.py 防回归。
- **clock 混入臂 estimand 口径（待定标注）**：现实现输出的真值
  h_k = f_k·N 为**未稀释**肿瘤组成（诊断口径）；稀释后"工具可观测
  真值"（含 normal-clock 份额如何计入绝对 exposure estimand）存在
  定义选择，**待作者裁决**。该臂在裁决前只作敏感性报告列（冻结增补
  条款 b，本就不进判定），判定语义不受影响。
- 判定输入契约：敏感性臂（nb/clock/sparse）只出报告列不进判定（冻结
  增补条款 b）；borderline cells 无 N≥300 限定（protocol-memo §2.4
  原文），全部格点的 ĉ<0.90 cell 都可进 gray 加倍流程。
- smoke（mock）结果的 verdict 无科学含义，只证明管线连通；正式判定
  只可出自冻结协议下的 docker × cosmic-file 运行。
