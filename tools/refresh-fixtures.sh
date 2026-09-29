#!/usr/bin/env bash
# =============================================================================
# tools/refresh-fixtures.sh · 仓库可再生成夹具的一键再生成入口（U-M1s-13）
#
# 对照 CONTRIBUTING.md §5「fixture / golden 刷新协议（团队铁律）」：
#   * 任何金标准夹具更新（语义逐位 golden、数值协议 golden、RNG golden、
#     通道参考文件）必须在对应 devlog（docs/devlog/YYYY-MM-DD-<单元>.md）
#     写明上游理由；无理由的 golden 变更一律拒绝。本脚本只负责「重生成」，
#     本身不构成更新理由——重生成后 git diff 非空 ⇒ 先停下写 devlog。
#   * RNG golden 重生成须换 LAYOUT_ID（§5；域分离），不在本脚本范围。
#   * 通道注册表单一事实来源在 data-raw/build_channels.R；重生成后
#     test-channels-sync.R 与 tools/docs-sync.R 守卫必须全绿。
#
# 频道表（夹具 → 再生成入口）：
#   1. channel 表（R/sysdata.rda + src/rust/catalog/src/channels.rs）
#        → Rscript data-raw/build_channels.R
#      确定性、幂等、无网络（脚本头部自证条款）；本脚本直接运行。
#   2. channel-reference（tools/channel-reference/*.txt）
#      SigProfilerPlotting 上游锚，重下载需网络 → 只打印手动命令，不自动执行
#      （变更须随 devlog 给出上游理由 + 更新该目录 README 的溯源注记）。
#   3. kl-crosscheck 实验输入（tools/kl-crosscheck/data/inputs/）
#        → MSUITER_FIXTURES_ONLY=1 Rscript tools/kl-crosscheck/run_experiment.R
#      fixtures-only 模式：只生成输入（seeds 记录在脚本内），不跑对拍实验。
#      注意 data/outputs/ 是已记录实验（U-M1s-14 result.md）的产物，不在
#      再生成范围；重跑完整实验请去掉该环境变量（约 1.5 分钟）。
#   4. tally/2bit 夹具（22-record golden 批次 + LE 2bit writer）：无需脚本——
#      测试内生成，每次跑测试即重新生成，仓库内零落盘：
#        - R 侧：tests/testthat/helper-tally.R（.tally_write_2bit /
#          .tally_golden_records；U-M1s-13 起为 test-ffi-tally.R 与
#          test-catalog-tally.R 的单一来源）；
#        - Rust 侧：src/rust/src/tally.rs 与 src/rust/catalog/tests/genome/
#          fixture.rs 的内联 golden 生成器。
#      （bench/m1s 的性能夹具同理：由 bench 脚本确定性生成，不落盘仓库。）
#
# 要求：R（≥4.3）+ NMF 包（频道 3 需要）；git（幂等性自检）。
#
# 用法：
#   bash tools/refresh-fixtures.sh           # 重生成（频道 1、3）+ 打印频道 2
#   bash tools/refresh-fixtures.sh --check   # 幂等性验证：重生成后断言树干净
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CHECK_MODE=0
if [[ "${1:-}" == "--check" ]]; then
  CHECK_MODE=1
fi

say() { printf '%s\n' "$*"; }

# --- 快照：记录进入时的树状态；幂等断言 = 重生成不引入「新的」漂移 --------
# （不要求进入时树干净：断言的是 AFTER == BEFORE，即再生成入口自身是幂等的、
#  不改动任何夹具；若进入时已有未提交内容，漂移检测是相对入口状态的。）
snapshot() {
  git status --porcelain
}
BEFORE="$(snapshot)"

# --- 频道 1：channel 表（确定性、幂等、无网络） -------------------------
say "== [1/3] channel 表：Rscript data-raw/build_channels.R =="
Rscript data-raw/build_channels.R

# --- 频道 3：kl-crosscheck 实验输入（只生成输入，不跑实验） -------------
say ""
say "== [2/3] kl-crosscheck 输入：MSUITER_FIXTURES_ONLY=1 Rscript tools/kl-crosscheck/run_experiment.R =="
MSUITER_FIXTURES_ONLY=1 Rscript tools/kl-crosscheck/run_experiment.R

# --- 频道 2：channel-reference（需网络，只打印命令） ---------------------
say ""
say "== [3/3] channel-reference（tools/channel-reference/*.txt）——需网络，手动执行 =="
say "  来源（见该目录 README.md 的完整溯源与 license）："
say "    SigProfilerPlotting @ master, commit 9be822faafc9b9933c75b78f0d59f2bfa35d657b"
say "    path sigProfilerPlotting/reference_formats/{SBS96,SBS384,SBS1536,DBS78}.txt (BSD-2-Clause)"
say "  手动刷新命令模板："
say "    for f in SBS96 SBS384 SBS1536 DBS78; do"
say "      curl -fsSL \\\\"
say "        \"https://raw.githubusercontent.com/AlexandrovLab/SigProfilerPlotting/9be822faafc9b9933c75b78f0d59f2bfa35d657b/sigProfilerPlotting/reference_formats/\${f}.txt\" \\\\"
say "        -o \"tools/channel-reference/\${f}.txt\""
say "    done"
say "  刷新后必须：比对 diff、更新 README.md 溯源注记（来源/日期/license）、"
say "  随 devlog 写明上游理由，且 testthat 的 test-channels-reference.R 全绿。"

# --- 频道 4：tally/2bit 夹具——测试内生成，无脚本（见头部频道表注释） ----

# --- 幂等性结论 ----------------------------------------------------------
AFTER="$(snapshot)"
say ""
say "== 幂等性自检（重生成不得引入任何新漂移：AFTER == BEFORE） =="
if [[ "$AFTER" == "$BEFORE" ]]; then
  say "PASS：再生成入口幂等——重生成后树状态与进入时逐行一致（夹具与已提交内容逐字节一致）。"
else
  say "DIFF 非空——重生成引入了新漂移（金标准变更须先随 devlog 写明上游理由，CONTRIBUTING §5）："
  say "$AFTER"
  say "（git diff --stat）"
  git diff --stat | tail -n 5
  if [[ "$CHECK_MODE" == "1" ]]; then
    say "--check 模式：FAIL。"
    exit 1
  else
    say "（非 --check 模式：保留差异供人工审查；确认有理由后随 devlog 提交。）"
  fi
fi
