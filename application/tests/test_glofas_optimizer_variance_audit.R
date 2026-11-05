# Fast generated driver checks. Full CLI runs are separate, source-frozen,
# default-control computations; these overrides cannot be exported as such.
local({
  source("scripts/diagnostics/glofas_collapsed_parameter_optimizer.R", local = TRUE)
  source("scripts/audit_glofas_optimizer_variance_qualification.R", local = TRUE)
  source("scripts/audit_glofas_collapsed_optimizer_generated.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  reject <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  parts <- c("baseline", "negative", "candidate", "sensitivity")
  plans <- lapply(parts, govqa_plan)
  ok(identical(vapply(plans, nrow, integer(1L)), c(6L, 6L, 6L, 3L)))
  plan <- do.call(rbind, plans)
  ok(nrow(plan) == 21L && !anyDuplicated(plan$case_id))
  ok(identical(as.character(plans[[1L]]$kind), rep(c("none", "exact"), each = 3L)))
  ok(identical(as.character(plans[[3L]]$kind), rep(c("exact", "state_frozen_taylor2"), each = 3L)))
  ok(all(plans[[4L]]$strategy == "short_memory_adam_095"))
  ctl <- gcpopt_control(max_iterations = 3L, minimum_iterations = 1L, batch_size = 4L,
    stable_iterations = 2L, max_wall_seconds = 30, max_evaluations = 1000L,
    inner_call_bound = 1L, max_inner_calls = 10000L)
  hashes <- c(generated = paste(rep("a", 64L), collapse = ""))
  results <- lapply(parts, function(part) govqa_compute(part, hashes, ctl))
  for (i in seq_along(parts)) {
    x <- results[[i]]; s <- x$summary
    ok(nrow(s) == nrow(plans[[i]]) && identical(s$case_id, plans[[i]]$case_id))
    ok(all(is.finite(s$achieved_ELBO)) && all(is.finite(s$reference_family_KL)))
    ok(all(!s$application_qualified) && all(!s$native_qualified) && all(s$original_reads == 0L))
    ok(x$control_override_for_test && all(s$control_override_for_test))
    ok(all(s$iterations <= 3L) && all(s$model_evaluations <= ctl$max_evaluations))
    ok(length(x$runs) == nrow(s) && length(x$histories) == nrow(s) && length(x$mcse) == nrow(s))
    ok(all(vapply(x$mcse, nrow, integer(1L)) == 4L))
    ok(all(vapply(x$runs, function(r) identical(dim(r$q$covariance), c(2L, 2L)), logical(1L))))
    ok(all(s$reference_optimizer_convergence == 0L) &&
      all(s$reference_family_KL[s$fixture == "concentrated_51"] > .1))
    ok(!any(grepl("minimum", names(s), fixed = TRUE)))
    ok(all(!s$tight_gate[s$fixture != "no_members"]))
    ok(all(vapply(x$runs, function(r) !r$publication_authorized && !r$application_qualified &&
      !r$native_qualified, logical(1L))))
  }
  # Budget-limited outcomes are recorded for every planned cell, including
  # zero-completed-iteration histories and unavailable gradient MCSEs.
  limited <- ctl; limited$max_evaluations <- 1L
  x <- govqa_compute("candidate", hashes, limited)
  ok(nrow(x$summary) == 6L && all(x$summary$iterations == 0L))
  ok(all(nzchar(x$summary$failure)) && all(!x$summary$tight_gate))
  ok(all(is.na(x$summary$max_standardized_gradient_mcse)))
  ok(all(vapply(x$histories, nrow, integer(1L)) == 0L))
  ok(all(is.finite(x$summary$achieved_ELBO)))
  # The actual CLI deliberately exposes no control/seed/budget override.
  parsed <- govqa_parse(c("--output", "/tmp/output", "--part", "candidate"))
  ok(parsed$part == "candidate" && parsed$output == "/tmp/output")
  reject(govqa_parse(c("--part", "candidate", "--seed", "123")))
  reject(govqa_parse(c("--part", "wrong", "--output", "x")))
  reject(govqa_parse(c("--part", "candidate", "--output", "x", "--iterations", "3")))
  reject(govqa_parse(c("--part", "candidate", "--part", "baseline")))
  reject(govqa_output(file.path(tempdir(), "must_not_be_exported")))
  reject(govqa_write_packet(results[[3L]], file.path(tempdir(), "override_not_exported"), list()))
  ok(!file.exists(file.path(tempdir(), "override_not_exported")))
  ok(length(govqa_sources()) == 6L && all(file.exists(govqa_sources())))
  state_json <- jsonlite::toJSON(results[[3L]]$runs[[1L]], auto_unbox = TRUE,
    null = "null", na = "null", digits = 17)
  ok(jsonlite::validate(state_json))
  # No-argument/full defaults remain the old contract, not tuned test values.
  source("scripts/diagnostics/glofas_collapsed_parameter_optimizer.R", local = TRUE)
  standard <- gcpoa_control(gcpopt_control)
  ok(standard$max_iterations == 1000L && standard$batch_size == 256L &&
    standard$learning_rate == .02 && standard$seed == 2026110507L)
  cat(sprintf("GLOFAS_OPTIMIZER_VARIANCE_AUDIT_PASS checks=%d planned_outcomes=21 full_runs=0 original_reads=0 production_qualified=FALSE\n", checks))
})
