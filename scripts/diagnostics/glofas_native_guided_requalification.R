# Same-target guided requalification layered on the frozen Stage E matrix.
# This module is pure: callers supply in-memory objects and frozen budgets.

gngr_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS native guided requalification: ", why),
    call. = FALSE)
  invisible(TRUE)
}

gngr_hash <- function(x) {
  gngr_require(requireNamespace("digest", quietly = TRUE), "digest is required")
  digest::digest(x, algo = "sha256", serialize = TRUE)
}

gngr_baseline_table <- function(x) {
  out <- do.call(rbind, lapply(x, function(row) data.frame(
    context = as.character(row$context), particles = as.integer(row$particles),
    mcse = as.numeric(row$mcse), stringsAsFactors = FALSE)))
  rownames(out) <- NULL
  out
}

gngr_validate_budget <- function(x, stage_e_budget) {
  q <- gngr_require
  q(is.list(x) && identical(x$schema_version,
    "glofas_native_guided_requalification_budget_v1"),
    "guided budget schema changed")
  required <- c("schema_version", "stage", "task_id", "posterior_target_sha256",
    "declared_prior_sha256", "effective_prior_sha256",
    "stage_e_budget_sha256", "stage_e_receipt_sha256", "guide_control",
    "initial_extension_gate", "authorizations")
  q(setequal(names(x), required), "guided budget fields changed")
  q(identical(x$stage, "GUIDED_NATIVE_PROPOSAL_REQUALIFICATION_NO_FIT") &&
    identical(x$task_id, stage_e_budget$task_id) &&
    identical(x$posterior_target_sha256, stage_e_budget$posterior_target_sha256) &&
    identical(x$declared_prior_sha256, stage_e_budget$declared_prior_sha256) &&
    identical(x$effective_prior_sha256, stage_e_budget$effective_prior_sha256),
    "guided budget target identity differs from Stage E")
  q(identical(x$stage_e_budget_sha256,
    "7b32e3279b76342bc95533271ce30c8752de2f5238b57a80658ccd0be625b6bd") &&
    identical(x$stage_e_receipt_sha256,
    "8a4f13057e228cbd133e50105e4cdad3219d1e561642d9eb44ac88b0aeb7995e"),
    "Stage E budget or receipt identity changed")
  control <- x$guide_control
  q(is.list(control) && setequal(names(control), "maximum_absolute_slope") &&
    is.numeric(control$maximum_absolute_slope) &&
    length(control$maximum_absolute_slope) == 1L &&
    is.finite(control$maximum_absolute_slope) &&
    control$maximum_absolute_slope > 0 && control$maximum_absolute_slope <= 1e6,
    "bounded guide control required")
  gate <- x$initial_extension_gate
  q(is.list(gate) && setequal(names(gate), c("require_all_complete",
    "require_all_degeneracy_diagnostics", "maximum_mcse_ratio_to_stage_e",
    "stage_e_initial_mcse")) &&
    identical(gate$require_all_complete, TRUE) &&
    identical(gate$require_all_degeneracy_diagnostics, TRUE) &&
    is.numeric(gate$maximum_mcse_ratio_to_stage_e) &&
    length(gate$maximum_mcse_ratio_to_stage_e) == 1L &&
    gate$maximum_mcse_ratio_to_stage_e > 0 &&
    gate$maximum_mcse_ratio_to_stage_e < 1,
    "prospective initial extension gate required")
  baseline <- gngr_baseline_table(gate$stage_e_initial_mcse)
  q(identical(names(baseline), c("context", "particles", "mcse")) &&
    nrow(baseline) == 9L && all(is.finite(baseline$particles)) &&
    all(is.finite(baseline$mcse)) && all(baseline$mcse > 0),
    "nine finite Stage E initial MCSE references required")
  expected <- expand.grid(context = unlist(stage_e_budget$particle_grid$contexts),
    particles = as.integer(unlist(stage_e_budget$particle_grid$particle_counts)),
    stringsAsFactors = FALSE)
  q(setequal(paste(baseline$context, baseline$particles),
    paste(expected$context, expected$particles)),
    "Stage E initial MCSE reference grid changed")
  q(is.list(x$authorizations) && all(vapply(x$authorizations, identical,
    logical(1L), FALSE)), "fit, truth, production, publication, and Stage F must remain false")
  invisible(TRUE)
}

gngr_make_evidence_once <- function(guide_control) {
  force(guide_control)
  function(binding, eta, particles, seed, budget, retain_particles = TRUE) {
    started <- proc.time()[["elapsed"]]
    evidence <- gtdpb_make_evidence(binding, particles = particles,
      ess_fraction = budget$particle_grid$ess_fraction,
      limits = list(max_horizon = 28L, max_particles = 4096L,
        max_calls = as.integer(budget$resource_caps$maximum_callback_calls_per_evidence)),
      gates = list(min_ess = budget$particle_grid$minimum_ess_diagnostic,
        min_unique_ancestors =
          as.integer(budget$particle_grid$minimum_unique_ancestors_diagnostic)),
      retain_particles = retain_particles, native_guide_control = guide_control)
    out <- evidence(eta, as.integer(seed))
    out$elapsed_seconds <- proc.time()[["elapsed"]] - started
    out
  }
}

gngr_initial_precision <- function(initial, guide_budget) {
  rows <- initial$rows
  current <- do.call(rbind, lapply(split(rows,
    interaction(rows$context, rows$particles, drop = TRUE)), function(z) {
      data.frame(context = z$context[[1L]], particles = z$particles[[1L]],
        replicates = nrow(z),
        mcse = if (nrow(z) > 1L) stats::sd(z$log_evidence) / sqrt(nrow(z)) else Inf,
        stringsAsFactors = FALSE)
    }))
  baseline <- gngr_baseline_table(
    guide_budget$initial_extension_gate$stage_e_initial_mcse)
  key <- paste(current$context, current$particles)
  at <- match(key, paste(baseline$context, baseline$particles))
  gngr_require(!anyNA(at), "initial grid does not match the frozen Stage E reference")
  current$stage_e_mcse <- baseline$mcse[at]
  current$mcse_ratio_to_stage_e <- current$mcse / current$stage_e_mcse
  current$ratio_budget <- guide_budget$initial_extension_gate$maximum_mcse_ratio_to_stage_e
  current$ratio_pass <- current$mcse_ratio_to_stage_e <= current$ratio_budget
  rownames(current) <- NULL
  current
}

gngr_extension_admission <- function(guide_budget) {
  force(guide_budget)
  function(initial, elapsed, remaining, budget) {
    base <- gnse_extension_admission(initial, elapsed, remaining, budget)
    precision <- gngr_initial_precision(initial, guide_budget)
    complete <- all(initial$rows$complete)
    diagnostics <- all(initial$rows$diagnostic_thresholds_passed)
    ratio <- all(precision$ratio_pass)
    base$all_initial_complete <- complete
    base$all_degeneracy_diagnostics_pass <- diagnostics
    base$all_mcse_ratio_pass <- ratio
    base$maximum_mcse_ratio_observed <- max(precision$mcse_ratio_to_stage_e)
    base$maximum_mcse_ratio_budget <-
      guide_budget$initial_extension_gate$maximum_mcse_ratio_to_stage_e
    base$admitted <- isTRUE(base$admitted[[1L]]) && complete && diagnostics && ratio
    attr(base, "initial_precision") <- precision
    base
  }
}

gngr_run <- function(engine, design, object, prior_export, stage_e_budget,
    guide_budget, wall_seconds, source_sha256) {
  gngr_validate_budget(guide_budget, stage_e_budget)
  evidence_once <- gngr_make_evidence_once(guide_budget$guide_control)
  extension_admission <- gngr_extension_admission(guide_budget)
  out <- gnse_run(engine, design, object, prior_export, stage_e_budget,
    wall_seconds, source_sha256, evidence_once = evidence_once,
    extension_admission = extension_admission)
  out$summary$schema_version <- "glofas_native_guided_requalification_summary_v1"
  out$summary$stage_e_receipt_sha256 <- guide_budget$stage_e_receipt_sha256
  out$summary$stage_e_budget_sha256 <- guide_budget$stage_e_budget_sha256
  out$summary$guide_control <- guide_budget$guide_control
  out$summary$guide_changes_target <- FALSE
  out$summary$stage_f_authorized <- FALSE
  out$summary$native_fit_authorized <- FALSE
  out$summary$production_authorized <- FALSE
  out$summary$publication_authorized <- FALSE
  out$initial_precision_comparison <- attr(out$extension, "initial_precision")
  attr(out$extension, "initial_precision") <- NULL
  out
}
