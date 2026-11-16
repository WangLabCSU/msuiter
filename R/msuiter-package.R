#' msuiter: Mutational Signature SUITE in R
#'
#' A complete toolkit for mutational signature analysis, following one
#' workflow grammar from raw variant calls to interpreted biology: tally
#' mutation catalogs across modalities (SBS, DBS, indel and beyond), extract
#' de novo signatures with an ensemble-plus-consensus pipeline and an
#' adjudicated default number of signatures, fit known signatures with
#' calibrated statistics that measure the empirical coverage of their
#' intervals, and compare, cluster and visualize signatures with
#' publication-grade figures. A reproducibility-by-construction core --
#' frozen random streams, bit-level thread invariance, structured errors,
#' and a provenance-governed reference database -- keeps results auditable
#' end to end. Numerical kernels are implemented in Rust and reached
#' through a stateless FFI behind the R object model and engine registry.
#'
#' @keywords internal
#' @useDynLib msuiter, .registration = TRUE
#' @importFrom stats setNames
#' @importFrom utils download.file getFromNamespace
"_PACKAGE"
