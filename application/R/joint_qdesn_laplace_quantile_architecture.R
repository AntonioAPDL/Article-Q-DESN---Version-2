# Quantile-aware architecture re-ranking for the difficult Laplace Bridge case.

app_joint_arch_contract_path <- function() {
  app_path("application/config/joint_qdesn_laplace_quantile_architecture_contract_v1.csv")
}

app_joint_arch_contract <- function(path = app_joint_arch_contract_path()) {
  tab <- app_read_csv(path)
  if (anyDuplicated(tab$name)) stop("Duplicate architecture contract keys.", call. = FALSE)
  out <- as.list(setNames(as.character(tab$value), tab$name))
  numeric_keys <- c(
    "shortlist_count", "frontier_score_multiplier", "vb_replicates",
    "vb_max_iterations", "screen_replicates", "screen_chains",
    "screen_al_iterations", "screen_al_burn", "screen_exal_iterations",
    "screen_exal_burn", "screen_thin", "confirmation_replicates",
    "confirmation_chains", "confirmation_al_iterations",
    "confirmation_al_burn", "confirmation_exal_iterations",
    "confirmation_exal_burn", "confirmation_thin", "state_draws_per_chain",
    "score_chunk_size", "oracle_paths_per_shard", "oracle_max_shards",
    "oracle_split_tolerance", "oracle_analytic_tolerance",
    "functional_review_rhat", "functional_review_relative_difference",
    "selection_epsilon", "max_mcmc_challengers", "max_workers",
    "min_free_gib", "screen_seed_base", "confirmation_seed_base",
    "chain_seed_base", "initialization_seed_base", "score_seed_base"
  )
  for (key in numeric_keys) out[[key]] <- as.numeric(out[[key]])
  out$tau <- c(.05, .10, .25, .50, .75, .90, .95)
  out$weights <- c(.025, .1, .2, .25, .2, .1, .025)
  stopifnot(
    out$version == "joint_laplace_quantile_architecture_v1",
    out$scenario == "laplace_bridge",
    out$reference_scenario == "asymmetric_laplace_tail",
    out$shortlist_count == 8, out$vb_replicates == 3,
    out$screen_replicates == 2, out$screen_chains == 2,
    out$confirmation_replicates == 2, out$confirmation_chains == 3,
    out$max_mcmc_challengers == 2, out$max_workers <= 15,
    out$exal_mcmc_method == "M0_v_collapsed_support_logit",
    out$exal_vb_method == "VB1_structured_v",
    out$primary_score == "dgp_integrated_acrps",
    out$shared_architecture_across_four_models == "true",
    out$publication_allowed == "false"
  )
  out
}

app_joint_arch_done <- function(path) app_joint_prior_done(path)

app_joint_arch_seal <- function(path) app_joint_prior_seal(path)

app_joint_arch_verify_manifest <- function(root, filename) {
  path <- file.path(root, filename)
  if (!file.exists(path)) stop(sprintf("Missing source manifest '%s'.", filename), call. = FALSE)
  checked <- app_joint_shared_verify_manifest(root, path)
  if (!nrow(checked) || any(!checked$verified)) {
    stop(sprintf("Source manifest '%s' does not verify.", filename), call. = FALSE)
  }
  checked
}

app_joint_arch_source_gate <- function(source_root, contract = app_joint_arch_contract()) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  required <- c(
    "rhs_candidate_aggregate.csv", "rhs_worker_plan.csv",
    "selected_family_backbones.csv", "ridge_final_health.csv",
    "rhs_final_health.csv", "selection_artifact_manifest.csv",
    "expanded_screen_final_manifest.csv", "final_expanded_screen_status.csv",
    "source_git_state.csv"
  )
  missing <- required[!file.exists(file.path(source_root, required))]
  if (length(missing)) stop(sprintf("Archived source is missing: %s", paste(missing, collapse = ", ")), call. = FALSE)
  app_joint_arch_verify_manifest(source_root, "selection_artifact_manifest.csv")
  app_joint_arch_verify_manifest(source_root, "expanded_screen_final_manifest.csv")
  ridge <- app_read_csv(file.path(source_root, "ridge_final_health.csv"))
  rhs <- app_read_csv(file.path(source_root, "rhs_final_health.csv"))
  status <- app_read_csv(file.path(source_root, "final_expanded_screen_status.csv"))
  if (ridge$expected[[1L]] != 18432L || ridge$completed[[1L]] != 18432L || ridge$failed[[1L]] != 0L ||
      rhs$expected[[1L]] != 7680L || rhs$completed[[1L]] != 7680L || rhs$failed[[1L]] != 0L ||
      status$status[[1L]] != "EXPANDED_RHS_SELECTION_COMPLETE_REVIEW_REQUIRED_BEFORE_QUANTILE_CONTINUATION" ||
      status$protected_rows_used_for_selection[[1L]] != 0L) {
    stop("Archived expanded screen is not complete under its frozen no-leakage contract.", call. = FALSE)
  }
  data.frame(
    source_root = source_root, ridge_complete = ridge$completed[[1L]],
    rhs_complete = rhs$completed[[1L]], source_status = status$status[[1L]],
    selection_manifest_verified = TRUE, final_manifest_verified = TRUE,
    stringsAsFactors = FALSE
  )
}

app_joint_arch_numeric_mean <- function(x) {
  mean(as.numeric(app_joint_shared_parse_num_vec(as.character(x))))
}

app_joint_arch_feature_matrix <- function(rows) {
  out <- cbind(
    D = as.numeric(rows$D),
    log_states = log1p(as.numeric(rows$retained_state_budget)),
    log_lags = log1p(as.numeric(rows$response_lags)),
    alpha = vapply(rows$alpha, app_joint_arch_numeric_mean, numeric(1L)),
    rho = vapply(rows$rho, app_joint_arch_numeric_mean, numeric(1L)),
    pi_w = vapply(rows$pi_w, app_joint_arch_numeric_mean, numeric(1L)),
    pi_in = vapply(rows$pi_in, app_joint_arch_numeric_mean, numeric(1L)),
    log_input_scale = log(as.numeric(rows$input_scale)),
    tapered = as.numeric(as.character(rows$width_shape) == "tapered")
  )
  center <- colMeans(out)
  scale <- apply(out, 2L, stats::sd)
  scale[!is.finite(scale) | scale <= 1e-12] <- 1
  sweep(sweep(out, 2L, center, "-"), 2L, scale, "/")
}

app_joint_arch_shortlist <- function(source_root, contract = app_joint_arch_contract()) {
  app_joint_arch_source_gate(source_root, contract)
  aggregate <- app_read_csv(file.path(source_root, "rhs_candidate_aggregate.csv"))
  selected <- app_read_csv(file.path(source_root, "selected_family_backbones.csv"))
  selected <- selected[selected$scenario_id == contract$scenario, , drop = FALSE]
  rows <- aggregate[aggregate$scenario_id == contract$scenario &
    aggregate$hard_gate_status == "pass" & is.finite(aggregate$calibration_acrps_mean), , drop = FALSE]
  if (nrow(selected) != 1L || !nrow(rows)) stop("Laplace source authority is malformed.", call. = FALSE)
  rows <- rows[order(rows$architecture_signature, rows$calibration_acrps_mean,
    rows$candidate_id, rows$rhs_tau0), , drop = FALSE]
  rows <- rows[!duplicated(rows$architecture_signature), , drop = FALSE]
  base_index <- which(rows$architecture_signature == selected$architecture_signature[[1L]] &
    abs(rows$rhs_tau0 - selected$rhs_tau0[[1L]]) <= 1e-15)
  if (length(base_index) != 1L) stop("Current Laplace baseline is absent from the archived RHS aggregate.", call. = FALSE)
  baseline_score <- rows$calibration_acrps_mean[[base_index]]
  frontier <- rows[rows$calibration_acrps_mean <= baseline_score * contract$frontier_score_multiplier, , drop = FALSE]
  if (nrow(frontier) < contract$shortlist_count) {
    frontier <- rows[order(rows$calibration_acrps_mean), , drop = FALSE]
    frontier <- head(frontier, max(32L, as.integer(contract$shortlist_count)))
  }
  base_frontier <- which(frontier$architecture_signature == selected$architecture_signature[[1L]])
  if (length(base_frontier) != 1L) {
    frontier <- rbind(rows[base_index, , drop = FALSE], frontier)
    frontier <- frontier[!duplicated(frontier$architecture_signature), , drop = FALSE]
    base_frontier <- 1L
  }
  features <- app_joint_arch_feature_matrix(frontier)
  chosen <- base_frontier
  selection_distance <- 0
  while (length(chosen) < contract$shortlist_count) {
    remaining <- setdiff(seq_len(nrow(frontier)), chosen)
    distance <- vapply(remaining, function(ii) {
      min(sqrt(rowSums((features[chosen, , drop = FALSE] -
        matrix(features[ii, ], nrow = length(chosen), ncol = ncol(features), byrow = TRUE))^2)))
    }, numeric(1L))
    best_distance <- max(distance)
    tied <- remaining[abs(distance - best_distance) <= 1e-12]
    pick <- tied[order(frontier$calibration_acrps_mean[tied], frontier$candidate_id[tied])][[1L]]
    chosen <- c(chosen, pick)
    selection_distance <- c(selection_distance, best_distance)
  }
  out <- frontier[chosen, , drop = FALSE]
  keep <- app_joint_pure_candidate_columns()
  out <- out[, c(keep, "rhs_tau0", "calibration_acrps_mean",
    "calibration_acrps_between_rep_sd", "convergence_fraction"), drop = FALSE]
  out$architecture_id <- sprintf("arch_%02d", seq_len(nrow(out)) - 1L)
  out$baseline <- seq_len(nrow(out)) == 1L
  out$source_selection_order <- seq_len(nrow(out))
  out$source_diversity_distance <- selection_distance
  out$source_relative_score <- out$calibration_acrps_mean / baseline_score
  out$source_role <- ifelse(out$baseline, "current_authoritative_backbone", "near_optimal_diverse_challenger")
  out <- out[, c("architecture_id", "baseline", "source_selection_order",
    "source_diversity_distance", "source_relative_score", "source_role", names(out)[!names(out) %in%
      c("architecture_id", "baseline", "source_selection_order", "source_diversity_distance",
        "source_relative_score", "source_role")]), drop = FALSE]
  if (nrow(out) != contract$shortlist_count || sum(out$baseline) != 1L ||
      anyDuplicated(out$architecture_signature) || any(out$raw_inputs_in_readout) ||
      any(!out$full_states_all_layers)) {
    stop("Frozen architecture shortlist violates its cardinality or pure-DESN contract.", call. = FALSE)
  }
  out
}

app_joint_arch_verify_shortlist_workers <- function(source_root, shortlist) {
  plan <- app_read_csv(file.path(source_root, "rhs_worker_plan.csv"))
  rows <- plan[plan$scenario_id == unique(shortlist$scenario_id) &
    plan$architecture_signature %in% shortlist$architecture_signature, , drop = FALSE]
  rows <- rows[do.call(paste, c(rows[c("architecture_signature", "rhs_tau0")], sep = "::")) %in%
    do.call(paste, c(shortlist[c("architecture_signature", "rhs_tau0")], sep = "::")), , drop = FALSE]
  if (nrow(rows) != nrow(shortlist) * 3L) stop("Shortlisted source RHS worker set is incomplete.", call. = FALSE)
  checks <- lapply(seq_len(nrow(rows)), function(ii) {
    directory <- app_joint_pure_worker_dir(source_root, "rhs", rows$rhs_worker_id[[ii]])
    verified <- app_joint_shared_verify_manifest(directory, file.path(directory, "artifact_manifest.csv"))
    data.frame(rhs_worker_id = rows$rhs_worker_id[[ii]],
      architecture_signature = rows$architecture_signature[[ii]],
      replicate_id = rows$replicate_id[[ii]], all_verified = all(verified$verified),
      manifest_sha256 = app_sha256_file(file.path(directory, "artifact_manifest.csv")),
      stringsAsFactors = FALSE)
  })
  out <- app_joint_qdesn_bind_rows(checks)
  if (!all(out$all_verified)) stop("At least one shortlisted archived RHS worker failed verification.", call. = FALSE)
  out
}

app_joint_arch_source_seeds <- function(source_root, scenario, n = 3L) {
  plan <- app_read_csv(file.path(source_root, "rhs_worker_plan.csv"))
  rows <- unique(plan[plan$scenario_id == scenario, c("replicate_id", "dgp_seed")])
  rows <- rows[order(rows$replicate_id), , drop = FALSE]
  if (nrow(rows) != n || !identical(as.integer(rows$replicate_id), seq_len(n))) {
    stop("Archived matched selector seeds are incomplete.", call. = FALSE)
  }
  rows
}

app_joint_arch_source_snapshot <- function(source_root) {
  files <- c(
    "rhs_candidate_aggregate.csv", "rhs_worker_plan.csv",
    "selected_family_backbones.csv", "selection_artifact_manifest.csv",
    "expanded_screen_final_manifest.csv", "final_expanded_screen_status.csv",
    "source_git_state.csv"
  )
  data.frame(relative_path = files,
    size_bytes = as.numeric(file.info(file.path(source_root, files))$size),
    sha256 = vapply(file.path(source_root, files), app_sha256_file, character(1L)),
    stringsAsFactors = FALSE)
}

app_joint_arch_prepare <- function(root, source_root = app_joint_arch_contract()$source_runtime) {
  if (dir.exists(root)) stop("Preparation will not overwrite an existing experiment.", call. = FALSE)
  ct <- app_joint_arch_contract(); source_root <- normalizePath(source_root, mustWork = TRUE)
  gate <- app_joint_arch_source_gate(source_root, ct)
  shortlist <- app_joint_arch_shortlist(source_root, ct)
  worker_checks <- app_joint_arch_verify_shortlist_workers(source_root, shortlist)
  seeds <- app_joint_arch_source_seeds(source_root, ct$scenario, ct$vb_replicates)
  app_ensure_dir(root); app_ensure_dir(file.path(root, "vb"))
  saveRDS(ct, file.path(root, "contract.rds"))
  app_write_csv(gate, file.path(root, "source_gate.csv"))
  app_write_csv(app_joint_arch_source_snapshot(source_root), file.path(root, "source_snapshot.csv"))
  app_write_csv(worker_checks, file.path(root, "shortlist_source_worker_verification.csv"))
  app_write_csv(shortlist, file.path(root, "architectures.csv"))
  datasets <- merge(shortlist[, c("architecture_id", "baseline")], seeds, by = NULL)
  datasets <- datasets[order(datasets$architecture_id, datasets$replicate_id), , drop = FALSE]
  datasets$dataset_id <- seq_len(nrow(datasets))
  datasets <- datasets[, c("dataset_id", "architecture_id", "baseline", "replicate_id", "dgp_seed")]
  app_write_csv(datasets, file.path(root, "vb", "datasets.csv"))
  source_files <- unique(c(
    list.files(app_path("application/R"), "^joint.*[.]R$", full.names = TRUE),
    list.files(app_path("application/scripts"), "joint.*[.](R|sh)$", full.names = TRUE),
    app_joint_arch_contract_path()
  ))
  app_write_csv(data.frame(relative_path = substring(source_files, nchar(app_path()) + 2L),
    sha256 = vapply(source_files, app_sha256_file, character(1L))), file.path(root, "source_manifest.csv"))
  writeLines(system2("git", c("rev-parse", "HEAD"), stdout = TRUE), file.path(root, "source_head.txt"))
  writeLines(capture.output(sessionInfo()), file.path(root, "session_info.txt"))
  files <- list.files(root, recursive = TRUE, full.names = TRUE)
  files <- files[!dir.exists(files)]
  app_joint_shared_write_manifest(root, setNames(files, substring(files, nchar(root) + 2L)))
  stopifnot(file.rename(file.path(root, "artifact_manifest.csv"), file.path(root, "freeze_manifest.csv")))
  invisible(root)
}

app_joint_arch_verify_freeze <- function(root) {
  checked <- app_joint_shared_verify_manifest(root, file.path(root, "freeze_manifest.csv"))
  if (!nrow(checked) || any(!checked$verified)) stop("Architecture experiment freeze changed.", call. = FALSE)
  source <- app_read_csv(file.path(root, "source_manifest.csv"))
  observed <- vapply(file.path(app_path(), source$relative_path), app_sha256_file, character(1L))
  if (!identical(unname(observed), as.character(source$sha256))) stop("Frozen source files changed.", call. = FALSE)
  if (system2("git", c("rev-parse", "HEAD"), stdout = TRUE) != readLines(file.path(root, "source_head.txt"))) {
    stop("Execution HEAD changed after preparation.", call. = FALSE)
  }
  invisible(TRUE)
}

app_joint_arch_vb_contract <- function(ct) {
  out <- app_joint_prior_vb_contract(ct)
  out$evaluation_replicates <- 1L
  out$max_dense_dim <- 2100L
  out
}

app_joint_arch_selected <- function(root, architecture_id) {
  rows <- app_read_csv(file.path(root, "architectures.csv"))
  row <- rows[rows$architecture_id == architecture_id, , drop = FALSE]
  if (nrow(row) != 1L) stop("Architecture identifier is not unique.", call. = FALSE)
  row
}

app_joint_arch_internal_context <- function(root, dataset_row) {
  ct <- readRDS(file.path(root, "contract.rds")); selected <- app_joint_arch_selected(root, dataset_row$architecture_id)
  registry <- app_joint_qdesn_load_simulation_registry()
  sc <- registry[registry$scenario_id == ct$scenario, , drop = FALSE]
  sc$seed <- as.integer(dataset_row$dgp_seed); sc$seed_role <- "laplace_architecture_internal_selector"
  fixture_full <- app_joint_qdesn_fixture_from_registry_row(sc); fixture_full$registry_row <- sc
  pure <- app_joint_pure_read_contract(); pure$max_readout_dimension <- 300L
  selector <- app_joint_pure_selector_fixture(fixture_full, pure)
  design <- app_joint_pure_build_design(selector, selected, pure, selector = TRUE)
  design$fit_local <- design$train_local
  design$validation_local <- design$calibration_local
  design$score_local <- design$calibration_local
  full <- design$row_meta$full_time_index[design$calibration_local]
  design$forecast_map <- data.frame(origin_index = rep(seq_len(5L), each = 30L),
    horizon = rep(seq_len(30L), 5L), full_time_index = full, stringsAsFactors = FALSE)
  full_index <- design$row_meta$full_time_index
  design$mu <- fixture_full$mu[full_index]; design$sigma <- fixture_full$sigma[full_index]
  design$seed <- as.integer(dataset_row$dgp_seed)
  end <- max(full)
  fixture <- fixture_full
  for (name in c("y", "mu", "sigma", "innovation", "innovation_raw")) {
    fixture[[name]] <- fixture[[name]][seq_len(end)]
  }
  fixture$true_q <- fixture$true_q[seq_len(end), , drop = FALSE]
  fixture$detailed_split <- fixture$detailed_split[seq_len(end), , drop = FALSE]
  fixture$Z <- fixture$Z[seq_len(end), , drop = FALSE]
  target <- list(y = design$y[design$fit_local], Z = design$Z[design$fit_local, , drop = FALSE])
  list(ct = ct, vc = app_joint_arch_vb_contract(ct), selected = selected,
    design = design, fixture = fixture, data_hash = digest::digest(target, algo = "sha256"))
}

app_joint_arch_save_fit <- function(root, job, fit) {
  directory <- app_joint_shared_quantile_worker_dir(root, job$job_id[[1L]])
  app_ensure_dir(directory); saveRDS(fit, file.path(directory, "fit_initializer.rds"))
}

app_joint_arch_nested_vb <- function(context, scratch) {
  d <- context$design; selected <- context$selected; vc <- context$vc
  app_ensure_dir(scratch); plan <- app_joint_shared_quantile_job_plan(vc)
  gaussian_job <- plan[plan$model_id == "gaussian_rhs_initializer", , drop = FALSE]
  gaussian <- app_joint_shared_quantile_gaussian_worker(gaussian_job, d, selected, vc)
  app_joint_arch_save_fit(scratch, gaussian_job, gaussian$fit)
  independent <- plan[plan$model_id %in% c("independent_qdesn_rhs", "independent_exqdesn_rhs"), , drop = FALSE]
  independent <- independent[order(independent$stage_order, independent$job_id), , drop = FALSE]
  for (ii in seq_len(nrow(independent))) {
    job <- independent[ii, , drop = FALSE]
    result <- if (job$model_id == "independent_qdesn_rhs") {
      app_joint_shared_quantile_independent_al_worker(scratch, job, plan, d, vc)
    } else {
      app_joint_shared_quantile_independent_exal_worker(scratch, job, plan, d, vc)
    }
    app_joint_arch_save_fit(scratch, job, result$fit)
  }
  independent_al <- app_joint_shared_quantile_stack_independent(
    scratch, plan, 1L, "independent_qdesn_rhs", d,
    rhs_vb_inner = vc$rhs_vb_inner, slab_fixed = vc$rhs_slab_fixed)
  independent_exal <- app_joint_shared_quantile_stack_independent(
    scratch, plan, 1L, "independent_exqdesn_rhs", d,
    rhs_vb_inner = vc$rhs_vb_inner, slab_fixed = vc$rhs_slab_fixed)
  joint_al_job <- plan[plan$model_id == "joint_qdesn_rhs", , drop = FALSE]
  joint_al <- app_joint_shared_quantile_joint_al_worker(scratch, joint_al_job, plan, d, vc)$fit
  app_joint_arch_save_fit(scratch, joint_al_job, joint_al)
  joint_exal_job <- plan[plan$model_id == "joint_exqdesn_rhs", , drop = FALSE]
  joint_exal <- app_joint_shared_quantile_joint_exal_worker(scratch, joint_exal_job, plan, d, vc)$fit
  list(gaussian = gaussian$fit, independent_al = independent_al,
    independent_exal = independent_exal, joint_al = joint_al, joint_exal = joint_exal)
}

app_joint_arch_recursive_qhat <- function(design, fixture, selected, fit) {
  beta <- as.numeric(fit$beta_mean); alpha <- as.numeric(fit$alpha_mean)
  snapshots <- app_joint_recursive_origin_snapshots(design, fixture, selected)
  out <- matrix(NA_real_, nrow = nrow(design$forecast_map), ncol = length(design$tau))
  for (origin_pos in seq_along(snapshots$origin_index)) {
    origin <- snapshots$origin_index[[origin_pos]]
    map_rows <- which(design$forecast_map$origin_index == origin)
    states <- snapshots$states[[origin_pos]]
    history <- fixture$y[seq_len(snapshots$origin_full_time_index[[origin_pos]])]
    for (row_index in map_rows) {
      tt <- design$forecast_map$full_time_index[[row_index]]
      raw <- app_joint_recursive_feature_from_history(tt, history, design)
      step <- app_joint_recursive_readout_row(raw, states, design, snapshots$reservoir_meta)
      states <- step$states
      q <- app_joint_recursive_predict_vector(step$z, beta, alpha, design$tau)
      out[row_index, ] <- q
      history[[tt]] <- app_joint_recursive_contract_vector(q, design$tau)[which.min(abs(design$tau - .5))]
    }
  }
  if (any(!is.finite(out))) stop("Recursive quantile-VB path is incomplete.", call. = FALSE)
  colnames(out) <- paste0("tau_", format(design$tau, trim = TRUE))
  out
}

app_joint_arch_vb_worker <- function(root, dataset_id) {
  app_joint_arch_verify_freeze(root)
  plan <- app_read_csv(file.path(root, "vb", "datasets.csv"))
  row <- plan[plan$dataset_id == dataset_id, , drop = FALSE]
  if (nrow(row) != 1L) stop("VB dataset identifier is invalid.", call. = FALSE)
  folder <- file.path(root, "vb", "workers", sprintf("worker_%03d", dataset_id))
  if (app_joint_arch_done(folder)) return(invisible(folder))
  if (dir.exists(folder)) stop("Incomplete VB worker directory already exists.", call. = FALSE)
  app_ensure_dir(folder); scratch <- tempfile("joint_arch_vb_")
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
  started <- Sys.time(); context <- app_joint_arch_internal_context(root, row)
  fits <- app_joint_arch_nested_vb(context, scratch)
  model_fits <- list(
    independent_qdesn_rhs = fits$independent_al,
    joint_qdesn_rhs = fits$joint_al,
    independent_exqdesn_rhs = fits$independent_exal,
    joint_exqdesn_rhs = fits$joint_exal
  )
  scores <- predictions <- health <- list()
  for (model in names(model_fits)) {
    fit <- model_fits[[model]]; d <- context$design
    forecast <- app_joint_arch_recursive_qhat(d, context$fixture, context$selected, fit)
    fit_q <- app_joint_qdesn_predict_fit(fit, d$Z[d$fit_local, , drop = FALSE], d$tau)
    scores[[length(scores) + 1L]] <- app_joint_shared_quantile_window_score(
      d, fit_q, d$fit_local, model, row$replicate_id[[1L]], "fit")
    scores[[length(scores) + 1L]] <- app_joint_shared_quantile_window_score(
      d, forecast, d$score_local, model, row$replicate_id[[1L]], "forecast")
    frame <- as.data.frame(forecast)
    names(frame) <- paste0("q_", seq_along(d$tau))
    frame <- cbind(data.frame(model_id = model, origin_index = d$forecast_map$origin_index,
      horizon = d$forecast_map$horizon, full_time_index = d$forecast_map$full_time_index), frame)
    predictions[[length(predictions) + 1L]] <- frame
    health[[length(health) + 1L]] <- data.frame(model_id = model,
      converged = isTRUE(fit$converged), iterations = fit$iterations_completed %||% fit$iterations %||% NA_integer_,
      inference_method_id = fit$inference_method_id %||% if (grepl("exq", model)) context$ct$exal_vb_method else "AL_joint_cavi",
      finite = all(is.finite(c(fit$beta_mean, fit$alpha_mean))), stringsAsFactors = FALSE)
  }
  score <- app_joint_qdesn_bind_rows(scores)
  score$architecture_id <- row$architecture_id[[1L]]; score$dataset_id <- dataset_id
  score$baseline <- row$baseline[[1L]]
  pred <- app_joint_qdesn_bind_rows(predictions)
  paths <- c(
    scores = app_write_csv(score, file.path(folder, "scores.csv")),
    predictions = app_write_csv(pred, file.path(folder, "recursive_forecast_quantiles.csv")),
    vb_health = app_write_csv(app_joint_qdesn_bind_rows(health), file.path(folder, "vb_health.csv")),
    design_diagnostic = app_write_csv(context$design$diagnostic, file.path(folder, "design_diagnostic.csv")),
    metadata = app_write_csv(cbind(row, data.frame(
      design_fingerprint = context$design$design_fingerprint %||% digest::digest(context$design$Z, algo = "sha256"),
      data_hash = context$data_hash,
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE)), file.path(folder, "metadata.csv"))
  )
  app_joint_shared_write_manifest(folder, paths)
  writeLines("VERIFIED", file.path(folder, "DONE"))
  if (!app_joint_arch_done(folder)) stop("VB worker manifest did not verify.", call. = FALSE)
  invisible(folder)
}

app_joint_arch_vb_collect <- function(root) {
  plan <- app_read_csv(file.path(root, "vb", "datasets.csv"))
  folders <- file.path(root, "vb", "workers", sprintf("worker_%03d", plan$dataset_id))
  if (!all(vapply(folders, app_joint_arch_done, logical(1L)))) stop("VB selection requires all verified workers.", call. = FALSE)
  scores <- app_joint_qdesn_bind_rows(lapply(folders, function(path) app_read_csv(file.path(path, "scores.csv"))))
  forecast <- scores[scores$window == "forecast", , drop = FALSE]
  if (nrow(forecast) != nrow(plan) * 4L || any(!is.finite(forecast$dgp_integrated_acrps)) ||
      any(forecast$contract_crossing_pairs != 0L)) stop("VB score packet is incomplete or invalid.", call. = FALSE)
  forecast
}

app_joint_arch_rank <- function(rows, baseline_id, replicate_count, score_name) {
  groups <- split(rows, paste(rows$architecture_id, rows$model_id, sep = "::"))
  agg <- app_joint_qdesn_bind_rows(lapply(groups, function(x) data.frame(
    architecture_id = x$architecture_id[[1L]], model_id = x$model_id[[1L]],
    replicates = nrow(x), score_mean = mean(x[[score_name]]),
    score_sd = stats::sd(x[[score_name]]),
    raw_crossing_pairs = sum(x$raw_crossing_pairs %||% 0L),
    contract_crossing_pairs = sum(x$contract_crossing_pairs %||% 0L),
    stringsAsFactors = FALSE)))
  if (any(agg$replicates != replicate_count) || any(!is.finite(agg$score_mean))) {
    stop("Matched architecture score aggregates are incomplete.", call. = FALSE)
  }
  baseline <- agg[agg$architecture_id == baseline_id, c("model_id", "score_mean")]
  names(baseline)[[2L]] <- "baseline_score_mean"
  agg <- merge(agg, baseline, by = "model_id", all.x = TRUE, sort = FALSE)
  agg$relative_score <- agg$score_mean / agg$baseline_score_mean
  ids <- unique(agg$architecture_id)
  decision <- app_joint_qdesn_bind_rows(lapply(ids, function(id) {
    x <- agg[agg$architecture_id == id, , drop = FALSE]
    get <- function(model) x$relative_score[x$model_id == model]
    joint_al <- get("joint_qdesn_rhs"); joint_exal <- get("joint_exqdesn_rhs")
    balanced <- mean(x$relative_score)
    data.frame(architecture_id = id, joint_al_relative_score = joint_al,
      joint_exal_relative_score = joint_exal,
      joint_relative_score_mean = mean(c(joint_al, joint_exal)),
      four_model_relative_score_mean = balanced,
      both_joint_improve = joint_al < 1 && joint_exal < 1,
      four_model_improves = balanced < 1,
      eligible = id != baseline_id && joint_al < 1 && joint_exal < 1 && balanced < 1,
      stringsAsFactors = FALSE)
  }))
  list(model_aggregate = agg, decision = decision)
}

app_joint_arch_write_selection_manifest <- function(root, stage, files) {
  directory <- file.path(root, stage)
  app_write_csv(data.frame(relative_path = files,
    sha256 = vapply(file.path(directory, files), app_sha256_file, character(1L))),
    file.path(directory, "selection_manifest.csv"))
  writeLines("FROZEN_BEFORE_FRESH_SEED_NEXT_STAGE", file.path(directory, "SELECTION_FROZEN"))
}

app_joint_arch_verify_selection <- function(root, stage) {
  path <- file.path(root, stage, "selection_manifest.csv")
  tab <- app_read_csv(path)
  observed <- vapply(file.path(root, stage, tab$relative_path), app_sha256_file, character(1L))
  if (!identical(unname(observed), as.character(tab$sha256))) stop(sprintf("%s selection receipt changed.", stage), call. = FALSE)
  invisible(TRUE)
}

app_joint_arch_select_vb <- function(root) {
  app_joint_arch_verify_freeze(root); ct <- readRDS(file.path(root, "contract.rds"))
  architectures <- app_read_csv(file.path(root, "architectures.csv"))
  baseline <- architectures$architecture_id[app_as_bool_vec(architectures$baseline)]
  rows <- app_joint_arch_vb_collect(root)
  ranked <- app_joint_arch_rank(rows, baseline, ct$vb_replicates, "dgp_integrated_acrps")
  eligible <- ranked$decision[app_as_bool_vec(ranked$decision$eligible), , drop = FALSE]
  challengers <- character()
  if (nrow(eligible)) {
    balanced <- eligible$architecture_id[which.min(eligible$four_model_relative_score_mean)]
    joint <- eligible$architecture_id[which.min(eligible$joint_relative_score_mean)]
    challengers <- head(unique(c(balanced, joint)), as.integer(ct$max_mcmc_challengers))
  }
  selection <- data.frame(
    stage = "quantile_vb_internal_selection", baseline_architecture_id = baseline,
    challenger_architecture_id = challengers,
    selection_rank = seq_along(challengers),
    status = if (length(challengers)) "MCMC_SCREEN_CHALLENGERS_FROZEN" else "NO_ELIGIBLE_CHALLENGER_STOP",
    stringsAsFactors = FALSE
  )
  if (!length(challengers)) selection <- data.frame(stage = "quantile_vb_internal_selection",
    baseline_architecture_id = baseline, challenger_architecture_id = NA_character_,
    selection_rank = NA_integer_, status = "NO_ELIGIBLE_CHALLENGER_STOP", stringsAsFactors = FALSE)
  app_write_csv(rows, file.path(root, "vb", "complete_scores.csv"))
  app_write_csv(ranked$model_aggregate, file.path(root, "vb", "model_aggregate.csv"))
  app_write_csv(ranked$decision, file.path(root, "vb", "architecture_decisions.csv"))
  app_write_csv(selection, file.path(root, "vb", "selection.csv"))
  app_joint_arch_write_selection_manifest(root, "vb", c("complete_scores.csv", "model_aggregate.csv",
    "architecture_decisions.csv", "selection.csv"))
  if (length(challengers)) app_joint_arch_stage_prepare(root, "screen", c(baseline, challengers))
  invisible(selection)
}

app_joint_arch_stage_prepare <- function(root, stage = c("screen", "confirmation"), architecture_ids) {
  stage <- match.arg(stage); app_joint_arch_verify_freeze(root)
  if (stage == "screen") app_joint_arch_verify_selection(root, "vb") else app_joint_arch_verify_selection(root, "screen")
  ct <- readRDS(file.path(root, "contract.rds")); architectures <- app_read_csv(file.path(root, "architectures.csv"))
  architecture_ids <- unique(as.character(architecture_ids))
  if (!all(architecture_ids %in% architectures$architecture_id)) stop("Stage architecture set is invalid.", call. = FALSE)
  destination <- file.path(root, stage)
  if (dir.exists(destination)) stop("Stage already prepared.", call. = FALSE)
  app_ensure_dir(destination)
  n_rep <- as.integer(ct[[paste0(stage, "_replicates")]])
  datasets <- expand.grid(architecture_id = architecture_ids, replicate_id = seq_len(n_rep), stringsAsFactors = FALSE)
  datasets <- datasets[order(datasets$architecture_id, datasets$replicate_id), , drop = FALSE]
  datasets$dataset_id <- seq_len(nrow(datasets))
  offset <- if (stage == "screen") 0L else 1000000L
  datasets$dgp_seed <- as.integer(ct[[paste0(stage, "_seed_base")]] + datasets$dataset_id * 100L)
  models <- data.frame(model_id = c("independent_qdesn_rhs", "joint_qdesn_rhs",
      "independent_exqdesn_rhs", "joint_exqdesn_rhs"),
    likelihood = c("AL", "AL", "exAL", "exAL"),
    structure = c("independent", "joint", "independent", "joint"), stringsAsFactors = FALSE)
  cells <- merge(datasets, models, by = NULL)
  cells <- cells[order(cells$dataset_id, cells$model_id), , drop = FALSE]
  cells$arm_id <- cells$architecture_id; cells$long_budget <- FALSE; cells$cell_id <- seq_len(nrow(cells))
  chains_n <- as.integer(ct[[paste0(stage, "_chains")]])
  chains <- cells[rep(seq_len(nrow(cells)), each = chains_n), , drop = FALSE]
  chains$chain_id <- rep(seq_len(chains_n), nrow(cells)); chains$worker_id <- seq_len(nrow(chains))
  chains$chain_seed <- as.integer(ct$chain_seed_base + offset + chains$worker_id * 1009L)
  chains$start_seed <- as.integer(ct$initialization_seed_base + offset + chains$worker_id * 1009L)
  warmups <- datasets; warmups$arm_id <- warmups$architecture_id; warmups$worker_id <- seq_len(nrow(warmups))
  app_write_csv(datasets, file.path(destination, "datasets.csv"))
  app_write_csv(cells, file.path(destination, "cells.csv"))
  app_write_csv(chains, file.path(destination, "chains.csv"))
  app_write_csv(warmups, file.path(destination, "warmups.csv"))
  paths <- list.files(destination, full.names = TRUE)
  app_joint_shared_write_manifest(destination, setNames(paths, basename(paths)))
  stopifnot(file.rename(file.path(destination, "artifact_manifest.csv"), file.path(destination, "plan_manifest.csv")))
  invisible(list(datasets = datasets, cells = cells, chains = chains, warmups = warmups))
}

app_joint_arch_full_design <- function(fixture, selected) {
  keep <- fixture$detailed_split$role %in% c("desn_washout", "fit", "validation")
  full_fixture <- list(
    scenario_id = fixture$scenario_id, y = fixture$y[keep],
    true_q = fixture$true_q[keep, , drop = FALSE], tau = fixture$tau,
    detailed_split = fixture$detailed_split[keep, , drop = FALSE],
    registry_row = fixture$registry_row, seed = fixture$seed,
    seed_role = fixture$seed_role, y_history = fixture$y
  )
  design <- app_joint_pure_build_design(full_fixture, selected, list(
    inner_training_rows = sum(full_fixture$detailed_split$role == "fit"),
    fit_rows = sum(full_fixture$detailed_split$role == "fit"),
    max_readout_dimension = 300L
  ), selector = FALSE)
  design$validation_local <- which(design$row_meta$role == "validation")
  origins <- app_joint_qdesn_forecast_origin_plan_rows(fixture)
  design$forecast_map <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(origins)), function(ii) {
    row <- origins[ii, , drop = FALSE]
    full <- seq.int(row$target_start_full_time_index[[1L]], row$target_end_full_time_index[[1L]])
    data.frame(origin_index = row$origin_index[[1L]], horizon = seq_along(full),
      full_time_index = full, stringsAsFactors = FALSE)
  }))
  design$score_local <- match(design$forecast_map$full_time_index,
    design$row_meta$full_time_index)
  if (anyNA(design$score_local) || any(!design$score_local %in% design$validation_local)) {
    stop("Architecture forecast map is malformed.", call. = FALSE)
  }
  design$mu <- fixture$mu[keep]; design$sigma <- fixture$sigma[keep]
  design$design_fingerprint <- app_joint_qvp_sha256_text(paste(
    selected$architecture_signature[[1L]], paste(colnames(design$Z), collapse = ";"),
    paste(format(design$Z[design$fit_local, , drop = FALSE], digits = 16), collapse = ";"), sep = "|"))
  design$posterior_data_design_fingerprint <- app_joint_qvp_sha256_text(paste(
    "joint_qdesn_posterior_data_design_v1", paste(design$fit_local, collapse = ";"),
    paste(colnames(design$Z), collapse = ";"),
    paste(format(design$y[design$fit_local], digits = 17L, scientific = TRUE), collapse = ";"),
    paste(format(design$Z[design$fit_local, , drop = FALSE], digits = 17L,
      scientific = TRUE), collapse = ";"), sep = "|"))
  design
}

app_joint_arch_mcmc_context <- function(root, stage, dataset_id) {
  row <- app_read_csv(file.path(root, stage, "datasets.csv"))[dataset_id, , drop = FALSE]
  ct <- readRDS(file.path(root, "contract.rds")); selected <- app_joint_arch_selected(root, row$architecture_id)
  registry <- app_joint_qdesn_load_simulation_registry(); sc <- registry[registry$scenario_id == ct$scenario, , drop = FALSE]
  sc$seed <- as.integer(row$dgp_seed); sc$seed_role <- paste0("laplace_architecture_", stage)
  fixture <- app_joint_qdesn_fixture_from_registry_row(sc); fixture$registry_row <- sc
  design <- app_joint_arch_full_design(fixture, selected)
  vc <- app_joint_arch_vb_contract(ct); vc$max_dense_dim <- max(300L, ncol(design$Z) * length(design$tau))
  context <- list(ct = ct, vc = vc, selected = selected, design = design, fixture = fixture,
    data_hash = digest::digest(list(y = design$y[design$fit_local],
      Z = design$Z[design$fit_local, , drop = FALSE]), algo = "sha256"))
  scratch <- tempfile("joint_arch_mcmc_vb_"); on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
  fits <- app_joint_arch_nested_vb(context, scratch)
  context$gaussian <- fits$gaussian; context$independent_al <- fits$independent_al
  context$independent_exal <- fits$independent_exal
  context$joint <- list(AL = fits$joint_al, exAL = fits$joint_exal)
  context
}

app_joint_arch_dataset <- function(root, stage, dataset_id) {
  row <- app_read_csv(file.path(root, stage, "datasets.csv"))[dataset_id, , drop = FALSE]
  folder <- file.path(root, stage, "datasets", sprintf("dataset_%02d", dataset_id))
  app_ensure_dir(folder); context <- app_joint_arch_mcmc_context(root, stage, dataset_id)
  ct <- context$ct; shards <- character(); oracle <- NULL
  for (s in seq_len(ct$oracle_max_shards)) {
    path <- file.path(folder, sprintf("oracle_shard_%02d.rds", s))
    saveRDS(app_joint_recursive_dgp_shard(context$fixture, context$design$forecast_map,
      n_paths = ct$oracle_paths_per_shard, seed = as.integer(row$dgp_seed + 5000L + s)), path)
    shards <- c(shards, path)
    if (s %% 2L == 0L) {
      oracle <- app_joint_recursive_combine_oracle_shards(shards, context$fixture,
        ct$tau, ct$weights, ct$oracle_analytic_tolerance, ct$oracle_split_tolerance)
      if (oracle$diagnostics$status == "pass") break
    }
  }
  if (is.null(oracle) || oracle$diagnostics$status != "pass") stop("Oracle integration failed after all declared shards.", call. = FALSE)
  saveRDS(oracle, file.path(folder, "oracle.rds")); app_write_csv(oracle$diagnostics, file.path(folder, "oracle_diagnostics.csv"))
  saveRDS(context, file.path(folder, "context.rds"))
  app_joint_shared_write_manifest(folder, c(context = file.path(folder, "context.rds"),
    oracle = file.path(folder, "oracle.rds"), diagnostics = file.path(folder, "oracle_diagnostics.csv")),
    filename = "component_manifest.csv")
  app_joint_arch_seal(folder)
}

app_joint_arch_warmup <- function(root, stage, worker_id) {
  row <- app_read_csv(file.path(root, stage, "warmups.csv"))[worker_id, , drop = FALSE]
  context <- app_joint_prior_context(root, stage, row$dataset_id)
  folder <- file.path(root, stage, "warmups", sprintf("worker_%03d", worker_id)); app_ensure_dir(folder)
  saveRDS(context$joint, file.path(folder, "initializers.rds"))
  app_write_csv(data.frame(likelihood = c("AL", "exAL"),
    converged = vapply(context$joint, function(x) isTRUE(x$converged), logical(1L))), file.path(folder, "vb_health.csv"))
  app_joint_arch_seal(folder)
}

app_joint_arch_baseline_prior_arm <- function() data.frame(anchor_multiplier = 1,
  innovation_multiplier = 1, arm_id = "shared_baseline_prior", baseline = TRUE)

app_joint_arch_chain <- function(root, stage, worker_id) {
  ct <- readRDS(file.path(root, "contract.rds")); job <- app_read_csv(file.path(root, stage, "chains.csv"))[worker_id, , drop = FALSE]
  context <- app_joint_prior_context(root, stage, job$dataset_id)
  if (job$structure == "joint") {
    warmups <- app_read_csv(file.path(root, stage, "warmups.csv"))
    wid <- warmups$worker_id[warmups$dataset_id == job$dataset_id]
    directory <- file.path(root, stage, "warmups", sprintf("worker_%03d", wid))
    stopifnot(length(wid) == 1L, app_joint_arch_done(directory))
    context$initializer <- readRDS(file.path(directory, "initializers.rds"))[[job$likelihood]]
  }
  folder <- file.path(root, stage, "chains", sprintf("worker_%04d", worker_id)); app_ensure_dir(folder)
  started <- Sys.time(); result <- app_joint_prior_mcmc_fit(context,
    app_joint_arch_baseline_prior_arm(), job, ct, stage)
  draws <- app_joint_article_draw_frame(result$fit)
  app_joint_article_write_gzip_csv(draws, file.path(folder, "posterior_draws.csv.gz"))
  method <- if (job$likelihood == "exAL") ct$exal_mcmc_method else "AL_latent_GIG_Gibbs"
  if (job$likelihood == "exAL") {
    observed <- result$fit$component_method_ids %||% result$fit$inference_method_id
    if (!length(observed) || any(observed != method)) stop("An exAL component did not use exact M0.", call. = FALSE)
  }
  app_write_csv(cbind(job, data.frame(target_hash = result$target_hash, method = method,
    retained_draws = nrow(draws), iterations = result$iterations, burn = result$burn,
    thin = result$thin, runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")))),
    file.path(folder, "metadata.csv"))
  saveRDS(list(manifest = result$fit$manifest, diagnostics = result$fit$precision_repair_diagnostics,
    components = result$fit$precision_components), file.path(folder, "precision_diagnostics.rds"))
  app_joint_arch_seal(folder)
}

app_joint_arch_mcmc_select <- function(root) {
  app_joint_arch_verify_freeze(root); app_joint_arch_verify_selection(root, "vb")
  ct <- readRDS(file.path(root, "contract.rds")); rows <- app_joint_prior_collect(root, "screen")
  rows$model_id <- ifelse(rows$structure == "joint", ifelse(rows$likelihood == "AL",
    "joint_qdesn_rhs", "joint_exqdesn_rhs"), ifelse(rows$likelihood == "AL",
      "independent_qdesn_rhs", "independent_exqdesn_rhs"))
  rows$architecture_id <- rows$arm_id
  baseline <- unique(rows$architecture_id[rows$baseline %||% FALSE])
  if (!length(baseline)) baseline <- app_read_csv(file.path(root, "vb", "selection.csv"))$baseline_architecture_id[[1L]]
  ranked <- app_joint_arch_rank(rows, baseline, ct$screen_replicates, "posterior_score_mean")
  eligible <- ranked$decision[app_as_bool_vec(ranked$decision$eligible), , drop = FALSE]
  selected <- if (nrow(eligible)) eligible$architecture_id[which.min(eligible$four_model_relative_score_mean)] else NA_character_
  selection <- data.frame(stage = "fresh_seed_mcmc_screen", baseline_architecture_id = baseline,
    selected_architecture_id = selected,
    status = if (is.na(selected)) "NO_MCMC_CONFIRMED_CHALLENGER_STOP" else "CONFIRMATION_CHALLENGER_FROZEN",
    mixing_policy = ct$mixing_gate_policy, stringsAsFactors = FALSE)
  app_write_csv(rows, file.path(root, "screen", "complete_scores.csv"))
  app_write_csv(ranked$model_aggregate, file.path(root, "screen", "model_aggregate.csv"))
  app_write_csv(ranked$decision, file.path(root, "screen", "architecture_decisions.csv"))
  app_write_csv(selection, file.path(root, "screen", "selection.csv"))
  app_joint_arch_write_selection_manifest(root, "screen", c("complete_scores.csv", "model_aggregate.csv",
    "architecture_decisions.csv", "selection.csv"))
  if (!is.na(selected)) app_joint_arch_stage_prepare(root, "confirmation", c(baseline, selected))
  invisible(selection)
}

app_joint_arch_finalize <- function(root) {
  app_joint_arch_verify_freeze(root); app_joint_arch_verify_selection(root, "screen")
  ct <- readRDS(file.path(root, "contract.rds")); selection <- app_read_csv(file.path(root, "screen", "selection.csv"))
  if (selection$status[[1L]] == "NO_MCMC_CONFIRMED_CHALLENGER_STOP") {
    writeLines("COMPLETE_NO_MCMC_CONFIRMED_ARCHITECTURE_CHALLENGER", file.path(root, "COMPLETE")); return(invisible(root))
  }
  rows <- app_joint_prior_collect(root, "confirmation")
  rows$model_id <- ifelse(rows$structure == "joint", ifelse(rows$likelihood == "AL",
    "joint_qdesn_rhs", "joint_exqdesn_rhs"), ifelse(rows$likelihood == "AL",
      "independent_qdesn_rhs", "independent_exqdesn_rhs"))
  rows$architecture_id <- rows$arm_id
  baseline <- selection$baseline_architecture_id[[1L]]; candidate <- selection$selected_architecture_id[[1L]]
  ranked <- app_joint_arch_rank(rows, baseline, ct$confirmation_replicates, "posterior_score_mean")
  decision <- ranked$decision[ranked$decision$architecture_id == candidate, , drop = FALSE]
  decision$promotion_decision <- if (isTRUE(decision$eligible[[1L]])) {
    "numerical_mean_improvement_ready_for_integration_review"
  } else "retain_current_backbone"
  decision$claim <- "fresh_seed_descriptive_evidence_not_article_fixture_supersession"
  decision$mixing_is_hard_gate <- FALSE
  packet <- file.path(root, "closeout"); app_ensure_dir(packet)
  app_write_csv(rows, file.path(packet, "confirmation_scores.csv"))
  app_write_csv(ranked$model_aggregate, file.path(packet, "confirmation_model_aggregate.csv"))
  app_write_csv(decision, file.path(packet, "decision.csv"))
  app_write_csv(app_read_csv(file.path(root, "architectures.csv")), file.path(packet, "frozen_architectures.csv"))
  grDevices::pdf(file.path(packet, "laplace_architecture_comparison.pdf"), width = 11, height = 7)
  on.exit(grDevices::dev.off(), add = TRUE)
  plot_rows <- rows[order(rows$model_id, rows$architecture_id, rows$replicate_id), ]
  labels <- paste(plot_rows$model_id, plot_rows$architecture_id, "rep", plot_rows$replicate_id)
  graphics::par(mar = c(5, 15, 4, 2))
  graphics::plot(plot_rows$posterior_score_mean, seq_len(nrow(plot_rows)), yaxt = "n",
    xlab = "DGP-integrated finite-grid score (lower is better)", ylab = "",
    main = "Laplace Bridge: fresh-seed architecture confirmation", pch = 19,
    xlim = range(plot_rows$posterior_score_q025, plot_rows$posterior_score_q975))
  graphics::segments(plot_rows$posterior_score_q025, seq_len(nrow(plot_rows)),
    plot_rows$posterior_score_q975, seq_len(nrow(plot_rows)))
  graphics::axis(2, at = seq_len(nrow(plot_rows)), labels = labels, las = 1, cex.axis = .65)
  grDevices::dev.off(); on.exit(NULL)
  app_joint_arch_seal(packet)
  writeLines("COMPLETE_READY_FOR_SCIENTIFIC_INTEGRATION_REVIEW", file.path(root, "COMPLETE"))
  invisible(root)
}

app_joint_arch_health <- function(root) {
  rows <- list()
  vb <- file.path(root, "vb", "datasets.csv")
  if (file.exists(vb)) {
    plan <- app_read_csv(vb); folders <- file.path(root, "vb", "workers", sprintf("worker_%03d", plan$dataset_id))
    rows[[length(rows) + 1L]] <- data.frame(stage = "vb", kind = "datasets", expected = nrow(plan),
      complete = sum(vapply(folders, app_joint_arch_done, logical(1L))),
      failed = sum(file.exists(file.path(folders, "FAILED"))), stringsAsFactors = FALSE)
  }
  for (stage in c("screen", "confirmation")) for (kind in c("datasets", "warmups", "chains", "cells")) {
    plan_path <- file.path(root, stage, paste0(kind, ".csv")); if (!file.exists(plan_path)) next
    plan <- app_read_csv(plan_path); width <- switch(kind, datasets = 2L, warmups = 3L, chains = 4L, cells = 4L)
    prefix <- if (kind == "datasets") "dataset_" else if (kind == "cells") "cell_" else "worker_"
    folder_kind <- if (kind == "cells") "scores" else kind
    folders <- file.path(root, stage, folder_kind, sprintf(paste0(prefix, "%0", width, "d"), seq_len(nrow(plan))))
    rows[[length(rows) + 1L]] <- data.frame(stage = stage, kind = kind, expected = nrow(plan),
      complete = sum(vapply(folders, app_joint_arch_done, logical(1L))),
      failed = sum(file.exists(file.path(folders, "FAILED"))), stringsAsFactors = FALSE)
  }
  out <- if (length(rows)) app_joint_qdesn_bind_rows(rows) else data.frame()
  if (nrow(out)) out$remaining <- out$expected - out$complete
  out
}
