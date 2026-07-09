#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))

args <- app_parse_args(list(
  fixture_dir = "application/cache/joint_qdesn_simulation_dgp_fixtures_20260706",
  output_dir = "application/cache/joint_qdesn_vb_convergence_readiness_20260706",
  scenario_ids = "normal_bridge,asymmetric_laplace_tail,persistent_heavy_tail,nonlinear_reservoir_friendly",
  model_ids = "joint_qdesn_rhs_vb,qdesn_rhs_independent_vb,joint_exqdesn_rhs_vb",
  iter_grid = "480,720,960",
  vb_tol = "1e-4",
  rhs_vb_inner = "5",
  tau0 = "1",
  zeta2 = "Inf",
  a_sigma = "2",
  b_sigma = "1",
  alpha_prior_sd = "1",
  alpha_min_spacing = "0",
  qhat_delta_review_threshold = "0.05",
  score_delta_review_threshold = "0.01",
  n_cores = "6"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_csv <- function(x) {
  vals <- trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]])
  vals[nzchar(vals)]
}

parse_csv_integer <- function(x) {
  out <- as.integer(parse_csv(x))
  if (!length(out) || any(is.na(out)) || any(out <= 0L)) stop("Expected comma-separated positive integers.", call. = FALSE)
  out
}

parse_number <- function(x) {
  out <- suppressWarnings(as.numeric(as.character(x)[[1L]]))
  if (is.na(out)) stop(sprintf("Expected numeric, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

parse_integer <- function(x) {
  out <- as.integer(parse_number(x))
  if (is.na(out)) stop(sprintf("Expected integer, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

resolve_repo_path <- function(path, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

write_csv <- function(x, path) {
  app_ensure_dir(dirname(path))
  utils::write.csv(x, path, row.names = FALSE, na = "")
  normalizePath(path, mustWork = TRUE)
}

bind_rows <- function(rows) app_bind_rows_fill(rows)

parallel_lapply <- function(X, FUN, ..., n_cores) {
  n_cores <- max(1L, min(as.integer(n_cores), length(X)))
  if (n_cores <= 1L || .Platform$OS.type == "windows") return(lapply(X, FUN, ...))
  parallel::mclapply(X, FUN, ..., mc.cores = n_cores, mc.preschedule = FALSE)
}

trace_tail_summary <- function(trace, tail_n = 50L) {
  trace <- trace %||% data.frame()
  if (!nrow(trace)) {
    return(data.frame(
      trace_rows = 0L,
      final_iter = NA_integer_,
      final_monitor = NA_real_,
      final_partial_elbo = NA_real_,
      tail_monitor_mean = NA_real_,
      tail_monitor_sd = NA_real_,
      tail_monitor_last_delta = NA_real_,
      tail_max_beta_change_mean = NA_real_,
      tail_max_beta_change_last = NA_real_,
      finite_trace = FALSE,
      stringsAsFactors = FALSE
    ))
  }
  tail <- utils::tail(trace, tail_n)
  monitor <- if ("monitor" %in% names(tail)) as.numeric(tail$monitor) else rep(NA_real_, nrow(tail))
  beta_change <- if ("max_beta_change" %in% names(tail)) as.numeric(tail$max_beta_change) else rep(NA_real_, nrow(tail))
  partial_elbo <- if ("partial_elbo" %in% names(trace)) as.numeric(trace$partial_elbo) else rep(NA_real_, nrow(trace))
  numeric_trace <- trace[vapply(trace, is.numeric, logical(1L))]
  data.frame(
    trace_rows = nrow(trace),
    final_iter = if ("iter" %in% names(trace)) max(trace$iter, na.rm = TRUE) else nrow(trace),
    final_monitor = if ("monitor" %in% names(trace)) utils::tail(trace$monitor, 1L) else NA_real_,
    final_partial_elbo = utils::tail(partial_elbo, 1L),
    tail_monitor_mean = mean(monitor, na.rm = TRUE),
    tail_monitor_sd = stats::sd(monitor, na.rm = TRUE),
    tail_monitor_last_delta = if (sum(is.finite(monitor)) >= 2L) utils::tail(diff(monitor[is.finite(monitor)]), 1L) else NA_real_,
    tail_max_beta_change_mean = mean(beta_change, na.rm = TRUE),
    tail_max_beta_change_last = utils::tail(beta_change, 1L),
    finite_trace = nrow(numeric_trace) > 0L && all(is.finite(as.matrix(numeric_trace))),
    stringsAsFactors = FALSE
  )
}

score_fit <- function(fit, fixture, controls, job, spec) {
  raw <- app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau)
  contract <- app_joint_qdesn_apply_monotone_contract(raw, fixture$tau)
  scored_rows <- app_joint_qdesn_quantile_long_rows(
    data.frame(
      scenario_id = job$scenario_id,
      model_id = job$model_id,
      display_label = spec$display_label,
      likelihood = spec$likelihood,
      fit_structure = spec$fit_structure,
      stringsAsFactors = FALSE
    ),
    fixture$row_meta,
    fixture$tau,
    fixture$y,
    fixture$true_q,
    contract$qhat_contract,
    "qhat"
  )
  scored <- app_joint_qdesn_quantile_scores(scored_rows, "qhat")
  data.frame(
    truth_mae = mean(scored$truth_abs_error),
    truth_rmse = sqrt(mean(scored$truth_sq_error)),
    check_loss_mean = mean(scored$check_loss),
    hit_error_mean = mean(abs(aggregate(hit ~ tau, scored, mean)$hit - sort(unique(scored$tau)))),
    raw_crossing_pairs = sum(contract$raw_crossing$n_crossing_pairs),
    contract_crossing_pairs = sum(contract$contract_crossing$n_crossing_pairs),
    max_abs_adjustment = contract$max_abs_adjustment,
    adjustment_rate = mean(abs(contract$adjustment) > 1.0e-10),
    finite_qhat = all(is.finite(raw)) && all(is.finite(contract$qhat_contract)),
    stringsAsFactors = FALSE
  )
}

fit_job <- function(job, artifacts, controls_base) {
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, job$scenario_id, role = "fit")
  spec <- app_joint_qdesn_simulation_model_specs()
  spec <- spec[spec$model_id == job$model_id, , drop = FALSE]
  if (nrow(spec) != 1L) stop(sprintf("Unknown model_id '%s'.", job$model_id), call. = FALSE)
  controls <- controls_base
  controls$vb_max_iter <- job$vb_max_iter
  controls$adaptive_vb_max_iter_grid <- job$vb_max_iter
  start <- proc.time()[["elapsed"]]
  fit <- app_joint_qdesn_fit_model(fixture, spec, controls)
  elapsed <- proc.time()[["elapsed"]] - start
  meta <- data.frame(
    scenario_id = job$scenario_id,
    model_id = job$model_id,
    display_label = spec$display_label,
    likelihood = spec$likelihood,
    fit_structure = spec$fit_structure,
    vb_max_iter = job$vb_max_iter,
    stringsAsFactors = FALSE
  )
  trace <- trace_tail_summary(fit$trace)
  score <- score_fit(fit, fixture, controls, job, spec)
  beta <- if (!is.null(fit$fits)) {
    unlist(lapply(fit$fits, `[[`, "beta_mean"), use.names = FALSE)
  } else {
    fit$beta_mean
  }
  qhat <- app_joint_qdesn_apply_monotone_contract(app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau), fixture$tau)$qhat_contract
  list(
    summary = cbind(meta, trace, score, data.frame(
      converged = isTRUE(fit$converged),
      reached_max_iter = !isTRUE(fit$converged),
      beta_l2_norm = sqrt(sum(as.numeric(beta)^2)),
      elapsed_seconds = elapsed,
      stringsAsFactors = FALSE
    )),
    qhat = data.frame(
      meta,
      row_index = rep(seq_len(nrow(qhat)), times = ncol(qhat)),
      tau = rep(fixture$tau, each = nrow(qhat)),
      qhat = as.numeric(qhat),
      stringsAsFactors = FALSE
    )
  )
}

delta_rows <- function(summary, qhat, qhat_delta_threshold, score_delta_threshold) {
  keys <- unique(summary[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure"), drop = FALSE])
  rows <- list()
  for (ii in seq_len(nrow(keys))) {
    key <- keys[ii, , drop = FALSE]
    s <- merge(key, summary, by = names(key))
    s <- s[order(s$vb_max_iter), , drop = FALSE]
    q <- merge(key, qhat, by = names(key))
    for (jj in seq_len(nrow(s))) {
      if (jj == 1L) next
      prev_iter <- s$vb_max_iter[[jj - 1L]]
      curr_iter <- s$vb_max_iter[[jj]]
      qp <- q[q$vb_max_iter == prev_iter, c("row_index", "tau", "qhat"), drop = FALSE]
      qc <- q[q$vb_max_iter == curr_iter, c("row_index", "tau", "qhat"), drop = FALSE]
      m <- merge(qp, qc, by = c("row_index", "tau"), suffixes = c("_previous", "_current"))
      qdiff <- m$qhat_current - m$qhat_previous
      truth_delta <- s$truth_mae[[jj]] - s$truth_mae[[jj - 1L]]
      check_delta <- s$check_loss_mean[[jj]] - s$check_loss_mean[[jj - 1L]]
      rows[[length(rows) + 1L]] <- cbind(key, data.frame(
        previous_vb_max_iter = prev_iter,
        current_vb_max_iter = curr_iter,
        mean_abs_qhat_delta = mean(abs(qdiff), na.rm = TRUE),
        max_abs_qhat_delta = max(abs(qdiff), na.rm = TRUE),
        truth_mae_previous = s$truth_mae[[jj - 1L]],
        truth_mae_current = s$truth_mae[[jj]],
        truth_mae_delta = truth_delta,
        check_loss_previous = s$check_loss_mean[[jj - 1L]],
        check_loss_current = s$check_loss_mean[[jj]],
        check_loss_delta = check_delta,
        max_adjustment_previous = s$max_abs_adjustment[[jj - 1L]],
        max_adjustment_current = s$max_abs_adjustment[[jj]],
        max_adjustment_delta = s$max_abs_adjustment[[jj]] - s$max_abs_adjustment[[jj - 1L]],
        contract_crossing_pairs_current = s$contract_crossing_pairs[[jj]],
        recommendation = if (s$contract_crossing_pairs[[jj]] > 0 || !isTRUE(s$finite_qhat[[jj]])) {
          "fail_contract_or_finiteness"
        } else if (max(abs(qdiff), na.rm = TRUE) <= qhat_delta_threshold && abs(truth_delta) <= score_delta_threshold && abs(check_delta) <= score_delta_threshold) {
          "stable_enough_for_article_note"
        } else {
          "review_extend_or_investigate"
        },
        stringsAsFactors = FALSE
      ))
    }
  }
  bind_rows(rows)
}

fixture_dir <- resolve_repo_path(arg_value("fixture_dir"), must_work = TRUE)
out_dir <- resolve_repo_path(arg_value("output_dir"), must_work = FALSE)
app_ensure_dir(out_dir)
scenario_ids <- parse_csv(arg_value("scenario_ids"))
model_ids <- parse_csv(arg_value("model_ids"))
iter_grid <- parse_csv_integer(arg_value("iter_grid"))
n_cores <- parse_integer(arg_value("n_cores"))
qhat_delta_threshold <- parse_number(arg_value("qhat_delta_review_threshold"))
score_delta_threshold <- parse_number(arg_value("score_delta_review_threshold"))
controls <- app_joint_qdesn_simulation_controls(
  vb_max_iter = max(iter_grid),
  adaptive_vb_max_iter_grid = max(iter_grid),
  vb_tol = parse_number(arg_value("vb_tol")),
  rhs_vb_inner = parse_integer(arg_value("rhs_vb_inner")),
  tau0 = parse_number(arg_value("tau0")),
  zeta2 = parse_number(arg_value("zeta2")),
  a_sigma = parse_number(arg_value("a_sigma")),
  b_sigma = parse_number(arg_value("b_sigma")),
  alpha_prior_sd = parse_number(arg_value("alpha_prior_sd")),
  alpha_min_spacing = parse_number(arg_value("alpha_min_spacing")),
  max_dense_dim = 300L,
  n_cores = n_cores
)
artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
available_scenarios <- artifacts$scenario_summary$scenario_id
missing_scenarios <- setdiff(scenario_ids, available_scenarios)
if (length(missing_scenarios)) stop("Unknown scenario_ids: ", paste(missing_scenarios, collapse = ", "), call. = FALSE)
available_models <- app_joint_qdesn_simulation_model_specs()$model_id
missing_models <- setdiff(model_ids, available_models)
if (length(missing_models)) stop("Unknown model_ids: ", paste(missing_models, collapse = ", "), call. = FALSE)

jobs <- expand.grid(
  scenario_id = scenario_ids,
  model_id = model_ids,
  vb_max_iter = iter_grid,
  stringsAsFactors = FALSE
)
jobs <- jobs[order(jobs$scenario_id, jobs$model_id, jobs$vb_max_iter), , drop = FALSE]
job_list <- split(jobs, seq_len(nrow(jobs)))
results <- parallel_lapply(job_list, fit_job, artifacts = artifacts, controls_base = controls, n_cores = n_cores)
summary <- bind_rows(lapply(results, `[[`, "summary"))
qhat <- bind_rows(lapply(results, `[[`, "qhat"))
deltas <- delta_rows(summary, qhat, qhat_delta_threshold, score_delta_threshold)
gate <- aggregate(recommendation ~ scenario_id + model_id + display_label + likelihood + fit_structure, deltas, function(x) {
  if (any(x == "fail_contract_or_finiteness")) "fail"
  else if (any(x == "review_extend_or_investigate")) "review"
  else "pass_with_note"
})
names(gate)[names(gate) == "recommendation"] <- "gate_recommendation"
gate$detail <- ifelse(
  gate$gate_recommendation == "pass_with_note",
  "480-to-960 changes are small enough for article use with convergence note.",
  ifelse(gate$gate_recommendation == "review", "At least one iteration-step delta remains material.", "Contract/finiteness failure detected.")
)
runtime_delta <- summary[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "vb_max_iter", "elapsed_seconds"), drop = FALSE]
run_config <- data.frame(
  run_id = "joint_qdesn_vb_convergence_readiness",
  fixture_dir = fixture_dir,
  out_dir = out_dir,
  scenario_ids = paste(scenario_ids, collapse = ","),
  model_ids = paste(model_ids, collapse = ","),
  iter_grid = paste(iter_grid, collapse = ","),
  vb_tol = controls$vb_tol,
  rhs_vb_inner = controls$rhs_vb_inner,
  tau0 = controls$tau0,
  qhat_delta_review_threshold = qhat_delta_threshold,
  score_delta_review_threshold = score_delta_threshold,
  n_cores = n_cores,
  stringsAsFactors = FALSE
)
readme_path <- file.path(out_dir, "README.md")
writeLines(c(
  "# Joint QDESN VB Convergence-Readiness Audit",
  "",
  "This targeted audit compares VB controls over a representative scenario/model subset.",
  "It is fit-stage only because the article forecast runner uses the same fit window and no-refit forecast protocol.",
  "",
  "Gate recommendation counts:",
  paste(capture.output(print(table(gate$gate_recommendation))), collapse = "\n")
), readme_path, useBytes = TRUE)
paths <- c(
  convergence_run_config = write_csv(run_config, file.path(out_dir, "convergence_run_config.csv")),
  trace_tail_summary = write_csv(summary, file.path(out_dir, "trace_tail_summary.csv")),
  parameter_delta_summary = write_csv(deltas[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "previous_vb_max_iter", "current_vb_max_iter", "mean_abs_qhat_delta", "max_abs_qhat_delta", "recommendation"), drop = FALSE], file.path(out_dir, "parameter_delta_summary.csv")),
  score_delta_summary = write_csv(deltas[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "previous_vb_max_iter", "current_vb_max_iter", "truth_mae_previous", "truth_mae_current", "truth_mae_delta", "check_loss_previous", "check_loss_current", "check_loss_delta", "recommendation"), drop = FALSE], file.path(out_dir, "score_delta_summary.csv")),
  raw_adjustment_delta_summary = write_csv(deltas[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "previous_vb_max_iter", "current_vb_max_iter", "max_adjustment_previous", "max_adjustment_current", "max_adjustment_delta", "contract_crossing_pairs_current", "recommendation"), drop = FALSE], file.path(out_dir, "raw_adjustment_delta_summary.csv")),
  runtime_delta_summary = write_csv(runtime_delta, file.path(out_dir, "runtime_delta_summary.csv")),
  convergence_gate_recommendation = write_csv(gate, file.path(out_dir, "convergence_gate_recommendation.csv")),
  provenance = write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
  readme = normalizePath(readme_path, mustWork = TRUE)
)
manifest <- data.frame(
  label = names(paths),
  relative_path = basename(paths),
  size_bytes = as.numeric(file.info(paths)$size),
  sha256 = vapply(paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
manifest_path <- write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))

cat(sprintf("Joint QDESN convergence-readiness audit written to %s\n", out_dir))
cat("Gate recommendation counts:\n")
print(table(gate$gate_recommendation))
cat(sprintf("Artifact manifest: %s\n", manifest_path))
