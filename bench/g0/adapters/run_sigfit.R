#!/usr/bin/env Rscript
# G0 Tier-1 adapter: sigfit v2.2.0（kgori/sigfit，Gori & Baez-Ortega, bioRxiv 372896）
#
# 契约：adapter_protocol.md（2026-09-28 修订版）。counts.csv + catalog.csv + params.json 进，
# intervals.csv（absolute + raw 两 estimand）+ manifest.json + errors.log 出。
#
# ── W1/D2 对账结论（已按 g0-sigfit:2.2.0 容器内实测核对，详见协议 §5）──
# 1) 正确入口是 fit_signatures()（fit_signatures_counts 不存在于 2.2.0）；
#    counts 行 = 样本，signatures 须传 t(catalog)（行 = 签名）。
# 2) fit_signatures 的 seed/chains/iter/warmup 经 ... 透传 rstan::sampling；
#    未提供时用包默认 chains=4 / iter=2000 / warmup=1000。
# 3) retrieve_pars(mcmc, par="exposures", hpd_prob=0.95) —— hpd_prob（不是
#    sig_level/CI/hpd/threshold.lower）；返回 mean/lower_95/upper_95（样本 × 签名）。
# 4) 2.2.0 **没有内建清零参数**（无 threshold.lower）：清零规则是 harness 的
#    后处理，本 runner 只输出 zeroed 标志（absolute 区间 lower<0.01 ⇒ 标志 1）。
# 5) **关键陷阱**：multinomial 模型下 exposures 是占比（每样本和 ≈ 1），
#    绝对 counts = 占比 × 该样本突变总数。本 runner 落盘前做占比和=1 与
#    还原后总数守恒两条断言（覆盖判定以 absolute estimand 为准）。
# ─────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages(library(sigfit))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  i <- match(flag, args)
  if (is.na(i)) stop(paste("missing arg:", flag))
  return(args[i + 1])
}

fail <- function(msg) {
  # 注意：writeLines 无 append 参数——追加写必须用 cat（旧 run_stl.R 的写法）
  cat(paste0(format(Sys.time()), " FATAL [run_sigfit]: ", msg, "\n"),
      file = err_log, append = TRUE, sep = "")
  quit(save = "no", status = 1)
}

counts_path  <- get_arg("--counts")
catalog_path <- get_arg("--catalog")
params_path  <- get_arg("--params")
outdir       <- get_arg("--outdir")
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

# errors.log 先行落盘（协议 §2.1：run_grid 缓存守卫要求 out/ 必有 errors.log；
# 先清掉上次可能残留的半截输出，失败路径绝不留 intervals.csv）
err_log <- file.path(outdir, "errors.log")
unlink(file.path(outdir, "intervals.csv"))
unlink(file.path(outdir, "manifest.json"))
writeLines(character(0), err_log)

tryCatch({

params <- jsonlite::fromJSON(params_path)
seed   <- as.integer(params$seed)
if (is.na(seed)) fail("params.seed missing or not an integer")

# ---- 读入 + 显式数值防御（非数值列拒绝） ----
read_matrix_csv <- function(path) {
  df <- read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
  if (ncol(df) < 2) fail(paste0(path, ": need >= 2 columns (id + data)"))
  ids <- trimws(as.character(df[[1]]))
  if (any(!nzchar(ids)) || anyNA(ids)) fail(paste0(path, ": empty id in first column"))
  if (anyDuplicated(ids)) fail(paste0(path, ": duplicated ids in first column"))
  dat <- df[, -1, drop = FALSE]
  for (cn in colnames(dat)) {
    if (!is.numeric(dat[[cn]])) {
      fail(paste0(path, ": column '", cn, "' is not numeric — non-numeric columns are rejected"))
    }
  }
  m <- as.matrix(dat); rownames(m) <- ids
  if (any(!is.finite(m))) fail(paste0(path, ": non-finite values (NA/NaN/Inf) not allowed"))
  m
}
counts  <- read_matrix_csv(counts_path)    # 行 = sample_id, 列 = 96 通道
catalog <- read_matrix_csv(catalog_path)   # 行 = channel（96）, 列 = 签名

stopifnot(ncol(counts) == 96, nrow(catalog) == 96)
if (!identical(colnames(counts), rownames(catalog))) {
  fail("channel labels of counts.csv and catalog.csv differ (order-sensitive)")
}
if (any(counts < 0)) fail("counts.csv: negative counts not allowed")
if (any(catalog < 0)) fail("catalog.csv: negative entries not allowed")
if (any(colSums(catalog) <= 0)) fail("catalog.csv: signature column with zero mass")
catalog <- sweep(catalog, 2, colSums(catalog), "/")   # 各列归一（防御）

# 0 突变样本：工具会拒绝 → 不进拟合，按协议写 NaN 行（不中断整批）
totals <- rowSums(counts)
fit_rows <- names(totals[totals > 0])
skip_rows <- names(totals[totals == 0])
if (length(fit_rows) == 0) fail("all samples have zero mutations — nothing to fit")
counts_fit <- counts[fit_rows, , drop = FALSE]

# ---- Tier-1 fit：包默认参数；params 可选 chains/iter/warmup 短链（smoke 用） ----
extra <- list()
if (!is.null(params$chains)) extra$chains <- as.integer(params$chains)
if (!is.null(params$iter))   extra$iter   <- as.integer(params$iter)
if (!is.null(params$warmup)) extra$warmup <- as.integer(params$warmup)
fit <- do.call(sigfit::fit_signatures,
               c(list(counts = counts_fit, signatures = t(catalog),
                      model = "multinomial", seed = seed), extra))

# ---- 后验提取：hpd_prob=0.95 → mean/lower_95/upper_95（样本 × 签名，占比） ----
pars <- sigfit::retrieve_pars(fit, par = "exposures", hpd_prob = 0.95)
stopifnot(all(c("mean", "lower_95", "upper_95") %in% names(pars)))

# 断言 1（占比口径）：每样本 exposures 占比和 ≈ 1
if (max(abs(rowSums(pars$mean) - 1)) > 1e-6) {
  fail("posterior exposure fractions do not sum to 1 per sample (multinomial assumption broken)")
}
# 断言 2（还原守恒）：占比 × 样本突变总数 = 绝对 counts，逐样本和还原回总数
totals_fit <- totals[fit_rows]
mu_abs <- sweep(pars$mean,     1, totals_fit, "*")
lo_abs <- sweep(pars$lower_95, 1, totals_fit, "*")
hi_abs <- sweep(pars$upper_95, 1, totals_fit, "*")
if (max(abs(rowSums(mu_abs) - totals_fit)) > 1e-6 * max(totals_fit)) {
  fail("absolute-count restoration failed: row sums of fraction*total != sample totals")
}

samples   <- rownames(mu_abs)
sig_names <- colnames(mu_abs)

rows <- list(); k <- 1
for (s in samples) {
  for (j in seq_along(sig_names)) {
    sg <- sig_names[j]
    # 无内建清零参数（2.2.0）：清零由 harness 按 zeroed 标志做后处理，
    # runner 只如实打标志（协议 absolute 区间 lower<0.01 ⇒ zeroed=1）
    zeroed <- if (lo_abs[s, j] < 0.01) 1 else 0
    rows[[k]] <- data.frame(sample_id = s, signature = sg,
                            estimate = mu_abs[s, j], lo95 = lo_abs[s, j], hi95 = hi_abs[s, j],
                            estimand = "absolute", zeroed = zeroed); k <- k + 1
    # raw = 未清零后验区间；2.2.0 无内建清零 ⇒ 数值与 absolute 相同，
    # 保留两行固定 schema 并与未来有内建清零的版本区分（协议 §2）
    rows[[k]] <- data.frame(sample_id = s, signature = sg,
                            estimate = mu_abs[s, j], lo95 = lo_abs[s, j], hi95 = hi_abs[s, j],
                            estimand = "raw", zeroed = 0); k <- k + 1
  }
}
for (s in skip_rows) {   # 被拒样本：NaN 行（协议 §2 guardline 口径）
  for (sg in colnames(catalog)) {
    rows[[k]] <- data.frame(sample_id = s, signature = sg, estimate = NaN, lo95 = NaN, hi95 = NaN,
                            estimand = "absolute", zeroed = 0); k <- k + 1
  }
    cat(paste0(format(Sys.time()), " sample '", s, "' rejected: zero total mutations (NaN rows written)\n"),
        file = err_log, append = TRUE, sep = "")
}
out <- do.call(rbind, rows)
write.csv(out, file.path(outdir, "intervals.csv"), row.names = FALSE)

# ---- manifest：版本必须可溯源（tag + commit SHA；"2.2" 级别的版本号不够） ----
pd  <- utils::packageDescription("sigfit")
tag <- if (!is.null(pd$GithubRef)) pd$GithubRef else "v2.2.0"
sha <- if (!is.null(pd$RemoteSha)) pd$RemoteSha else "unknown"
ch  <- if (!is.null(extra$chains)) extra$chains else 4L     # rstan::sampling 默认
it  <- if (!is.null(extra$iter))   extra$iter   else 2000L
wu  <- if (!is.null(extra$warmup)) extra$warmup else 1000L
writeLines(jsonlite::toJSON(list(
  tool = "sigfit", version_tag = tag, version_r = as.character(utils::packageVersion("sigfit")),
  commit = sha, seed = seed, model = "multinomial", hpd_prob = 0.95,
  chains = ch, iter = it, warmup = wu,
  counts_restoration = "absolute = exposure_fraction * sample_total (multinomial)",
  zero_rule = "no built-in zeroing in 2.2.0; runner flags lower<0.01 -> zeroed=1, harness post-processes"
), auto_unbox = TRUE), file.path(outdir, "manifest.json"))

}, error = function(e) fail(paste0("run_sigfit failed: ", conditionMessage(e))))
quit(save = "no", status = 0)
