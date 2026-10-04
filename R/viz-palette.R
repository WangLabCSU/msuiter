# viz-palette.R: the COSMIC channel palette + shared viz plumbing
# (U-M4-03; design memo docs/devlog/2026-10-04-M4-03-viz-memo.md).
#
# The six substitution-class colors are verified byte-for-byte against
# the upstream SigProfilerPlotting source (sigProfilerPlotting.py,
# plotSBS, the colors list at L2895-2902; fetched 2026-10-04): each
# 16-channel substitution block (C>A, C>G, C>T, T>A, T>C, T>G) takes one
# color. NOTE (memo §1): the older research/04 note swapped two entries
# — the source array order is authoritative here.
#
# ggplot2 is a Suggests dependency (the calibrate-plot precedent):
# lazily attached at call time, absence is a structured package error.

.ms_viz_require_ggplot <- function(call = rlang::caller_call()) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    msuiter_abort(
      "package",
      "ggplot2 is required for the visualization faces",
      i = "viz is a Suggests dependency; install.packages(\"ggplot2\")",
      call = call
    )
  }
}

# The COSMIC SBS substitution palette: named by the substitution class,
# ordered as the registry's 16-channel blocks appear in the class cycle
# (C>A, C>G, C>T, T>A, T>C, T>G). Values = the verified upstream list.
.ms_viz_sbs_palette <- c(
  "C>A" = "#03BDEF",
  "C>G" = "#010101",
  "C>T" = "#E42926",
  "T>A" = "#CBCACA",
  "T>C" = "#A2CF63",
  "T>G" = "#ECC7C5"
)

# Per-channel color vector for a canonical SBS96 label set.
.ms_viz_channel_colors <- function(labels) {
  sub6 <- sub(".*\\[([ACTG]>[ACTG])\\].*", "\\1", labels)
  unname(.ms_viz_sbs_palette[sub6])
}

# The gray for the simplified non-SBS96 faces (DBS78/ID83 first pass).
.ms_viz_mono_color <- "#4D4D4D"

# Canonical-order guard shared with the interop face: the viz faces
# refuse to reorder silently.
.ms_viz_check_table <- function(labels, tables = c("SBS96", "DBS78", "ID83")) {
  registry <- get("channel_tables", envir = asNamespace("msuiter"))
  for (nm in tables) {
    if (identical(as.character(labels), registry[[nm]]$labels)) {
      return(nm)
    }
  }
  msuiter_abort(
    "input",
    "matrix rownames must equal a supported channel table in canonical order",
    i = paste0("supported: ", paste(tables, collapse = ", ")),
    j = sprintf("rows: %d; first label: %s", length(labels),
                if (length(labels) >= 1L) labels[1L] else "(none)"),
    c = "order the matrix with the registry labels (viz never reorders silently)"
  )
}

# The minimal COSMIC-ish theme (fixed; customization goes through the
# ggplot2 `+` operator upstream).
.ms_viz_theme <- function() {
  ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      axis.text.x = ggplot2::element_text(angle = 90, vjust = 0.5,
                                          hjust = 1),
      strip.text = ggplot2::element_text(face = "bold"),
      legend.position = "right"
    )
}
