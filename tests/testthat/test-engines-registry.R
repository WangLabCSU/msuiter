# Engine registry contract tests (U-M0-04; ARCHITECTURE.md section 3.4,
# decisions A14/A17): registration governance, string sugar resolution,
# certified three-state treatment and the fit_engine/required_pkgs generics.
# Everything here is synthetic -- no real engine is registered before M1s
# (docs/IMPLEMENTATION-PLAN.md U-M0-04).

# Synthetic S7 engine class with the property defaults required for string
# sugar: a registered engine class must build a valid spec from its defaults.
.make_engine_class <- function(name = "synth_a",
                               mode = "extract",
                               packages = character(0),
                               deterministic = TRUE) {
  S7::new_class(
    paste0("SynthEngine_", name),
    package = "msuiter.test",
    parent = MsEngine,
    properties = list(
      name = S7::new_property(S7::class_character, default = name),
      mode = S7::new_property(S7::class_character, default = mode),
      deterministic = S7::new_property(S7::class_logical, default = deterministic),
      packages = S7::new_property(S7::class_character, default = packages)
    )
  )
}

# Synthetic fit function: the fit_engine() contract is dispatch to the
# registered implementation, nothing more at M0.
.make_fit_fn <- function() {
  function(engine, ...) {
    list(engine = engine@name, dot_args = list(...))
  }
}

.register_synth <- function(name = "synth_a", mode = "extract",
                            packages = character(0), certified = "certified") {
  suppressWarnings(register_ms_engine(
    name = name,
    mode = mode,
    engine_class = .make_engine_class(name, mode, packages),
    fit_fn = .make_fit_fn(),
    packages = packages,
    tags = "synthetic",
    engine_version = "0.1.0",
    contract_version = "1",
    certified = certified
  ))
}

test_that("ms_engines() on an empty registry returns a zero-row summary", {
  msuiter_registry_reset()
  df <- ms_engines()
  expect_s3_class(df, "data.frame")
  expect_identical(nrow(df), 0L)
  expect_named(df, c("name", "mode", "engine_version", "contract_version", "certified"))
})

test_that("register_ms_engine stores governance fields; ms_engines() lists them", {
  msuiter_registry_reset()
  .register_synth("synth_a")
  df <- ms_engines()
  expect_identical(nrow(df), 1L)
  expect_identical(df$name, "synth_a")
  expect_identical(df$mode, "extract")
  expect_identical(df$engine_version, "0.1.0")
  expect_identical(df$contract_version, "1")
  expect_identical(df$certified, "certified")
})

test_that("ms_engines() rows are sorted by name for deterministic output", {
  msuiter_registry_reset()
  .register_synth("synth_b")
  .register_synth("synth_a")
  expect_identical(ms_engines()$name, c("synth_a", "synth_b"))
})

test_that("duplicate engine names are rejected and the row survives unchanged", {
  msuiter_registry_reset()
  .register_synth("synth_a")
  expect_ms_error(
    .register_synth("synth_a"),
    "registry",
    regexp = "already registered"
  )
  expect_identical(nrow(ms_engines()), 1L)
})

test_that("registry field violations raise msuiter_error_registry", {
  msuiter_registry_reset()
  good <- list(
    mode = "extract",
    engine_class = .make_engine_class("synth_x"),
    fit_fn = .make_fit_fn(),
    packages = character(0),
    tags = character(0),
    engine_version = "0.1.0",
    contract_version = "1",
    certified = "certified"
  )
  register <- function(...) {
    do.call(register_ms_engine, modifyList(good, list(...), keep.null = FALSE))
  }

  expect_ms_error(register(name = "Bad Name"), "registry", regexp = "name")
  expect_ms_error(
    register(name = "synth_x", mode = "transform"),
    "registry", regexp = "mode"
  )
  # missing governance fields (A17: all three are mandatory and explicit)
  expect_ms_error(
    register(name = "synth_x", engine_version = NULL),
    "registry", regexp = "engine_version"
  )
  expect_ms_error(
    register(name = "synth_x", contract_version = NULL),
    "registry", regexp = "contract_version"
  )
  expect_ms_error(
    register(name = "synth_x", certified = NULL),
    "registry", regexp = "certified"
  )
  # certified outside the three governance states
  expect_ms_error(
    register(name = "synth_x", certified = "verified"),
    "registry", regexp = "certified"
  )
  # engine_class must be an S7 class deriving from MsEngine
  expect_ms_error(
    register(name = "synth_x", engine_class = "not-a-class"),
    "registry", regexp = "engine_class"
  )
  expect_ms_error(
    register(name = "synth_x",
             engine_class = S7::new_class("NotAnEngine", package = "msuiter.test")),
    "registry", regexp = "engine_class"
  )
  # fit_fn must be a function
  expect_ms_error(register(name = "synth_x", fit_fn = "nope"), "registry", regexp = "fit_fn")
  # packages / tags must be NA-free character vectors
  expect_ms_error(
    register(name = "synth_x", packages = c("S7", NA)),
    "registry", regexp = "packages"
  )
  expect_ms_error(
    register(name = "synth_x", tags = NA_character_),
    "registry", regexp = "tags"
  )
  expect_identical(nrow(ms_engines()), 0L)
})

test_that("certified accepts exactly the three governance states", {
  msuiter_registry_reset()
  .register_synth("e_certified", certified = "certified")
  .register_synth("e_selfrep", certified = "self-reported")
  .register_synth("e_unknown", certified = "unknown")
  df <- ms_engines()
  expect_setequal(df$certified, c("certified", "self-reported", "unknown"))
})

test_that("string sugar resolves and failure lists all available names (A14)", {
  msuiter_registry_reset()
  .register_synth("synth_a")
  .register_synth("synth_b")

  spec <- match_ms_engine("synth_a")
  expect_true(S7::S7_inherits(spec, MsEngine))
  expect_identical(spec@name, "synth_a")
  expect_identical(spec@mode, "extract")

  cnd <- expect_ms_error(match_ms_engine("nope"), "registry")
  # the error must list every available engine name
  expect_match(conditionMessage(cnd), "synth_a", fixed = TRUE)
  expect_match(conditionMessage(cnd), "synth_b", fixed = TRUE)

  # malformed sugar is rejected too
  expect_ms_error(match_ms_engine(c("synth_a", "synth_b")), "registry")
  expect_ms_error(match_ms_engine(1), "registry")
})

test_that("MsEngine objects pass through match_ms_engine unchanged", {
  msuiter_registry_reset()
  .register_synth("synth_a")
  spec <- .make_engine_class("synth_a")()
  expect_identical(match_ms_engine(spec), spec)
})

test_that("fit_engine dispatches to the registered fit_fn with dots", {
  msuiter_registry_reset()
  .register_synth("synth_a")
  spec <- match_ms_engine("synth_a")
  out <- fit_engine(spec, rank = 3)
  expect_identical(out$engine, "synth_a")
  expect_identical(out$dot_args$rank, 3)
})

test_that("fit_engine requires a registered engine", {
  msuiter_registry_reset()
  .register_synth("synth_a")
  lonely <- .make_engine_class("lonely", packages = "matrixStats")()
  expect_ms_error(fit_engine(lonely), "registry", regexp = "lonely")
  expect_identical(required_pkgs(lonely), "matrixStats")
})

test_that("required_pkgs prefers the registry row and falls back to the spec", {
  msuiter_registry_reset()
  .register_synth("synth_a", packages = c("S7", "rlang"))
  spec <- match_ms_engine("synth_a")
  expect_identical(required_pkgs(spec), c("S7", "rlang"))
})

test_that("third-party .onLoad registration path works end to end", {
  msuiter_registry_reset()
  # Simulate what a third-party package does in .onLoad(): build its own S7
  # engine class and register it through the exported extension entry point.
  # Registry rows are data, not methods (research/06 section 6), so no
  # S7::methods_register() call is needed for the registration itself; a
  # third party only calls it when defining its own methods on msuiter
  # generics, in its own namespace.
  fake_onLoad <- function() {
    cls <- S7::new_class(
      "ThirdPartyEngine", package = "fake.othersig", parent = MsEngine,
      properties = list(
        name = S7::new_property(S7::class_character, default = "othersig_kl"),
        mode = S7::new_property(S7::class_character, default = "fit"),
        deterministic = S7::new_property(S7::class_logical, default = FALSE)
      )
    )
    msuiter::register_ms_engine(
      name = "othersig_kl",
      mode = "fit",
      engine_class = cls,
      fit_fn = function(engine, ...) engine@name,
      packages = "fake.othersig",
      tags = c("third-party", "reference"),
      engine_version = "2.3.4",
      contract_version = "1",
      certified = "self-reported"
    )
    invisible(NULL)
  }
  fake_onLoad()

  # self-reported is non-certified: first resolution warns (A17), then idempotent
  expect_warning(
    spec <- msuiter::match_ms_engine("othersig_kl"),
    class = "msuiter_warning_uncertified_engine"
  )
  expect_no_warning(msuiter::match_ms_engine("othersig_kl"))
  expect_true(S7::S7_inherits(spec, MsEngine))
  expect_identical(spec@name, "othersig_kl")
  expect_identical(spec@mode, "fit")
  expect_identical(msuiter::fit_engine(spec), "othersig_kl")
  expect_identical(msuiter::required_pkgs(spec), "fake.othersig")
  df <- msuiter::ms_engines()
  expect_true("othersig_kl" %in% df$name)
})

test_that("engine classes without usable defaults fail resolution clearly", {
  msuiter_registry_reset()
  # The no-seed extract class triggers the registry seed warning (by
  # design since the hard-reject downgrade) — expect it here.
  expect_warning(
    register_ms_engine(
    name = "nodefault",
    mode = "extract",
    engine_class = S7::new_class("NoDefaults", package = "msuiter.test", parent = MsEngine),
    fit_fn = function(engine, ...) NULL,
    packages = character(0),
    tags = character(0),
    engine_version = "1",
    contract_version = "1",
    certified = "certified"
  ))

  expect_ms_error(
    match_ms_engine("nodefault"),
    "registry",
    regexp = "default spec"
  )
})

test_that("non-certified engines warn once per session per engine on resolution", {
  msuiter_registry_reset()
  .register_synth("synth_warn", certified = "self-reported")

  expect_warning(
    spec <- match_ms_engine("synth_warn"),
    class = "msuiter_warning_uncertified_engine"
  )
  expect_identical(spec@name, "synth_warn")
  # idempotent: resolving the same engine again (string path)
  expect_no_warning(match_ms_engine("synth_warn"))
  # idempotent: object path for the same engine
  expect_no_warning(match_ms_engine(spec))

  # "unknown" is also non-certified and must warn on first resolution
  msuiter_registry_reset()
  .register_synth("synth_unknown", certified = "unknown")
  expect_warning(
    match_ms_engine("synth_unknown"),
    class = "msuiter_warning_uncertified_engine"
  )

  # certified engines never warn
  msuiter_registry_reset()
  .register_synth("synth_cert")
  expect_no_warning(match_ms_engine("synth_cert"))
})
