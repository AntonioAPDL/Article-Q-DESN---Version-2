# Fit-first continuation for the frozen persistent-heavy-tail V3 shortlist.

app_joint_phtff_contract_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_fit_first_contract.csv")
}

app_joint_phtff_default_root <- function() {
  app_path("application/cache/joint_qdesn_persistent_tail_fit_first_20261125")
}

app_joint_phtff_value <- function(tab, name) {
  row <- tab[tab$name == name, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("Fit-first contract requires one '%s'.", name), call. = FALSE)
  as.character(row$value[[1L]])
}

app_joint_phtff_read_contract <- function(path = app_joint_phtff_contract_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "persistent-tail fit-first contract")
  if (anyDuplicated(tab$name)) stop("Fit-first contract fields must be unique.", call. = FALSE)
  value <- function(name) app_joint_phtff_value(tab, name)
  number <- function(name) as.numeric(value(name))
  integer <- function(name) as.integer(number(name))
  bool <- function(name) identical(tolower(value(name)), "true")
  intvec <- function(name) as.integer(strsplit(value(name), ";", fixed = TRUE)[[1L]])
  out <- list(
    table = tab,
    version = value("contract_version"), run_tag = value("run_tag"),
    parent_branch = value("parent_branch"), parent_head = value("parent_head"),
    source_runtime_head = value("source_runtime_head"),
    source_run_tag = value("source_run_tag"), scenario_id = value("scenario_id"),
    source_candidate_count = integer("source_candidate_count"),
    fresh_replicates = integer("fresh_replicates"),
    fresh_seed_offset = integer("fresh_seed_offset"),
    full_origins = intvec("full_origin_indices"),
    shards_per_fixture = integer("shards_per_fixture"),
    paths_per_shard = integer("paths_per_shard"),
    analytic_tolerance = number("analytic_tolerance"),
    split_half_tolerance = number("split_half_tolerance"),
    fit_relative_margin = number("fit_relative_margin"),
    fit_absolute_margin = number("fit_absolute_margin"),
    h1_relative_margin = number("h1_relative_margin"),
    h1_absolute_margin = number("h1_absolute_margin"),
    tail_relative_margin = number("tail_relative_margin"),
    tail_absolute_margin = number("tail_absolute_margin"),
    forecast_near_tie_relative_margin = number("forecast_near_tie_relative_margin"),
    forecast_near_tie_absolute_margin = number("forecast_near_tie_absolute_margin"),
    short_horizon_relative_guard = number("short_horizon_relative_guard"),
    minimum_fit_eligible_candidates = integer("minimum_fit_eligible_candidates"),
    protected_selection_forbidden = bool("protected_selection_forbidden"),
    article_fixture_materialization_forbidden = bool("article_fixture_materialization_forbidden"),
    require_finite_outputs = bool("require_finite_outputs"),
    require_zero_contract_crossings = bool("require_zero_contract_crossings"),
    require_recursive_state_finite = bool("require_recursive_state_finite"),
    require_verified_source_manifests = bool("require_verified_source_manifests"),
    required_hostname = value("required_hostname"),
    max_physical_workers = integer("max_physical_workers"),
    min_data_free_gib = number("min_data_free_gib"),
    min_available_memory_gib = number("min_available_memory_gib"),
    automatic_downstream_launch = bool("automatic_downstream_launch")
  )
  valid <- identical(out$version, "joint_qdesn_persistent_tail_fit_first_v1") &&
    identical(out$scenario_id, "persistent_heavy_tail") &&
    identical(out$full_origins, seq_len(10L)) &&
    out$source_candidate_count == 10L && out$fresh_replicates >= 3L &&
    out$shards_per_fixture >= 2L && out$paths_per_shard >= 1000L &&
    out$protected_selection_forbidden && out$article_fixture_materialization_forbidden &&
    !out$automatic_downstream_launch && out$max_physical_workers <= 30L
  if (!valid) stop("Persistent-tail fit-first contract is malformed.", call. = FALSE)
  out
}

app_joint_phtff_verify_source <- function(source_root, contract = app_joint_phtff_read_contract()) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  required <- c("frozen_contract.csv", "frozen_registry.csv", "derived_dgp_registry.csv",
    "tail_al_worker_plan.csv", "tail_sentinel_manifest.csv", "sealed_full7_manifest.csv",
    "sealed_full7_decision.csv", "source_git_state.csv")
  missing <- required[!file.exists(file.path(source_root, required))]
  if (length(missing)) stop(sprintf("Frozen V3 source is incomplete: %s",
    paste(missing, collapse = ", ")), call. = FALSE)
  for (manifest in c("tail_sentinel_manifest.csv", "sealed_full7_manifest.csv")) {
    verified <- app_joint_shared_verify_manifest(source_root, file.path(source_root, manifest))
    if (!nrow(verified) || any(!verified$verified)) {
      stop(sprintf("Frozen V3 source manifest failed: %s", manifest), call. = FALSE)
    }
  }
  git_state <- app_read_csv(file.path(source_root, "source_git_state.csv"))
  head_fields <- intersect(c("git_head", "head", "commit"), names(git_state))
  if (!length(head_fields) ||
      !any(as.character(git_state[[head_fields[[1L]]]]) == contract$source_runtime_head)) {
    stop("Frozen V3 source HEAD does not match the fit-first parent pin.", call. = FALSE)
  }
  decision <- app_read_csv(file.path(source_root, "sealed_full7_decision.csv"))
  if (nrow(decision) != 1L || !grepl("^SEALED_Q3_COMPLETE_", decision$status[[1L]])) {
    stop("Frozen V3 terminal decision is not complete.", call. = FALSE)
  }
  invisible(source_root)
}

app_joint_phtff_source_candidates <- function(source_root,
    contract = app_joint_phtff_read_contract()) {
  app_joint_phtff_verify_source(source_root, contract)
  plan <- app_read_csv(file.path(source_root, "tail_al_worker_plan.csv"))
  plan <- plan[order(plan$candidate_id, plan$replicate_id, plan$tau), , drop = FALSE]
  candidates <- plan[!duplicated(plan$candidate_id), , drop = FALSE]
  if (nrow(candidates) != contract$source_candidate_count) {
    stop("Frozen V3 tail shortlist cardinality changed.", call. = FALSE)
  }
  candidates$fit_first_role <- "v3_tail_shortlist"
  candidates$fit_first_role[which(!is.na(candidates$source_candidate_id) &
    candidates$source_candidate_id ==
      "persistent_heavy_tail__targeted_0209")] <- "exact_v2_fallback"
  candidates$fit_first_role[which(!is.na(candidates$source_candidate_id) &
    candidates$source_candidate_id ==
      "persistent_heavy_tail__targeted_0001")] <- "exact_historical_authority"
  runtime_fields <- c("replicate_id", "dgp_seed", "fixture_path", "median_tau",
    "origin_indices", "median_worker_id", "tau", "m1_worker_id", "tail_worker_id")
  candidates <- candidates[, setdiff(names(candidates), runtime_fields), drop = FALSE]
  candidates$source_runtime_root <- normalizePath(source_root, mustWork = TRUE)
  candidates[, c("candidate_id", "fit_first_role",
    setdiff(names(candidates), c("candidate_id", "fit_first_role"))), drop = FALSE]
}

app_joint_phtff_fixture_row <- function(sc, registry, contract, replicate_id, root) {
  row <- sc
  row$seed <- as.integer(registry$selector_seed_base[[1L]]) +
    contract$fresh_seed_offset + as.integer(replicate_id) - 1L
  row$seed_role <- sprintf("persistent_tail_fit_first_rep%02d", replicate_id)
  fixture <- app_joint_qdesn_fixture_from_registry_row(row)
  fixture$registry_row <- row
  selector <- app_joint_pure_selector_fixture(fixture,
    app_joint_sw_read_contract(file.path(root, "frozen_contract.csv")))
  path <- file.path(root, "fixtures", sprintf("fit_first_rep%02d.rds", replicate_id))
  saveRDS(selector, path, version = 3L, compress = "xz")
  oracle_end <- length(selector$y_history)
  oracle_fixture <- list(
    scenario_id = fixture$scenario_id,
    y = fixture$y[seq_len(oracle_end)],
    mu = fixture$mu[seq_len(oracle_end)],
    sigma = fixture$sigma[seq_len(oracle_end)],
    registry_row = row,
    seed = fixture$seed,
    seed_role = fixture$seed_role,
    protected_rows_persisted = 0L)
  if (any(vapply(oracle_fixture[c("y", "mu", "sigma")], length, integer(1L)) !=
      oracle_end) || any(!is.finite(c(oracle_fixture$y, oracle_fixture$mu,
        oracle_fixture$sigma))) || any(oracle_fixture$sigma <= 0)) {
    stop("Fit-first oracle-only fixture is malformed.", call. = FALSE)
  }
  oracle_path <- file.path(root, "fixtures",
    sprintf("fit_first_oracle_rep%02d.rds", replicate_id))
  saveRDS(oracle_fixture, oracle_path, version = 3L, compress = "xz")
  data.frame(scenario_id = contract$scenario_id, replicate_id = replicate_id,
    dgp_seed = row$seed[[1L]], seed_role = row$seed_role[[1L]],
    fixture_path = normalizePath(path, mustWork = TRUE),
    size_bytes = file.info(path)$size, sha256 = app_sha256_file(path),
    oracle_fixture_path = normalizePath(oracle_path, mustWork = TRUE),
    oracle_size_bytes = file.info(oracle_path)$size,
    oracle_sha256 = app_sha256_file(oracle_path),
    protected_rows_persisted = selector$protected_rows_persisted,
    article_fixture = FALSE, stringsAsFactors = FALSE)
}

app_joint_phtff_forecast_map <- function(design, base_contract) {
  blocks <- app_joint_sw_origin_rows(design, base_contract$full_origins,
    base_contract$calibration_max_lead)
  data.frame(
    full_time_index = unlist(lapply(blocks,
      function(index) design$row_meta$full_time_index[index]), use.names = FALSE),
    origin_index = rep(base_contract$full_origins, lengths(blocks)),
    horizon = unlist(lapply(blocks, seq_along), use.names = FALSE),
    stringsAsFactors = FALSE)
}

app_joint_phtff_prepare <- function(source_root, root = app_joint_phtff_default_root()) {
  contract <- app_joint_phtff_read_contract()
  source_root <- app_joint_phtff_verify_source(source_root, contract)
  root <- normalizePath(root, mustWork = FALSE)
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty fit-first root.", call. = FALSE)
  }
  app_ensure_dir(root); app_ensure_dir(file.path(root, "fixtures"))
  app_ensure_dir(file.path(root, "workers"))
  file.copy(file.path(source_root, "frozen_contract.csv"),
    file.path(root, "frozen_contract.csv"), overwrite = FALSE)
  registry <- app_read_csv(file.path(source_root, "frozen_registry.csv"))
  derived <- app_read_csv(file.path(source_root, "derived_dgp_registry.csv"))
  sc <- derived[derived$scenario_id == contract$scenario_id, , drop = FALSE]
  if (nrow(sc) != 1L || nrow(registry) != 1L) stop("Fit-first DGP source is malformed.", call. = FALSE)
  candidates <- app_joint_phtff_source_candidates(source_root, contract)
  fixtures <- app_bind_rows_fill(lapply(seq_len(contract$fresh_replicates), function(rep) {
    app_joint_phtff_fixture_row(sc, registry, contract, rep, root)
  }))
  fit_plan <- merge(candidates, fixtures[, c("scenario_id", "replicate_id", "dgp_seed",
    "fixture_path", "oracle_fixture_path")], by = "scenario_id", all = TRUE, sort = FALSE)
  fit_plan$job_type <- "fit"
  fit_plan$oracle_shard_id <- NA_integer_
  fit_plan$oracle_seed <- NA_integer_
  oracle_plan <- fixtures[rep(seq_len(nrow(fixtures)), each = contract$shards_per_fixture),
    c("scenario_id", "replicate_id", "dgp_seed", "fixture_path", "oracle_fixture_path"),
    drop = FALSE]
  oracle_plan$job_type <- "oracle"
  oracle_plan$oracle_shard_id <- rep(seq_len(contract$shards_per_fixture),
    times = nrow(fixtures))
  oracle_plan$oracle_seed <- as.integer(611250000L + oracle_plan$replicate_id * 100000L +
    oracle_plan$oracle_shard_id * 1009L)
  template <- candidates[rep(1L, nrow(oracle_plan)), , drop = FALSE]
  common <- intersect(names(template), names(oracle_plan))
  template[, common] <- oracle_plan[, common]
  template$job_type <- oracle_plan$job_type
  template$replicate_id <- oracle_plan$replicate_id
  template$dgp_seed <- oracle_plan$dgp_seed
  template$fixture_path <- oracle_plan$fixture_path
  template$oracle_fixture_path <- oracle_plan$oracle_fixture_path
  template$oracle_shard_id <- oracle_plan$oracle_shard_id
  template$oracle_seed <- oracle_plan$oracle_seed
  jobs <- app_bind_rows_fill(list(template, fit_plan))
  jobs$worker_id <- seq_len(nrow(jobs))
  jobs <- jobs[, c("worker_id", "job_type", setdiff(names(jobs), c("worker_id", "job_type"))),
    drop = FALSE]
  expected_oracle <- contract$fresh_replicates * contract$shards_per_fixture
  expected_fit <- contract$fresh_replicates * contract$source_candidate_count
  if (nrow(jobs) != expected_oracle + expected_fit || anyNA(jobs$fixture_path) ||
      any(fixtures$protected_rows_persisted != 0L) || any(fixtures$article_fixture)) {
    stop("Fit-first preparation violates its frozen cardinality or protection contract.",
      call. = FALSE)
  }
  source_receipt <- data.frame(
    source_root = source_root,
    source_branch_head = contract$parent_head,
    source_runtime_head = contract$source_runtime_head,
    tail_manifest_sha256 = app_sha256_file(file.path(source_root, "tail_sentinel_manifest.csv")),
    q3_manifest_sha256 = app_sha256_file(file.path(source_root, "sealed_full7_manifest.csv")),
    tail_plan_sha256 = app_sha256_file(file.path(source_root, "tail_al_worker_plan.csv")),
    stringsAsFactors = FALSE)
  files <- c(
    contract = app_write_csv(contract$table, file.path(root, "frozen_fit_first_contract.csv")),
    base_contract = file.path(root, "frozen_contract.csv"),
    candidates = app_write_csv(candidates, file.path(root, "frozen_candidate_shortlist.csv")),
    fixtures = app_write_csv(fixtures, file.path(root, "fresh_fixture_manifest.csv")),
    plan = app_write_csv(jobs, file.path(root, "worker_plan.csv")),
    source = app_write_csv(source_receipt, file.path(root, "source_runtime_receipt.csv")),
    git = app_write_csv(app_joint_shared_git_state(), file.path(root, "source_git_state.csv")))
  readiness <- data.frame(status = "FIT_FIRST_PREPARED_NOT_LAUNCHED",
    oracle_workers = expected_oracle, fit_workers = expected_fit,
    total_workers = nrow(jobs), protected_rows_used = 0L,
    article_fixture_materialized = FALSE, downstream_launched = FALSE,
    stringsAsFactors = FALSE)
  files <- c(files, readiness = app_write_csv(readiness,
    file.path(root, "launch_readiness.csv")))
  app_joint_shared_write_manifest(root, files, filename = "preparation_manifest.csv")
  verified <- app_joint_shared_verify_manifest(root,
    file.path(root, "preparation_manifest.csv"))
  if (!all(verified$verified)) stop("Fit-first preparation manifest failed.", call. = FALSE)
  app_write_csv(verified, file.path(root, "preparation_manifest_verification.csv"))
  list(root = root, readiness = readiness)
}

app_joint_phtff_worker_dir <- function(root, worker_id) {
  file.path(root, "workers", sprintf("worker_%05d", as.integer(worker_id)))
}

app_joint_phtff_matrix_from_detail <- function(detail, column, tau) {
  blocks <- lapply(tau, function(level) {
    x <- detail[abs(detail$tau - level) < 1e-12, , drop = FALSE]
    x <- x[order(x$origin_index, x$horizon), , drop = FALSE]
    as.numeric(x[[column]])
  })
  lengths <- vapply(blocks, length, integer(1L))
  if (length(unique(lengths)) != 1L) stop("Fit-first detail grid is unbalanced.", call. = FALSE)
  do.call(cbind, blocks)
}

app_joint_phtff_fit_metrics <- function(result, base_contract) {
  design <- result$design; tau <- base_contract$tau; tr <- design$train_local
  fits <- result$fit
  fit_q <- do.call(cbind, lapply(tau, function(level) {
    fit <- fits[[sprintf("%.2f", level)]]
    as.numeric(app_joint_qdesn_predict_fit(fit, design$Z[tr, , drop = FALSE], level))
  }))
  fit_contract <- app_joint_qdesn_apply_monotone_contract(fit_q, tau)
  fit_truth <- design$true_q[tr, , drop = FALSE]
  detail <- result$detail
  qhat <- app_joint_phtff_matrix_from_detail(detail, "qhat", tau)
  truth <- app_joint_phtff_matrix_from_detail(detail, "true_quantile", tau)
  forecast_contract <- app_joint_qdesn_apply_monotone_contract(qhat, tau)
  reference <- detail[abs(detail$tau - tau[[1L]]) < 1e-12, , drop = FALSE]
  reference <- reference[order(reference$origin_index, reference$horizon), , drop = FALSE]
  fit_error <- fit_contract$qhat_contract - fit_truth
  forecast_error <- forecast_contract$qhat_contract - truth
  tail <- which(tau %in% c(0.05, 0.95))
  h1 <- reference$horizon == 1L
  h15 <- reference$horizon <= 5L
  data.frame(
    fit_oracle_quantile_mae = mean(abs(fit_error)),
    fit_oracle_quantile_rmse = sqrt(mean(fit_error^2)),
    fit_outer_tail_mae_max = max(colMeans(abs(fit_error))[[tail[[1L]]]],
      colMeans(abs(fit_error))[[tail[[2L]]]]),
    forecast_oracle_quantile_mae = mean(abs(forecast_error)),
    forecast_oracle_quantile_rmse = sqrt(mean(forecast_error^2)),
    horizon1_oracle_quantile_mae = mean(abs(forecast_error[h1, , drop = FALSE])),
    horizon1_5_oracle_quantile_mae = mean(abs(forecast_error[h15, , drop = FALSE])),
    realized_acrps = mean(app_joint_shared_acrps(reference$y,
      forecast_contract$qhat_contract, tau)),
    fit_raw_crossing_pairs = sum(fit_contract$raw_crossing$n_crossing_pairs),
    fit_contract_crossing_pairs = sum(fit_contract$contract_crossing$n_crossing_pairs),
    forecast_raw_crossing_pairs = sum(forecast_contract$raw_crossing$n_crossing_pairs),
    forecast_contract_crossing_pairs = sum(
      forecast_contract$contract_crossing$n_crossing_pairs),
    recursive_state_finite = all(is.finite(qhat)), stringsAsFactors = FALSE)
}

app_joint_phtff_run_worker <- function(root, worker_id) {
  root <- normalizePath(root, mustWork = TRUE)
  plan <- app_read_csv(file.path(root, "worker_plan.csv"))
  row <- plan[plan$worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("Fit-first worker ID is not unique.", call. = FALSE)
  out <- app_joint_phtff_worker_dir(root, worker_id)
  if (file.exists(file.path(out, "DONE")) &&
      file.exists(file.path(out, "artifact_manifest.csv"))) return(invisible(out))
  tmp <- paste0(out, ".tmp_", Sys.getpid())
  unlink(tmp, recursive = TRUE, force = TRUE); app_ensure_dir(tmp)
  started <- Sys.time(); base <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  selector_fixture <- readRDS(row$fixture_path[[1L]])
  captured <- tryCatch(app_joint_sw_capture_warnings(function() {
    if (row$job_type[[1L]] == "oracle") {
      oracle_fixture <- readRDS(row$oracle_fixture_path[[1L]])
      design <- app_joint_pure_build_design(selector_fixture, row, base, selector = TRUE)
      map <- app_joint_phtff_forecast_map(design, base)
      return(list(shard = app_joint_recursive_dgp_shard(oracle_fixture, map,
        n_paths = app_joint_phtff_read_contract(file.path(root,
          "frozen_fit_first_contract.csv"))$paths_per_shard,
        seed = row$oracle_seed[[1L]])))
    }
    result <- app_joint_pht3_fit_full7(selector_fixture, row, base, base$full_origins)
    list(result = result, metrics = app_joint_phtff_fit_metrics(result, base))
  }), error = function(e) e)
  if (inherits(captured, "error")) {
    app_ensure_dir(out)
    app_write_csv(cbind(row, data.frame(error_message = conditionMessage(captured),
      stringsAsFactors = FALSE)), file.path(out, "failure.csv"))
    writeLines("failed", file.path(out, "FAILED"))
    stop(conditionMessage(captured), call. = FALSE)
  }
  files <- character()
  if (row$job_type[[1L]] == "oracle") {
    path <- file.path(tmp, "oracle_shard.rds")
    saveRDS(captured$value$shard, path, version = 3L, compress = "xz")
    summary <- data.frame(worker_id = worker_id, job_type = "oracle",
      replicate_id = row$replicate_id, oracle_shard_id = row$oracle_shard_id,
      oracle_seed = row$oracle_seed, n_paths = captured$value$shard$n_paths,
      finite_output = all(is.finite(captured$value$shard$response)),
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      warning_count = length(captured$warnings), protected_rows_loaded = 0L,
      stringsAsFactors = FALSE)
    files <- c(summary = app_write_csv(summary, file.path(tmp, "summary.csv")),
      oracle_shard = path)
  } else {
    result <- captured$value$result
    summary <- cbind(row[, c("worker_id", "job_type", "candidate_id", "fit_first_role",
      "replicate_id", "dgp_seed", "D", "n", "response_lags", "alpha", "rho",
      "input_scale", "rhs_tau0", "rhs_zeta2_fixed"), drop = FALSE],
      captured$value$metrics)
    summary$all_components_converged <- result$summary$all_components_converged
    summary$runtime_seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
    summary$warning_count <- length(captured$warnings)
    summary$protected_rows_loaded <- result$summary$protected_rows_loaded
    files <- c(summary = app_write_csv(summary, file.path(tmp, "summary.csv")),
      forecast_detail = app_write_csv(result$detail, file.path(tmp, "forecast_detail.csv")))
    fit_path <- file.path(tmp, "fit_initializer.rds")
    saveRDS(result$fit, fit_path, version = 3L, compress = "xz")
    files <- c(files, fit_initializer = fit_path)
  }
  if (length(captured$warnings)) files <- c(files, warnings = app_write_csv(data.frame(
    warning_index = seq_along(captured$warnings), warning_message = captured$warnings,
    stringsAsFactors = FALSE), file.path(tmp, "warnings.csv")))
  app_joint_shared_write_manifest(tmp, files)
  verified <- app_joint_shared_verify_manifest(tmp, file.path(tmp, "artifact_manifest.csv"))
  if (!all(verified$verified)) stop("Fit-first worker manifest failed.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE"))
  if (dir.exists(out)) unlink(out, recursive = TRUE, force = TRUE)
  if (!file.rename(tmp, out)) stop("Could not atomically publish fit-first worker.", call. = FALSE)
  invisible(out)
}

app_joint_phtff_health <- function(root = app_joint_phtff_default_root()) {
  plan_path <- file.path(root, "worker_plan.csv")
  if (!file.exists(plan_path)) return(data.frame(expected = 0L, completed = 0L,
    failed = 0L, remaining = 0L, status = "not_prepared"))
  plan <- app_read_csv(plan_path)
  dirs <- vapply(plan$worker_id, function(id) app_joint_phtff_worker_dir(root, id), character(1L))
  done <- file.exists(file.path(dirs, "DONE")) &
    file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) |
    file.exists(file.path(dirs, "failure.csv"))
  data.frame(expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), status = if (any(failed)) "failed" else if (all(done))
      "complete" else if (any(done)) "running" else "ready", stringsAsFactors = FALSE)
}

app_joint_phtff_subset_oracle <- function(oracle, index) {
  out <- oracle
  out$forecast_map <- oracle$forecast_map[index, , drop = FALSE]
  out$sorted_response <- oracle$sorted_response[, index, drop = FALSE]
  out$prefix_response <- oracle$prefix_response[, index, drop = FALSE]
  out$true_q <- oracle$true_q[index, , drop = FALSE]
  out$observed_y <- oracle$observed_y[index]
  out
}

app_joint_phtff_oracle_true_q <- function(fixture, tau) {
  required <- c("mu", "sigma", "registry_row")
  missing <- required[!vapply(required, function(name) !is.null(fixture[[name]]), logical(1L))]
  if (length(missing)) {
    stop(sprintf("Fit-first oracle fixture is missing: %s.", paste(missing, collapse = ", ")),
      call. = FALSE)
  }
  mu <- as.numeric(fixture$mu)
  sigma <- as.numeric(fixture$sigma)
  tau <- as.numeric(tau)
  if (!length(mu) || length(sigma) != length(mu) || !length(tau) ||
      any(!is.finite(c(mu, sigma, tau))) || any(sigma <= 0) ||
      any(tau <= 0 | tau >= 1)) {
    stop("Fit-first oracle truth inputs are malformed.", call. = FALSE)
  }
  standardized <- app_joint_qvp_registry_standardized_quantile(tau, fixture$registry_row)
  truth <- matrix(mu, nrow = length(mu), ncol = length(tau)) + sigma %o% standardized
  if (!identical(dim(truth), c(length(mu), length(tau))) || any(!is.finite(truth))) {
    stop("Fit-first oracle truth reconstruction failed.", call. = FALSE)
  }
  truth
}

app_joint_phtff_apply_selection <- function(aggregate, contract) {
  required <- c("candidate_id", "fit_first_role", "fit_oracle_quantile_mae_mean",
    "horizon1_oracle_quantile_mae_mean", "fit_outer_tail_mae_max_mean",
    "origin_marginal_dgp_integrated_acrps_mean", "horizon1_5_dgp_acrps_mean",
    "finite_all", "recursive_state_finite_all", "contract_crossings_sum")
  app_check_required_columns(aggregate, required, "fit-first aggregate")
  valid <- app_as_bool_vec(aggregate$finite_all) &
    app_as_bool_vec(aggregate$recursive_state_finite_all) &
    aggregate$contract_crossings_sum == 0L
  if (!any(valid)) stop("No fit-first candidate passes hard gates.", call. = FALSE)
  best_fit <- min(aggregate$fit_oracle_quantile_mae_mean[valid])
  best_h1 <- min(aggregate$horizon1_oracle_quantile_mae_mean[valid])
  best_tail <- min(aggregate$fit_outer_tail_mae_max_mean[valid])
  fit_limit <- best_fit + max(contract$fit_absolute_margin,
    contract$fit_relative_margin * best_fit)
  h1_limit <- best_h1 + max(contract$h1_absolute_margin,
    contract$h1_relative_margin * best_h1)
  tail_limit <- best_tail + max(contract$tail_absolute_margin,
    contract$tail_relative_margin * best_tail)
  aggregate$hard_gate_pass <- valid
  aggregate$fit_gate_pass <- valid &
    aggregate$fit_oracle_quantile_mae_mean <= fit_limit &
    aggregate$horizon1_oracle_quantile_mae_mean <= h1_limit &
    aggregate$fit_outer_tail_mae_max_mean <= tail_limit
  eligible <- aggregate[aggregate$fit_gate_pass, , drop = FALSE]
  if (nrow(eligible) < contract$minimum_fit_eligible_candidates) {
    stop("No candidate passes the frozen fit-competence gate.", call. = FALSE)
  }
  best_forecast <- min(eligible$origin_marginal_dgp_integrated_acrps_mean)
  tie_limit <- best_forecast + max(contract$forecast_near_tie_absolute_margin,
    contract$forecast_near_tie_relative_margin * abs(best_forecast))
  near <- eligible[eligible$origin_marginal_dgp_integrated_acrps_mean <= tie_limit, , drop = FALSE]
  best_short <- min(near$horizon1_5_dgp_acrps_mean)
  short_limit <- best_short * (1 + contract$short_horizon_relative_guard)
  near <- near[near$horizon1_5_dgp_acrps_mean <= short_limit, , drop = FALSE]
  near <- near[order(near$fit_oracle_quantile_mae_mean,
    near$horizon1_oracle_quantile_mae_mean,
    near$origin_marginal_dgp_integrated_acrps_mean,
    near$candidate_id), , drop = FALSE]
  selected <- near[1L, , drop = FALSE]
  aggregate$forecast_near_tie <- aggregate$fit_gate_pass &
    aggregate$origin_marginal_dgp_integrated_acrps_mean <= tie_limit
  aggregate$selected <- aggregate$candidate_id == selected$candidate_id[[1L]]
  list(table = aggregate, selected = selected,
    limits = data.frame(best_fit = best_fit, fit_limit = fit_limit,
      best_horizon1 = best_h1, horizon1_limit = h1_limit,
      best_tail = best_tail, tail_limit = tail_limit,
      best_forecast = best_forecast, forecast_near_tie_limit = tie_limit,
      best_short_horizon = best_short, short_horizon_limit = short_limit,
      stringsAsFactors = FALSE))
}

app_joint_phtff_finalize <- function(root = app_joint_phtff_default_root()) {
  root <- normalizePath(root, mustWork = TRUE)
  health <- app_joint_phtff_health(root)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L) {
    stop("Fit-first campaign is not complete and failure-free.", call. = FALSE)
  }
  contract <- app_joint_phtff_read_contract(file.path(root, "frozen_fit_first_contract.csv"))
  base <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  plan <- app_read_csv(file.path(root, "worker_plan.csv"))
  for (id in plan$worker_id) {
    worker <- app_joint_phtff_worker_dir(root, id)
    verified <- app_joint_shared_verify_manifest(worker,
      file.path(worker, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified)) {
      stop(sprintf("Fit-first worker %d manifest failed verification.", id), call. = FALSE)
    }
  }
  oracle_plan <- plan[plan$job_type == "oracle", , drop = FALSE]
  fit_plan <- plan[plan$job_type == "fit", , drop = FALSE]
  oracle_banks <- list(); oracle_diagnostics <- list()
  app_ensure_dir(file.path(root, "oracle_banks"))
  for (rep in seq_len(contract$fresh_replicates)) {
    block <- oracle_plan[oracle_plan$replicate_id == rep, , drop = FALSE]
    shard_paths <- vapply(block$worker_id, function(id) file.path(
      app_joint_phtff_worker_dir(root, id), "oracle_shard.rds"), character(1L))
    fixture <- readRDS(block$oracle_fixture_path[[1L]])
    fixture$true_q <- app_joint_phtff_oracle_true_q(fixture, base$tau)
    oracle <- app_joint_recursive_combine_oracle_shards(shard_paths, fixture, base$tau,
      app_joint_shared_weights(base$tau), contract$analytic_tolerance,
      contract$split_half_tolerance)
    path <- file.path(root, "oracle_banks", sprintf("rep%02d.rds", rep))
    saveRDS(oracle, path, version = 3L, compress = "xz")
    oracle_banks[[as.character(rep)]] <- oracle
    oracle_diagnostics[[as.character(rep)]] <- cbind(data.frame(replicate_id = rep),
      oracle$diagnostics)
  }
  diagnostics <- app_bind_rows_fill(oracle_diagnostics)
  if (any(diagnostics$status != "pass")) stop("Fit-first oracle diagnostics failed.", call. = FALSE)
  rows <- lapply(seq_len(nrow(fit_plan)), function(i) {
    row <- fit_plan[i, , drop = FALSE]
    worker <- app_joint_phtff_worker_dir(root, row$worker_id[[1L]])
    summary <- app_read_csv(file.path(worker, "summary.csv"))
    detail <- app_read_csv(file.path(worker, "forecast_detail.csv"))
    qhat <- app_joint_phtff_matrix_from_detail(detail, "qhat", base$tau)
    qhat <- app_joint_qdesn_apply_monotone_contract(qhat, base$tau)$qhat_contract
    oracle <- oracle_banks[[as.character(row$replicate_id[[1L]])]]
    score <- app_joint_recursive_oracle_point_score(oracle, qhat, base$tau,
      app_joint_shared_weights(base$tau))
    h15 <- oracle$forecast_map$horizon <= 5L
    short <- app_joint_recursive_oracle_point_score(
      app_joint_phtff_subset_oracle(oracle, h15), qhat[h15, , drop = FALSE], base$tau,
      app_joint_shared_weights(base$tau))
    summary$origin_marginal_dgp_integrated_acrps <-
      score$origin_marginal_dgp_integrated_acrps
    summary$horizon1_5_dgp_acrps <- short$origin_marginal_dgp_integrated_acrps
    summary
  })
  scores <- app_bind_rows_fill(rows)
  groups <- split(scores, scores$candidate_id)
  aggregate <- app_bind_rows_fill(lapply(groups, function(x) data.frame(
    candidate_id = x$candidate_id[[1L]], fit_first_role = x$fit_first_role[[1L]],
    D = x$D[[1L]], n = x$n[[1L]], response_lags = x$response_lags[[1L]],
    alpha = x$alpha[[1L]], rho = x$rho[[1L]], input_scale = x$input_scale[[1L]],
    rhs_tau0 = x$rhs_tau0[[1L]], rhs_zeta2_fixed = x$rhs_zeta2_fixed[[1L]],
    replicates = nrow(x),
    fit_oracle_quantile_mae_mean = mean(x$fit_oracle_quantile_mae),
    fit_oracle_quantile_mae_sd = stats::sd(x$fit_oracle_quantile_mae),
    horizon1_oracle_quantile_mae_mean = mean(x$horizon1_oracle_quantile_mae),
    fit_outer_tail_mae_max_mean = mean(x$fit_outer_tail_mae_max),
    origin_marginal_dgp_integrated_acrps_mean =
      mean(x$origin_marginal_dgp_integrated_acrps),
    origin_marginal_dgp_integrated_acrps_sd =
      stats::sd(x$origin_marginal_dgp_integrated_acrps),
    horizon1_5_dgp_acrps_mean = mean(x$horizon1_5_dgp_acrps),
    realized_acrps_mean = mean(x$realized_acrps),
    finite_all = all(is.finite(c(x$fit_oracle_quantile_mae,
      x$horizon1_oracle_quantile_mae, x$fit_outer_tail_mae_max,
      x$origin_marginal_dgp_integrated_acrps, x$horizon1_5_dgp_acrps,
      x$realized_acrps))),
    recursive_state_finite_all = all(app_as_bool_vec(x$recursive_state_finite)),
    contract_crossings_sum = sum(x$fit_contract_crossing_pairs) +
      sum(x$forecast_contract_crossing_pairs),
    all_components_converged = all(app_as_bool_vec(x$all_components_converged)),
    stringsAsFactors = FALSE)))
  selected <- app_joint_phtff_apply_selection(aggregate, contract)
  winner <- selected$selected
  status <- if (winner$fit_first_role[[1L]] == "exact_v2_fallback") {
    "FIT_FIRST_COMPLETE_RETAIN_EXACT_V2"
  } else {
    "FIT_FIRST_COMPLETE_FOUR_MODEL_CONFIRMATION_AUTHORIZED"
  }
  decision <- data.frame(status = status,
    selected_candidate_id = winner$candidate_id,
    selected_role = winner$fit_first_role,
    selected_fit_mae = winner$fit_oracle_quantile_mae_mean,
    selected_horizon1_mae = winner$horizon1_oracle_quantile_mae_mean,
    selected_dgp_integrated_acrps = winner$origin_marginal_dgp_integrated_acrps_mean,
    fit_eligible_candidates = sum(selected$table$fit_gate_pass),
    forecast_near_tie_candidates = sum(selected$table$forecast_near_tie),
    article_fixture_used = FALSE, protected_rows_used = 0L,
    downstream_launched = FALSE, stringsAsFactors = FALSE)
  files <- c(
    worker_scores = app_write_csv(scores, file.path(root, "fit_first_scores_by_replicate.csv")),
    aggregate = app_write_csv(selected$table, file.path(root, "fit_first_candidate_aggregate.csv")),
    limits = app_write_csv(selected$limits, file.path(root, "fit_first_selection_limits.csv")),
    oracle = app_write_csv(diagnostics, file.path(root, "oracle_diagnostics.csv")),
    decision = app_write_csv(decision, file.path(root, "fit_first_decision.csv")),
    finalization_git = app_write_csv(app_joint_shared_git_state(),
      file.path(root, "fit_first_finalization_git_state.csv")))
  app_joint_shared_write_manifest(root, files, filename = "fit_first_final_manifest.csv")
  verified <- app_joint_shared_verify_manifest(root,
    file.path(root, "fit_first_final_manifest.csv"))
  if (!all(verified$verified)) stop("Fit-first final manifest failed.", call. = FALSE)
  app_write_csv(verified, file.path(root, "fit_first_final_manifest_verification.csv"))
  decision
}
