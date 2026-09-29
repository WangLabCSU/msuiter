# bench/m1s · M1s 验收门性能 bench（docs/ARCHITECTURE.md §8 预算行）

「目录生成 ≥50× SPMG（钉硬件 bench；CI 只 sanity bound <5s）；NMF ≥100× R NMF」
（docs/ROADMAP.md M1s 验收行）。**不属于 CI**：CI 只放 sanity bound。

## 布局

| 目录 | 内容 | 判据 |
|---|---|---|
| `sbs/` | 目录生成 SBS96（10⁶ 突变）vs SPMG（自定义基因组 install + 正确性逐格对拍） | ≥50× SPMG 且我方 <5s 单核 |
| `nmf/` | NMF KL（96×1000, k=10, 100 iter）vs R NMF 0.28 brunet | ≥100× |
| `nnls/` | 批量 NNLS（101×10³, k=10）vs scipy nnls 逐样本 | ≥10× |

## 一键复跑

```bash
# 0) SPMG venv（一次性；gitignored）
python3 -m venv bench/m1s/.venv
bench/m1s/.venv/bin/pip install SigProfilerMatrixGenerator   # 1.3.6

# 1) SBS 目录生成 bench（夹具确定性生成 → 我方计时 → SPMG 基线 → 逐格对拍 → 判据）
python3 bench/m1s/sbs/gen_fixtures.py
Rscript   bench/m1s/sbs/run_bench.R

# 2) NMF bench
Rscript bench/m1s/nmf/run_bench.R

# 3) NNLS bench
python3 bench/m1s/nnls/run_bench.py
```

各 bench 的数字与判据结论写在自己的 `result.md`；汇总见 `result.md`。

## 口径纪律

- 计时环境如实写入各 result.md（本机 Apple Silicon、功耗状态不可控——数字为
  该钉硬件口径）；协议统一为「预热 1 次 + 计时 3 次取中位」（SPMG 全量为
  分钟级单次墙钟，如实标注）。
- 我方计时全部走**未改动的包代码**真实路径（ms_tally / .ms_tally_rust /
  engine crate 公开 API）；driver 均为独立 `[workspace]`，仅 path 依赖，
  包树零改动（Rust bin 纯核口径不可得的原因见 sbs/result.md 注记）。
- SPMG 基线的自定义基因组经运行时校验注册绕过上游 1.3.6 的硬编码白名单
  （不改上游文件）；正确性逐格对拍是比速度更硬的锚。
- 夹具（基因组/变异/VCF/矩阵）全部确定性生成（seeds 记录在各脚本头部），
  cache/ 本地再生、不入库。
