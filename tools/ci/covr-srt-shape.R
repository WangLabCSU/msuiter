# The covr lane's single SRT renderer (the contract covmerge.py names).
# Shape is byte-frozen from the pre-sharding runner: one row per instrumented
# line, "<hits>|<filename>:<line>", one row per covr's own tally-by-line triple
# (covr exports no to_srt -- this trio is what its to_cobertura renders).
# Returns NULL for a tally that is not a consumable line-rows data.frame;
# the caller attests the absence honestly. This function never stops or quits.
.covr_srt_lines <- function(cov) {
  df <- try(covr:::tally_coverage(cov, by = "line"), silent = TRUE)
  if (inherits(df, "try-error") || !is.data.frame(df) || !nrow(df) ||
      !all(c("filename", "line", "value") %in% names(df))) return(NULL)
  paste0(as.character(as.integer(df$value)), "|", df$filename, ":", df$line)
}
