local({
  source("scripts/diagnostics/glofas_native_stage_e.R", local = TRUE)
  source("scripts/diagnostics/glofas_native_guided_requalification.R", local = TRUE)
  n <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); n <<- n + 1L }
  reject <- function(x) ok(inherits(try(force(x), silent = TRUE), "try-error"))
  stage_e <- jsonlite::read_json(
    "scripts/diagnostics/glofas_native_stage_e_acceptance_budget.json",
    simplifyVector = FALSE)
  guided <- jsonlite::read_json(
    "scripts/diagnostics/glofas_native_guided_requalification_budget.json",
    simplifyVector = FALSE)
  gngr_validate_budget(guided, stage_e); ok(TRUE)
  mutate <- function(x, path, value) {
    if (length(path) == 1L) x[[path]] <- value else
      x[[path[[1L]]]][[path[[2L]]]] <- value
    x
  }
  reject(gngr_validate_budget(mutate(guided, "task_id", "other"), stage_e))
  reject(gngr_validate_budget(mutate(guided,
    c("guide_control", "maximum_absolute_slope"), 1e7), stage_e))
  reject(gngr_validate_budget(mutate(guided,
    c("initial_extension_gate", "maximum_mcse_ratio_to_stage_e"), 1), stage_e))
  reject(gngr_validate_budget(mutate(guided,
    c("authorizations", "stage_f"), TRUE), stage_e))
  baseline <- gngr_baseline_table(
    guided$initial_extension_gate$stage_e_initial_mcse)
  rows <- do.call(rbind, lapply(seq_len(nrow(baseline)), function(i) {
    target <- baseline$mcse[[i]] / 4
    values <- c(-3, -1, 1, 3) * target / sqrt(5 / 3)
    data.frame(context = baseline$context[[i]], particles = baseline$particles[[i]],
      replicate = 1:4, complete = TRUE, diagnostic_thresholds_passed = TRUE,
      log_evidence = values, elapsed_seconds = 0.01)
  }))
  initial <- list(rows = rows)
  precision <- gngr_initial_precision(initial, guided)
  ok(nrow(precision) == 9L && all(precision$ratio_pass))
  ok(max(abs(precision$mcse_ratio_to_stage_e - .25)) < 1e-12)
  rows$log_evidence[rows$context == baseline$context[[1L]] &
    rows$particles == baseline$particles[[1L]]] <- c(-30, -10, 10, 30) *
      baseline$mcse[[1L]] / sqrt(5)
  failed <- gngr_initial_precision(list(rows = rows), guided)
  ok(any(!failed$ratio_pass))
  ev <- gngr_make_evidence_once(guided$guide_control)
  ok(is.function(ev))
  ok("evidence_once" %in% names(formals(gnse_h2_check)) &&
    "evidence_once" %in% names(formals(gnse_particle_grid)) &&
    "evidence_once" %in% names(formals(gnse_rhs_invariance)) &&
    "evidence_once" %in% names(formals(gnse_gradient_assessment)) &&
    all(c("evidence_once", "extension_admission") %in% names(formals(gnse_run))))
  ok(identical(guided$authorizations$future_truth_read, FALSE) &&
    identical(guided$authorizations$model_fit, FALSE) &&
    identical(guided$authorizations$optimizer_iteration, FALSE) &&
    identical(guided$authorizations$stage_f, FALSE) &&
    identical(guided$authorizations$production, FALSE) &&
    identical(guided$authorizations$publication, FALSE))
  cat(sprintf(paste0("GLOFAS_NATIVE_GUIDED_REQUALIFICATION_PASS checks=%d ",
    "authentic_reads=0 model_runs=0\n"), n))
})
