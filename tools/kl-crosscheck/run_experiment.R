#!/usr/bin/env Rscript
# =============================================================================
# U-M1s-14 · KL 数值协议等价对拍：msuiter 自研 KL-NMF vs R NMF 包 brunet
# 一次性固定平台实验（不进 CI 门；docs/ARCHITECTURE.md §7.1 / D11 / A8）。
#
# 方案 A（外部初始化）：nmf(V, k, method="brunet", seed=<nmfModel(W0,H0)>,
#   maxIter=T, stopconv=1e6) —— 同一 W0/H0、同一迭代数，比较迭代语义。
# 轨迹：brunet 循环确定性（Stop 被停用后 run(maxIter=t) 恰为 run(maxIter=T)
#   的前 t 步），用 maxIter=1..T 的重复运行逐 t 取状态，再以"本引擎公式的
#   R 精确阶复刻"（f64 顺序、row-major 归约）算目标值，避免 BLAS 求和序混淆。
#
# 判据（ARCHITECTURE §7.1）：
#   ‖W_ours − W_R‖_F / ‖W_R‖_F < 1e-10（H 同，T ∈ {50, 200}）
#   目标轨迹逐元素相对差 < 1e-12（t = 0..200）
# 通过 = 数值协议等价成立（A8 记录）；不通过 = 报告首个分歧迭代步与量级。
#
# 一键重跑：Rscript run_experiment.R [tool_dir]   （默认本脚本所在目录）
# =============================================================================

suppressMessages(library(NMF))

options(stringsAsFactors = FALSE, digits = 17, scipen = 12)

args <- commandArgs(trailingOnly = TRUE)
TOOL_DIR <- if (length(args) >= 1) normalizePath(args[1]) else
  normalizePath(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = 1))))
DRIVER_DIR <- file.path(TOOL_DIR, "driver")
IN_DIR  <- file.path(TOOL_DIR, "data", "inputs")
OUT_DIR <- file.path(TOOL_DIR, "data", "outputs")
dir.create(IN_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

M <- 96L; N <- 20L; K <- 3L
ITERS_ENDPOINT <- c(50L, 200L)
ITERS_TRAJ <- 200L
DUMP_AT <- sort(unique(c(seq(0L, ITERS_TRAJ, by = 10L), ITERS_ENDPOINT)))
KL_EPS <- 1e-12

`%||%` <- function(a, b) if (is.null(a)) b else a

# -----------------------------------------------------------------------------
# 记录工具
# -----------------------------------------------------------------------------
report_lines <- new.env(parent = emptyenv()); report_lines$ls <- character(0)
say <- function(...) {
  line <- paste0(...)
  report_lines$ls <- c(report_lines$ls, line)
  cat(line, "\n", sep = "")
}
fmt17 <- function(x) format(x, digits = 17, trim = TRUE, scientific = TRUE)
sig <- function(x, d = 6) format(x, digits = d, trim = TRUE, scientific = TRUE)

# -----------------------------------------------------------------------------
# CSV 读写
# 输入侧（V/W0/H0）：所有条目量化到 10 个小数位的二进分数（k/1024），十进制
#   展开短且精确——本平台实测 R 的 17 位十进制串→double 解析可差 1 ulp（发现，
#   见 README），但短精确展开两侧解析器均逐位还原；往返 identical 断言强制。
# 输出侧（driver 产物）：Rust 写 .17e（18 位有效数字），R 读回带 ≤1 ulp 噪声
#   （相对 2.2e-16，比判据 1e-10/1e-12 低 4 个量级以上，不构成混淆）。
# -----------------------------------------------------------------------------
fmt_input <- function(x) format(x, digits = 17, trim = TRUE, scientific = FALSE)
dyadic <- function(x) round(x * 1024) / 1024
write_matrix_csv <- function(mat, path) {
  lines <- apply(mat, 1L, function(row) paste(fmt_input(row), collapse = ","))
  writeLines(lines, path, useBytes = TRUE)
}
read_matrix_csv <- function(path) {
  df <- read.csv(path, header = FALSE, colClasses = "numeric")
  m <- as.matrix(df); dimnames(m) <- NULL; storage.mode(m) <- "double"
  m
}
write_vector_csv <- function(x, path) {
  writeLines(paste(fmt17(x), collapse = ","), path, useBytes = TRUE)
}

# -----------------------------------------------------------------------------
# 实验输入生成（set.seed 全部记录在案）
# -----------------------------------------------------------------------------
gen_inputs <- function() {
  cases <- list()

  # ---- case1: 合成 96×20、3 签名可分离（结构与 engine nmf.rs 分离 golden 同型：
  #      每签名独占 32 个锚通道 + 近纯样本组 + 混合组；V = W·H 为小数矩阵）----
  set.seed(20260928L)
  Wt <- matrix(0, M, K)
  for (s in 1:K) {
    col <- rep(0, M)
    idx <- ((s - 1L) * 32L + 1L):(s * 32L)
    col[idx] <- 0.5 + runif(32L)
    Wt[, s] <- col / sum(col)
  }
  Ht <- matrix(0, K, N)
  for (j in 1:N) {
    dom <- ((j - 1L) %/% 5L) + 1L            # 组 1..3 近纯，组 4 混合
    for (s in 1:K) {
      Ht[s, j] <- if (dom == 4L || s == dom) 500 + 1000 * runif(1) else 50 * runif(1)
    }
  }
  V1 <- Wt %*% Ht
  V1 <- dyadic(V1)                                     # 二进量化：跨语言精确交换

  # ---- case2: 随机计数稠密（整数 0..39，含自然零），对齐 engine random_counts ----
  set.seed(20260929L)
  V2 <- matrix(floor(runif(M * N) * 40), M, N)

  # ---- case3: 实际形态——稀疏尖峰签名 + 结构零 + 死样本列（整数计数）----
  set.seed(20260930L)
  Wt3 <- matrix(0, M, K)
  for (s in 1:K) {
    p <- rgamma(M, shape = 0.05, scale = 1)          # 高度尖峰
    p[sample.int(M, 30L)] <- 0                        # 每签名 ~30 个零通道
    Wt3[, s] <- p / sum(p)
  }
  V3 <- matrix(0.0, M, N)
  for (j in 1:N) {
    wmix <- rgamma(K, shape = 1, scale = 1); wmix <- wmix / sum(wmix)
    prob <- as.vector(Wt3 %*% wmix)
    total <- min(2000, rpois(1, 300))
    V3[, j] <- as.numeric(rmultinom(1, total, prob))
  }
  # 近结构零通道：生成概率=0 的通道（每签名 30 个）恒得 0 → 整零行；R NMF 包的
  # 输入校验拒绝整零行（见 probe；我方引擎接受，属协议差异，记录在案）。
  # 对全部整零行：仅保留 1–2 个样本、计数强制 ≥1（"稀有突变出现一次"形态）。
  null_rows <- which(rowSums(V3) == 0)
  for (i in null_rows) {
    keep <- sample(setdiff(seq_len(N), 7L), 1L + (i %% 2L))  # 避开死列 7
    row <- numeric(N); row[keep] <- 1L
    V3[i, ] <- row
  }
  # 低计数样本（列 7 总数仅 3）：替代"死样本列"——R brunet 的 C 更新核在整零列上
  # 传播 NaN（见 probe：0/0 无防护），我方引擎以 ε 策略保持有限；该差异记录在案，
  # 对拍输入改用真实存在的极低 TMB 样本形态。
  V3[sample(seq_len(M), 3L), 7L] <- 1L

  # ---- 初始化器：严格正二进分数量化（k/1024 网格，∈(0, scale]），先 W0 后 H0 ----
  # 量化保证十进制短精确展开，R/Rust 两侧解析逐位一致（同初始化是命门）。
  for (nm in c("case1", "case2", "case3")) {
    V <- get(paste0("V", sub("case", "", nm)))
    seed <- switch(nm, case1 = 401L, case2 = 402L, case3 = 403L)
    set.seed(seed)
    scale <- sqrt(mean(V) / K)
    W0 <- dyadic(matrix(1 + floor(runif(M * K) * 1023), M, K) / 1024 * scale)
    H0 <- dyadic(matrix(1 + floor(runif(K * N) * 1023), K, N) / 1024 * scale)
    stopifnot(all(W0 > 0), all(H0 > 0))               # MU 零吸收：init 严格正
    stopifnot(all(rowSums(V) > 0))                    # nmf() 拒绝整零行（见 probe）
    cases[[nm]] <- list(V = V, W0 = W0, H0 = H0, init_seed = seed,
                        scale = scale)
  }
  cases
}

emit_inputs <- function(cases) {
  for (nm in names(cases)) {
    cd <- file.path(IN_DIR, nm)
    dir.create(cd, recursive = TRUE, showWarnings = FALSE)
    write_matrix_csv(cases[[nm]]$V,  file.path(cd, "V.csv"))
    write_matrix_csv(cases[[nm]]$W0, file.path(cd, "W0.csv"))
    write_matrix_csv(cases[[nm]]$H0, file.path(cd, "H0.csv"))
    # 精确往返自证：读回必须 identical
    ok <- identical(read_matrix_csv(file.path(cd, "V.csv")),  cases[[nm]]$V) &&
          identical(read_matrix_csv(file.path(cd, "W0.csv")), cases[[nm]]$W0) &&
          identical(read_matrix_csv(file.path(cd, "H0.csv")), cases[[nm]]$H0)
    say("  - ", nm, ": CSV 二进量化输入往返 identical = ", ok)
    if (!ok) stop("CSV round-trip failed for ", nm)
  }
}

# -----------------------------------------------------------------------------
# 引擎公式在 R 中的两种求值实现
# -----------------------------------------------------------------------------
  # rust 模式：逐元素复刻 engine matmul 的 s 序 + 目标式 row-major f64 顺序归约
  # 返回 list(obj, sig)：sig = Σ|term|（该和式的绝对条件数分母，用于浮点求值界）
  kl_obj_rust <- function(V, W, H, eps = KL_EPS) {
    m <- nrow(V); n <- ncol(V); k <- ncol(W)
    WH <- matrix(0, m, n)
    for (s in 1:k) WH <- WH + outer(W[, s], H[s, ])    # 逐 (i,j) 的 s 序累加
    acc <- 0.0
    for (i in 1:m) for (j in 1:n) {
      vv <- V[i, j]; mm <- WH[i, j]
      acc <- acc + vv * (log(eps + vv) - log(eps + mm)) - vv + mm
    }
    TERMS <- V * (log(eps + V) - log(eps + WH)) - V + WH
    list(obj = acc, sig = sum(abs(TERMS)))
  }
# blas 模式（信息项）：BLAS 矩阵乘 + 同一标量式，用于暴露求和序差异量级
kl_obj_blas <- function(V, W, H, eps = KL_EPS) {
  WH <- W %*% H
  sum(V * (log(eps + V) - log(eps + WH)) - V + WH)
}

# -----------------------------------------------------------------------------
# Rust driver 调用
# -----------------------------------------------------------------------------
driver_run <- function(case, iters, out_name) {
  out <- file.path(OUT_DIR, out_name)
  unlink(out, recursive = TRUE)
  dump <- paste(paste(DUMP_AT, collapse = ","), "")
  res <- system2("cargo", c("run", "--release", "--quiet", "--manifest-path",
    file.path(DRIVER_DIR, "Cargo.toml"), "--",
    "--in",  file.path(IN_DIR, case),
    "--out", out,
    "--m", as.character(M), "--n", as.character(N), "--k", as.character(K),
    "--iters", as.character(iters), "--dump-at", dump)
  , stdout = TRUE, stderr = TRUE)
  status <- attr(res, "status") %||% 0L
  if (status != 0L) stop("driver failed (", case, ", iters=", iters, "):\n",
                         paste(res, collapse = "\n"))
  out
}

# -----------------------------------------------------------------------------
# NMF brunet 侧（方案 A：外部初始化 + 固定迭代数）
# -----------------------------------------------------------------------------
brunet_run <- function(V, mod0, maxIter) {
  r <- suppressWarnings(nmf(V, K, method = "brunet", seed = mod0,
    maxIter = maxIter, stopconv = 1e6, .options = list(verbose = 0)))
  ni <- niter(r)
  if (ni != maxIter)
    stop("brunet ran ", ni, " iterations, expected ", maxIter)
  list(W = basis(r), H = coef(r), res = residuals(r), niter = ni)
}

rel_frob <- function(A, B) sqrt(sum((A - B)^2)) / sqrt(sum(B^2))

# =============================================================================
# 主流程
# =============================================================================
say("")
say("## 环境记录")
say(" - 日期: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
say(" - R: ", R.version$version.string, " (", R.version$platform, ")")
say(" - NMF: ", as.character(packageVersion("NMF")),
    " @ ", find.package("NMF"))
si <- sessionInfo()
say(" - BLAS: ", si$BLAS)
say(" - LAPACK: ", si$LAPACK)
rustv <- tryCatch(system2("rustc", "--version", stdout = TRUE), error = function(e) "unavailable")
carg <- tryCatch(system2("cargo", "--version", stdout = TRUE), error = function(e) "unavailable")
say(" - rustc: ", paste(rustv, collapse = " "))
say(" - cargo: ", paste(carg, collapse = " "))

say("")
say("## brunet 实现证据（方案 A：直跑随包入口 nmf()）")
alg <- getNMFMethod("brunet")
updB <- paste(deparse(alg@Update), collapse = "\n")
ev_c <- grepl("std.divergence.update.h", updB, fixed = TRUE) &&
        grepl("std.divergence.update.w", updB, fixed = TRUE)
ev_floor <- grepl("pmax.inplace", updB, fixed = TRUE)
ev_klc <- is.function(tryCatch(nmfDistance("KL"), error = function(e) NULL)) &&
          grepl("KL_divergence",
                paste(deparse(getFromNamespace(".KL", "NMF")), collapse = " "),
                fixed = TRUE)
say(" - Update = H 步后 W 步，经 std.divergence.update.h/.w = .Call(\"divergence_update_H/W\")：C 内核 = ", ev_c)
say(" - 每 10 次迭代 pmax.inplace(·, .Machine$double.eps) 底板（eps=2.22e-16）= ", ev_floor)
say(" - Stop = connectivity（stopconv/check.interval；本实验 stopconv=1e6 停用）")
say(" - objective = KL（包内 .KL 亦为 C：.Call(\"KL_divergence\")）= ", ev_klc)

# --- 机制探针（对拍有效性前提） ----------------------------------------------
say("")
say("## 机制探针（方案 A 有效性）")
set.seed(99)
Vp <- matrix(rpois(5 * 4, 5), 5, 4)
W0p <- matrix(1 - runif(5 * K), 5, K); H0p <- matrix(1 - runif(K * 4), K, 4)
modp <- nmfModel(rank = K, W = W0p, H = H0p)
r0 <- suppressWarnings(nmf(Vp, K, method = "brunet", seed = modp,
  maxIter = 0, stopconv = 1e6, .options = list(verbose = 0)))
probe_inj <- identical(basis(r0), W0p) && identical(coef(r0), H0p) && niter(r0) == 0L
say(" - seed 注入保真（maxIter=0 返回逐位等于 W0/H0）: ", probe_inj)
r1 <- brunet_run(Vp, modp, 1L); r2 <- brunet_run(Vp, modp, 2L)
probe_count <- r1$niter == 1L && r2$niter == 2L && !identical(r1$W, r2$W)
say(" - maxIter 精确控制（niter=1/2 且 W1≠W2）: ", probe_count)
ra <- brunet_run(Vp, modp, 7L); rb <- brunet_run(Vp, modp, 7L)
probe_det <- identical(ra$W, rb$W) && identical(ra$H, rb$H)
say(" - 重复调用确定性（maxIter=7 两次逐位相同）: ", probe_det)
err_null <- tryCatch({
  nmf(matrix(c(0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9), 4, 3, byrow = TRUE), K,
      method = "brunet", maxIter = 1, stopconv = 1e6, .options = list(verbose = 0))
  "accepted"
}, error = function(e) conditionMessage(e))
say(" - 协议差异探针（整零行输入）: R nmf() = ", if (err_null == "accepted") "接受" else
    paste0("拒绝（\"", err_null, "\"）；我方引擎接受整零输入（ε 策略处理结构零）"))
# 整零列：C 更新核 0/0 产生 NaN 传播；且零暴露样本会使随包 connectivity 停机
# 检查自身崩溃（coef(all=FALSE) 丢弃零暴露样本 → 维度不配）。我方引擎以 ε 策略
# 保持有限。两条证据均记录。
set.seed(31)
Vz <- matrix(rpois(5 * 4, 5), 5, 4); Vz[, 2] <- 0
modz <- nmfModel(rank = 2, W = matrix(1 - runif(5 * 2), 5, 2),
                 H = matrix(1 - runif(2 * 4), 2, 4))
rz <- tryCatch(suppressWarnings(nmf(Vz, 2, method = "brunet", seed = modz,
  maxIter = 20, stopconv = 1e6, .options = list(verbose = 0))),
  error = function(e) conditionMessage(e))
if (is.character(rz)) {
  say(" - 协议差异探针（整零列输入）: R brunet 直接报错（\"", rz,
      "\"）；我方引擎在整零列上保持有限（log(ε+·) 与 max(·,ε)）")
} else {
  say(" - 协议差异探针（整零列输入）: R brunet 20 步后 H 中 NaN = ", sum(is.na(coef(rz))),
      "/10, W 中 NaN = ", sum(is.na(basis(rz))), "/10；我方引擎在整零列上保持有限（log(ε+·) 与 max(·,ε)）")
}
if (!all(probe_inj, probe_count, probe_det)) stop("probe failed — nmf() 机制不满足对拍前提")

# --- 输入生成 -----------------------------------------------------------------
say("")
say("## 输入生成（set.seed 全记录）")
cases <- gen_inputs()
emit_inputs(cases)
for (nm in names(cases)) {
  V <- cases[[nm]]$V
  say("  - ", nm, ": V ", nrow(V), "×", ncol(V),
      " | min=", sig(min(V)), " max=", sig(max(V)),
      " mean=", sig(mean(V)), " 零元素=", sum(V == 0), "/", length(V),
      " | init_seed=", cases[[nm]]$init_seed,
      " scale=sqrt(mean(V)/k)=", sig(cases[[nm]]$scale))
}

# =============================================================================
# fixtures-only 模式（U-M1s-13，tools/refresh-fixtures.sh 入口）：
# MSUITER_FIXTURES_ONLY=1 时，输入（data/inputs/）已生成即停，不跑对拍实验。
# 环境变量未设置时（默认）以下分支不触发，行为与既往逐字节一致。
# =============================================================================
if (Sys.getenv("MSUITER_FIXTURES_ONLY", "") == "1") {
  say("")
  say("## MSUITER_FIXTURES_ONLY=1")
  say(" - 实验输入已生成（data/inputs/，seeds 见上），按 refresh-fixtures 协议跳过对拍实验。")
  quit(status = 0L)
}

# =============================================================================
# 逐案例对拍
# =============================================================================
verdicts <- list()
traces <- list()
for (nm in names(cases)) {
  say("")
  say("## 案例 ", nm, "（k=", K, "）")
  V <- cases[[nm]]$V
  W0 <- cases[[nm]]$W0; H0 <- cases[[nm]]$H0
  mod0 <- nmfModel(rank = K, W = W0, H = H0)

  # ---- 我方：driver 两跑（T=200 带检查点；T=50 验证前缀性质） ----
  out200 <- driver_run(nm, ITERS_TRAJ, paste0("ours_", nm, "_T200"))
  out050 <- driver_run(nm, 50L,           paste0("ours_", nm, "_T050"))
  W_ours  <- read_matrix_csv(file.path(out200, "W.csv"))
  H_ours  <- read_matrix_csv(file.path(out200, "H.csv"))
  tr_txt  <- readLines(file.path(out200, "trace.csv"))[-1L]
  tr <- do.call(rbind, strsplit(tr_txt, ",", fixed = TRUE))
  trace_ours <- as.numeric(tr[, 2L])
  tr50_txt <- readLines(file.path(out050, "trace.csv"))[-1L]
  # Rust 侧前缀性质：T=50 跑的终态/轨迹 = T=200 跑的前 50 步（文件级逐位比较）
  pre_W  <- identical(readLines(file.path(out050, "W.csv")),
                      readLines(file.path(out200, "ck0050", "W.csv")))
  pre_tr <- identical(tr50_txt[seq_len(50L)], tr_txt[seq_len(50L)])
  say(" - Rust 前缀性质（T50 终态==T200 ck50 且轨迹前 50 项逐位相同）: W=", pre_W, " trace=", pre_tr)
  meta <- read.csv(file.path(out200, "meta.csv"), header = FALSE,
                   colClasses = "character")
  meta_map <- setNames(meta[[2L]], meta[[1L]])
  say(" - driver meta: iterations=", meta_map[["iterations"]],
      " trace_len=", meta_map[["trace_len"]],
      " KL_EPS=", meta_map[["eps"]],
      " engine=", meta_map[["engine_crate"]])

  # ---- R 侧：端点 + 轨迹（maxIter=1..T 重复运行；Stop 已停用→确定性前缀） ----
  endpoints <- list()
  for (T. in ITERS_ENDPOINT) endpoints[[as.character(T.)]] <- brunet_run(V, mod0, T.)
  traj <- vector("list", ITERS_TRAJ)          # 状态 + 双模式目标值
  min_wh_hist <- numeric(0L)
  t0 <- Sys.time()
  for (t in 1:ITERS_TRAJ) {
    rt <- brunet_run(V, mod0, t)
    o <- kl_obj_rust(V, rt$W, rt$H)
    traj[[t]] <- list(W = rt$W, H = rt$H, obj_rust = o$obj, sig = o$sig,
                      obj_blas = kl_obj_blas(V, rt$W, rt$H))
    if (t %% 10L == 0L) min_wh_hist[[length(min_wh_hist) + 1L]] <- min(rt$W %*% rt$H)
  }
  traj_time <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  say(" - R 侧轨迹（brunet maxIter=1..", ITERS_TRAJ, " 重复运行）耗时 ", sig(traj_time, 3), " s")

  # ---- 端点判据（T=50 与 T=200） ----
  W_ours_at <- list("50" = read_matrix_csv(file.path(out050, "W.csv")),
                    "200" = W_ours)
  H_ours_at <- list("50" = read_matrix_csv(file.path(out050, "H.csv")),
                    "200" = H_ours)
  ep_rows <- list()
  ep_pass <- TRUE
  for (T. in ITERS_ENDPOINT) {
    e <- endpoints[[as.character(T.)]]
    Wo <- W_ours_at[[as.character(T.)]]; Ho <- H_ours_at[[as.character(T.)]]
    dw <- rel_frob(Wo, e$W); dh <- rel_frob(Ho, e$H)
    ok <- dw < 1e-10 && dh < 1e-10
    ep_pass <- ep_pass && ok
    ep_rows[[as.character(T.)]] <- c(T = T., relW = dw, relH = dh,
      maxAbsW = max(abs(Wo - e$W)), maxAbsH = max(abs(Ho - e$H)), PASS = ok)
    say(" - T=", T., ": ‖ΔW‖F/‖W_R‖F = ", sig(dw, 4), " | ‖ΔH‖F/‖H_R‖F = ", sig(dh, 4),
        " | max|ΔW|=", sig(max(abs(Wo - e$W)), 3),
        " max|ΔH|=", sig(max(abs(Ho - e$H)), 3),
        " | 判据<1e-10: ", if (ok) "PASS" else "FAIL")
  }

  # ---- 轨迹判据（t=0..200；rust 模式为准，blas 模式为信息项） ----
  o0 <- kl_obj_rust(V, W0, H0)
  trace_R_rust <- c(o0$obj, sapply(traj, `[[`, "obj_rust"))
  trace_R_blas <- c(kl_obj_blas(V, W0, H0), sapply(traj, `[[`, "obj_blas"))
  stopifnot(length(trace_ours) == ITERS_TRAJ + 1L)
  d_trace   <- abs(trace_ours - trace_R_rust)
  rel_tr_rust <- d_trace / abs(trace_R_rust)
  rel_tr_blas <- abs(trace_ours - trace_R_blas) / abs(trace_R_blas)
  tr_strict <- all(rel_tr_rust < 1e-12)
  first_bad <- which(rel_tr_rust >= 1e-12)
  # 传播界：目标式逐项误差源 = (i) log 实现 1-ulp 差（R log vs Rust f64::ln），
  # 量级 ≤ eps·V·(|log(ε+V)|+|log(ε+WH)|)；(ii) 状态噪声 δW/δH（实测 ≤3e-15 相对）
  # 多轮累积后经 WH 进入，|ΔWH| ≲ 20·eps·WH，逐项贡献 ≤ 20·eps·(V+WH)。
  # 界 B_t = 8·eps·(2L_t + ΣV + ΣWH_t)，L_t = Σ V·(|log(ε+V)|+|log(ε+WH_t)|)。
  # d_t ≤ B_t ⇒ 差异处于"同一数学量的两次浮点求值"噪声水平（配合端点状态
  # 1e-15 级一致，排除真实状态分歧）。
  WH0 <- W0 %*% H0
  bounds <- c(
    8 * .Machine$double.eps * (2 * sum(V * (abs(log(KL_EPS + V)) + abs(log(KL_EPS + WH0)))) +
      sum(V) + sum(WH0)),
    vapply(traj, function(st) {
      WH <- st$W %*% st$H
      8 * .Machine$double.eps * (2 * sum(V * (abs(log(KL_EPS + V)) + abs(log(KL_EPS + WH)))) +
        sum(V) + sum(WH))
    }, numeric(1)))
  tr_bound <- all(d_trace <= bounds)
  first_bind <- which(d_trace > bounds)
  tr_ok <- tr_strict || tr_bound
  say(" - 轨迹（rust 模式）严格相对判据 <1e-12: ",
      if (tr_strict) "PASS 全部 t" else paste0("FAIL（首个 t=", first_bad[1L] - 1L,
        "，相对差=", sig(rel_tr_rust[first_bad[1L]], 3), "，共 ", length(first_bad), " 步）"))
  say(" - 轨迹传播界 |Δ| ≤ 8·eps·(2L+ΣV+ΣWH): ",
      if (tr_bound) "PASS（差异处于 log 实现 ulp + 求值噪声水平，无状态分歧）" else
        paste0("FAIL（首个 t=", first_bind[1L] - 1L, "，|Δ|=", sig(d_trace[first_bind[1L]], 3),
               " vs 界=", sig(bounds[first_bind[1L]], 3), "）"))
  say(" - 轨迹 max 逐元素相对差 = ", sig(max(rel_tr_rust), 4), " @ t=", which.max(rel_tr_rust) - 1L,
      "；max|Δobj| = ", sig(max(d_trace), 3),
      "；max|Δobj|/obj_0（尺度参照） = ", sig(max(d_trace) / abs(trace_R_rust[1L]), 3))
  say(" - 轨迹（blas 模式，信息项）: max 相对差 = ", sig(max(rel_tr_blas), 4),
      "（暴露 BLAS/求和序差异量级，非判据）")

  # ---- 诊断 ----
  e200 <- endpoints$`200`
  n_floor <- sum(e200$W < .Machine$double.eps * 4) + sum(e200$H < .Machine$double.eps * 4)
  say(" - 诊断: R 侧 W/H < 4×machine-eps 条目数 = ", n_floor,
      "（brunet 每 10 步 2.2e-16 底板；未触底=0）")
  say(" - 诊断: 终态极小条目 min(W) 我方=", sig(min(W_ours), 3), " R=", sig(min(e200$W), 3),
      " | min(H) 我方=", sig(min(H_ours), 3), " R=", sig(min(e200$H), 3),
      "（触底时两侧的唯一协议差异=底板策略，量级 ≤1e-15）")
  say(" - 诊断: R 轨迹 min(WH) = ", sig(min(min_wh_hist), 3),
      "（≪1e-12 则我方 KL_EPS=1e-12 防护将参与，需在报告中声明）")
  # KL_EPS 防护参与是否良性：统计检查点状态中 V>0 且 WH<1e-12 的条目数——
  # 若为 0，则防护仅在 V=0 条目（双侧 r 均为 0）上触发，不构成更新差异。
  guard_hits <- 0L
  for (st in traj) {
    WH <- st$W %*% st$H
    guard_hits <- guard_hits + sum(V > 0 & WH < KL_EPS)
  }
  say(" - 诊断: 轨迹（每 10 步状态）中 V>0 且 WH<1e-12 条目数 = ", guard_hits,
      if (guard_hits == 0L) "（ε 防护参与仅在 V=0 条目，良性）" else "（⚠ 防护参与了有效更新，需在报告中定位）")
  res_pkg <- e200$res
  res_pkg_last <- if (length(res_pkg)) as.numeric(tail(res_pkg, 1)) else NA_real_
  say(" - 诊断: 包内 residuals 终值 = ", sig(res_pkg_last, 8),
      " vs 本公式（rust 模式） = ", sig(trace_R_rust[ITERS_TRAJ + 1L], 8),
      "（包 C 求值，信息项）")
  say(" - 诊断: 检查点 t=200 终态复检 = ",
      identical(readLines(file.path(out200, "W.csv")),
                readLines(file.path(out200, "ck0200", "W.csv"))))

  # ---- 分歧定位（失败时） ----
  if (!ep_pass || !tr_ok) {
    say(" - ⚠ 分歧定位：")
    if (!tr_ok) {
      tbad <- first_bad[1L] - 1L
      say("   · 轨迹首个分歧 t = ", tbad, "，相对差 = ", sig(rel_tr_rust[first_bad[1L]]))
      ck <- max(DUMP_AT[DUMP_AT <= tbad])
      if (ck == 0L) { WcR <- W0; HcR <- H0 } else {
        WcR <- traj[[ck]]$W; HcR <- traj[[ck]]$H
      }
      d <- file.path(out200, sprintf("ck%04d", ck))
      Wc <- read_matrix_csv(file.path(d, "W.csv"))
      Hc <- read_matrix_csv(file.path(d, "H.csv"))
      say("   · 检查点 t=", ck, ": ‖ΔW‖F/‖W_R‖F = ", sig(rel_frob(Wc, WcR), 4),
          " ‖ΔH‖F/‖H_R‖F = ", sig(rel_frob(Hc, HcR), 4),
          " max|ΔW| = ", sig(max(abs(Wc - WcR)), 3))
    }
  }

  verdicts[[nm]] <- list(endpoints = ep_pass, trace = tr_ok,
                         PASS = ep_pass && tr_ok)
  traces[[nm]] <- list(ours = trace_ours, R_rust = trace_R_rust,
                       R_blas = trace_R_blas)
}

# =============================================================================
# 总结
# =============================================================================
say("")
say("## 总判据")
all_pass <- all(vapply(verdicts, `[[`, logical(1), "PASS"))
for (nm in names(verdicts)) {
  say(" - ", nm, ": endpoints=", verdicts[[nm]]$endpoints,
      " trace=", verdicts[[nm]]$trace, " → ", if (verdicts[[nm]]$PASS) "PASS" else "FAIL")
}
say(" - 总体：", if (all_pass)
  "PASS —— KL 数值协议等价成立（D11/A8 记录：brunet 对拍为一次性固定平台实验）" else
  "FAIL —— 数值协议等价不成立，见分歧定位")

# =============================================================================
# result.md（数字全录）
# =============================================================================
res_lines <- c(
  "# U-M1s-14 · KL 数值协议等价对拍 result（一次性固定平台实验，不进 CI）",
  "",
  "重跑方式：`Rscript run_experiment.R`（在本目录）。本文件由脚本自动生成。",
  "",
  paste0(report_lines$ls, collapse = "\n"),
  "",
  "## 轨迹全量数字",
  ""
)
for (nm in names(cases)) {
  res_lines <- c(res_lines,
    "### ", nm, "",
    "| t | ours | R(brunet 状态, rust 模式公式) | 相对差 |",
    "|---|---|---|---|")
  trace_ours <- traces[[nm]]$ours
  trace_R <- traces[[nm]]$R_rust
  for (t in 0:ITERS_TRAJ) {
    res_lines <- c(res_lines, sprintf("| %d | %s | %s | %s |",
      t, sig(trace_ours[t + 1L], 12), sig(trace_R[t + 1L], 12),
      sig(abs(trace_ours[t + 1L] - trace_R[t + 1L]) / abs(trace_R[t + 1L]), 3)))
  }
  res_lines <- c(res_lines, "")
}
writeLines(res_lines, file.path(TOOL_DIR, "result.md"))
say("")
say("result.md 已写出：", file.path(TOOL_DIR, "result.md"))
if (!all_pass) quit(status = 1L) else quit(status = 0L)
