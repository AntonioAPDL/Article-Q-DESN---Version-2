#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_desn_part2_bridge.R"))
source(app_path("application/R/glofas_normal_desn_part3_joint_bridge.R"))

Sys.setenv(
  OMP_NUM_THREADS = "1",
  OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1",
  NUMEXPR_NUM_THREADS = "1"
)

default_baseline_runtime <- "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_part2_rhs_jerez_20260904/local_trackers/runtime_configs/glofas_part3_normal_historical_jerez_20260904"
default_base_config <- "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_part2_rhs_jerez_20260904/local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml"

args <- app_parse_args(list(
  job = "all",
  runtime_root = "local_trackers/runtime_configs/glofas_part3_cross_input_normal_challenger_jerez_20260905",
  baseline_runtime = default_baseline_runtime,
  base_config = default_base_config,
  candidate_id = "part3_cross_input_normal_challenger_ref_glofas_disc_glofas",
  extension_seed = "20260905",
  max_iter = "100",
  min_iter = "30",
  tol = "1e-4",
  progress_every = "1",
  freeze_beta_warmup_iters = "20",
  min_beta_updates = "30"
))

runtime_root <- app_resolve_path(args$runtime_root, must_work = FALSE)
baseline_runtime <- normalizePath(as.character(args$baseline_runtime), mustWork = TRUE)
base_config_path <- normalizePath(as.character(args$base_config), mustWork = TRUE)
job <- match.arg(as.character(args$job), c("design_cache", "ridge", "rhs", "compare", "all"))

subdirs <- c("configs", "objects", "scores", "details", "traces", "coefficients", "tables", "logs", "status", "manifests", "diagnostics")
for (d in subdirs) app_ensure_dir(file.path(runtime_root, d))

status_path <- function(job_id, state) file.path(runtime_root, "status", paste0(job_id, ".", state))
mark_status <- function(job_id, state) {
  for (s in c("running", "completed", "failed")) {
    p <- status_path(job_id, s)
    if (file.exists(p)) unlink(p)
  }
  writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), status_path(job_id, state))
}

peak_rss_mb <- function() {
  path <- "/proc/self/status"
  if (!file.exists(path)) return(NA_real_)
  lines <- readLines(path, warn = FALSE)
  hit <- grep("^VmHWM:", lines, value = TRUE)
  if (!length(hit)) return(NA_real_)
  as.numeric(gsub("[^0-9]", "", hit[[1L]])) / 1024
}

thread_guard_table <- function() {
  vars <- c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS")
  data.frame(
    variable = vars,
    value = Sys.getenv(vars),
    status = ifelse(Sys.getenv(vars) == "1", "pass", "fail"),
    stringsAsFactors = FALSE
  )
}

cache_file <- file.path(runtime_root, "configs", "part3_cross_input_design_cache.rds")
candidate_file <- file.path(runtime_root, "configs", "part3_cross_input_candidate.csv")
baseline_summary_file <- function(method) file.path(baseline_runtime, "scores", paste0(method, "_summary.csv"))
baseline_detail_file <- function(method) file.path(baseline_runtime, "details", paste0(method, "_validation_detail.csv"))

load_candidate <- function() {
  winners <- app_read_csv(file.path(baseline_runtime, "configs", "part3_frozen_g1_g2_winners.csv"))
  candidate <- app_glofas_normal_part3_cross_input_challenger_candidate(
    winners,
    candidate_id = as.character(args$candidate_id),
    require_frozen = TRUE,
    extension_seed = as.integer(args$extension_seed)
  )
  candidate$rhs_max_iter <- as.integer(args$max_iter)
  candidate$rhs_min_iter <- as.integer(args$min_iter)
  candidate$rhs_tol <- as.numeric(args$tol)
  candidate$rhs_update_every <- 1L
  candidate$rhs_freeze_beta_warmup_iters <- as.integer(args$freeze_beta_warmup_iters)
  candidate$rhs_min_beta_updates <- as.integer(args$min_beta_updates)
  candidate
}

write_artifact_manifest <- function() {
  files <- list.files(runtime_root, recursive = TRUE, full.names = TRUE, all.files = FALSE, no.. = TRUE)
  files <- files[file.info(files)$isdir %in% FALSE]
  manifest_path <- file.path(runtime_root, "manifests", "artifact_manifest.csv")
  files <- setdiff(files, manifest_path)
  rel <- sub(paste0("^", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", runtime_root), "/?"), "", files)
  out <- data.frame(
    relative_path = rel,
    role = dirname(rel),
    size_bytes = as.numeric(file.info(files)$size),
    sha256 = vapply(files, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  out <- out[order(out$relative_path), , drop = FALSE]
  app_write_csv(out, manifest_path)
  invisible(out)
}

write_contract <- function(job_id, status, output_paths = character(), extra = data.frame()) {
  rel <- function(path) {
    sub(paste0("^", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", repo_root), "/?"), "", normalizePath(path, mustWork = FALSE))
  }
  out <- data.frame(
    job_id = job_id,
    status = status,
    repo_root = repo_root,
    runtime_root = runtime_root,
    baseline_runtime = baseline_runtime,
    base_config = base_config_path,
    git_head = app_system2_repo("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = TRUE)[[1L]],
    peak_rss_mb = peak_rss_mb(),
    output_paths = paste(vapply(output_paths, rel, character(1L)), collapse = ";"),
    stringsAsFactors = FALSE
  )
  if (nrow(extra)) out <- cbind(out, extra[1L, , drop = FALSE])
  app_write_csv(out, file.path(runtime_root, "logs", paste0(job_id, "_execution_contract.csv")))
  write_artifact_manifest()
  invisible(out)
}

train_design_hash <- function(design, split) {
  stack_split <- app_glofas_normal_part3_stack_split(design, split)
  app_glofas_normal_part1_design_fingerprint(
    design$H[stack_split$train_idx, , drop = FALSE],
    design$z[stack_split$train_idx],
    design$row_info$date[stack_split$train_idx],
    design$feature_info
  )
}

build_design_cache <- function() {
  job_id <- "design_cache"
  mark_status(job_id, "running")
  tryCatch({
    app_write_csv(thread_guard_table(), file.path(runtime_root, "configs", "thread_guard.csv"))
    candidate <- load_candidate()
    app_write_csv(candidate, candidate_file)
    cfg <- app_read_config(base_config_path)
    started <- Sys.time()
    design <- app_glofas_normal_part3_build_design(cfg, candidate)
    split <- app_glofas_normal_part3_validation_split(design, candidate)
    audit <- app_glofas_normal_part3_validate_cross_input_design(design, candidate)
    stack_split <- app_glofas_normal_part3_stack_split(design, split)
    td_hash <- train_design_hash(design, split)
    cert <- data.frame(
      schema_version = "glofas_part3_cross_input_normal_challenger_design_v1",
      candidate_id = candidate$candidate_id[[1L]],
      part3_input_contract = candidate$part3_input_contract[[1L]],
      n_dates = design$n_dates,
      n_stacked_rows = nrow(design$H),
      n_train_stacked_rows = length(stack_split$train_idx),
      n_valid_stacked_rows = length(stack_split$valid_idx),
      p_reference = design$p_beta,
      p_discrepancy = design$p_alpha,
      p_joint = ncol(design$H),
      train_design_hash = td_hash,
      reference_design_hash = design$design_hash[["reference_full"]],
      discrepancy_design_hash = design$design_hash[["discrepancy_full"]],
      part3_stacked_design_hash = design$design_hash[["part3_stacked_full"]],
      baseline_train_hash = "f2e1fb16fd5ccc04eabbfb7b7962fce48d06ec6b755594f96e906bbce556058c",
      baseline_runtime = baseline_runtime,
      design_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      peak_rss_mb = peak_rss_mb(),
      stringsAsFactors = FALSE
    )
    expected <- c(n_dates = 12495L, n_stacked_rows = 24990L, p_reference = 3001L, p_discrepancy = 2501L, p_joint = 5502L)
    if (cert$n_dates[[1L]] != expected[["n_dates"]] ||
        cert$n_stacked_rows[[1L]] != expected[["n_stacked_rows"]] ||
        cert$p_reference[[1L]] != expected[["p_reference"]] ||
        cert$p_discrepancy[[1L]] != expected[["p_discrepancy"]] ||
        cert$p_joint[[1L]] != expected[["p_joint"]]) {
      stop("Part 3 cross-input design dimensions do not match the fixed winner geometry.", call. = FALSE)
    }
    app_write_csv(cert, file.path(runtime_root, "configs", "part3_cross_input_design_certificate.csv"))
    app_write_csv(audit$input_lag_audit, file.path(runtime_root, "configs", "part3_cross_input_lag_manifest.csv"))
    app_write_csv(audit$win_preservation_audit, file.path(runtime_root, "diagnostics", "part3_cross_input_win_preservation.csv"))
    app_write_csv(audit$reservoir_activity, file.path(runtime_root, "diagnostics", "part3_cross_input_reservoir_activity.csv"))
    app_write_csv(design$feature_info, file.path(runtime_root, "configs", "part3_cross_input_readout_feature_manifest.csv"))
    app_write_csv(design$reference$component_design$design_meta$reservoir_input_info, file.path(runtime_root, "configs", "part3_cross_input_reference_reservoir_inputs.csv"))
    app_write_csv(design$discrepancy$component_design$design_meta$reservoir_input_info, file.path(runtime_root, "configs", "part3_cross_input_discrepancy_reservoir_inputs.csv"))
    cache <- list(
      schema_version = "glofas_part3_cross_input_normal_challenger_cache_v1",
      repo_root = repo_root,
      baseline_runtime = baseline_runtime,
      base_config = base_config_path,
      candidate = candidate,
      design = design,
      split = split,
      stack_split = stack_split,
      train_design_hash = td_hash,
      audits = audit
    )
    saveRDS(cache, cache_file, version = 2L)
    app_write_csv(data.frame(path = cache_file, sha256 = app_sha256_file(cache_file), stringsAsFactors = FALSE), file.path(runtime_root, "configs", "part3_cross_input_design_cache_sha256.csv"))
    mark_status(job_id, "completed")
    write_contract(job_id, "completed", c(cache_file, candidate_file))
  }, error = function(e) {
    writeLines(conditionMessage(e), file.path(runtime_root, "logs", paste0(job_id, "_error.txt")))
    mark_status(job_id, "failed")
    stop(e)
  })
}

load_cache <- function() {
  if (!file.exists(cache_file)) stop(sprintf("Missing design cache: %s", cache_file), call. = FALSE)
  readRDS(cache_file)
}

fit_ridge <- function() {
  job_id <- "normal_ridge_joint"
  mark_status(job_id, "running")
  tryCatch({
    cache <- load_cache()
    design <- cache$design
    split <- cache$split
    candidate <- cache$candidate
    started <- Sys.time()
    stack_split <- app_glofas_normal_part3_stack_split(design, split)
    fit <- app_glofas_normal_ridge_fit(
      X = design$H[stack_split$train_idx, , drop = FALSE],
      y = design$z[stack_split$train_idx],
      ridge_tau2 = as.numeric(app_glofas_normal_part2_row_value(candidate, "ridge_tau2", app_glofas_normal_part2_default_values()$ridge_tau2)),
      intercept_var = as.numeric(app_glofas_normal_part2_row_value(candidate, "intercept_var", app_glofas_normal_part2_default_values()$intercept_var)),
      sigma_a = as.numeric(app_glofas_normal_part2_row_value(candidate, "sigma_a", app_glofas_normal_part2_default_values()$sigma_a)),
      sigma_b = as.numeric(app_glofas_normal_part2_row_value(candidate, "sigma_b", app_glofas_normal_part2_default_values()$sigma_b))
    )
    fit$type <- "normal_ridge_joint_historical_cross_input"
    fit$input_contract <- candidate$part3_input_contract[[1L]]
    fit$iterations <- NA_integer_
    fit$converged <- TRUE
    warm_start <- app_glofas_normal_part3_make_ridge_warm_start(fit, design, split, candidate)
    coeffs <- app_glofas_normal_part3_coefficient_table(fit, design)
    out <- app_glofas_normal_part3_score_from_fit(
      design = design,
      split = split,
      fit = fit,
      candidate_row = candidate,
      method = "normal_scaled_ridge_joint_historical_cross_input",
      started = started,
      coefficients = coeffs
    )
    fit_path <- file.path(runtime_root, "objects", "normal_ridge_joint_fit.rds")
    warm_path <- file.path(runtime_root, "objects", "normal_ridge_joint_warm_start.rds")
    saveRDS(fit, fit_path, version = 2L)
    saveRDS(warm_start, warm_path, version = 2L)
    app_write_csv(out$summary, file.path(runtime_root, "scores", "normal_ridge_joint_summary.csv"))
    app_write_csv(out$detail, file.path(runtime_root, "details", "normal_ridge_joint_validation_detail.csv"))
    app_write_csv(coeffs, file.path(runtime_root, "coefficients", "normal_ridge_joint_coefficients.csv"))
    app_write_csv(data.frame(iter = NA_integer_, status = "closed_form", stringsAsFactors = FALSE), file.path(runtime_root, "traces", "normal_ridge_joint_trace.csv"))
    app_write_csv(data.frame(path = c(fit_path, warm_path), sha256 = c(app_sha256_file(fit_path), app_sha256_file(warm_path)), stringsAsFactors = FALSE), file.path(runtime_root, "objects", "normal_ridge_joint_hashes.csv"))
    mark_status(job_id, "completed")
    write_contract(job_id, "completed", c(fit_path, warm_path, file.path(runtime_root, "scores", "normal_ridge_joint_summary.csv")))
  }, error = function(e) {
    writeLines(conditionMessage(e), file.path(runtime_root, "logs", paste0(job_id, "_error.txt")))
    mark_status(job_id, "failed")
    stop(e)
  })
}

fit_rhs <- function() {
  job_id <- "normal_rhs_vb_joint"
  mark_status(job_id, "running")
  tryCatch({
    cache <- load_cache()
    design <- cache$design
    split <- cache$split
    candidate <- cache$candidate
    warm_path <- file.path(runtime_root, "objects", "normal_ridge_joint_warm_start.rds")
    warm_sha <- app_sha256_file(warm_path)
    warm_start <- app_glofas_normal_part3_load_warm_start(warm_path, warm_sha, design = design, split = split)
    started <- Sys.time()
    stack_split <- app_glofas_normal_part3_stack_split(design, split)
    progress_path <- file.path(runtime_root, "traces", "normal_rhs_vb_joint_progress.csv")
    fit <- app_glofas_normal_part3_rhs_fit_blocked(
      X = design$H[stack_split$train_idx, , drop = FALSE],
      y = design$z[stack_split$train_idx],
      ridge_warm_start = warm_start,
      p_beta = design$p_beta,
      p_alpha = design$p_alpha,
      reference_intercept_index = 1L,
      discrepancy_intercept_index = 1L,
      tau0_reference = as.numeric(app_glofas_normal_part2_row_value(candidate, "rhs_tau0_reference", 1)),
      tau0_discrepancy = as.numeric(app_glofas_normal_part2_row_value(candidate, "rhs_tau0_discrepancy", 0.001)),
      max_iter = as.integer(candidate$rhs_max_iter[[1L]]),
      min_iter = as.integer(candidate$rhs_min_iter[[1L]]),
      tol = as.numeric(candidate$rhs_tol[[1L]]),
      rhs_update_every = as.integer(candidate$rhs_update_every[[1L]]),
      freeze_beta_warmup_iters = as.integer(candidate$rhs_freeze_beta_warmup_iters[[1L]]),
      min_beta_updates = as.integer(candidate$rhs_min_beta_updates[[1L]]),
      progress_path = progress_path,
      progress_every = as.integer(args$progress_every)
    )
    fit$type <- "normal_rhs_vb_joint_historical_cross_input"
    fit$input_contract <- candidate$part3_input_contract[[1L]]
    fit$warm_start_sha256 <- warm_sha
    coeffs <- app_glofas_normal_part3_coefficient_table(fit, design)
    out <- app_glofas_normal_part3_score_from_fit(
      design = design,
      split = split,
      fit = fit,
      candidate_row = candidate,
      method = "normal_rhs_vb_joint_historical_cross_input",
      started = started,
      trace = fit$trace,
      coefficients = coeffs
    )
    fit_path <- file.path(runtime_root, "objects", "normal_rhs_vb_joint_fit.rds")
    saveRDS(fit, fit_path, version = 2L)
    app_write_csv(out$summary, file.path(runtime_root, "scores", "normal_rhs_vb_joint_summary.csv"))
    app_write_csv(out$detail, file.path(runtime_root, "details", "normal_rhs_vb_joint_validation_detail.csv"))
    app_write_csv(fit$trace, file.path(runtime_root, "traces", "normal_rhs_vb_joint_trace.csv"))
    app_write_csv(coeffs, file.path(runtime_root, "coefficients", "normal_rhs_vb_joint_coefficients.csv"))
    app_write_csv(data.frame(path = fit_path, sha256 = app_sha256_file(fit_path), warm_start_sha256 = warm_sha, stringsAsFactors = FALSE), file.path(runtime_root, "objects", "normal_rhs_vb_joint_hashes.csv"))
    mark_status(job_id, "completed")
    write_contract(job_id, "completed", c(fit_path, progress_path, file.path(runtime_root, "scores", "normal_rhs_vb_joint_summary.csv")))
  }, error = function(e) {
    writeLines(conditionMessage(e), file.path(runtime_root, "logs", paste0(job_id, "_error.txt")))
    mark_status(job_id, "failed")
    stop(e)
  })
}

score_detail_window <- function(detail, method, window_n) {
  detail <- detail[order(as.Date(detail$date)), , drop = FALSE]
  if (nrow(detail) > window_n) detail <- utils::tail(detail, window_n)
  pred <- function(mean_col, sd_col, observed_col, prefix) {
    observed <- as.numeric(detail[[observed_col]])
    mean <- as.numeric(detail[[mean_col]])
    sd <- if (sd_col %in% names(detail)) as.numeric(detail[[sd_col]]) else rep(NA_real_, length(mean))
    crps <- if (all(is.finite(sd))) {
      mean(app_glofas_normal_crps(observed, mean, sd), na.rm = TRUE)
    } else {
      NA_real_
    }
    data.frame(
      metric = c(paste0(prefix, "mean_crps"), paste0(prefix, "mae"), paste0(prefix, "rmse")),
      value = c(
        crps,
        mean(abs(mean - observed), na.rm = TRUE),
        sqrt(mean((mean - observed)^2, na.rm = TRUE))
      ),
      stringsAsFactors = FALSE
    )
  }
  out <- app_bind_rows_fill(list(
    pred("reference_mean", "reference_sd", "observed_usgs", "reference_"),
    pred("discrepancy_mean", "discrepancy_sd", "observed_discrepancy", "discrepancy_"),
    pred("corrected_usgs_mean", "corrected_usgs_sd", "observed_usgs", "corrected_"),
    pred("joint_usgs_mean", "joint_usgs_sd", "observed_usgs", "joint_usgs_"),
    pred("joint_glofas_mean", "joint_glofas_sd", "retrospective_glofas", "joint_glofas_")
  ))
  data.frame(
    method = method,
    trailing_n = nrow(detail),
    valid_start_date = as.character(min(as.Date(detail$date))),
    valid_end_date = as.character(max(as.Date(detail$date))),
    out,
    stringsAsFactors = FALSE
  )
}

compare_results <- function() {
  job_id <- "comparison"
  mark_status(job_id, "running")
  tryCatch({
    rows <- list()
    for (method in c("normal_ridge_joint", "normal_rhs_vb_joint")) {
      baseline <- app_read_csv(baseline_summary_file(method))
      challenger <- app_read_csv(file.path(runtime_root, "scores", paste0(method, "_summary.csv")))
      metrics <- c(
        "reference_valid_mean_crps", "reference_valid_mae", "reference_valid_rmse",
        "discrepancy_valid_mean_crps", "discrepancy_valid_mae", "discrepancy_valid_rmse",
        "corrected_valid_mean_crps", "corrected_valid_mae", "corrected_valid_rmse",
        "joint_usgs_valid_mean_crps", "joint_usgs_valid_mae", "joint_usgs_valid_rmse",
        "joint_glofas_valid_mean_crps", "joint_glofas_valid_mae", "joint_glofas_valid_rmse"
      )
      for (m in metrics) {
        if (!m %in% names(baseline) || !m %in% names(challenger)) next
        rows[[length(rows) + 1L]] <- data.frame(
          method = method,
          metric = m,
          baseline = as.numeric(baseline[[m]][[1L]]),
          challenger = as.numeric(challenger[[m]][[1L]]),
          delta_challenger_minus_baseline = as.numeric(challenger[[m]][[1L]]) - as.numeric(baseline[[m]][[1L]]),
          stringsAsFactors = FALSE
        )
      }
    }
    comparison <- app_bind_rows_fill(rows)
    app_write_csv(comparison, file.path(runtime_root, "scores", "baseline_vs_cross_input_comparison.csv"))

    trailing <- list()
    for (method in c("normal_ridge_joint", "normal_rhs_vb_joint")) {
      base_detail <- app_read_csv(baseline_detail_file(method))
      chal_detail <- app_read_csv(file.path(runtime_root, "details", paste0(method, "_validation_detail.csv")))
      for (window_n in c(200L, 50L)) {
        trailing[[length(trailing) + 1L]] <- transform(score_detail_window(base_detail, paste0(method, "_baseline"), window_n), source = "baseline")
        trailing[[length(trailing) + 1L]] <- transform(score_detail_window(chal_detail, paste0(method, "_challenger"), window_n), source = "challenger")
      }
    }
    trailing_summary <- app_bind_rows_fill(trailing)
    app_write_csv(trailing_summary, file.path(runtime_root, "scores", "trailing_window_summary.csv"))

    rhs_cmp <- comparison[comparison$method == "normal_rhs_vb_joint", , drop = FALSE]
    corrected_delta <- rhs_cmp$delta_challenger_minus_baseline[rhs_cmp$metric == "corrected_valid_mean_crps"][[1L]]
    joint_g_delta <- rhs_cmp$delta_challenger_minus_baseline[rhs_cmp$metric == "joint_glofas_valid_mean_crps"][[1L]]
    ref_delta <- rhs_cmp$delta_challenger_minus_baseline[rhs_cmp$metric == "reference_valid_mean_crps"][[1L]]
    disc_delta <- rhs_cmp$delta_challenger_minus_baseline[rhs_cmp$metric == "discrepancy_valid_mean_crps"][[1L]]
    eps <- 1.0e-4
    classification <- if (is.finite(corrected_delta) && is.finite(joint_g_delta) &&
                          corrected_delta < -eps && joint_g_delta < -eps &&
                          ref_delta <= eps && disc_delta <= eps) {
      "PART3_CROSS_INPUT_NORMAL_PROMISING"
    } else if (any(c(corrected_delta, joint_g_delta, ref_delta, disc_delta) > eps, na.rm = TRUE)) {
      "PART3_CROSS_INPUT_NORMAL_REJECTED"
    } else {
      "PART3_CROSS_INPUT_NORMAL_EQUIVALENT"
    }
    decision <- data.frame(
      classification = classification,
      corrected_valid_mean_crps_delta = corrected_delta,
      joint_glofas_valid_mean_crps_delta = joint_g_delta,
      reference_valid_mean_crps_delta = ref_delta,
      discrepancy_valid_mean_crps_delta = disc_delta,
      tolerance_for_practical_equivalence = eps,
      stringsAsFactors = FALSE
    )
    app_write_csv(decision, file.path(runtime_root, "scores", "cross_input_decision.csv"))
    writeLines(c(
      "# Part 3 Cross-Input Normal Challenger",
      "",
      sprintf("Classification: `%s`", classification),
      "",
      sprintf("Runtime root: `%s`", runtime_root),
      sprintf("Baseline runtime: `%s`", baseline_runtime),
      "",
      "Primary Normal RHS/VB deltas are challenger minus baseline; negative is better.",
      "",
      paste(capture.output(print(rhs_cmp[, c("metric", "baseline", "challenger", "delta_challenger_minus_baseline")], row.names = FALSE)), collapse = "\n")
    ), file.path(runtime_root, "scores", "cross_input_decision.md"))
    mark_status(job_id, "completed")
    write_contract(job_id, "completed", c(
      file.path(runtime_root, "scores", "baseline_vs_cross_input_comparison.csv"),
      file.path(runtime_root, "scores", "trailing_window_summary.csv"),
      file.path(runtime_root, "scores", "cross_input_decision.csv")
    ))
  }, error = function(e) {
    writeLines(conditionMessage(e), file.path(runtime_root, "logs", paste0(job_id, "_error.txt")))
    mark_status(job_id, "failed")
    stop(e)
  })
}

if (identical(job, "design_cache")) {
  build_design_cache()
} else if (identical(job, "ridge")) {
  fit_ridge()
} else if (identical(job, "rhs")) {
  fit_rhs()
} else if (identical(job, "compare")) {
  compare_results()
} else {
  build_design_cache()
  fit_ridge()
  fit_rhs()
  compare_results()
}
