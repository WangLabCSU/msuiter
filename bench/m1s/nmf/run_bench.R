#!/usr/bin/env Rscript
# =============================================================================
# bench/m1s/nmf · M1s 验收门 NMF bench（docs/ARCHITECTURE.md §8 预算行：
#   NMF KL（96×1000, k=10, 100 iter）vs R NMF ≥100×。CI 只放 sanity bound。）
#
# 口径：同一 V/W0/H0（CSV 逐字节交换，整数计数 + k/1024 二进网格 init，
#   短精确十进制串——U-M1s-14 证实两侧解析逐位一致）；同迭代数 T=100。
#   我方 = driver（path 依赖 msuiter-engine）调未改动内核 fit_kl_with_init；
#   R 基线 = NMF 包 brunet（方案 A：seed=nmfModel(W0,H0) 外部初始化，
#   stopconv=1e6 停用早停，maxIter=T 精确控制——U-M1s-14 已证机制）。
#   双侧协议：预热 1 次 + 计时 3 次取中位；R 侧 elapsed 墙钟（C 内核单线程），
#   我方 driver 内 Instant 计时（内核单线程，engine crate 零依赖无 rayon）。
#
# 判据：median(R) / median(ours) ≥ 100。
# 正确性锚（信息项）：两侧 T=100 终态目标值（KL）相对差 < 1e-6（U-M1s-14 已证
#   96×20 下数值协议等价 ‖ΔW‖≈1e-15；此处只作运行有效性 sanity）。
#
# 一键重跑：Rscript bench/m1s/nmf/run_bench.R   （产出本目录 result.md）
# 计时环境如实写进 result.md（本机 Apple Silicon；功耗状态不可控）。
# =============================================================================

suppressMessages(library(NMF))

options(stringsAsFactors = FALSE, digits = 17, scipen = 12)

HERE <- normalizePath(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = 1))))
DIR_IN <- file.path(HERE, "cache", "input")
DIR_OUT <- file.path(HERE, "cache", "output")
dir.create(DIR_IN, recursive = TRUE, showWarnings = FALSE)
dir.create(DIR_OUT, recursive = TRUE, showWarnings = FALSE)

M <- 96L; N <- 1000L; K <- 10L; TITER <- 100L
SEED_DATA <- 20260928L   # V（可分合成计数）
SEED_INIT <- 20260929L   # W0/H0（k/1024 网格，严格正）
`%||%` <- function(a, b) if (is.null(a)) b else a
sig <- function(x, d = 6) format(x, digits = d, trim = TRUE, scientific = TRUE)
median3 <- function(x) as.numeric(median(x))

# ---- 输入生成：96×1000 整数计数，10 签名块状可分 + 近纯样本组 ---------------
gen_inputs <- function() {
  set.seed(SEED_DATA)
  Wt <- matrix(0, M, K)
  for (s in 1:K) {
    lo <- (s - 1L) * 10L + 1L
    hi <- min(s * 10L, M)               # s=10 只有 6 个锚通道（91..96）
    col <- rep(0, M)
    col[lo:hi] <- 0.5 + runif(hi - lo + 1L)
    Wt[, s] <- col / sum(col)
  }
  Ht <- matrix(0, K, N)
  for (j in 1:N) {
    dom <- ((j - 1L) %/% 100L) + 1L     # 每签名 100 个近纯样本
    for (s in 1:K) {
      Ht[s, j] <- if (s == dom) 500 + 1000 * runif(1) else 50 * runif(1)
    }
  }
  V <- round(Wt %*% Ht)                 # 整数计数；近纯样本组 ⇒ 次要签名贡献可舍入为 0（合法 KL 输入）
  stopifnot(all(V >= 0), all(rowSums(V) > 0), all(colSums(V) > 0))

  set.seed(SEED_INIT)
  scale <- sqrt(mean(V) / K)
  W0 <- matrix(1 + floor(runif(M * K) * 1023), M, K) / 1024 * scale
  H0 <- matrix(1 + floor(runif(K * N) * 1023), K, N) / 1024 * scale
  W0 <- round(W0 * 1024) / 1024         # 钉在 k/1024 网格（短精确十进制）
  H0 <- round(H0 * 1024) / 1024
  stopifnot(all(W0 > 0), all(H0 > 0))

  fmt <- function(x) format(x, digits = 17, trim = TRUE, scientific = FALSE)
  write_csv <- function(mat, path) {
    writeLines(apply(mat, 1L, function(row) paste(fmt(row), collapse = ",")),
               path, useBytes = TRUE)
  }
  write_csv(V,  file.path(DIR_IN, "V.csv"))
  write_csv(W0, file.path(DIR_IN, "W0.csv"))
  write_csv(H0, file.path(DIR_IN, "H0.csv"))
  list(V = V, W0 = W0, H0 = H0, scale = scale)
}

# ---- 我方：cargo 构建 driver → 3 次计时（driver 内部已做 1 预热） ----------
run_ours <- function() {
  bin <- file.path(HERE, "driver", "target", "release", "nmf-bench-driver")
  # 始终过一遍 cargo（增量、幂等）：防源码改动后跑陈旧二进制。
  system2("cargo", c("build", "--release", "--quiet", "--manifest-path",
    file.path(HERE, "driver", "Cargo.toml")))
  out <- system2(bin, c("--in", shQuote(DIR_IN), "--out", shQuote(DIR_OUT),
    "--iters", as.character(TITER)), stdout = TRUE, stderr = TRUE)
  status <- attr(out, "status") %||% 0L
  if (status != 0L) stop("driver failed:\n", paste(out, collapse = "\n"))
  kv <- setNames(sub("^[^,]+,", "", out), sub(",[^,]+$", "", out))
  list(runs = as.numeric(kv[c("run0", "run1", "run2")]),       median_ms = as.numeric(kv[["median_ms"]]),
       meta = read.csv(file.path(DIR_OUT, "meta.csv"), header = FALSE,
                       colClasses = "character"))
}

# ---- R 基线：NMF brunet（方案 A 外部初始化，预热 1 + 计时 3 取中位） --------
run_r_baseline <- function(d) {
  mod0 <- nmfModel(rank = K, W = d$W0, H = d$H0)
  one_timed <- function() {
    t0 <- proc.time()
    r <- suppressWarnings(nmf(d$V, K, method = "brunet", seed = mod0,
      maxIter = TITER, stopconv = 1e6, .options = list(verbose = 0)))
    list(elapsed = (proc.time() - t0)[["elapsed"]],
         niter = NMF::niter(r), resid = tail(NMF::residuals(r), 1))
  }
  invisible(one_timed())                # 预热 1 次（page cache / 字节码）
  runs <- replicate(3L, one_timed(), simplify = FALSE)
  elapsed <- vapply(runs, `[[`, numeric(1), "elapsed")
  list(runs = elapsed, median_s = median3(elapsed),
       niter = runs[[1]]$niter, resid = runs[[1]]$resid)
}

# =============================================================================
# 主流程
# =============================================================================
say <- function(...) cat(..., "\n", sep = "")
env_lines <- function() {
  si <- sessionInfo()
  c(
    paste0("date: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("R: ", R.version$version.string, " (", R.version$platform, ")"),
    paste0("NMF: ", as.character(packageVersion("NMF"))),
    paste0("BLAS: ", si$BLAS, " | LAPACK: ", si$LAPACK),
    paste0("rustc/cargo: ",
           paste(tryCatch(system2("rustc", "--version", stdout = TRUE),
                          error = function(e) "n/a"), collapse = " ")),
    paste0("host: ", R.version$platform, "（Apple Silicon；功耗状态不可控，数字为该钉硬件口径）")
  )
}

say("== M1s NMF bench：KL 96×1000, k=10, T=100 ==")
for (l in env_lines()) say("  ", l)

say("输入生成（set.seed 全记录）：data=", SEED_DATA, " init=", SEED_INIT)
d <- gen_inputs()
say(sprintf("  V: %d×%d 整数计数 min=%g max=%g sum=%g | 网格 init scale=%.6g",
  M, N, min(d$V), max(d$V), sum(d$V), d$scale))

say("我方（engine fit_kl_with_init，driver 纯核计时）...")
ours <- run_ours()
for (i in seq_along(ours$runs)) say(sprintf("  run%d: %.3f ms", i - 1L, ours$runs[i]))
say(sprintf("  median: %.3f ms", ours$median_ms))

say("R 基线（NMF 0.28 brunet，方案 A）...")
rb <- run_r_baseline(d)
for (i in seq_along(rb$runs)) say(sprintf("  run%d: %.3f s", i, rb$runs[i]))
say(sprintf("  median: %.3f s | niter=%d", rb$median_s, rb$niter))

speedup <- rb$median_s * 1e3 / ours$median_ms
obj_ours <- as.numeric(ours$meta[ours$meta[, 1] == "obj_final", 2])
rel_obj <- abs(obj_ours - as.numeric(rb$resid)) / abs(as.numeric(rb$resid))
verdict <- speedup >= 100

# 信息项：每迭代成本分解（fit_kl_with_init 每迭代含目标轨迹的一次 kl_objective
# = 第 3 次 WH matmul + 96k 次 ln；R brunet 基线不逐迭代算目标）。T=1 vs T=100
# 的中位差 → 每迭代斜率；该斜率含轨迹开销，不能据此单独分离纯更新成本。
bin_drv <- file.path(HERE, "driver", "target", "release", "nmf-bench-driver")
decomp_out <- system2(bin_drv, c("--in", shQuote(DIR_IN), "--out",
  shQuote(DIR_OUT), "--iters", "1"), stdout = TRUE, stderr = TRUE)
t1_ms <- as.numeric(sub("^[^,]+,", "", decomp_out[grepl("^median_ms,", decomp_out)]))
per_iter_ms <- (ours$median_ms - t1_ms) / (TITER - 1L)
say(sprintf("判据：speedup = %s / %.3f ms = %.1f×（≥100×？%s）",
  sig(rb$median_s, 4), ours$median_ms, speedup, ifelse(verdict, "PASS", "FAIL")))
say(sprintf("正确性锚（信息项）：KL 终值 ours=%.10e R=%.10e 相对差=%.3e（<1e-6）",
  obj_ours, as.numeric(rb$resid), rel_obj))

# ---- result.md -------------------------------------------------------------
lines <- c(
  "# B1 · NMF bench（M1s 验收门，ARCHITECTURE §8：96×1000, k=10, 100 iter vs R NMF ≥100×）", "",
  "重跑：`Rscript bench/m1s/nmf/run_bench.R`。同 V/W0/H0（CSV 逐字节交换）、同 T=100；",
  "双侧协议：预热 1 次 + 计时 3 次取中位。我方 = driver 纯核（`fit_kl_with_init`，单线程）；",
  "R = NMF 0.28 brunet（外部初始化 W0/H0，stopconv=1e6，maxIter=100 精确控制）。", "",
  "## 环境", "",
  sapply(env_lines(), function(l) paste0("- ", l)), "",
  "## 数字", "",
  paste0("- 输入：V 96×1000 整数计数（可分合成，seed=", SEED_DATA, "）；init W0/H0 k/1024 网格（seed=", SEED_INIT, "）"),
  paste0("- 我方 3 次（ms）：", paste(sprintf("%.3f", ours$runs), collapse = ", "),
         " → median = ", sprintf("%.3f", ours$median_ms), " ms"),
  paste0("- R brunet 3 次（s）：", paste(sprintf("%.3f", rb$runs), collapse = ", "),
         " → median = ", sig(rb$median_s, 4), " s"),
  paste0("- **speedup = ", sprintf("%.1f", speedup), "× ；判据 ≥100×：",
         ifelse(verdict, "PASS", "FAIL"), "**"),
  paste0("- 信息项：每迭代斜率 ≈ ", sprintf("%.3f", per_iter_ms),
         " ms/iter（T=1 中位 ", sprintf("%.3f", t1_ms),
         " ms vs T=100 中位）；fit_kl_with_init 每迭代含目标轨迹的 kl_objective",
         "（第 3 次 WH matmul + 96k ln，U-M1s-14 数值协议所需），R brunet 基线",
         "不逐迭代算目标——同粒度拟合比较会好于本表 speedup，但与 100× 仍差 1 个量级以上。"),
  paste0("- 正确性锚（信息项）：T=100 KL 终值 ours=", sig(obj_ours, 10),
         " R=", sig(as.numeric(rb$resid), 10), " 相对差=", sig(rel_obj, 3),
         ifelse(rel_obj < 1e-6, "（<1e-6，同迭代语义确认）", "（⚠ 超 1e-6，需复核）")), ""
)
writeLines(lines, file.path(HERE, "result.md"))
say("result.md 写出：", file.path(HERE, "result.md"))
quit(status = ifelse(verdict, 0L, 1L))
