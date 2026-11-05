#!/usr/bin/env Rscript
# Frozen generated-only optimizer experiments. No application/model reads.
govqa_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS variance audit: ", why), call. = FALSE)
}
govqa_sources <- function() c("scripts/audit_glofas_optimizer_variance_qualification.R",
  "scripts/diagnostics/glofas_collapsed_parameter_optimizer.R",
  "scripts/diagnostics/glofas_optimizer_control_reference.R",
  "scripts/diagnostics/glofas_collapsed_optimizer_reference.R",
  "scripts/diagnostics/glofas_collapsed_particle_reference.R",
  "scripts/audit_glofas_collapsed_optimizer_generated.R")
govqa_plan <- function(part) {
  govqa_require(is.character(part) && length(part) == 1L && part %in%
    c("baseline", "negative", "candidate", "sensitivity"), "one recognized part required")
  methods <- switch(part,
    baseline = data.frame(strategy = "legacy_adam_0999", kind = c("none", "exact")),
    negative = data.frame(strategy = "short_memory_adam_099", kind = c("frozen_scale", "adaptive_frozen_scale")),
    candidate = data.frame(strategy = "short_memory_adam_099", kind = c("exact", "state_frozen_taylor2")),
    sensitivity = data.frame(strategy = "short_memory_adam_095", kind = "state_frozen_taylor2"))
  methods <- methods[rep(seq_len(nrow(methods)), each = 3L), , drop = FALSE]
  methods$fixture <- rep(c("no_members", "moderate_51", "concentrated_51"), nrow(methods) / 3L)
  methods$part <- part
  methods$case_id <- paste(part, methods$strategy, methods$kind, methods$fixture, sep = "__")
  rownames(methods) <- NULL; methods
}
govqa_compute <- function(part, source_hashes, control = NULL) {
  source("scripts/diagnostics/glofas_collapsed_parameter_optimizer.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_particle_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_optimizer_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_optimizer_control_reference.R", local = TRUE)
  source("scripts/audit_glofas_collapsed_optimizer_generated.R", local = TRUE)
  plan <- govqa_plan(part); override <- !is.null(control)
  if (is.null(control)) control <- gcpoa_control(gcpopt_control)
  gcpopt_validate_control(control)
  fixtures <- list(no_members = numeric(), moderate_51 = seq(-.3, .7, length.out = 51L),
    concentrated_51 = rep(.2, 51L))
  offset <- c(.1, log(.3 / 4) + 1 / 8); units <- c(.2, .5); F <- diag(units)
  references <- lapply(fixtures, function(G) list(
    q = gcpor_h1_optimize(offset, c(0, 0), factor = F, members = G, probability = .2),
    target = gcpor_h1_joint_moments(G, probability = .2)))
  summaries <- histories <- mcse <- run_records <- list()
  for (i in seq_len(nrow(plan))) {
    cell <- plan[i, ]; members <- fixtures[[cell$fixture]]
    historical <- function(mean, log_sd, factor) {
      stopifnot(is.null(factor))
      h <- gcpor_h1_elbo(offset + units * mean, log_sd, F)
      list(value = h$value, gradient_mean = units * h$gradient[1:2], gradient_log_sd = h$gradient[3:4])
    }
    evidence <- function(point, seed) {
      x <- offset + units * point; r <- members - x[1L]
      list(log_estimate = length(members) * (log(.2 * .8) - x[2L]) -
        exp(-x[2L]) * sum(r * (.2 - (r < 0))), complete = TRUE,
        diagnostic_thresholds_passed = TRUE, callback_calls = 0L)
    }
    inputs <- list(case_id = cell$case_id, members = members, probability = .2,
      Normal_prior_mean = .1, Normal_prior_sd = .2, IG_shape = 4, IG_rate = .3,
      offset = offset, units = units, initial_mean = c(0, 0), initial_log_sd = c(0, 0),
      kind = cell$kind, step_strategy = cell$strategy, frozen_anchor = offset[2L])
    contract <- gcpopt_input_contract(c("standardized_theta", "standardized_log_sigma"),
      "fixed_affine_theta_logsigma_same_measure_Jacobian_once_analytic_entropy_once",
      inputs, source_hashes)
    cv <- if (cell$kind == "none") NULL else gocr_h1_control(members, .2, offset, units,
      kind = cell$kind, anchor_log_sigma = offset[2L])
    fit <- gcpopt_optimize(log_evidence_estimate = evidence, analytic_historical = historical,
      initial_mean = c(0, 0), initial_log_sd = c(0, 0), control = control,
      input_contract = contract, control_variate = cv, step_strategy = cell$strategy)
    mean <- offset + units * fit$mean
    covariance <- tcrossprod(sweep(F, 2L, exp(fit$log_sd), "*"))
    value <- gcpor_h1_elbo(mean, fit$log_sd, F, members = members, probability = .2)
    ref <- references[[cell$fixture]]$q; truth <- references[[cell$fixture]]$target
    gap <- ref$value - value$value
    mean_error <- max(abs(mean - ref$mean) / sqrt(diag(ref$covariance)))
    variance_error <- max(abs(diag(covariance) / diag(ref$covariance) - 1))
    g <- fit$last_gradient
    vector <- function(field) if (is.null(g) || is.null(g[[field]])) rep(NA_real_, 4L) else g[[field]]
    max_value <- function(x) if (!length(x) || anyNA(x)) NA_real_ else max(abs(x))
    mcse[[cell$case_id]] <- data.frame(component = c("mean_theta", "mean_eta", "logsd_theta", "logsd_eta"),
      raw_uncontrolled = vector("raw_no_control_mcse"),
      controlled = vector("controlled_unprojected_mcse"),
      raw_uncontrolled_standardized = vector("raw_no_control_standardized_mcse"),
      controlled_standardized = vector("controlled_unprojected_standardized_mcse"))
    histories[[cell$case_id]] <- fit$history
    run_records[[cell$case_id]] <- list(inputs = inputs, input_contract = contract,
      control = control, initial_physical_mean = offset, initial_fixed_factor = F,
      q = list(physical_mean = mean, log_sd = fit$log_sd, fixed_factor = F, covariance = covariance),
      deterministic_q_reference = ref, exact_target = truth[c("mean", "covariance", "log_evidence")],
      reference_scope = "Deterministically optimized exact ELBO; no global-optimality certificate.",
      reference_family_KL = truth$log_evidence - ref$value,
      mcse_coordinates = "Raw mean-score columns use standardized optimizer coordinates; standardized columns use current q standard-deviation units. Log-SD coordinates are dimensionless.",
      last_gradient = g, source_seal = fit$input_seal_sha256,
      callback_source_sha256 = fit$callback_source_sha256,
      status = fit$status, failure = fit$failure,
      application_qualified = FALSE, native_qualified = FALSE, publication_authorized = FALSE)
    summaries[[i]] <- data.frame(part = part, case_id = cell$case_id, fixture = cell$fixture,
      strategy = cell$strategy, kind = cell$kind, members = length(members),
      iterations = fit$completed_iterations, status = fit$status,
      failure = if (is.null(fit$failure)) "" else fit$failure,
      stopping_criteria_met = fit$stopping_criteria_met,
      reference_ELBO_gap = gap, mean_error_in_reference_sd = mean_error,
      maximum_variance_relative_error = variance_error,
      tight_gate = fit$stopping_criteria_met && ref$convergence == 0 &&
        is.finite(gap) && gap >= -1e-7 && gap <= .001 && mean_error < .05 && variance_error < .05,
      achieved_ELBO = value$value, reference_ELBO = ref$value,
      reference_optimizer_convergence = ref$convergence,
      reference_family_KL = truth$log_evidence - ref$value,
      theta_mean = mean[1L], eta_mean = mean[2L], log_sd_1 = fit$log_sd[1L], log_sd_2 = fit$log_sd[2L],
      factor_11 = F[1L, 1L], factor_12 = F[1L, 2L], factor_21 = F[2L, 1L], factor_22 = F[2L, 2L],
      covariance_11 = covariance[1L, 1L], covariance_12 = covariance[1L, 2L], covariance_22 = covariance[2L, 2L],
      reference_theta_mean = ref$mean[1L], reference_eta_mean = ref$mean[2L],
      reference_covariance_11 = ref$covariance[1L, 1L], reference_covariance_12 = ref$covariance[1L, 2L],
      reference_covariance_22 = ref$covariance[2L, 2L],
      exact_target_theta_mean = truth$mean[1L], exact_target_theta_variance = truth$covariance[1L, 1L],
      exact_target_theta_eta_covariance = truth$covariance[1L, 2L],
      max_standardized_gradient = max_value(vector("standardized_gradient")),
      max_standardized_gradient_mcse = max_value(vector("standardized_mcse")),
      objective_mcse = if (nrow(fit$history)) tail(fit$history$objective_mcse, 1L) else NA_real_,
      model_evaluations = fit$evaluations, model_evaluation_limit = control$max_evaluations,
      inner_calls = fit$inner_calls, inner_call_limit = control$max_inner_calls,
      control_evaluations = fit$control_variate_evaluations,
      control_evaluation_limit = fit$control_variate_call_limit, total_callbacks = fit$total_callbacks,
      clipping_ever_active = if (nrow(fit$history)) any(fit$history$gradient_clip_multiplier < 1) else FALSE,
      scale_bound_ever_active = if (nrow(fit$history)) any(fit$history$variance_bound_active) else FALSE,
      elapsed_seconds = fit$elapsed_seconds, control_override_for_test = override,
      original_reads = 0L, application_qualified = FALSE, native_qualified = FALSE)
  }
  list(part = part, plan = plan, summary = do.call(rbind, summaries), histories = histories,
    mcse = mcse, runs = run_records, control = control, control_override_for_test = override,
    scope = "Generated H1 jointly uncertain Normal theta/shared AL sigma only; not native or source-specific RHS/scales.")
}

govqa_parse <- function(args) {
  govqa_require(is.character(args) && length(args) == 4L &&
    setequal(args[c(1L, 3L)], c("--part", "--output")),
    "usage: --part {baseline|negative|candidate|sensitivity} --output FRESH_IGNORED_PATH")
  values <- setNames(args[c(2L, 4L)], args[c(1L, 3L)])
  govqa_plan(unname(values[["--part"]]))
  govqa_require(nzchar(values[["--output"]]), "nonempty output path required")
  list(part = unname(values[["--part"]]), output = unname(values[["--output"]]))
}
govqa_git <- function(args, root = getwd()) {
  x <- system2("git", c("--no-replace-objects", "-C", shQuote(root), "-c", "core.fsmonitor=false", args),
    stdout = TRUE)
  govqa_require(is.null(attr(x, "status")), "Git read-only command failed")
  unname(x)
}
govqa_output <- function(path, root = getwd()) {
  root <- normalizePath(root, mustWork = TRUE)
  parent <- normalizePath(dirname(path), mustWork = TRUE)
  out <- file.path(parent, basename(path)); link <- Sys.readlink(out)
  govqa_require(startsWith(parent, paste0(root, "/local_trackers/")) && !file.exists(out) &&
    (is.na(link) || !nzchar(link)), "output must be a fresh nonsymlink ignored tracker directory")
  status <- system2("git", c("-C", shQuote(root), "check-ignore", "--quiet", "--", shQuote(out)))
  govqa_require(status == 0L, "output is not ignored")
  out
}
govqa_preflight <- function(root = getwd()) {
  root <- normalizePath(root, mustWork = TRUE)
  govqa_require(identical(normalizePath(govqa_git(c("rev-parse", "--show-toplevel"), root)), root),
    "run from the repository root")
  govqa_require(!length(govqa_git(c("status", "--porcelain", "--untracked-files=all"), root)),
    "source worktree must be clean")
  commit <- govqa_git(c("rev-parse", "HEAD"), root); tree <- govqa_git(c("rev-parse", "HEAD^{tree}"), root)
  paths <- govqa_sources(); hashes <- tools::sha256sum(file.path(root, paths)); names(hashes) <- paths
  for (path in paths) {
    link <- Sys.readlink(file.path(root, path))
    govqa_require(is.na(link) || !nzchar(link), "source symlink forbidden")
    govqa_require(identical(govqa_git(c("hash-object", "--no-filters", "--", shQuote(path)), root),
      govqa_git(c("rev-parse", shQuote(paste0(commit, ":", path))), root)), "source differs from committed blob")
  }
  list(commit = commit, tree = tree, source_sha256 = hashes)
}
govqa_write_packet <- function(result, output, checkpoint) {
  govqa_require(!result$control_override_for_test && !file.exists(output) && dir.create(output, mode = "0700"),
    "only unchanged prespecified controls may be exported into a fresh packet")
  write.csv(result$summary, file.path(output, "optimizer_quality.csv"), row.names = FALSE)
  write.csv(result$plan, file.path(output, "case_plan.csv"), row.names = FALSE)
  if (result$part == "candidate") write.csv(result$summary,
    file.path(output, "candidate_states.csv"), row.names = FALSE)
  for (id in names(result$runs)) {
    write.csv(result$histories[[id]], file.path(output, paste0("history_", id, ".csv")), row.names = FALSE)
    write.csv(result$mcse[[id]], file.path(output, paste0("mcse_", id, ".csv")), row.names = FALSE)
    jsonlite::write_json(result$runs[[id]], file.path(output, paste0("state_", id, ".json")),
      auto_unbox = TRUE, pretty = TRUE, digits = 17, null = "null", na = "null")
  }
  receipt <- list(schema_version = "glofas_generated_variance_part_v1", part = result$part,
    status = "GENERATED_VARIANCE_PART_COMPLETE_APPLICATION_NOT_QUALIFIED",
    source_commit = checkpoint$commit, source_tree = checkpoint$tree,
    source_sha256 = as.list(checkpoint$source_sha256),
    controls = result$control, controls_sha256 = digest::digest(result$control, algo = "sha256"),
    input_plan_sha256 = digest::digest(result$plan, algo = "sha256"),
    cases = nrow(result$summary), strict_gate_passes = sum(result$summary$tight_gate),
    failed_or_limited_runs = sum(nzchar(result$summary$failure) | !result$summary$stopping_criteria_met),
    callback_or_wall_failures = sum(nzchar(result$summary$failure)),
    nonstopping_runs = sum(!result$summary$stopping_criteria_met),
    strict_gate_failures = sum(!result$summary$tight_gate),
    R_version = R.version.string, scope = result$scope,
    reference_interpretation = "Deterministically optimized exact ELBO; no global-optimality certificate. Reference family KL is not a minimum over all variational parameters.",
    mcse_interpretation = "Raw mean-score columns use standardized optimizer coordinates, not physical theta/logsigma. Standardized mean columns use current q standard-deviation units; log-SD columns are dimensionless.",
    original_RDS_reads = 0L, application_fits = 0L, future_truth_reads = 0L,
    application_qualified = FALSE, native_qualified = FALSE,
    production_launch_authorized = FALSE, publication_authorized = FALSE)
  jsonlite::write_json(receipt, file.path(output, "DECISION.json"), auto_unbox = TRUE,
    pretty = TRUE, digits = 17, null = "null", na = "null")
  files <- sort(list.files(output)); paths <- file.path(output, files)
  write.csv(data.frame(relative_path = files, size_bytes = as.numeric(file.info(paths)$size),
    sha256 = unname(tools::sha256sum(paths))), file.path(output, "artifact_manifest.csv"), row.names = FALSE)
  invisible(receipt)
}
govqa_main <- function(args = commandArgs(TRUE)) {
  parsed <- govqa_parse(args); root <- normalizePath(".", mustWork = TRUE)
  output <- govqa_output(parsed$output, root); before <- govqa_preflight(root)
  result <- govqa_compute(parsed$part, before$source_sha256)
  after <- govqa_preflight(root)
  govqa_require(identical(before, after), "commit/tree/source identity changed during computation")
  receipt <- govqa_write_packet(result, output, before)
  final <- govqa_preflight(root)
  govqa_require(identical(before, final), "commit/tree/source identity changed during export")
  cat("GLOFAS_GENERATED_VARIANCE_PART_COMPLETE_APPLICATION_NOT_QUALIFIED part=", parsed$part,
    " cases=", nrow(result$summary), "\n", sep = "")
  invisible(receipt)
}
if (sys.nframe() == 0L) govqa_main()
