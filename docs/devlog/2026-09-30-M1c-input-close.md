# Devlog · M1c 输入层收尾（2026-09-30）——M1c 里程碑 4/4 关闭

## 交付
- **ms_segments**（R/io-segments.R）：8-caller 列映射全钉 SPMG master edccbea6 行号（ASCAT/ASCAT_NGS/ABSOLUTE/PCAWG/FACETS/Battenberg 双 block/PURPLE/Sequenza）；CNVkit 上游无分支 → documented-limited 显式拒绝；统一 typed 记录（chrom/start/end 1-based/minor/major）+ 解析统计 provenance。
- **ms_sv**（R/io-sv.R）：BEDPE 解析 + svtype 推导（strand 对规则 :1100-1128）+ **kat 聚类完整移植**（annotateBedpe :797-930：阈值 3e9/n/10、gamma=25·MAD、exactPcf、kmin=10、region 过滤与合并、flag 任一断点命中）。
- 错误纪律全 msuiter_error_*；零新增依赖；Collate 穷尽。

## 审核（PASS + P2×5 引文精度已修）
审核员以**真上游 annotateBedpe 为 oracle、36 个自构 BEDPE（1037 事件）对拍：0 偏差**——我们的 34/34 声明被加强为 36/36。caller 映射抽查 ≥4 个逐行命中；PCAWG 三条硬拒绝经上游源码验证（loss+tcn≥2 会致上游 LOH 列表 desync 崩溃、het+tcn<2 的通道在 48 features 中不存在）。P2 修复：SVTYPE 别名扩展登记 divergences、Sequenza A+B==CNt gate 移 divergences 段（上游不校验）、Battenberg any-missing 措辞 + 硬拒更严声明、2^53 kvad 注记精确化、测试数更正（18+14=32）。

## 电池
testthat 1761 / R CMD check 0-0-1NOTE / docs-sync 绿。

## M1c 里程碑：4/4 关闭
ID83 ✅ / GMM 分层器 ✅ / CN48 ✅（语义） / SV32 ✅（语义） / 输入层 ✅。
**待办**：速度预算口径裁决后与 M1s 一起过联合验收门 → v0.1 发布准备。
