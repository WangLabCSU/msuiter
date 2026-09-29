#!/usr/bin/env Rscript
# G0 Tier-1 adapter: signature.tools.lib v2.5.2（Nik-Zainal-Group）
#
# 契约：adapter_protocol.md（2026-09-28 修订版）。Tier-1 口径：FitMS 包默认
# （KLD / fixedThreshold 5%）+ useBootstrap=TRUE + nboot=params$nboot（正式冻结 200）。
#
# ── W1/D2 对账结论（按 STL v2.5.2 源码逐条核对，详见协议 §5）──
# 1) FitMS 实参名：catalogues=（样本为**列**，通道为行）、commonSignatures=、
#    rareSignatures=、useBootstrap=、nboot=、nparallel=、randomSeed=。
#    （旧代码的 signature/counts/method/nboot/parallelisation 全部不存在。）
# 2) W1 裁决：正式实验 STL 侧**不走 organ T1**（Breast RefSig T1 不含 SBS40
#    等真值签名）；统一走 commonSignatures=<拟合目录> 路径（正式 = 冻结
#    v3.6 目录文件，经 G0_CATALOG_PATH 由 harness 挂成 catalog.csv）。
#    rareSignatures= 置空 + maxRareSigsPerSample=0 ⇒ 退化为全目录 common
#    拟合（FitMS 文档明确该用法），不做稀有签名搜索——目录即部署口径。
# 3) **通道序陷阱**：STL 要求其经典序（C>A,C>G,C>T,T>A,T>C,T>G 外层 ×
#    5' A/C/G/T × 3' A/C/G/T；getTypeOfMutationsFromChannels 的 SBSchannels），
#    与仓库锚 tools/channel-reference/SBS96.txt 的字典序**不同**。输入须
#    重排进（catalog 与 counts 同步重排；暴露量结果无通道维，无须重排回）。
#    重排后用包自带的 :::getTypeOfMutationsFromChannels 断言 "subs"。
# 4) 返回结构：res$exposures = 样本(行) × 签名(列)（**含 "unassigned" 列，
#    丢弃**；全零签名列被包丢弃 ⇒ 须映射回全目录列，缺席签名如实报
#    [0,0] 区间）；bootstrap 区间从逐样本 res$bootstrap_exposures_samples
#    [[样本]]（签名 × nboot，未过滤 bootstrap 拟合）自算 2.5/97.5 百分位。
#    被包过滤（est==0）的签名：区间塌缩为 [0,0]，zeroed=1。
# ─────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages(library(signature.tools.lib))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  i <- match(flag, args)
  if (is.na(i)) stop(paste("missing arg:", flag))
  return(args[i + 1])
}

fail <- function(msg) {
  # 注意：writeLines 无 append 参数——追加写必须用 cat
  cat(paste0(format(Sys.time()), " FATAL [run_stl]: ", msg, "\n"),
      file = err_log, append = TRUE, sep = "")
  quit(save = "no", status = 1)
}

counts_path  <- get_arg("--counts")
catalog_path <- get_arg("--catalog")
params_path  <- get_arg("--params")
outdir       <- get_arg("--outdir")
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

# errors.log 先行落盘（run_grid 缓存守卫要求 out/ 必有 errors.log；失败信息
# 追加写入——部署行为即证据，协议 §2.1）。先清残留半截输出。
err_log <- file.path(outdir, "errors.log")
unlink(file.path(outdir, "intervals.csv"))
unlink(file.path(outdir, "manifest.json"))
writeLines(character(0), err_log)

tryCatch({

params <- jsonlite::fromJSON(params_path)
seed   <- as.integer(params$seed)
if (is.na(seed)) fail("params.seed missing or not an integer")
nboot  <- as.integer(ifelse(is.null(params$nboot), 200, params$nboot))  # 正式冻结值

# ---- STL 经典 96 通道序（substitution 外层 × 5' × 3'，与包源码 SBSchannels 一致） ----
stl_channels <- local({
  subs  <- c("C>A", "C>G", "C>T", "T>A", "T>C", "T>G")
  bases <- c("A", "C", "G", "T")
  unlist(lapply(subs, function(s) {
    g <- expand.grid(b3 = bases, b5 = bases, stringsAsFactors = FALSE)  # b3 变化最快
    paste0(g$b5, "[", s, "]", g$b3)
  }))
})
stopifnot(length(stl_channels) == 96)

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
counts  <- read_matrix_csv(counts_path)    # 行 = sample_id, 列 = 96 通道（仓库锚序）
catalog <- read_matrix_csv(catalog_path)   # 行 = channel（96）, 列 = 签名（仓库锚序）

stopifnot(ncol(counts) == 96, nrow(catalog) == 96)
if (!identical(colnames(counts), rownames(catalog))) {
  fail("channel labels of counts.csv and catalog.csv differ (order-sensitive)")
}
if (!setequal(colnames(counts), stl_channels)) {
  fail("channel labels do not cover the STL SBS96 classic set")
}
if (any(counts < 0)) fail("counts.csv: negative counts not allowed")
if (any(catalog < 0)) fail("catalog.csv: negative entries not allowed")
if (any(colSums(catalog) <= 0)) fail("catalog.csv: signature column with zero mass")
catalog <- sweep(catalog, 2, colSums(catalog), "/")   # 各列归一（防御）

# 仓库锚序 → STL 经典序（catalog 与 counts 同步重排；Fit 的矩阵乘按位置对齐）
counts_stl <- t(counts)[stl_channels, , drop = FALSE]       # 通道(行) × 样本(列)
cat_stl    <- catalog[stl_channels, , drop = FALSE]         # 通道(行) × 签名(列)
# 用包自带校验器断言通道序（非 "subs" 则 organ/类型识别全错）
if (!identical(signature.tools.lib:::getTypeOfMutationsFromChannels(counts_stl), "subs")) {
  fail("channel reorder to STL classic order failed getTypeOfMutationsFromChannels check")
}

# 0 突变样本：STL 会给全 0 拟合 → 不进拟合，按协议写 NaN 行（不中断整批）
totals <- colSums(counts_stl)
fit_cols <- names(totals[totals > 0])
skip_cols <- names(totals[totals == 0])
if (length(fit_cols) == 0) fail("all samples have zero mutations — nothing to fit")

# ---- Tier-1 fit：FitMS 包默认 + bootstrap（不开 bootstrap 区间会静默缺失） ----
res <- signature.tools.lib::FitMS(
  catalogues        = counts_stl[, fit_cols, drop = FALSE],
  commonSignatures  = cat_stl,                    # W1 裁决：全目录喂 commonSignatures
  rareSignatures    = cat_stl[, integer(0)],      # 置空 ⇒ 无稀有签名搜索
  maxRareSigsPerSample = 0,                       # 0 = 只做 common 拟合（包文档口径）
  method            = "KLD",                      # 包默认
  exposureFilterType = "fixedThreshold",           # 包默认（threshold_percent=5）
  useBootstrap      = TRUE,
  nboot             = nboot,
  nparallel         = 1,
  randomSeed        = seed,
  verbose           = FALSE)

if (is.null(res)) {   # FitMS 的错误路径是静默 return(NULL)（源码口径），须显式拦截
  fail("FitMS returned NULL (see FitMS '[error]' message on stdout) — catalogue/channel shape rejected")
}

# ---- 提取：exposures（样本 × 签名 + "unassigned" 列，丢弃之） ----
exps <- res$exposures
if (!"unassigned" %in% colnames(exps)) fail("FitMS result lacks expected 'unassigned' column")
exps <- exps[, setdiff(colnames(exps), "unassigned"), drop = FALSE]
samples    <- rownames(exps)
sig_names  <- colnames(catalog)                   # 全目录列（含被包丢掉的缺席签名）
boot_by_sample <- res$bootstrap_exposures_samples # 逐样本：签名 × nboot
if (is.null(boot_by_sample)) fail("bootstrap_exposures_samples missing — was useBootstrap=TRUE set?")

rows <- list(); k <- 1
for (s in samples) {
  bm <- boot_by_sample[[s]]
  if (is.null(bm)) fail(paste0("no bootstrap matrix for sample '", s, "'"))
  for (sg in sig_names) {
    est <- if (sg %in% colnames(exps)) exps[s, sg] else 0   # 缺席签名 ⇒ 0
    if (!is.finite(est)) {  # guardline：非有限估计 → NaN 行如实落盘
      rows[[k]] <- data.frame(sample_id = s, signature = sg, estimate = NaN,
                              lo95 = NaN, hi95 = NaN, estimand = "absolute", zeroed = 1); k <- k + 1
      writeLines(paste0(format(Sys.time()), " sample '", s, "' signature '", sg,
                        "': non-finite exposure, NaN row written"), err_log)
      next
    }
    zeroed <- (est == 0)
    if (zeroed) {           # 包过滤（fixedThreshold 5%）⇒ 区间塌缩 [0,0]
      lo <- 0; hi <- 0
    } else {
      if (!sg %in% rownames(bm)) fail(paste0("bootstrap matrix for '", s, "' lacks signature '", sg, "'"))
      b  <- as.numeric(bm[sg, ])
      qq <- stats::quantile(b, probs = c(0.025, 0.975), names = FALSE, na.rm = TRUE)
      lo <- qq[1]; hi <- qq[2]
    }
    rows[[k]] <- data.frame(sample_id = s, signature = sg,
                            estimate = est, lo95 = lo, hi95 = hi,
                            estimand = "absolute", zeroed = as.integer(zeroed)); k <- k + 1
  }
}
for (s in skip_cols) {   # 被拒样本（0 突变）：NaN 行
  for (sg in sig_names) {
    rows[[k]] <- data.frame(sample_id = s, signature = sg, estimate = NaN, lo95 = NaN, hi95 = NaN,
                            estimand = "absolute", zeroed = 0); k <- k + 1
  }
  cat(paste0(format(Sys.time()), " sample '", s, "' rejected: zero total mutations (NaN rows written)\n"),
      file = err_log, append = TRUE, sep = "")
}
out <- do.call(rbind, rows)
write.csv(out, file.path(outdir, "intervals.csv"), row.names = FALSE)

# ---- manifest：tag + commit SHA（build 阶段固化在 /usr/local/share/g0） ----
info <- list(version_tag = "v2.5.2", commit = "unknown")
bi <- "/usr/local/share/g0/build_info.json"
if (file.exists(bi)) {
  j <- jsonlite::fromJSON(bi)
  info$version_tag <- j$tag; info$commit <- j$commit
}
writeLines(jsonlite::toJSON(list(
  tool = "signature.tools.lib", version_tag = info$version_tag,
  version_r = as.character(utils::packageVersion("signature.tools.lib")),
  commit = info$commit, seed = seed, nboot = nboot, method = "KLD",
  nparallel = 1, useBootstrap = TRUE, maxRareSigsPerSample = 0,
  filter = "fixedThreshold 5% (package default); filtered -> [0,0] interval, zeroed=1",
  catalog_mode = "commonSignatures=<catalog.csv> (W1: no organ T1); rare search disabled",
  interval_source = "2.5/97.5 percentiles of bootstrap_exposures_samples (signatures x nboot)",
  channel_order = "input repo-anchor SBS96.txt order -> reordered to STL classic (COSMIC) order in, exposures have no channel dim"
), auto_unbox = TRUE), file.path(outdir, "manifest.json"))

}, error = function(e) fail(paste0("run_stl failed: ", conditionMessage(e))))
quit(save = "no", status = 0)
