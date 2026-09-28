#!/usr/bin/env Rscript
# G0 Tier-1 adapter: sigfit v2.2.0（kgori/sigfit，Gori & Baez-Ortega, bioRxiv 372896）
#
# 契约：adapter_protocol.md。counts.csv + catalog.csv + params.json 进，
# intervals.csv（absolute 主 estimand + raw 对照列）出。
# Tier-1 口径：**一律包默认参数**（似然族默认、4 链 HMC 默认、
# adapt_delta 默认）+ **默认 CI 清零规则照用**（95% 区间下界 < 0.01 ⇒ 0，
# Medo 2024 证实其有益，是部署行为的一部分）。raw（未清零）另报一列。
#
# ── W1/D2 API 对账清单（首次容器 smoke 时逐条核对实际包版本）──
# 1) fit_signatures_counts() 的实参名（counts/signatures/model/seed/chains/iter）
# 2) retrieve_pars() 的 hpd / sig_level / threshold.lower 实参名与
#    threshold.lower=0.01 是否即"下界<0.01 置零"的默认清零开关
# 3) raw 提取：threshold.lower=NULL（或 0）重取一遍
# 4) 4 链 HMC 默认 iter/chains 值记入 out/manifest.json（协议 §2.3 要求落盘）
# ─────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages(library(sigfit))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  i <- match(flag, args)
  if (is.na(i)) stop(paste("missing arg:", flag))
  return(args[i + 1])
}
counts_path  <- get_arg("--counts")
catalog_path <- get_arg("--catalog")
params_path  <- get_arg("--params")
outdir       <- get_arg("--outdir")
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

params <- jsonlite::fromJSON(params_path)
seed   <- as.integer(params$seed)

# ---- 读入 ----
read_matrix_csv <- function(path) {
  m <- read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
  rownames(m) <- m[[1]]
  as.matrix(m[, -1, drop = FALSE])
}
counts  <- read_matrix_csv(counts_path)    # 行 = sample_id, 列 = 96 通道
catalog <- read_matrix_csv(catalog_path)   # 行 = channel（96）, 列 = 签名

stopifnot(nrow(catalog) == 96)
stopifnot(ncol(counts) == 96)
catalog <- sweep(catalog, 2, colSums(catalog), "/")   # 各列归一（防御）

# ---- Tier-1 fit：包默认参数 ----
fit <- sigfit::fit_signatures_counts(
  counts     = counts,
  signatures = catalog,
  model      = "multinomial",   # 协议 §2.2 主生成模型对应的似然族默认
  seed       = seed
)

# 用户可见区间（默认清零：95% 下界 < 0.01 ⇒ 0）与 raw（未清零）
pars_user <- sigfit::retrieve_pars(fit, par = "exposures",
                                   sig_level = 0.95, CI = TRUE, hpd = TRUE,
                                   threshold.lower = 0.01)
pars_raw  <- sigfit::retrieve_pars(fit, par = "exposures",
                                   sig_level = 0.95, CI = TRUE, hpd = TRUE,
                                   threshold.lower = NULL)

get_exp  <- function(p) p$exposures            # 点估计矩阵（签名 × 样本）
get_ci   <- function(p) p$exposures_ci         # 3 维数组：lower/upper × 签名 × 样本

exp_user <- get_exp(pars_user);  ci_user <- get_ci(pars_user)
exp_raw  <- get_exp(pars_raw);   ci_raw  <- get_ci(pars_raw)

sig_names <- rownames(exp_user)
samples   <- colnames(exp_user)

rows <- list()
k <- 1
for (s in samples) {
  for (j in seq_along(sig_names)) {
    sg <- sig_names[j]
    lo_u <- ci_user[1, j, s]; hi_u <- ci_user[2, j, s]
    lo_r <- ci_raw[1, j, s];  hi_r <- ci_raw[2, j, s]
    zeroed <- if (is.finite(exp_raw[j, s]) && exp_raw[j, s] > 0 &&
                  (!is.finite(exp_user[j, s]) || exp_user[j, s] == 0)) 1 else 0
    rows[[k]] <- data.frame(sample_id = s, signature = sg,
                            estimate = exp_user[j, s], lo95 = lo_u, hi95 = hi_u,
                            estimand = "absolute", zeroed = zeroed); k <- k + 1
    rows[[k]] <- data.frame(sample_id = s, signature = sg,
                            estimate = exp_raw[j, s], lo95 = lo_r, hi95 = hi_r,
                            estimand = "raw", zeroed = 0); k <- k + 1
  }
}
out <- do.call(rbind, rows)
write.csv(out, file.path(outdir, "intervals.csv"), row.names = FALSE)

writeLines(jsonlite::toJSON(list(
  tool = "sigfit", version = "2.2.0", seed = seed,
  likelihood = "multinomial", hpd_level = 0.95,
  zero_rule = "lower<0.01 -> 0 (package default)",
  chains = "package default", iter = "package default",
  note = "chains/iter 默认值核对后写入实际数字（W1/D2 对账清单 #4）"
)), file.path(outdir, "manifest.json"))

err_log <- file.path(outdir, "errors.log")
if (!file.exists(err_log)) writeLines(character(0), err_log)
