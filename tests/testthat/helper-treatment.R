# Shared fixtures for the treatment-forensics face (ms_treatment_report)
# and its case-study law units. Synthetic-only (D3): planted activities are
# hand-set numbers, the dictionary columns are the sealed bundled refdb
# served at runtime through the exported ms_refdb_bundled() face.

.ms_trt_labels <- function() msuiter:::.ms_io_channel_tables()$SBS96

# The governed default map (pinned verbatim by test-treatment-report.R).
.MS_TRT_MAP <- list(
  temozolomide = "SBS11",
  platinum = c("SBS31", "SBS35"),
  thiopurine = "SBS32"
)

# One synthetic 17-sample cohort: five unexposed (U) plus four exposed per
# treatment (T: temozolomide, P: platinum, H: thiopurine). Each treatment
# plants one strong activity on its governed signature(s); every signature
# carries an equal low baseline everywhere, so the a-priori truth is: the
# planted (treatment, signature) cells associate, no other cell does.
.ms_trt_cohort <- function(seed = 301L, baseline = 20, planted = 600) {
  dict_names <- sort(unique(unlist(.MS_TRT_MAP, use.names = FALSE)))
  refdb <- ms_refdb_bundled(build = "GRCh37")
  mat <- refdb$SBS_GRCh37@matrices[[1]]
  dict <- mat[, dict_names, drop = FALSE]

  group_of <- rep(c("U", "T", "P", "H"), times = c(5L, 4L, 4L, 4L))
  samples <- paste0(group_of, sequence(c(5L, 4L, 4L, 4L)))
  n <- length(samples)
  group_to_trt <- c(T = "temozolomide", P = "platinum", H = "thiopurine")

  act <- matrix(baseline, nrow = length(dict_names), ncol = n,
                dimnames = list(dict_names, samples))
  for (grp in c("T", "P", "H")) {
    sigs <- .MS_TRT_MAP[[group_to_trt[[grp]]]]
    act[sigs, group_of == grp] <- planted
  }

  set.seed(seed)
  act <- act * matrix(runif(length(act), 0.85, 1.15), nrow = nrow(act))
  catalog <- ms_simulate(dict, act, arm = "multinomial", burden = 1000,
                         seed = seed)
  treatments <- data.frame(
    sample = samples,
    treatment = unname(ifelse(group_of == "U", NA_character_,
                              group_to_trt[group_of])),
    stringsAsFactors = FALSE
  )
  planted_truth <- function(treatment, signature) {
    signature %in% .MS_TRT_MAP[[treatment]]
  }
  list(catalog = catalog, dict = dict, samples = samples, group_of = group_of,
       treatments = treatments, planted_truth = planted_truth)
}
