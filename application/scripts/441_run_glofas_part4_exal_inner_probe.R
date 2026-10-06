#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "engine_contract.R", "model_contract.R", "feature_contract.R",
  "covariate_design.R", "build_application_panel.R", "build_qdesn_features.R",
  "latent_path_design.R", "discrepancy_design.R", "forecast_contract.R",
  "fit_qdesn_discrepancy.R", "latent_path_runtime_backend.R", "latent_path_checkpoint.R",
  "latent_path_vb_al.R", "latent_path_vb_normal.R", "joint_qvp_qdesn.R",
  "joint_exqdesn_exact_structured_inference.R", "latent_path_vb_exal.R",
  "glofas_normal_desn_part1_screening.R", "glofas_part3_partitioned_rhs.R",
  "latent_path_vb_joint.R", "fit_qdesn_latent_path.R",
  "glofas_part4_ensemble_likelihood_contract.R", "glofas_part4_latent_family.R",
  "glofas_part4_exal_inner_audit.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  source_runtime_root = "local_trackers/runtime_configs/glofas_part4_search3_dependency_closure_20260930_r4",
  release_runtime_root = "local_trackers/runtime_configs/glofas_part4_search3_joint_release_r1_20261004",
  output_runtime_root = "local_trackers/runtime_configs/glofas_part4_exal_inner_probe_r1_20261006",
  source_job_id = "glofas_part4_search3_dependency_closure_20260930_r4_joint_exal_rhs_vb",
  final_job_id = "part4_joint_exal_continuation_b03",
  expected_final_fit_sha256 = "4dfb1bd05733c9a538483d6d5feca0ce413399ae18d09a0edb6eec68420da027",
  expected_design_sha256 = "a2fbcec6523802f01c98ec272253e58a598a5adc5c7b0f9063b615b36c07bcf9",
  stage1_max_iter = 30L,
  extended_max_iter = 170L,
  min_iter = 10L,
  workers = 14L,
  parameter_tolerance = 1.0e-4,
  quadrature_tolerance = 1.0e-6,
  n_draws = 16L,
  dry_run = FALSE
))

source_root <- app_resolve_path(args$source_runtime_root, must_work = TRUE)
release_root <- app_resolve_path(args$release_runtime_root, must_work = TRUE)
output_root <- app_resolve_path(args$output_runtime_root, must_work = FALSE)
if (dir.exists(output_root) && length(list.files(output_root, all.files = TRUE, no.. = TRUE))) {
  stop(sprintf("Probe output root is non-empty: %s", output_root), call. = FALSE)
}
invisible(lapply(file.path(output_root, c(
  "objects", "traces", "tables", "logs", "manifests", "status", "reports"
)), app_ensure_dir))

verify_hash <- function(path, expected, label) {
  path <- normalizePath(path, mustWork = TRUE)
  observed <- tolower(app_sha256_file(path))
  expected <- tolower(as.character(expected)[[1L]])
  if (!grepl("^[0-9a-f]{64}$", expected) || !identical(observed, expected)) {
    stop(sprintf("%s SHA256 mismatch: expected %s, observed %s.", label, expected, observed), call. = FALSE)
  }
  observed
}

source_job <- as.character(args$source_job_id)[[1L]]
final_job <- as.character(args$final_job_id)[[1L]]
final_fit_path <- file.path(release_root, "objects", paste0(final_job, "_fit_side.rds"))
design_path <- file.path(source_root, "objects", "part4_shared_design_truth_free.rds")
sidecar_path <- file.path(source_root, "objects", "part4_scoring_panel_sidecar.rds")
final_fit_sha <- verify_hash(final_fit_path, args$expected_final_fit_sha256, "final exAL fit")
design_sha <- verify_hash(design_path, args$expected_design_sha256, "truth-free design")

manifest_path <- file.path(source_root, "configs", "part4_model_manifest.csv")
manifest <- app_read_csv(manifest_path)
job <- manifest[manifest$run_id == source_job, , drop = FALSE]
if (nrow(job) != 1L || !identical(as.character(job$part4_family[[1L]]), "joint_exal_rhs_vb")) {
  stop("The probe source manifest does not contain the expected joint exAL job.", call. = FALSE)
}
cfg_path <- app_resolve_path(job$config_path[[1L]], must_work = TRUE)
grid_path <- app_resolve_path(job$model_grid_path[[1L]], must_work = TRUE)
cfg <- app_read_config(cfg_path)
grid <- app_validate_model_grid(grid_path, app_config_path(cfg, "schema"))
model_rows <- grid[grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
model_rows <- model_rows[order(as.numeric(model_rows$quantile_level)), , drop = FALSE]
tau <- as.numeric(model_rows$quantile_level)
if (!identical(tau, c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95))) {
  stop("The probe requires the frozen seven-quantile grid.", call. = FALSE)
}

design <- readRDS(design_path)
joint <- readRDS(final_fit_path)
app_validate_glofas_latent_path_design(design)
if (!identical(design$future_truth_policy, "physically_excluded_from_fit_objects_scoring_sidecar_only") ||
    !identical(joint$future_truth_policy, design$future_truth_policy)) {
  stop("The inner probe requires the physical future-truth firewall.", call. = FALSE)
}
if (!identical(as.numeric(joint$tau), tau) || length(joint$fits) != length(tau)) {
  stop("The final joint fit is not aligned with the probe quantile grid.", call. = FALSE)
}

vb_args <- app_make_qdesn_discrepancy_vb_args(
  cfg,
  prior = app_map_qdesn_prior(model_rows$coefficient_prior[[1L]]),
  seed = as.integer(model_rows$reservoir_seed[[1L]]),
  likelihood_family = "exal"
)
parameter_tolerance <- as.numeric(args$parameter_tolerance)
quadrature_tolerance <- as.numeric(args$quadrature_tolerance)
stage1_max <- as.integer(args$stage1_max_iter)
extended_max <- as.integer(args$extended_max_iter)
min_iter <- as.integer(args$min_iter)
workers <- as.integer(args$workers)
n_draws <- as.integer(args$n_draws)
if (stage1_max < min_iter || extended_max < min_iter || workers < 1L || n_draws < 1L ||
    parameter_tolerance <= 0 || quadrature_tolerance <= 0) {
  stop("Invalid inner-probe controls.", call. = FALSE)
}

reference_terms <- app_glofas_part3_rhs_prior_terms(
  joint$rhs_state_reference, joint$beta_reference_mean
)
discrepancy_terms <- app_glofas_part3_rhs_prior_terms(
  joint$rhs_state_discrepancy, joint$beta_discrepancy_mean
)

preflight <- do.call(rbind, lapply(seq_along(tau), function(index) {
  state <- app_latent_joint_initial_state(joint$fits[[index]])
  lengths <- vapply(c("latent_mean", "latent_inv_mean", "s_mean", "s2_mean"), function(name) {
    length(state[[name]] %||% numeric())
  }, integer(1L))
  data.frame(
    quantile_level = tau[[index]],
    complete_local_state = isTRUE(state$provenance$local_factor_state_complete),
    local_factor_length = min(lengths),
    local_factor_length_consistent = length(unique(lengths)) == 1L && min(lengths) > 0L,
    block_moments_complete = is.list(state$block_moments) &&
      all(c("Y", "G") %in% names(state$block_moments)),
    stringsAsFactors = FALSE
  )
}))
app_write_csv(preflight, file.path(output_root, "tables", "preflight.csv"))
if (any(!preflight$complete_local_state) || any(!preflight$local_factor_length_consistent) ||
    any(!preflight$block_moments_complete) || length(unique(preflight$local_factor_length)) != 1L) {
  stop("The retained joint fit does not contain a complete aligned exAL local state.", call. = FALSE)
}
if (app_as_bool(args$dry_run)) {
  writeLines("DRY_RUN_COMPLETE", file.path(output_root, "status", "probe.dry_run_complete"))
  cat(sprintf(
    "DRY_RUN_COMPLETE\nfinal_fit_sha256=%s\ndesign_sha256=%s\nquantiles=%s\nlocal_factor_length=%d\n",
    final_fit_sha, design_sha, paste(format(tau, trim = TRUE), collapse = ","),
    unique(preflight$local_factor_length)
  ))
  quit(save = "no", status = 0L)
}

tau_id <- function(value) sprintf("p%02d", as.integer(round(100 * value)))
compact_fit <- function(fit) {
  fit$draws <- NULL
  fit$variational_state$theta_mean <- NULL
  fit$variational_state$theta_cov <- NULL
  fit$variational_state$y_future_mean <- NULL
  fit$variational_state$y_future_cov <- NULL
  fit
}
run_one <- function(index, arm, max_iter, initializer_fit, stage) {
  q <- tau[[index]]
  id <- sprintf("%s_%s_%s", stage, arm, tau_id(q))
  running <- file.path(output_root, "status", paste0(id, ".running"))
  completed <- file.path(output_root, "status", paste0(id, ".completed"))
  failed <- file.path(output_root, "status", paste0(id, ".failed"))
  writeLines(sprintf("pid=%d\nstarted_at=%s", Sys.getpid(), format(Sys.time(), tz = "UTC", usetz = TRUE)), running)
  tryCatch({
    qdesign <- app_glofas_part4_design_for_quantile(design, q)
    qdesign$p0 <- q
    inner <- vb_args
    inner$max_iter <- as.integer(max_iter)
    inner$min_iter_elbo <- min_iter
    inner$tol <- parameter_tolerance
    inner$n_draws <- n_draws
    inner$freeze_beta_warmup_iters <- 0L
    inner$min_beta_updates <- 1L
    inner$beta_ridge <- list(precision = 1.0e-12)
    inner$quadrature_nodes <- c(4L, 8L, 12L)
    inner$quadrature_tolerance <- quadrature_tolerance
    inner$progress_every <- 1L
    inner$progress_path <- file.path(output_root, "traces", paste0(id, "_progress.csv"))
    inner$initial_state <- app_latent_joint_initial_state(
      initializer_fit,
      include_local_factors = identical(arm, "full_state")
    )
    inner$prior_addition <- app_latent_joint_prior_additions(
      reference_terms, discrepancy_terms, qdesign, index
    )
    before_theta <- as.numeric(initializer_fit$summary$theta_mean)
    before_path <- as.numeric(initializer_fit$summary$y_future_mean)
    started <- Sys.time()
    fit <- app_fit_latent_path_exal_vb_core(
      qdesign, q, coefficient_prior = "ridge", vb_args = inner,
      seed = as.integer(model_rows$reservoir_seed[[index]]) + 900000L + index
    )
    elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
    gate <- app_glofas_part4_exal_inner_gate(
      fit, q, parameter_tolerance, quadrature_tolerance
    )
    object_path <- file.path(output_root, "objects", paste0(id, "_fit_compact.rds"))
    app_glofas_part4_atomic_save_rds(compact_fit(fit), object_path)
    row <- cbind(
      data.frame(
        stage = stage, arm = arm, object_path = normalizePath(object_path, mustWork = TRUE),
        runtime_seconds = elapsed,
        local_factors_reused = isTRUE(fit$vb_diagnostics$initialization$local_factors_reused),
        block_moments_reused = isTRUE(fit$vb_diagnostics$initialization$block_moments_reused),
        coefficient_max_abs_change = max(abs(as.numeric(fit$summary$theta_mean) - before_theta)),
        latent_path_max_abs_change = max(abs(as.numeric(fit$summary$y_future_mean) - before_path)),
        stringsAsFactors = FALSE
      ),
      gate
    )
    app_write_csv(row, file.path(output_root, "tables", paste0(id, "_summary.csv")))
    unlink(running)
    writeLines(c(
      sprintf("quantile_level=%s", q), sprintf("converged=%s", fit$vb_diagnostics$converged),
      sprintf("fit_sha256=%s", app_sha256_file(object_path))
    ), completed)
    row
  }, error = function(error) {
    unlink(running)
    writeLines(conditionMessage(error), failed)
    data.frame(stage = stage, arm = arm, quantile_level = q, error = conditionMessage(error), stringsAsFactors = FALSE)
  })
}

stage1_tasks <- expand.grid(
  index = seq_along(tau), arm = c("legacy_partial", "full_state"),
  stringsAsFactors = FALSE
)
stage1 <- parallel::mclapply(seq_len(nrow(stage1_tasks)), function(task_index) {
  task <- stage1_tasks[task_index, , drop = FALSE]
  run_one(task$index[[1L]], task$arm[[1L]], stage1_max, joint$fits[[task$index[[1L]]]], "stage1")
}, mc.cores = min(workers, nrow(stage1_tasks)), mc.preschedule = TRUE, mc.set.seed = FALSE)
if (any(vapply(stage1, function(x) "error" %in% names(x), logical(1L)))) {
  stop("At least one stage-1 inner probe failed; inspect status markers.", call. = FALSE)
}
stage1 <- do.call(rbind, stage1)
app_write_csv(stage1, file.path(output_root, "tables", "stage1_legacy_vs_full_state.csv"))

full <- stage1[stage1$arm == "full_state", , drop = FALSE]
failed_tau <- as.numeric(full$quantile_level[!full$recorded_converged])
extended <- data.frame()
if (length(failed_tau)) {
  extended <- parallel::mclapply(failed_tau, function(q) {
    index <- match(q, tau)
    prior_path <- full$object_path[match(q, full$quantile_level)]
    initializer <- readRDS(prior_path)
    run_one(index, "full_state", extended_max, initializer, "extended")
  }, mc.cores = min(workers, length(failed_tau)), mc.preschedule = TRUE, mc.set.seed = FALSE)
  if (any(vapply(extended, function(x) "error" %in% names(x), logical(1L)))) {
    stop("At least one extended inner probe failed; inspect status markers.", call. = FALSE)
  }
  extended <- do.call(rbind, extended)
  app_write_csv(extended, file.path(output_root, "tables", "extended_full_state.csv"))
}

final_probe <- full
if (nrow(extended)) {
  for (q in extended$quantile_level) final_probe[final_probe$quantile_level == q, ] <- extended[extended$quantile_level == q, names(final_probe)]
}
decision <- app_glofas_part4_exal_probe_decision(final_probe)
app_write_csv(final_probe, file.path(output_root, "tables", "final_probe_gate.csv"))

contract <- data.frame(
  final_fit_sha256 = final_fit_sha, design_sha256 = design_sha,
  scoring_sidecar_sha256 = app_sha256_file(sidecar_path),
  source_manifest_sha256 = app_sha256_file(manifest_path),
  config_sha256 = app_sha256_file(cfg_path), model_grid_sha256 = app_sha256_file(grid_path),
  code_head = trimws(system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)),
  exal_core_sha256 = app_sha256_file(app_path("application/R/latent_path_vb_exal.R")),
  joint_core_sha256 = app_sha256_file(app_path("application/R/latent_path_vb_joint.R")),
  audit_module_sha256 = app_sha256_file(app_path("application/R/glofas_part4_exal_inner_audit.R")),
  worker_sha256 = app_sha256_file(app_path("application/scripts/441_run_glofas_part4_exal_inner_probe.R")),
  stage1_max_iter = stage1_max, extended_max_iter = extended_max,
  min_iter = min_iter, parameter_tolerance = parameter_tolerance,
  quadrature_tolerance = quadrature_tolerance, quadrature_nodes = "4,8,12",
  workers = workers, n_draws = n_draws,
  future_truth_policy = design$future_truth_policy,
  decision = decision, stringsAsFactors = FALSE
)
app_write_csv(contract, file.path(output_root, "manifests", "probe_contract.csv"))

report <- c(
  "# Part 4 Joint exAL Inner-State Probe",
  "",
  sprintf("Generated: %s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  "",
  sprintf("Decision: `%s`", decision),
  "",
  "The probe holds the final outer-20 RHS prior terms fixed and excludes future truth.",
  "Stage 1 compares the executed legacy partial initializer with a corrected full variational-state initializer.",
  "Only full-state levels that remain uncertified receive the bounded extended probe.",
  "No probe fit is a production or publication fit."
)
writeLines(report, file.path(output_root, "reports", "probe_findings.md"), useBytes = TRUE)

files <- list.files(output_root, recursive = TRUE, full.names = TRUE)
files <- files[file.info(files)$isdir %in% FALSE]
manifest_out <- data.frame(
  relative_path = substring(files, nchar(normalizePath(output_root, mustWork = TRUE)) + 2L),
  size_bytes = as.numeric(file.info(files)$size),
  sha256 = vapply(files, app_sha256_file, character(1L)), stringsAsFactors = FALSE
)
app_write_csv(manifest_out, file.path(output_root, "manifests", "probe_output_manifest.csv"))
writeLines(decision, file.path(output_root, "status", "probe.completed"))
cat(sprintf("decision=%s\nruntime_root=%s\n", decision, normalizePath(output_root, mustWork = TRUE)))
