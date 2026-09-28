#' msuiter: Mutational Signature Analysis with a Rust Compute Core
#'
#' Tally, extract and fit mutational signatures across modalities (SBS,
#' DBS, indel and beyond). Numerical kernels live in a Rust workspace
#' exposed through a stateless FFI; the R side provides the object model,
#' the engine registry and the tidy user interface.
#'
#' @keywords internal
"_PACKAGE"
