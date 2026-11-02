#!/usr/bin/env Rscript
# U-M7-02 signeR 2.12.0 image installer (harness-side; design memo §2c,
# PI-confirmed identity ruling 2026-11-02).
#
# The package installs from the live-probed Bioconductor 3.22 release index
# (signeR-c probe bank: signeR@2.12.0 present, index size 2300, MD5
# 7872383e48eed0b6f753bfdee9f32d7e; CRAN negative control: absent). The CRAN
# side rides the base image's own era snapshot so dependency versions are
# deterministic; the pin itself is resolved from the Bioc index verbatim.
#
# G0 build-guard idiom: after the install, the pin and the witnessed call
# surface are asserted from the installed package's own bytes — pin or API
# drift is a build death, never a silent float.
options(repos = c(CRAN = "https://p3m.dev/cran/__linux__/noble/2026-03-10",
                  Bioc_3_22 = "https://bioconductor.org/packages/3.22/bioc"))
install.packages("signeR", dependencies = TRUE, quiet = TRUE)

# ---- build-time pin assert (G0 build-guard idiom) ----
version <- as.character(packageVersion("signeR"))
if (!identical(version, "2.12.0")) {
  stop("signeR pin drift: image carries ", version, ", want 2.12.0",
       call. = FALSE)
}

# ---- witnessed call surface (package's own NAMESPACE/Rd bytes, probe03) ----
# The cell runner's whole lever set is signeR(M) at defaults plus the two
# S4 point-estimate accessors; anything they touch must exist or the image
# must not exist.
CORE_API <- c("signeR", "Average_exp", "Average_sign", "setSamples",
              "setMutations", "Normalize")
for (fn in CORE_API) {
  if (!exists(fn, mode = "function", where = asNamespace("signeR"))) {
    stop("witnessed signeR export missing: ", fn, call. = FALSE)
  }
}
if (!"M" %in% names(formals(get("signeR", asNamespace("signeR"))))) {
  stop("signeR() entry point lost its documented M argument", call. = FALSE)
}

# jsonlite: the cell runner's params.json parser (single call site, mirrors
# the sigminer row's RB-03 convergence-gate provisioning discipline).
install.packages("jsonlite", dependencies = NA, quiet = TRUE)
jv <- as.character(packageVersion("jsonlite"))
if (is.null(jv) || !nzchar(jv) || identical(jv, NA_character)) {
  stop("jsonlite provisioning unverified", call. = FALSE)
}
cat("[image] signeR ", version, ", jsonlite ", jv, " provisioned\n", sep = "")
