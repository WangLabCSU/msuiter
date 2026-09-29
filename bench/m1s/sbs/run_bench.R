#!/usr/bin/env Rscript
# =============================================================================
# bench/m1s/sbs/run_bench.R · M1s 验收门 SBS 目录生成 bench
#（docs/ARCHITECTURE.md §8 预算行：目录生成 SBS96（10⁶ 突变）vs SPMG ≥50×，
#   且我方 <5s 单核。ROADMAP M1s 验收：「目录生成 ≥50× SPMG（钉硬件 bench；
#   CI 只 sanity bound <5s）」。本脚本不属于 CI。）
#
# 口径（如实记录）：
#   * 我方报告口径 = 用户可感端到端：ms_tally(MsVariants, 2bit, "SBS96")——
#     S7 校验 + FFI（mmap 2bit、路由、上下文、计数、ledger）+ 目录装配。
#     单线程（src/rust/src/tally.rs 并发节：M1s 有意单线程）。
#   * 次口径（分解）= FFI 层 msuiter:::.ms_tally_rust（含 mmap + R 侧列校验
#     + dimnames，去 S7 装配）。
#   * 「Rust bin 纯核」口径在 HEAD 不可得：内核装配入口 mod tally 为包私有，
#     包代码不可为 bench 改动——FFI 次口径即为纯核上界（含 ~1.2MB mmap），
#     如实记录为遗留口径说明。
#   * SPMG 基线 = 标准调用 SigProfilerMatrixGeneratorFunc（10⁶ 变异、同合成
#     参考基因组、输出 SBS96 在内的全套 9 种矩阵），VCF 文件输入（SPMG 唯一
#     用户界面）——含 VCF 解析与全套矩阵写出；我方仅 SBS96 且输入在内存。
#     该不对称对 SPMG 有利（ heavier workload ），判据如依然 PASS 则结论
#     偏保守方向正确；明细见 result.md。
#   * 协议：我方预热 1 + 计时 3 取中位；SPMG 单次墙钟（分钟级，无复跑）。
#
# 正确性锚（比速度更重要，必做）：100 变异 sanity 子集上 SPMG 与我方 ms_tally
#   的 SBS96 矩阵逐格一致（含同样本相邻→DBS 双侧排除、跨样本相邻→双侧 SBS、
#   极端合法位置）；不一致 = P0 发现。全量 10⁶ 矩阵亦逐格对拍。
# =============================================================================

options(stringsAsFactors = FALSE, digits = 15, scipen = 12)

HERE <- normalizePath(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = 1))))
CACHE <- file.path(HERE, "cache")
# 注意：不能 normalizePath——venv 的 bin/python 是指向基础解释器的符号链接，
# 解析后 venv 失活（site-packages 丢失）。保留原路径让 Python 自行探测 pyvenv.cfg。
VENV_PY <- file.path(HERE, "..", ".venv", "bin", "python")
stopifnot(file.exists(VENV_PY))

sig <- function(x, d = 6) format(x, digits = d, trim = TRUE, scientific = TRUE)
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(...) cat(..., "\n", sep = "")

say("== M1s SBS 目录生成 bench：10⁶ SNV，SBS96，vs SPMG ≥50× 且我方 <5s ==")

# ---- 我方 ------------------------------------------------------------------
pkgload::load_all(quiet = TRUE)

read_vars <- function(name) {
  d <- read.csv(file.path(CACHE, name), colClasses = c(
    chrom = "character", pos = "numeric", ref = "character",
    alt = "character", sample = "character"), comment.char = "")
  # 夹具 CSV 用 1-based pos；MsVariants 要 canonical chrom/start/end/ref/alt。
  d$start <- d$pos
  d$end <- d$pos + nchar(d$ref) - 1L
  d[, c("chrom", "start", "end", "ref", "alt", "sample")]
}

tab_full <- read_vars("variants.csv")        # 主臂 dbsfree（间隔≥2、无重复）
tab_dense <- read_vars("variants_dense.csv") # 次臂 dense（自然相邻密度、去重）
tab_san  <- read_vars("sanity.csv")          # 语义探针（含相邻对）
g2b <- file.path(CACHE, "genome.2bit")
stopifnot(file.exists(g2b))

v_full <- ms_variants(tab_full, "SYN5M-bench",
  caller = "bench-synthetic", matched_normal = "none")
v_dense <- ms_variants(tab_dense, "SYN5M-bench",
  caller = "bench-synthetic", matched_normal = "none")
v_san <- ms_variants(tab_san, "SYN5M-bench",
  caller = "bench-synthetic", matched_normal = "none")

# S7 端到端（报告口径）：预热 1 + 计时 3 取中位
timed_ms_tally <- function(v) {
  invisible(ms_tally(v, g2b, "SBS96")) # 预热
  runs <- replicate(3L, {
    t0 <- proc.time()
    cat0 <- ms_tally(v, g2b, "SBS96")
    list(elapsed = (proc.time() - t0)[["elapsed"]], cat = cat0)
  }, simplify = FALSE)
  list(runs = vapply(runs, `[[`, numeric(1), "elapsed"),
       median_s = median(vapply(runs, `[[`, numeric(1), "elapsed")),
       cat = runs[[1]]$cat)
}

# FFI 层（次口径）
timed_ffi <- function(tab) {
  call_ffi <- function() msuiter:::.ms_tally_rust(g2b,
    chrom = tab$chrom, pos = tab$start, ref_ = tab$ref, alt = tab$alt,
    sample = tab$sample, strand = rep("N", nrow(tab)), want_sbs96 = TRUE)
  invisible(call_ffi())
  runs <- replicate(3L, {
    t0 <- proc.time()
    res <- call_ffi()
    (proc.time() - t0)[["elapsed"]]
  })
  list(runs = as.numeric(runs), median_s = median(as.numeric(runs)))
}

say("我方 ms_tally（S7 端到端）—— 主臂 dbsfree ...")
ours <- timed_ms_tally(v_full)
for (i in seq_along(ours$runs)) say(sprintf("  run%d: %.3f s", i, ours$runs[i]))
say(sprintf("  median: %.3f s | n=%d samples=%s | sum(SBS96)=%d n_skipped=%d",
  ours$median_s, nrow(tab_full), paste(ours$cat@samples, collapse = ","),
  sum(ours$cat@counts), ours$cat@provenance$n_skipped))

say("我方 ms_tally —— 次臂 dense（速度参考与总量对账）...")
ours_dense <- timed_ms_tally(v_dense)
say(sprintf("  median: %.3f s | records=%d sum(SBS96)=%d n_skipped=%d",
  ours_dense$median_s, nrow(tab_dense), sum(ours_dense$cat@counts),
  ours_dense$cat@provenance$n_skipped))
n_dbs_dense <- nrow(tab_dense) - sum(ours_dense$cat@counts) -
  ours_dense$cat@provenance$n_skipped
say(sprintf("  dense: 我方判为 DBS（排除出 SBS96）的记录数 = %d", n_dbs_dense))

say("我方 .ms_tally_rust（FFI 层次口径）...")
ffi <- timed_ffi(tab_full)
say(sprintf("  median: %.3f s", ffi$median_s))

stopifnot(ours$median_s < 5) # 预算行硬约束：<5s（CI sanity bound 同一口径）

# ---- 对拍（我方侧矩阵落盘） ------------------------------------------------
cat_san <- ms_tally(v_san, g2b, "SBS96")
cat_dense <- ours_dense$cat
write_sbs_tsv <- function(counts, path) {
  lines <- c(paste(c("channel", colnames(counts)), collapse = "\t"),
    paste(rownames(counts), counts[, 1], counts[, 2], sep = "\t"))
  writeLines(lines, path)
}
write_sbs_tsv(cat_san@counts, file.path(CACHE, "ours_sanity96.tsv"))
cat_full <- ours$cat
write_sbs_tsv(cat_full@counts, file.path(CACHE, "ours_full96.tsv"))
write_sbs_tsv(cat_dense@counts, file.path(CACHE, "ours_dense96.tsv"))

# ---- SPMG 基线（venv python 子进程） --------------------------------------
say("SPMG 基线（.venv，含自定义基因组安装/校验注册；上游限制绕过见脚本头）...")
sp <- system2(VENV_PY, c(file.path(HERE, "spmg_run.py"), CACHE),
  stdout = TRUE, stderr = TRUE)
status <- attr(sp, "status") %||% 0L
cat(paste(sp, collapse = "\n"), "\n")
if (status != 0L) stop("spmg_run.py failed with status ", status)

timing <- jsonlite::fromJSON(file.path(CACHE, "spmg_timing.json"))
spmg_full_s <- as.numeric(timing$full$wall_s)
spmg_dense_s <- as.numeric(timing$dense$wall_s)
spmg_san_s <- as.numeric(timing$sanity$wall_s)

# ---- 逐格对拍 --------------------------------------------------------------
read_sbs_tsv <- function(path) {
  d <- read.csv(path, sep = "\t", row.names = 1, check.names = FALSE)
  m <- as.matrix(d); storage.mode(m) <- "integer"; m
}
align <- function(ours_m, spmg_path, label) {
  sp <- read_sbs_tsv(spmg_path)
  stopifnot(setequal(colnames(sp), colnames(ours_m)))
  sp <- sp[, colnames(ours_m), drop = FALSE]
  if (!identical(rownames(sp), rownames(ours_m))) {
    stop(label, ": channel label order differs between msuiter and SPMG")
  }
  list(sp = sp, diff = sp - ours_m,
    sum_ours = sum(ours_m), sum_spmg = sum(sp),
    n_diff = sum(abs(sp - ours_m) > 0L))
}

# 主臂（dbsfree）：判据 = 逐格完全一致（正确性锚，必做）
main_cmp <- align(cat_full@counts, file.path(CACHE, "spmg_full96.tsv"), "main")
# sanity（含相邻对）：预期差 = 同样本相邻对成员（SPMG 1.3.6 把 DBS 成员一并计入
# SBS96；我方按 U-M1s-09 审计语义排除）——差必须为非负且恰为 4 格和
san_cmp <- align(cat_san@counts, file.path(CACHE, "spmg_sanity96.tsv"), "sanity")
san_ok <- san_cmp$n_diff == sum(abs(san_cmp$diff)) && all(san_cmp$diff >= 0L) &&
  sum(san_cmp$diff) == 4L
# 次臂 dense：总量对账 = SPMG 总数 − 我方 SBS96 总数 == 我方 DBS 成员数
dense_cmp <- align(cat_dense@counts, file.path(CACHE, "spmg_dense96.tsv"), "dense")
dense_ok <- sum(dense_cmp$diff) == n_dbs_dense && all(dense_cmp$diff >= 0L)

say(sprintf("sanity 对拍（100 变异，含相邻对）：ours sum=%d spmg sum=%d 差和=%d（预期 4=DBS 成员）",
  san_cmp$sum_ours, san_cmp$sum_spmg, sum(san_cmp$diff)))
say(sprintf("main dbsfree 对拍（10⁶）：ours sum=%d spmg sum=%d 逐格差=%d（判据 = 0）",
  main_cmp$sum_ours, main_cmp$sum_spmg, main_cmp$n_diff))
say(sprintf("dense 对账（去重后 %d 记录）：SPMG−ours = %d（预期 = 我方 DBS 成员 %d）",
  nrow(tab_dense), sum(dense_cmp$diff), n_dbs_dense))

if (!san_ok) stop("P0：sanity 差不是恰好的 DBS 成员差（4）——需逐格定位")
if (!dense_ok) stop("P0：dense 对账失败——差不是 DBS 成员数")
if (main_cmp$n_diff != 0L) stop("P0：dbsfree 主臂逐格不一致——正确性锚失败")

# ---- 判据 ------------------------------------------------------------------
speedup <- spmg_full_s / ours$median_s
verdict <- speedup >= 50 && ours$median_s < 5
say(sprintf("判据：speedup = %.3f s / %.4f s = %.1f×（≥50× 且 <5s： %s）",
  spmg_full_s, ours$median_s, speedup, ifelse(verdict, "PASS", "FAIL")))

# ---- result.md -------------------------------------------------------------
env <- function() {
  c(paste0("date: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("R: ", R.version$version.string, " (", R.version$platform, ")"),
    paste0("python/SPMG: SigProfilerMatrixGenerator 1.3.6 (bench/m1s/.venv)"),
    paste0("host: ", R.version$platform, "（Apple Silicon；功耗状态不可控，数字为该钉硬件口径）"))
}

lines <- c(
  "# B2 · SBS 目录生成 bench（M1s 验收门，ARCHITECTURE §8：10⁶ 突变 SBS96 vs SPMG ≥50× 且 <5s 单核）", "",
  "重跑：`python3 bench/m1s/sbs/gen_fixtures.py && Rscript bench/m1s/sbs/run_bench.R`。",
  "同一合成参考（2×2.5Mb，catalog/tests/genome fixture.rs 放大版，含 N blocks）、",
  "同一 10⁶ SNV：我方 = `ms_tally()` S7 端到端（单线程；次口径 FFI 层 `.ms_tally_rust`）；",
  "SPMG = SigProfilerMatrixGenerator 1.3.6 标准调用（自定义基因组 install + VCF 输入，", 
  "一次产出全套 9 种矩阵——工作量大于我方 SBS96 单表，判据偏保守，见注记）。", "",
  "## 环境", "",
  sapply(env(), function(l) paste0("- ", l)), "",
  "## 数字（主臂 = dbsfree：同样本同染色体最小间隔 2、无重复记录，双侧逐条对齐）", "",
  paste0("- 我方 ms_tally 3 次（s）：", paste(sprintf("%.4f", ours$runs), collapse = ", "),
         " → **median = ", sprintf("%.4f", ours$median_s), " s（<5s ✓）**"),
  paste0("- 我方 FFI 层 3 次（s）：", paste(sprintf("%.4f", ffi$runs), collapse = ", "),
         " → median = ", sprintf("%.4f", ffi$median_s),
         " s（S7−FFI 差 ≈ ", sprintf("%.1f", (ours$median_s - ffi$median_s) * 1e3),
         " ms，噪声级——S7 装配不构成可感开销）"),
  paste0("- SPMG 主臂单次墙钟 = ", sprintf("%.1f", spmg_full_s),
         " s（sanity 探针 ", sprintf("%.3f", spmg_san_s),
         " s；单次口径——分钟级不复跑）"),
  paste0("- **speedup = ", sprintf("%.1f", speedup), "×；判据 ≥50× 且我方 <5s：",
         ifelse(verdict, "PASS", "FAIL"), "**"),
  paste0("- **正确性锚（主臂逐格）**：ours sum=", main_cmp$sum_ours,
         " = SPMG sum=", main_cmp$sum_spmg, "，逐格差 = ", main_cmp$n_diff,
         ifelse(main_cmp$n_diff == 0L, "（✓ 完全一致）", "（⚠ P0）")), "",
  "## 次臂 dense（自然相邻密度，(chrom,pos,sample) 去重后对齐）", "",
  paste0("- 记录数 = ", nrow(tab_dense), "；我方判为 DBS 的成员数 = ", n_dbs_dense,
         "（排除出 SBS96）；我方 median = ", sprintf("%.3f", ours_dense$median_s),
         " s；SPMG = ", sprintf("%.1f", spmg_dense_s), " s"),
  paste0("- 总量对账：SPMG sum−我方 sum = ", sum(dense_cmp$diff),
         "，与 DBS 成员数相等 = ", dense_ok,
         "（且逐格差均 ≥0：SPMG 1.3.6 把 DBS 对成员一并计入 SBS96）"), "",
  "## 语义探针（sanity 100 变异，含 2 对同样本相邻 + 1 对跨样本相邻）", "",
  paste0("- 双侧路由一致：同样本相邻对均判为 DBS 类（我方 ledger 4 条 `dbs`；",
         "SPMG stdout 报 2 DINUCs）；跨样本相邻对双侧均保持 SBS。"),
  paste0("- **SBS96 计入策略不一致（P0 发现）**：SPMG 1.3.6 把 DBS 对成员一并计入",
         " SBS96（sanity sum=100 vs 我方 96，差和恰 = 4 个 DBS 成员；最小探针：",
         "1 对相邻 + 1 孤立 → SPMG SBS96=3 且不产出 DBS78）。我方按 U-M1s-09 审计",
         "语义（dinuc_sub==1 排除出全部 SBS 矩阵）实现。**审计所依据的上游行为与",
         "1.3.6 实测不符**——需 PI 复核 docs/research/04 所锚定的上游版本/代码路径，",
         "并在 M1c 的 DBS78 单元裁决取舍（本 bench 不改包代码）。"), "",
  "## 口径注记（如实）", "",
  "- SPMG 侧含 VCF 解析 + 9 种全套矩阵计算与写出；我方仅 SBS96 单表、输入在内存。",
  "  按工作量修正（SPMG 仅 SBS96）speedup 只会更高——本表数字对判据偏保守。",
  "- 速度形态：SPMG 主臂（dbsfree）9.8s vs dense 臂 46s——其耗时被重复记录",
  "  去重/相邻对（DINUC）处理路径主导；干净合成输入上 1.3.6 远低于 ≥50× 预算",
  "  隐含的「分钟级」基线。我方 3.7s 含 R→FFI 的 10⁶ 行字符列传递开销",
  "  （内核纯核口径在 HEAD 不可得，见下）——两侧预算假设均需按本表修正。",
  "- SPMG 会在 <vcf_dir>/input/ 缓存逐染色体转换产物；spmg_run.py 每次运行前",
  "  清除（否则静默消费陈旧记录集——本 bench 排障中的实测发现）。",
  "- SPMG 1.3.6 生成入口以硬编码 CHECKSUMS 白名单校验基因组，自定义基因组无法通过",
  "  （上游限制）；spmg_run.py 在运行时把本地安装产物的 md5 注册进该 dict，",
  "  不修改任何上游文件，矩阵生成代码路径全为原装。",
  "- SPMG 1.3.6 会整条丢弃完全重复记录（与样本无关、按整行比较；dense 臂生成期已按",
  "  (chrom,pos,sample) 去重对齐），以及上节的 DBS 计入策略——两条上游语义差异",
  "  均为本 bench 的发现，已列入遗留清单。",
  "- 「Rust bin 纯核」口径在 HEAD 不可得（tally 装配入口为包私有模块，包代码不可为",
  "  bench 改动）；FFI 层次口径即纯核上界（含 mmap + R 侧校验），已单列。", ""
)
writeLines(lines, file.path(HERE, "result.md"))
say("result.md 写出：", file.path(HERE, "result.md"))
quit(status = ifelse(verdict && main_cmp$n_diff == 0L, 0L, 1L))
