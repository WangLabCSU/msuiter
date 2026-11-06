# Shared RNG-hygiene guard for library faces that must seed the base RNG.
#
# A library call that runs set.seed() overwrites the user's global stream;
# under the package's bitwise-reproducibility posture that is a side effect,
# not a convenience (audit #74 P1-5, 2026-11-04: seven such faces). The law
# these two helpers carry: the user's RNG state -- the whole recorded tuple,
# kinds included, not just .Random.seed -- is what the caller sees again on
# return, whether or not the face consumed any draws.
#
# Usage at each face (the on.exit rides the face's own frame):
#   saved <- .ms_rng_snapshot()
#   on.exit(.ms_rng_restore(saved), add = TRUE)
#   set.seed(seed)

.ms_rng_state_keys <- c(".Random.seed", ".Random.kind", ".Random.number.type",
                        ".Random.sample.kind", ".Random.normal.kind")

#' Capture the user-visible base-RNG state from the global environment.
#' @noRd
.ms_rng_snapshot <- function() {
  g <- globalenv()
  present <- .ms_rng_state_keys[
    vapply(.ms_rng_state_keys, function(k) exists(k, envir = g,
                                                  inherits = FALSE),
           logical(1L))]
  stats <- mget(present, envir = g)
  attr(stats, "absent") <- setdiff(.ms_rng_state_keys, present)
  stats
}

#' Restore a snapshot taken by .ms_rng_snapshot(): assign the captured state
#' mirrors back and remove the state variables that did not pre-exist (a
#' fresh session that never touched the RNG must not inherit our set.seed()
#' residue). The restore assigns the mirrors directly -- the base's own
#' set.seed(mirror) round-trip re-expands an advanced MT state through its
#' seed layout and does not reproduce it (measured on this base); the
#' mirrors are what the stream consults.
#' @noRd
.ms_rng_restore <- function(saved) {
  g <- globalenv()
  absent <- setdiff(attr(saved, "absent"), names(saved))
  if (length(absent)) {
    suppressWarnings(rm(list = absent, envir = g))
  }
  for (k in names(saved)) {
    assign(k, saved[[k]], envir = g)
  }
  invisible(NULL)
}
