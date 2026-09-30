# ms_stratify_hypermutants: GMM hypermutant stratification (U-M1c-02).
#
# Upstream rule pinned to SigProfilerExtractor master cc6bf5ef (tag v1.5.0):
# cutoff = trunc(mean + 2*sd) of the majority-cluster-pruned sample totals
# (GaussianMixture(n_components=2) labels; population mean/sd; floor at
# 100 x channels), classification = total > cutoff. See
# docs/devlog/2026-09-30-GMM-stratify-memo.md (source line numbers there).
#
# This unit ships no FFI (the FFI shell is frozen for M1c), so the R side
# carries a protocol twin of the Rust kernel
# (src/rust/engine/src/stats.rs): identical EM, identical prune loop, and a
# bit-exact pure-R replication of the canonical MsRng stream (PCG64 +
# SplitMix64, 16-bit limbs on doubles -- every intermediate value stays
# below 2^53, so all limb arithmetic is exact). The KAT test pins this
# replication to the frozen rng.rs goldens. The twin retires to a reference
# implementation when the M2 pipeline wires the FFI.
#
# Policy divergence (ARCHITECTURE section 5, deliberate): upstream rescales
# flagged columns down to the cutoff ("normalization"); msuiter EXCLUDES
# the flagged samples from de novo extraction and refits them afterwards
# (M2). The returned object is the decision record both stages consume.

#' MsStratification: hypermutant stratification decision
#'
#' The decision record produced by [ms_stratify_hypermutants()]: the GMM
#' cutoff in mutations per sample, the per-sample totals, the hypermutant /
#' non-hypermutant sample lists and counts, the cutoff diagnostics, and the
#' pipeline policy this decision feeds. Violations raise
#' `msuiter_error_stratify`.
#'
#' @param cutoff single whole number: the cutoff (mutations per sample).
#' @param totals named numeric vector of per-sample mutation totals.
#' @param hyper character vector: sample ids with `total > cutoff` (the
#'   samples M2 excludes from de novo extraction).
#' @param nonhyper character vector: the remaining sample ids (the de novo
#'   extraction input).
#' @param n_hyper,n_nonhyper single whole numbers: group sizes.
#' @param gmm named list of cutoff diagnostics: `retained_mean`,
#'   `retained_sd`, `retained_n`, `n_fits`, `converged` (feeds the
#'   load-distribution / cutoff plot).
#' @param policy single string: the downstream pipeline semantics this
#'   decision feeds (`"exclude_de_novo_then_refit"`; upstream rescales
#'   instead -- declared divergence, memo section 1.4).
#' @param seed single whole number: the seed behind the GMM initialization.
#'
#' @export
MsStratification <- S7::new_class(
  "MsStratification",
  package = "msuiter",
  properties = list(
    cutoff = S7::new_property(S7::class_numeric),
    totals = S7::new_property(S7::class_numeric),
    hyper = S7::new_property(S7::class_character),
    nonhyper = S7::new_property(S7::class_character),
    n_hyper = S7::new_property(S7::class_numeric),
    n_nonhyper = S7::new_property(S7::class_numeric),
    gmm = S7::new_property(S7::class_list),
    policy = S7::new_property(S7::class_character),
    seed = S7::new_property(S7::class_numeric)
  ),
  validator = function(self) msuiter_validate_stratification(self)
)

msuiter_validate_stratification <- function(self) {
  msuiter_check_whole_number(self@cutoff, "cutoff", "stratify")
  msuiter_check_whole_number(self@seed, "seed", "stratify")

  totals <- self@totals
  if (!is.numeric(totals) || is.null(names(totals)) || anyNA(names(totals)) ||
      any(!nzchar(names(totals)))) {
    msuiter_abort(
      "stratify",
      "totals must be a named numeric vector of per-sample mutation totals",
      i = "sample names are the identity key for the two group lists",
      j = paste0("received: ", class(totals)[1L], " with names present: ",
        !is.null(names(totals))),
      c = "derive totals from an MsCatalog or pass named per-sample totals"
    )
  }
  if (length(totals) == 0L) {
    msuiter_abort(
      "stratify",
      "totals must contain at least one sample",
      i = "the cutoff rule is defined for non-empty cohorts",
      j = "received an empty vector",
      c = "check the catalog or totals vector"
    )
  }
  if (anyNA(totals) || any(!is.finite(totals)) || any(totals < 0)) {
    msuiter_abort(
      "stratify",
      "totals must be finite and non-negative",
      i = "totals are mutation counts",
      j = paste0("offending samples: ",
        msuiter_quote_trunc(names(totals)[is.na(totals) | !is.finite(totals) |
          totals < 0])),
      c = "fix the upstream tally output"
    )
  }

  if (!setequal(self@hyper, names(totals)[totals > self@cutoff]) ||
      !setequal(self@nonhyper, names(totals)[totals <= self@cutoff]) ||
      length(intersect(self@hyper, self@nonhyper)) != 0L) {
    msuiter_abort(
      "stratify",
      "hyper/nonhyper must partition the sample names by the strict cutoff",
      i = "classification is total > cutoff (upstream SigProfilerExtractor",
      j = paste0("n_hyper = ", self@n_hyper, ", n_nonhyper = ", self@n_nonhyper,
        ", n_samples = ", length(totals)),
      c = "build the object through ms_stratify_hypermutants()"
    )
  }
  msuiter_check_whole_number(self@n_hyper, "n_hyper", "stratify")
  msuiter_check_whole_number(self@n_nonhyper, "n_nonhyper", "stratify")
  if (self@n_hyper != length(self@hyper) ||
      self@n_nonhyper != length(self@nonhyper) ||
      self@n_hyper + self@n_nonhyper != length(totals)) {
    msuiter_abort(
      "stratify",
      "group counts must agree with the group lists and the totals",
      i = "counts are derived, not asserted",
      j = paste0("n_hyper = ", self@n_hyper, " vs ", length(self@hyper),
        "; n_nonhyper = ", self@n_nonhyper, " vs ", length(self@nonhyper)),
      c = "build the object through ms_stratify_hypermutants()"
    )
  }

  gmm <- self@gmm
  if (!is.list(gmm) || !setequal(names(gmm),
      c("retained_mean", "retained_sd", "retained_n", "n_fits", "converged"))) {
    msuiter_abort(
      "stratify",
      "gmm must be the cutoff diagnostics list (retained_mean, retained_sd, retained_n, n_fits, converged)",
      i = "the diagnostics feed the load-distribution and cutoff plots",
      j = paste0("received fields: ", msuiter_quote_trunc(names(gmm))),
      c = "build the object through ms_stratify_hypermutants()"
    )
  }
  if (!isTRUE(self@policy == "exclude_de_novo_then_refit")) {
    msuiter_abort(
      "stratify",
      "policy must be 'exclude_de_novo_then_refit'",
      i = "msuiter diverges from upstream rescaling on purpose (ARCHITECTURE section 5)",
      j = paste0("received: ", msuiter_quote_trunc(self@policy)),
      c = "build the object through ms_stratify_hypermutants()"
    )
  }
  NULL
}

# Shared whole-number check for stratification fields.
msuiter_check_whole_number <- function(x, what, topic) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) ||
      x < 0 || x != floor(x)) {
    msuiter_abort(
      topic,
      sprintf("%s must be a single non-negative whole number", what),
      i = "stratification fields are integer-valued by construction",
      j = paste0("received: ", msuiter_quote_trunc(x)),
      c = sprintf("pass %s as a whole number", what)
    )
  }
  NULL
}

# One-line print/format.
S7::method(format, MsStratification) <- function(x, ...) {
  line <- sprintf(
    "<MsStratification> GMM cutoff %d: %d/%d hypermutated",
    as.integer(x@cutoff), as.integer(x@n_hyper),
    as.integer(x@n_hyper + x@n_nonhyper)
  )
  if (x@policy == "exclude_de_novo_then_refit") {
    line <- paste0(
      line,
      "; excluded from de novo, refit pending (M2)"
    )
  }
  line
}

S7::method(print, MsStratification) <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}

# ---------------------------------------------------------------------------
# Pure-R replication of the canonical MsRng stream (PCG64 + SplitMix64).
#
# A 64-bit word is 4 limbs, a 128-bit word 8 limbs, of 16 bits each,
# little-endian, stored as doubles. Every intermediate value stays below
# 2^53 (limb products below 2^32, accumulated products below 2^35), so all
# arithmetic here is EXACT and bit-identical to the Rust kernel on any R
# build. The KAT test pins the frozen rng.rs goldens.
# ---------------------------------------------------------------------------

msuiter_pcg_layout_id <- c(0x5631, 0x4E47, 0x5552, 0x4D53) # "MSURNGV1"
msuiter_pcg_mult <- c(0xF645, 0x9FCC, 0xDF64, 0x4385, 0x5DA4, 0x1FC6, 0xED05, 0x2360)
msuiter_splitmix_gamma <- c(0x7C15, 0x7F4A, 0x79B9, 0x9E37) # golden ratio gamma
msuiter_mix_m1 <- c(0xE5B9, 0x1CE4, 0x476D, 0xBF58)
msuiter_mix_m2 <- c(0x11EB, 0x1331, 0x49BB, 0x94D0)

# Non-negative double (< 2^53) to a 4-limb 64-bit word.
msuiter_lim_u64 <- function(v) {
  c(
    v %% 65536,
    (v %/% 65536) %% 65536,
    (v %/% 4294967296) %% 65536,
    (v %/% 281474976710656) %% 65536
  )
}

msuiter_lim_add <- function(a, b) {
  nl <- length(a)
  out <- numeric(nl)
  carry <- 0
  for (i in seq_len(nl)) {
    v <- a[i] + b[i] + carry
    out[i] <- v %% 65536
    carry <- v %/% 65536
  }
  out # final carry dropped: mod 2^(16*nl)
}

msuiter_lim_mul <- function(a, b) {
  nl <- length(a)
  acc <- numeric(2 * nl)
  for (i in seq_len(nl)) {
    ai <- a[i]
    if (ai == 0) next
    for (j in seq_len(nl)) {
      acc[i + j - 1] <- acc[i + j - 1] + ai * b[j]
    }
  }
  out <- numeric(nl)
  carry <- 0
  for (k in seq_len(nl)) {
    v <- acc[k] + carry
    out[k] <- v %% 65536
    carry <- v %/% 65536
  }
  out # mod 2^(16*nl)
}

msuiter_lim_xor <- function(a, b) {
  as.numeric(bitwXor(as.integer(a), as.integer(b)))
}

msuiter_lim_or <- function(a, b) {
  as.numeric(bitwOr(as.integer(a), as.integer(b)))
}

msuiter_lim_shr <- function(a, s) {
  nl <- length(a)
  full <- as.integer(s %/% 16)
  rem <- s %% 16
  out <- numeric(nl)
  if (full >= nl) {
    return(out)
  }
  for (i in seq_len(nl - full)) {
    src <- i + full
    lo <- a[src] %/% 2^rem
    hi <- if (src < nl) (a[src + 1] %% 2^rem) * 2^(16 - rem) else 0
    out[i] <- lo + hi
  }
  out
}

msuiter_lim_shl <- function(a, s) {
  nl <- length(a)
  full <- as.integer(s %/% 16)
  rem <- s %% 16
  out <- numeric(nl)
  if (full >= nl) {
    return(out)
  }
  carry <- 0
  for (i in seq_len(nl - full)) {
    v <- a[i] * 2^rem + carry
    out[i + full] <- v %% 65536
    carry <- v %/% 65536
  }
  out
}

# SplitMix64 finalizer (rng.rs mix64).
msuiter_mix64 <- function(z) {
  x <- msuiter_lim_xor(z, msuiter_lim_shr(z, 30))
  x <- msuiter_lim_mul(x, msuiter_mix_m1)
  x <- msuiter_lim_xor(x, msuiter_lim_shr(x, 27))
  x <- msuiter_lim_mul(x, msuiter_mix_m2)
  msuiter_lim_xor(x, msuiter_lim_shr(x, 31))
}

# Canonical stream layout v1 (rng.rs from_stream): returns an ENVIRONMENT
# holding state + inc. R is pass-by-value for lists, so the generator must
# live in an environment for successive next_u64 calls to advance one
# shared state (the R mirror of the Rust `&mut MsRng`).
msuiter_pcg_from_stream <- function(master_seed, replicate = 0, rank = 0, fold = 0) {
  h <- msuiter_mix64(msuiter_pcg_layout_id)
  h <- msuiter_mix64(msuiter_lim_xor(h, msuiter_lim_u64(master_seed)))
  h <- msuiter_mix64(msuiter_lim_xor(h, msuiter_lim_u64(replicate)))
  h <- msuiter_mix64(msuiter_lim_xor(h, msuiter_lim_u64(rank)))
  h <- msuiter_mix64(msuiter_lim_xor(h, msuiter_lim_u64(fold)))

  sm1 <- msuiter_lim_add(h, msuiter_splitmix_gamma)
  initstate <- msuiter_mix64(sm1)
  sm2 <- msuiter_lim_add(sm1, msuiter_splitmix_gamma)
  initseq <- msuiter_mix64(sm2)

  # inc = (initseq << 1) | 1 as a 128-bit word: the shift must run on the
  # zero-extended word so the carry out of bit 63 lands in bit 64 (the
  # Rust kernel shifts in u128).
  inc <- msuiter_lim_shl(c(initseq, 0, 0, 0, 0), 1)
  inc[1] <- msuiter_lim_or(inc[1], 1) # odd -> distinct LCG subsequence

  state <- rep(0, 8) # pcg_basic seeding: two forced LCG steps
  state <- msuiter_lim_add(msuiter_lim_mul(state, msuiter_pcg_mult), inc)
  state <- msuiter_lim_add(state, c(initstate, 0, 0, 0, 0))
  state <- msuiter_lim_add(msuiter_lim_mul(state, msuiter_pcg_mult), inc)

  rng <- new.env(parent = emptyenv())
  rng$state <- state
  rng$inc <- inc
  rng
}

msuiter_pcg_lcg_step <- function(state, inc) {
  msuiter_lim_add(msuiter_lim_mul(state, msuiter_pcg_mult), inc)
}

msuiter_pcg_next_u64 <- function(rng) {
  rng$state <- msuiter_pcg_lcg_step(rng$state, rng$inc)
  st <- rng$state
  rot <- msuiter_lim_shr(st, 122)[1] # top 6 bits of the post-step state
  hi <- msuiter_lim_shr(st, 64)[1:4]
  lo <- st[1:4]
  xsl <- msuiter_lim_xor(hi, lo)
  if (rot == 0) {
    return(xsl)
  }
  msuiter_lim_or(msuiter_lim_shr(xsl, rot), msuiter_lim_shl(xsl, 64 - rot))
}

# Exact value of (64-bit word mod n) for small n: high-to-low limb fold;
# every intermediate stays below n * 2^16.
msuiter_lim_mod <- function(word, n) {
  r <- 0
  for (limb in rev(word)) {
    r <- (r * 65536 + limb) %% n
  }
  r
}

# First `n` words of a stream as hex strings (test/diagnostic helper).
msuiter_rng_words_hex <- function(master_seed, n, replicate = 0, rank = 0, fold = 0) {
  rng <- msuiter_pcg_from_stream(master_seed, replicate, rank, fold)
  vapply(seq_len(n), function(i) {
    w <- msuiter_pcg_next_u64(rng)
    paste(sprintf("%04x", rev(w)), collapse = "")
  }, character(1L))
}

# ---------------------------------------------------------------------------
# Protocol twin of engine::stats (same EM, same prune loop, same frozen
# constants; operation order mirrors the Rust code line by line).
# ---------------------------------------------------------------------------

msuiter_gmm_var_reg <- 1e-6
msuiter_gmm_tol <- 1e-8
msuiter_gmm_max_iter <- 200L

msuiter_log_normal_pdf <- function(x, mean, var) {
  -0.5 * (log(2 * pi) + log(var) + (x - mean) * (x - mean) / var)
}

# Sequential-order sums: mirror the Rust kernel's left-to-right f64
# reduction (R's sum()/mean() may accumulate in extended precision).
msuiter_seq_sum <- function(x) {
  s <- 0
  for (v in x) s <- s + v
  s
}

msuiter_population_mean_sd <- function(values) {
  n <- length(values)
  mean <- msuiter_seq_sum(values) / n
  var <- 0
  for (v in values) var <- var + (v - mean) * (v - mean)
  var <- var / n
  c(mean, sqrt(var))
}

# 1-D two-component EM, seeded via the MsRng stream. Mirrors
# stats::fit_gmm1d_with_rng (canonical components 1 = low, 2 = high).
msuiter_gmm_fit_1d <- function(x, rng, max_iter = msuiter_gmm_max_iter,
                               tol = msuiter_gmm_tol) {
  n <- length(x)
  ia <- as.integer(msuiter_lim_mod(msuiter_pcg_next_u64(rng), n)) + 1L
  ib <- 1L
  best <- -1
  for (j in seq_len(n)) {
    d <- abs(x[j] - x[ia])
    if (d > best) {
      best <- d
      ib <- j
    }
  }
  if (ib == ia) ib <- (ia %% n) + 1L
  lo <- min(x[ia], x[ib])
  hi <- max(x[ia], x[ib])
  pop_sd <- msuiter_population_mean_sd(x)[2]
  pop_var <- pop_sd * pop_sd + msuiter_gmm_var_reg
  means <- c(lo, hi)
  vars <- c(pop_var, pop_var)
  weights <- c(0.5, 0.5)

  resp <- numeric(n)
  prev_ll <- -Inf
  converged <- FALSE
  n_iter <- 0L
  for (it in seq_len(max_iter)) {
    ll_sum <- 0
    for (k in seq_len(n)) {
      l0 <- msuiter_log_normal_pdf(x[k], means[1], vars[1])
      l1 <- msuiter_log_normal_pdf(x[k], means[2], vars[2])
      top <- max(l0, l1)
      mix <- top + log(weights[1] * exp(l0 - top) + weights[2] * exp(l1 - top))
      ll_sum <- ll_sum + mix
      # Clamp into [0, 1] (mirror of stats.rs): rounding can push the raw
      # responsibility a few ulp past 1, and r1 = 1 - r0 < 0 would drive a
      # collapsed component's variance below zero (log(var) -> NaN).
      resp[k] <- min(1, max(0, weights[1] * exp(l0 - mix)))
    }
    ll <- ll_sum / n
    if (it > 1 && abs(ll - prev_ll) < tol) {
      converged <- TRUE
      n_iter <- it - 1L
      break
    }
    prev_ll <- ll

    r0_sum <- 0
    m0_num <- 0
    m1_num <- 0
    for (k in seq_len(n)) {
      r0 <- resp[k]
      r1 <- 1 - r0
      r0_sum <- r0_sum + r0
      m0_num <- m0_num + r0 * x[k]
      m1_num <- m1_num + r1 * x[k]
    }
    r1_sum <- n - r0_sum
    n0 <- if (r0_sum > 0) r0_sum else 1
    n1 <- if (r1_sum > 0) r1_sum else 1
    new_means <- c(
      if (r0_sum > 0) m0_num / n0 else means[1],
      if (r1_sum > 0) m1_num / n1 else means[2]
    )
    v0_num <- 0
    v1_num <- 0
    for (k in seq_len(n)) {
      r0 <- resp[k]
      v0_num <- v0_num + r0 * (x[k] - new_means[1]) * (x[k] - new_means[1])
      v1_num <- v1_num + (1 - r0) * (x[k] - new_means[2]) * (x[k] - new_means[2])
    }
    new_vars <- c(
      if (r0_sum > 0) v0_num / n0 + msuiter_gmm_var_reg else vars[1],
      if (r1_sum > 0) v1_num / n1 + msuiter_gmm_var_reg else vars[2]
    )
    means <- new_means
    vars <- new_vars
    weights <- c(r0_sum / n, r1_sum / n)
    n_iter <- it
  }

  labels <- integer(n)
  ll_sum <- 0
  for (k in seq_len(n)) {
    l0 <- msuiter_log_normal_pdf(x[k], means[1], vars[1])
    l1 <- msuiter_log_normal_pdf(x[k], means[2], vars[2])
    top <- max(l0, l1)
    mix <- top + log(weights[1] * exp(l0 - top) + weights[2] * exp(l1 - top))
    ll_sum <- ll_sum + mix
    labels[k] <- if (weights[1] * exp(l0 - mix) >= 0.5) 1L else 2L
  }
  mean_loglik <- ll_sum / n

  if (means[1] > means[2]) {
    means <- rev(means)
    vars <- rev(vars)
    weights <- rev(weights)
    labels <- 3L - labels
  }
  list(
    means = means, vars = vars, weights = weights, labels = labels,
    mean_loglik = mean_loglik, converged = converged, n_iter = n_iter
  )
}

# The frozen SigProfiler cutoff rule (memo section 1.3), protocol twin of
# stats::normalization_cutoff.
msuiter_normalization_cutoff <- function(totals, manual_cutoff, seed) {
  values <- as.numeric(totals)
  rng <- msuiter_pcg_from_stream(seed)
  n_fits <- 0L
  converged <- TRUE
  repeat {
    if (length(values) < 2) break
    fit <- tryCatch(
      msuiter_gmm_fit_1d(values, rng),
      error = function(e) NULL
    )
    if (is.null(fit)) {
      converged <- FALSE
      break
    }
    n_fits <- n_fits + 1L
    converged <- converged && isTRUE(fit$converged)
    c1 <- sum(fit$labels == 1L)
    c2 <- length(values) - c1
    if (c1 == 0L || c2 == 0L) break
    bigger <- if (c1 >= c2) 1L else 2L # first-max tie-break, ascending labels
    smaller <- 3L - bigger
    stat_big <- msuiter_subset_mean_sd(values, fit$labels, bigger)
    mean_small <- msuiter_subset_mean_sd(values, fit$labels, smaller)[1]
    if (abs(stat_big[1] - mean_small) < 4 * stat_big[2]) break
    values <- values[fit$labels == bigger]
  }
  stat <- msuiter_population_mean_sd(values)
  cutoff <- trunc(max(0, stat[1] + 2 * stat[2]))
  if (cutoff < manual_cutoff) cutoff <- manual_cutoff
  list(
    cutoff = cutoff,
    retained_n = length(values),
    retained_mean = stat[1],
    retained_sd = stat[2],
    n_fits = n_fits,
    converged = converged
  )
}

msuiter_subset_mean_sd <- function(values, labels, label) {
  keep <- which(labels == label)
  if (length(keep) == 0L) {
    return(c(0, 0))
  }
  msuiter_population_mean_sd(values[keep])
}

# ---------------------------------------------------------------------------
# User API
# ---------------------------------------------------------------------------

#' Stratify hypermutated samples with the SigProfiler GMM cutoff
#'
#' Applies the frozen SigProfilerExtractor hypermutant rule
#' (`docs/devlog/2026-09-30-GMM-stratify-memo.md`): a k = 2 Gaussian
#' mixture on the raw per-sample mutation totals (no log transform), an
#' iterative majority-cluster prune until the cluster means differ by less
#' than 4 standard deviations, then `cutoff = trunc(mean + 2 sd)` of the
#' retained bulk, floored at `manual_cutoff` (default 100 x channels,
#' matching the upstream call site). A sample is hypermutated iff its total
#' is strictly greater than the cutoff.
#'
#' msuiter's pipeline policy diverges deliberately from upstream's
#' rescaling: the flagged samples are **excluded from de novo extraction**
#' and refitted afterwards (M2; ARCHITECTURE section 5). This function
#' returns the decision record; the extraction pipeline consumes it.
#'
#' @param catalog an [MsCatalog] (totals are the catalog column sums) or a
#'   named numeric vector of per-sample mutation totals.
#' @param manual_cutoff single whole number: the floor applied to the
#'   derived cutoff. Defaults to `100 * nrow(counts)` for an [MsCatalog]
#'   (the upstream call-site convention; 9600 for SBS96) and to 0 for a
#'   totals vector.
#' @param seed single non-negative whole number seeding the GMM
#'   initialization stream (canonical MsRng layout; same input and seed
#'   give identical results).
#'
#' @return An [MsStratification] object.
#' @examples
#' labels <- paste0("CH", 1:3)
#' counts <- matrix(1:12, 3, 4, dimnames = list(labels, paste0("S", 1:4)))
#' counts[1, 4] <- 9500 # a hypermutated sample
#' cat1 <- ms_catalog(counts, list(name = "SYN3", labels = labels),
#'   colnames(counts), provenance = list(genome = "GRCh38"))
#' ms_stratify_hypermutants(cat1, seed = 1)
#' @export
ms_stratify_hypermutants <- function(catalog, manual_cutoff = NULL, seed = 1) {
  msuiter_check_whole_number(seed, "seed", "input")
  if (!is.null(manual_cutoff)) {
    msuiter_check_whole_number(manual_cutoff, "manual_cutoff", "input")
  }

  if (S7::S7_inherits(catalog, MsCatalog)) {
    counts <- catalog@counts
    if (ncol(counts) == 0L) {
      msuiter_abort(
        "input",
        "the catalog has no samples to stratify",
        i = "stratification needs at least one sample column",
        j = "received a channels x 0 catalog",
        c = "tally variants into the catalog first"
      )
    }
    # Integer-valued count columns: the column sums are exact in any
    # accumulation order, so colSums matches the kernel's sequential sums.
    totals <- colSums(counts)
    if (is.null(manual_cutoff)) manual_cutoff <- 100 * nrow(counts)
  } else if (is.numeric(catalog) && !is.null(names(catalog))) {
    totals <- catalog
    if (is.null(manual_cutoff)) manual_cutoff <- 0
  } else {
    msuiter_abort(
      "input",
      "catalog must be an MsCatalog or a named numeric vector of per-sample totals",
      i = "the stratifier consumes tallied catalogs (or bare totals for diagnostics)",
      j = paste0("received: ", class(catalog)[1L]),
      c = "tally variants with ms_tally() first, or pass named totals"
    )
  }

  # Upfront hygiene (before any computation; the S7 validator alone would
  # only fire at construction, after the twin has already run):
  # totals must be finite, non-negative, and uniquely named.
  if (anyNA(totals) || any(!is.finite(totals)) || any(totals < 0)) {
    msuiter_abort(
      "input",
      "totals must be finite and non-negative mutation counts",
      i = "the cutoff rule consumes raw per-sample totals",
      j = paste0("offending samples: ",
        msuiter_quote_trunc(names(totals)[is.na(totals) | !is.finite(totals) |
          totals < 0])),
      c = "fix the upstream tally output"
    )
  }
  if (anyDuplicated(names(totals)) != 0L || anyNA(names(totals)) ||
      any(!nzchar(names(totals)))) {
    msuiter_abort(
      "input",
      "totals must carry unique, non-empty sample names",
      i = "sample names are the identity key for the two group lists",
      j = paste0("n = ", length(totals), " totals, ",
        anyDuplicated(names(totals)), " duplicated"),
      c = "name each sample uniquely before stratifying"
    )
  }

  fit <- msuiter_normalization_cutoff(totals, manual_cutoff, seed)
  is_hyper <- totals > fit$cutoff
  hyper <- names(totals)[is_hyper]
  nonhyper <- names(totals)[!is_hyper]

  MsStratification(
    cutoff = fit$cutoff,
    totals = totals,
    hyper = hyper,
    nonhyper = nonhyper,
    n_hyper = as.numeric(length(hyper)),
    n_nonhyper = as.numeric(length(nonhyper)),
    gmm = list(
      retained_mean = fit$retained_mean,
      retained_sd = fit$retained_sd,
      retained_n = as.numeric(fit$retained_n),
      n_fits = as.numeric(fit$n_fits),
      converged = fit$converged
    ),
    policy = "exclude_de_novo_then_refit",
    seed = seed
  )
}
