# Exercise the production worker's guard without its top-level I/O or any fit.
local({
  checks <- 0L
  check <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  worker_ast <- parse("application/scripts/386_run_glofas_part4_latent_family_job.R")
  assigns <- function(expr, name) {
    is.call(expr) && length(expr) == 3L &&
      identical(expr[[1L]], as.name("<-")) && identical(expr[[2L]], as.name(name))
  }
  worker_definition <- Filter(function(expr) assigns(expr, "run_job"), as.list(worker_ast))
  check(length(worker_definition) == 1L)

  # These are source-level bindings, outside run_job's frame, just as in the
  # real worker. A local-only override cannot intercept the actual adapter.
  scope <- new.env(parent = baseenv())
  evalq({
    `%||%` <- function(x, y) if (is.null(x)) y else x
    engine_calls <- 0L
    validation_mode <- "indirect_engine"
    app_qdesn_engine_function <- function(...) {
      engine_calls <<- engine_calls + 1L
      function(...) invisible(NULL)
    }
    app_resolve_path <- function(path, ...) path
    app_read_config <- function(path) test_cfg
    app_validate_model_grid <- function(...) {
      if (identical(validation_mode, "indirect_engine")) {
        app_build_qdesn_design(1, test_cfg)
      }
      stop("engine-guard validation sentinel", call. = FALSE)
    }
  }, envir = scope)
  sys.source("application/R/build_qdesn_features.R", envir = scope)
  eval(worker_definition[[1L]], envir = scope)
  check(identical(environment(scope$app_build_qdesn_design), scope))
  original_engine <- scope$app_qdesn_engine_function
  scope$original_engine_marker <- original_engine
  run <- function(policy = NULL, mode = "indirect_engine", worker = scope$run_job) {
    scope$test_cfg <- list(reservoir = list(n = 1L))
    if (!is.null(policy)) {
      scope$test_cfg$application_model <- list(ensemble_member_weight_policy = policy)
    }
    scope$validation_mode <- mode
    tryCatch(worker(), error = identity)
  }
  restored <- function() identical(scope$app_qdesn_engine_function, original_engine)

  blocked <- run("unit_member_likelihood_v1")
  check(inherits(blocked, "error"))
  check(identical(conditionMessage(blocked),
    "Unit-member fits must not dynamically load an external feature engine."))
  check(scope$engine_calls == 0L)
  check(restored())

  # An unrelated failure also unwinds the temporary source-level replacement.
  failed <- run("unit_member_likelihood_v1", mode = "unrelated_error")
  check(inherits(failed, "error"))
  check(identical(conditionMessage(failed), "engine-guard validation sentinel"))
  check(scope$engine_calls == 0L)
  check(restored())

  # Explicit legacy and default policies continue through the original engine.
  for (policy in list("fractional_per_horizon_v1", NULL)) {
    before <- scope$engine_calls
    legacy <- run(policy)
    check(inherits(legacy, "error"))
    check(identical(conditionMessage(legacy), "engine-guard validation sentinel"))
    check(scope$engine_calls == before + 1L)
    check(restored())
  }

  # Copy only the production prefix preceding validation to check ordinary
  # return as well. Its final expression observes the installed binding.
  statements <- as.list(body(scope$run_job))[-1L]
  validation <- which(vapply(statements, assigns, logical(1L), name = "model_grid"))
  check(length(validation) == 1L && validation[[1L]] > 1L)
  prefix <- scope$run_job
  body(prefix) <- as.call(c(list(as.name("{")),
    statements[seq_len(validation[[1L]] - 1L)],
    list(quote(!identical(app_qdesn_engine_function, original_engine_marker)))))
  check(identical(run("unit_member_likelihood_v1", worker = prefix), TRUE))
  check(restored())
  check(identical(run("fractional_per_horizon_v1", worker = prefix), FALSE))
  check(restored())
  check(identical(run(worker = prefix), FALSE))
  check(restored())

  cat(sprintf("PASS: GloFAS unit-member worker engine guard (%d no-fit checks)\n", checks))
})
