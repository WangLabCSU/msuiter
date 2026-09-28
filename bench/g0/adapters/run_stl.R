#!/usr/bin/env Rscript
# G0 Tier-1 adapter: signature.tools.lib v2.5.2（Nik-Zainal-Group）
#
# 契约：adapter_protocol.md。Tier-1 口径：FitMS 默认 + nboot=200（冻结），
# STL 默认 exposure 过滤（fixedThreshold 5% / Gini）照用；被过滤为 0 的
# 签名记为区间塌缩到 0（zeroed=1）。
#
# ── W1/D2 API 对账清单（首次容器 smoke 时逐条核对实际包版本）──
# 1) FitMS() 的实参名（signature/counts/method/nboot/parallelisation）
# 2) bootstrap 百分位区间的返回对象字段名（此处按
#    res$exposures.bootstrap.confidence.intervals 假定，vignette 核对）
# 3) fixedThreshold/Gini 过滤后的 exposure 与阈值字段名（res$exposures /
#    res$thresholds 假定）
# 4) W1 兼容性检查：STL 仅支持器官 RefSig 目录（audit [V]）——正式跑前
#    须验证 Breast RefSig T1 含全部 5 个真值签名；缺失则换器官或按协议
#    §3 报告交集子集并注明目录差异
# ─────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages(library(signature.tools.lib))
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
nboot  <- as.integer(ifelse(is.null(params$nboot), 200, params$nboot))  # 冻结值

set.seed(seed)   # bootstrap 全部随机性由 G0 派生种子驱动（可复现纪律）

# errors.log 先行落盘（P2c，与 run_sigfit.R 的契约对齐）：run_grid 的缓存
# 跳过守卫要求 out/ 必有 errors.log——若只在成功路径末尾写，容器一旦
# 中途报错就永远无法命中缓存守卫，cell 会被无限重跑。失败信息也追加进
# 该文件（部署行为即证据，协议 §2.1）。
err_log <- file.path(outdir, "errors.log")
writeLines(character(0), err_log)

read_matrix_csv <- function(path) {
  m <- read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
  rownames(m) <- m[[1]]
  as.matrix(m[, -1, drop = FALSE])
}
counts_t  <- read_matrix_csv(counts_path)    # 行 = sample_id, 列 = 96 通道
catalog   <- read_matrix_csv(catalog_path)   # 行 = channel（96）, 列 = 签名

stopifnot(nrow(catalog) == 96, ncol(counts_t) == 96)
catalog <- sweep(catalog, 2, colSums(catalog), "/")

# STL 的 FitMS：counts 行 = 样本；逐样本 fit（此处逐个调用以取全 bootstrap 区间）
res <- tryCatch(
  signature.tools.lib::FitMS(
    signature       = catalog,
    counts          = counts_t,
    method          = "backtracking",
    parallelisation = 1,
    nboot           = nboot
  ),
  error = function(e) {
    cat(conditionMessage(e), "\n", file = err_log, append = TRUE)
    stop(e)
  })

exposures <- res$exposures                                  # 签名 × 样本
cis       <- res$exposures.bootstrap.confidence.intervals   # [lower/upper, 签名, 样本]（对账 #2）
sig_names <- rownames(exposures)
samples   <- colnames(exposures)

rows <- list()
k <- 1
for (s in samples) {
  for (j in seq_along(sig_names)) {
    sg <- sig_names[j]
    est <- exposures[j, s]
    lo <- cis[1, j, s]; hi <- cis[2, j, s]
    # 默认过滤（fixedThreshold 5% / Gini）后 exposure 为 0 ⇒ 区间塌缩到 0
    if ((!is.finite(est)) || est == 0) { lo <- 0; hi <- 0 }
    zeroed <- if ((!is.finite(est)) || est == 0) 1 else 0
    rows[[k]] <- data.frame(sample_id = s, signature = sg,
                            estimate = ifelse(is.finite(est), est, NA),
                            lo95 = lo, hi95 = hi,
                            estimand = "absolute", zeroed = zeroed)
    k <- k + 1
  }
}
out <- do.call(rbind, rows)
write.csv(out, file.path(outdir, "intervals.csv"), row.names = FALSE)

writeLines(jsonlite::toJSON(list(
  tool = "signature.tools.lib", version = "2.5.2", seed = seed,
  nboot = nboot, method = "backtracking",
  filter = "fixedThreshold 5% / Gini (package default)"
)), file.path(outdir, "manifest.json"))
