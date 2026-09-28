"""G0 先导覆盖实验 harness（自有一部分：模拟 / 种子 / 覆盖率 / LRT / 网格）。

协议事实来源（冻结，不可在代码中改动）：
- docs/devlog/2026-09-28-G0-pi-adjudication.md   （F1–F4 冻结 + 冻结后增补两条诊断列）
- docs/devlog/2026-09-28-G0-protocol-memo.md     （完整协议：§2.3 网格/种子、§2.4 判定规则）
- docs/devlog/2026-09-28-G0-realism-memo.md      （网格低端 ~30、NB 臂必选、clock 混入臂）
- docs/devlog/2026-09-28-assumption-audit-memo.md（P1/P3 增补列依据）

许可红线：COSMIC 签名矩阵绝不入库（D3）。签名数据只有两个来源：
synthetic provider（默认，开发/测试）与 cosmic-file provider（用户提供
环境变量 G0_SIGNATURES_PATH，加载时对照 SBS96.txt 标签序强校验）。

本包是 bench 对照物，永不进 msuiter 包本体（D9）。
"""
