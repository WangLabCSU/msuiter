## RB-05(5) harvest: called-name -> witnessed formals allowlist, resolved
## inside the pinned image's own R (era truth). Names come from a host-minted
## token file (mint_called_names.py over the 7f3067-proven bytes); the
## container performs only get()/formals()/where() lookups -- zero regex in
## era R, zero hand-typed dependency literals.
suppressMessages(library(sigminer))
suppressMessages(library(jsonlite))
names <- trimws(readLines("/m7scaffold/called_names.txt"))
lookup <- function(nm) {
  f <- try(get(nm, mode = "function"), silent = TRUE)
  if (inherits(f, "try-error")) return(list(state = "unresolved", env = NA))
  env <- environmentName(environment(f))
  if (!nzchar(env)) env <- NA_character_
  fm <- try(formals(f), silent = TRUE)
  if (inherits(fm, "try-error") || is.null(fm)) {
    return(list(state = "primitive", env = env))
  }
  list(state = "ok", formals = trimws(names(fm)), env = env)
}
rows <- lapply(names, lookup)
names(rows) <- names
out <- list(schema = "m7-formals-allowlist-1",
            image = Sys.getenv("M7_IMAGE_TAG"),
            r_version = paste(R.version[c("major", "minor")], collapse = "."),
            harvested_at = format(Sys.time(), tz = "UTC"),
            names_source = "called_names.txt (host-minted, 45 tokens)",
            entries = rows)
writeLines(toJSON(out, pretty = TRUE, auto_unbox = TRUE),
           "/m7scaffold/formals_allowlist.json")
cat("HARVEST-OK", length(names), "called names\n")
