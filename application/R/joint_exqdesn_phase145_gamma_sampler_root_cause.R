# Phase145 sampled-gamma exQDESN sampler root-cause screen.

app_joint_exqdesn_phase145_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase145_gamma_sampler_root_cause_student_t_20260723")
}

app_joint_exqdesn_phase145_default_case_ids <- function() {
  "student_t_location_scale__joint_exqdesn_rhs_vb"
}

app_joint_exqdesn_phase145_variant_specs <- function() {
  data.frame(
    phase136_variant_id = c(
      "phase145_logit_w4_vb_local",
      "phase145_logit_w4_support_steps500",
      "phase145_logit_w4_vb_steps500",
      "phase145_logit_w4_vb_refresh3_sigma",
      "phase145_logit_w4_vb_refresh5_sigma",
      "phase145_logit_w4_vb_refresh3_sigma_s"
    ),
    gamma_update = rep("logit_slice", 6L),
    bounded_width_multiplier = rep(NA_real_, 6L),
    logit_eta_width = rep(4, 6L),
    gamma_prior_type = rep("none", 6L),
    gamma_prior_center = rep(NA_real_, 6L),
    gamma_prior_sd_eta = rep(NA_real_, 6L),
    gamma_slice_max_steps = c(100L, 500L, 500L, 500L, 500L, 500L),
    gamma_refresh_repeats = c(1L, 1L, 1L, 3L, 5L, 3L),
    gamma_refresh_block = c("none", "none", "none", "sigma", "sigma", "sigma_s"),
    gamma_init_mode = c("vb_jittered", "support_grid", "vb_jittered", "vb_jittered", "vb_jittered", "vb_jittered"),
    gamma_jitter_fraction = c(0.02, NA_real_, 0.02, 0.02, 0.02, 0.02),
    phase136_variant_role = c(
      "vb_local_initialization_baseline",
      "support_grid_stronger_stepout_test",
      "vb_local_stronger_stepout_test",
      "gamma_sigma_refresh3_ridge_test",
      "gamma_sigma_refresh5_ridge_test",
      "gamma_sigma_s_refresh3_latent_lag_test"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase145_select_variant_specs <- function(variant_ids = NULL) {
  specs <- app_joint_exqdesn_phase145_variant_specs()
  if (!is.null(variant_ids) && length(variant_ids)) {
    variant_ids <- as.character(variant_ids)
    missing <- setdiff(variant_ids, specs$phase136_variant_id)
    if (length(missing)) {
      stop(sprintf("Unknown Phase145 variant id(s): %s", paste(missing, collapse = ", ")), call. = FALSE)
    }
    specs <- specs[match(variant_ids, specs$phase136_variant_id), , drop = FALSE]
  }
  specs
}

app_joint_exqdesn_phase145_variant_registry <- function(selected_cases) {
  specs <- app_joint_exqdesn_phase145_select_variant_specs()
  rows <- list()
  for (ii in seq_len(nrow(selected_cases))) {
    for (jj in seq_len(nrow(specs))) {
      row <- cbind(selected_cases[ii, , drop = FALSE], specs[jj, , drop = FALSE], stringsAsFactors = FALSE)
      rows[[length(rows) + 1L]] <- row
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  out$phase136_case_variant_id <- paste(out$case_id, out$phase136_variant_id, sep = "__")
  app_joint_exqdesn_phase136_normalize_variant_registry(out)
}

app_joint_exqdesn_phase145_variant_registry_for_specs <- function(selected_cases, specs) {
  rows <- list()
  for (ii in seq_len(nrow(selected_cases))) {
    for (jj in seq_len(nrow(specs))) {
      rows[[length(rows) + 1L]] <- cbind(selected_cases[ii, , drop = FALSE], specs[jj, , drop = FALSE], stringsAsFactors = FALSE)
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  out$phase136_case_variant_id <- paste(out$case_id, out$phase136_variant_id, sep = "__")
  app_joint_exqdesn_phase136_normalize_variant_registry(out)
}

app_joint_exqdesn_phase145_safe_cor <- function(x, y) {
  x <- as.numeric(x)
  y <- as.numeric(y)
  ok <- is.finite(x) & is.finite(y)
  if (sum(ok) < 2L || stats::sd(x[ok]) == 0 || stats::sd(y[ok]) == 0) return(NA_real_)
  as.numeric(stats::cor(x[ok], y[ok]))
}

app_joint_exqdesn_phase145_safe_max_abs <- function(x) {
  x <- abs(as.numeric(x))
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  max(x)
}

app_joint_exqdesn_phase145_trace_enrich <- function(trace_summary, variant_registry = NULL) {
  trace_summary <- as.data.frame(trace_summary, stringsAsFactors = FALSE)
  if (!nrow(trace_summary)) return(trace_summary)
  if (!"phase136_variant_id" %in% names(trace_summary)) {
    if ("variant_id" %in% names(trace_summary)) {
      trace_summary$phase136_variant_id <- as.character(trace_summary$variant_id)
    } else if ("experiment_id" %in% names(trace_summary)) {
      trace_summary$phase136_variant_id <- as.character(trace_summary$experiment_id)
    } else {
      trace_summary$phase136_variant_id <- NA_character_
    }
  }
  if (!"variant_id" %in% names(trace_summary)) trace_summary$variant_id <- trace_summary$phase136_variant_id
  if (!"experiment_id" %in% names(trace_summary)) trace_summary$experiment_id <- trace_summary$phase136_variant_id

  if (!is.null(variant_registry) && nrow(variant_registry)) {
    variant_registry <- app_joint_exqdesn_phase136_normalize_variant_registry(variant_registry)
    keep <- intersect(
      c(
        "phase136_variant_id", "gamma_update", "gamma_refresh_repeats",
        "gamma_refresh_block", "gamma_init_mode", "gamma_jitter_fraction",
        "gamma_prior_type", "gamma_prior_center", "gamma_prior_sd_eta",
        "logit_eta_width", "bounded_width_multiplier", "phase136_variant_role"
      ),
      names(variant_registry)
    )
    variant_registry <- unique(variant_registry[, keep, drop = FALSE])
    add <- setdiff(names(variant_registry), c("phase136_variant_id", names(trace_summary)))
    if (length(add)) {
      trace_summary <- merge(
        trace_summary,
        variant_registry[, c("phase136_variant_id", add), drop = FALSE],
        by = "phase136_variant_id",
        all.x = TRUE,
        sort = FALSE
      )
    }
  }

  defaults <- list(
    gamma_update = NA_character_,
    gamma_refresh_repeats = NA_integer_,
    gamma_refresh_block = NA_character_,
    gamma_init_mode = NA_character_,
    gamma_jitter_fraction = NA_real_,
    gamma_prior_type = NA_character_,
    gamma_prior_center = NA_real_,
    gamma_prior_sd_eta = NA_real_
  )
  for (nm in names(defaults)) {
    if (!nm %in% names(trace_summary)) trace_summary[[nm]] <- defaults[[nm]]
  }
  trace_summary
}

app_joint_exqdesn_phase145_gamma_chain_memory_summary <- function(trace_summary) {
  trace_summary <- app_joint_exqdesn_phase145_trace_enrich(trace_summary)
  if (!nrow(trace_summary)) {
    return(data.frame(
      case_id = character(), scenario_id = character(), phase136_variant_id = character(),
      tau = numeric(), n_chains = integer(), gamma_mean_min = numeric(),
      gamma_mean_max = numeric(), gamma_mean_gap = numeric(),
      corr_chain_id_gamma_mean = numeric(), gamma_first_min = numeric(),
      gamma_first_max = numeric(), gamma_last_min = numeric(), gamma_last_max = numeric(),
      n_low_mobility_chains = integer(), stringsAsFactors = FALSE
    ))
  }
  gamma <- trace_summary[trace_summary$parameter == "gamma", , drop = FALSE]
  groups <- split(gamma, paste(gamma$case_id, gamma$phase136_variant_id, gamma$tau, sep = "||"))
  app_joint_qdesn_bind_rows(lapply(groups, function(block) {
    mean_val <- as.numeric(block$mean)
    first_val <- as.numeric(block$first)
    last_val <- as.numeric(block$last)
    sd_val <- as.numeric(block$sd)
    drift <- abs(last_val - first_val)
    data.frame(
      case_id = block$case_id[[1L]],
      scenario_id = block$scenario_id[[1L]],
      model_id = block$model_id[[1L]],
      phase136_variant_id = block$phase136_variant_id[[1L]],
      gamma_update = block$gamma_update[[1L]],
      gamma_refresh_repeats = block$gamma_refresh_repeats[[1L]],
      gamma_refresh_block = block$gamma_refresh_block[[1L]],
      gamma_init_mode = block$gamma_init_mode[[1L]],
      gamma_jitter_fraction = block$gamma_jitter_fraction[[1L]],
      tau = as.numeric(block$tau[[1L]]),
      n_chains = nrow(block),
      gamma_mean_min = min(mean_val, na.rm = TRUE),
      gamma_mean_max = max(mean_val, na.rm = TRUE),
      gamma_mean_gap = max(mean_val, na.rm = TRUE) - min(mean_val, na.rm = TRUE),
      corr_chain_id_gamma_mean = app_joint_exqdesn_phase145_safe_cor(block$chain_id, mean_val),
      gamma_first_min = min(first_val, na.rm = TRUE),
      gamma_first_max = max(first_val, na.rm = TRUE),
      gamma_last_min = min(last_val, na.rm = TRUE),
      gamma_last_max = max(last_val, na.rm = TRUE),
      n_low_mobility_chains = sum(sd_val < 0.05 & drift < 0.25, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase145_gamma_sigma_ridge_summary <- function(trace_summary) {
  trace_summary <- app_joint_exqdesn_phase145_trace_enrich(trace_summary)
  if (!nrow(trace_summary)) {
    return(data.frame(
      case_id = character(), scenario_id = character(), phase136_variant_id = character(),
      tau = numeric(), n_chains = integer(), gamma_sigma_chain_mean_cor = numeric(),
      gamma_mean_gap = numeric(), sigma_mean_gap = numeric(), stringsAsFactors = FALSE
    ))
  }
  keep <- trace_summary[trace_summary$parameter %in% c("gamma", "sigma"), , drop = FALSE]
  groups <- split(keep, paste(keep$case_id, keep$phase136_variant_id, keep$tau, sep = "||"))
  app_joint_qdesn_bind_rows(lapply(groups, function(block) {
    gamma <- block[block$parameter == "gamma", c("chain_id", "mean"), drop = FALSE]
    sigma <- block[block$parameter == "sigma", c("chain_id", "mean"), drop = FALSE]
    names(gamma)[names(gamma) == "mean"] <- "gamma_mean"
    names(sigma)[names(sigma) == "mean"] <- "sigma_mean"
    merged <- merge(gamma, sigma, by = "chain_id", all = FALSE)
    gamma_mean <- as.numeric(merged$gamma_mean)
    sigma_mean <- as.numeric(merged$sigma_mean)
    data.frame(
      case_id = block$case_id[[1L]],
      scenario_id = block$scenario_id[[1L]],
      model_id = block$model_id[[1L]],
      phase136_variant_id = block$phase136_variant_id[[1L]],
      gamma_update = block$gamma_update[[1L]],
      gamma_refresh_repeats = block$gamma_refresh_repeats[[1L]],
      gamma_refresh_block = block$gamma_refresh_block[[1L]],
      gamma_init_mode = block$gamma_init_mode[[1L]],
      tau = as.numeric(block$tau[[1L]]),
      n_chains = nrow(merged),
      gamma_sigma_chain_mean_cor = app_joint_exqdesn_phase145_safe_cor(gamma_mean, sigma_mean),
      gamma_mean_gap = max(gamma_mean, na.rm = TRUE) - min(gamma_mean, na.rm = TRUE),
      sigma_mean_gap = max(sigma_mean, na.rm = TRUE) - min(sigma_mean, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase145_tail_region_summary <- function(trace_summary) {
  trace_summary <- app_joint_exqdesn_phase145_trace_enrich(trace_summary)
  if (!nrow(trace_summary)) {
    return(data.frame(
      case_id = character(), scenario_id = character(), phase136_variant_id = character(),
      tau = numeric(), n_chains = integer(), n_lower_tail_region = integer(),
      n_upper_tail_region = integer(), stringsAsFactors = FALSE
    ))
  }
  gamma <- trace_summary[trace_summary$parameter == "gamma", , drop = FALSE]
  gamma <- gamma[as.numeric(gamma$tau) <= 0.10 | as.numeric(gamma$tau) >= 0.90, , drop = FALSE]
  groups <- split(gamma, paste(gamma$case_id, gamma$phase136_variant_id, gamma$tau, sep = "||"))
  app_joint_qdesn_bind_rows(lapply(groups, function(block) {
    support <- app_joint_qvp_exal_support(as.numeric(block$tau[[1L]]))
    rel <- (as.numeric(block$mean) - support$lower[[1L]]) / (support$upper[[1L]] - support$lower[[1L]])
    data.frame(
      case_id = block$case_id[[1L]],
      scenario_id = block$scenario_id[[1L]],
      model_id = block$model_id[[1L]],
      phase136_variant_id = block$phase136_variant_id[[1L]],
      gamma_update = block$gamma_update[[1L]],
      gamma_refresh_repeats = block$gamma_refresh_repeats[[1L]],
      gamma_refresh_block = block$gamma_refresh_block[[1L]],
      gamma_init_mode = block$gamma_init_mode[[1L]],
      tau = as.numeric(block$tau[[1L]]),
      n_chains = nrow(block),
      relative_gamma_position_min = min(rel, na.rm = TRUE),
      relative_gamma_position_max = max(rel, na.rm = TRUE),
      n_lower_tail_region = sum(rel < 0.15, na.rm = TRUE),
      n_upper_tail_region = sum(rel > 0.85, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase145_decision_summary <- function(out_dir, memory, ridge) {
  assessment_path <- file.path(out_dir, "phase136_case_assessment.csv")
  failures_path <- file.path(out_dir, "phase136_chain_worker_failures.csv")
  prep_failures_path <- file.path(out_dir, "phase136_case_variant_prep_failures.csv")
  assessment <- if (file.exists(assessment_path)) app_read_csv(assessment_path) else data.frame()
  failures <- if (file.exists(failures_path)) app_read_csv(failures_path) else data.frame()
  prep_failures <- if (file.exists(prep_failures_path)) app_read_csv(prep_failures_path) else data.frame()
  hard_fail <- nrow(failures) > 0L || nrow(prep_failures) > 0L ||
    (nrow(assessment) && any(assessment$phase136_gate_status == "fail"))
  best <- if (nrow(assessment)) {
    assessment[order(assessment$phase136_gate_status != "pass", assessment$mcmc_forecast_truth_mae, assessment$max_gamma_rhat), , drop = FALSE][1L, , drop = FALSE]
  } else {
    data.frame()
  }
  data.frame(
    decision_id = "phase145_gamma_sampler_root_cause_screen",
    gate_status = if (hard_fail) "fail" else if (nrow(assessment)) "review" else "dry_run",
    case_variant_rows = nrow(assessment),
    worker_failures = nrow(failures),
    prep_failures = nrow(prep_failures),
    best_phase136_variant_id = if (nrow(best)) best$phase136_variant_id[[1L]] else NA_character_,
    best_forecast_mae = if (nrow(best)) best$mcmc_forecast_truth_mae[[1L]] else NA_real_,
    best_fit_mae = if (nrow(best)) best$mcmc_fit_truth_mae[[1L]] else NA_real_,
    max_abs_chain_memory_cor = if (nrow(memory)) app_joint_exqdesn_phase145_safe_max_abs(memory$corr_chain_id_gamma_mean) else NA_real_,
    max_abs_gamma_sigma_cor = if (nrow(ridge)) app_joint_exqdesn_phase145_safe_max_abs(ridge$gamma_sigma_chain_mean_cor) else NA_real_,
    recommendation = if (hard_fail) {
      "fix_phase145_implementation_failures_before_interpreting_sampler_results"
    } else if (nrow(assessment)) {
      "audit_qhat_metrics_and_gamma_geometry_before_any_high_priority_propagation"
    } else {
      "dry_run_only_launch_phase145b_after_registry_review"
    },
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase145_readme <- function(run_config, decision) {
  c(
    "# Joint exQDESN Phase145 Gamma Sampler Root-Cause Screen",
    "",
    "This artifact tests target-preserving sampler changes for the sampled-gamma exAL extension.",
    "It does not change the exAL model and it is not an article-table promotion layer.",
    "",
    sprintf("- Cases: `%s`", run_config$selected_case_ids[[1L]]),
    sprintf("- Variant rows: `%s`", run_config$n_case_variants[[1L]]),
    sprintf("- Chains per variant: `%s`", run_config$n_chains[[1L]]),
    sprintf("- Iterations/burn/thin: `%s/%s/%s`", run_config$mcmc_n_iter[[1L]], run_config$mcmc_burn[[1L]], run_config$mcmc_thin[[1L]]),
    sprintf("- Cores: `%s`", run_config$n_cores[[1L]]),
    "",
    "The main diagnostics are chain-id memory in gamma, gamma-sigma ridge summaries, qhat fit/forecast scores, raw/contract crossings, and runtime.",
    "",
    sprintf("- Gate status: `%s`", decision$gate_status[[1L]]),
    sprintf("- Recommendation: `%s`", decision$recommendation[[1L]])
  )
}

app_joint_exqdesn_phase145_refresh_manifest <- function(out_dir, extra_paths) {
  manifest_path <- file.path(out_dir, "artifact_manifest.csv")
  old_paths <- character()
  if (file.exists(manifest_path)) {
    old <- app_read_csv(manifest_path)
    old <- old[old$relative_path != "artifact_manifest.csv", , drop = FALSE]
    old_paths <- file.path(out_dir, old$relative_path)
    names(old_paths) <- old$label
  }
  paths <- c(old_paths[file.exists(old_paths)], extra_paths)
  app_joint_qdesn_write_manifest(paths, out_dir)
}

app_joint_exqdesn_recover_phase145_gamma_sampler_root_cause_artifacts <- function(out_dir) {
  out_dir <- normalizePath(out_dir, mustWork = TRUE)
  variant_path <- file.path(out_dir, "phase136_variant_registry.csv")
  trace_summary_path <- file.path(out_dir, "mcmc_trace_summary.csv")
  run_config_path <- file.path(out_dir, "run_config.csv")
  if (!file.exists(trace_summary_path)) stop("Cannot recover Phase145 artifacts without mcmc_trace_summary.csv.", call. = FALSE)
  if (!file.exists(run_config_path)) stop("Cannot recover Phase145 artifacts without run_config.csv.", call. = FALSE)
  variant_registry <- if (file.exists(variant_path)) app_read_csv(variant_path) else data.frame()
  trace_summary <- app_read_csv(trace_summary_path)
  trace_summary <- app_joint_exqdesn_phase145_trace_enrich(trace_summary, variant_registry)
  memory <- app_joint_exqdesn_phase145_gamma_chain_memory_summary(trace_summary)
  ridge <- app_joint_exqdesn_phase145_gamma_sigma_ridge_summary(trace_summary)
  tail <- app_joint_exqdesn_phase145_tail_region_summary(trace_summary)
  decision <- app_joint_exqdesn_phase145_decision_summary(out_dir, memory, ridge)
  run_config <- app_read_csv(run_config_path)
  readme_path <- file.path(out_dir, "README_phase145.md")
  writeLines(app_joint_exqdesn_phase145_readme(run_config, decision), readme_path, useBytes = TRUE)
  extra_paths <- c(
    phase145_variant_registry = app_joint_qvp_write_csv(variant_registry, file.path(out_dir, "phase145_variant_registry.csv")),
    gamma_chain_memory_summary = app_joint_qvp_write_csv(memory, file.path(out_dir, "gamma_chain_memory_summary.csv")),
    gamma_sigma_ridge_summary = app_joint_qvp_write_csv(ridge, file.path(out_dir, "gamma_sigma_ridge_summary.csv")),
    tail_gamma_region_summary = app_joint_qvp_write_csv(tail, file.path(out_dir, "tail_gamma_region_summary.csv")),
    phase145_decision_summary = app_joint_qvp_write_csv(decision, file.path(out_dir, "phase145_decision_summary.csv")),
    phase145_readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_exqdesn_phase145_refresh_manifest(out_dir, extra_paths)
  list(
    out_dir = out_dir,
    variant_registry = variant_registry,
    memory = memory,
    ridge = ridge,
    tail = tail,
    decision = decision,
    paths = c(extra_paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest
  )
}

app_joint_exqdesn_run_phase145_gamma_sampler_root_cause_screen <- function(
  out_dir = app_joint_exqdesn_phase145_default_dir(),
  phase135_screening_dir = app_joint_exqdesn_phase136_default_phase135_screening_dir(),
  phase135_audit_dir = app_joint_exqdesn_phase136_default_phase135_audit_dir(),
  fixture_dir = app_joint_exqdesn_phase136_default_fixture_dir(),
  case_ids = app_joint_exqdesn_phase145_default_case_ids(),
  phase145_variant_ids = NULL,
  n_chains = 8L,
  mcmc_n_iter = 10000L,
  mcmc_burn = 3000L,
  mcmc_thin = 2L,
  mcmc_seed_offset = 14500L,
  chain_seed_stride = 100L,
  sigma_upper_multiplier = 50,
  distance_pass = 5,
  chain_pass = 5,
  n_cores = 32L,
  vb_n_cores = 6L,
  trace_write_stride = 50L,
  save_rdata = FALSE,
  dry_run = FALSE
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  phase135 <- app_joint_exqdesn_phase136_load_phase135(phase135_screening_dir, phase135_audit_dir)
  selected <- app_joint_exqdesn_phase136_select_cases(phase135, case_ids = case_ids, case_limit = NULL)
  specs <- app_joint_exqdesn_phase145_select_variant_specs(phase145_variant_ids)
  variant_registry <- app_joint_exqdesn_phase145_variant_registry_for_specs(selected, specs)
  phase136 <- app_joint_exqdesn_run_phase136_gamma_kernel_packet(
    out_dir = out_dir,
    phase135_screening_dir = phase135_screening_dir,
    phase135_audit_dir = phase135_audit_dir,
    fixture_dir = fixture_dir,
    case_ids = case_ids,
    case_limit = NULL,
    variant_ids = "logit_w4",
    logit_eta_width = 4,
    gamma_slice_max_steps = 100L,
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_seed_offset = mcmc_seed_offset,
    chain_seed_stride = chain_seed_stride,
    sigma_upper_multiplier = sigma_upper_multiplier,
    distance_pass = distance_pass,
    chain_pass = chain_pass,
    n_cores = n_cores,
    vb_n_cores = vb_n_cores,
    gamma_init_mode = "vb_jittered",
    gamma_jitter_fraction = 0.02,
    trace_write_stride = trace_write_stride,
    save_rdata = save_rdata,
    dry_run = dry_run,
    variant_registry_override = variant_registry,
    run_id = "joint_qdesn_phase145_gamma_sampler_root_cause_screen"
  )
  trace_summary_path <- file.path(out_dir, "mcmc_trace_summary.csv")
  trace_summary <- if (file.exists(trace_summary_path)) app_read_csv(trace_summary_path) else data.frame()
  trace_summary <- app_joint_exqdesn_phase145_trace_enrich(trace_summary, variant_registry)
  memory <- app_joint_exqdesn_phase145_gamma_chain_memory_summary(trace_summary)
  ridge <- app_joint_exqdesn_phase145_gamma_sigma_ridge_summary(trace_summary)
  tail <- app_joint_exqdesn_phase145_tail_region_summary(trace_summary)
  decision <- app_joint_exqdesn_phase145_decision_summary(out_dir, memory, ridge)
  run_config <- app_read_csv(file.path(out_dir, "run_config.csv"))
  readme_path <- file.path(out_dir, "README_phase145.md")
  writeLines(app_joint_exqdesn_phase145_readme(run_config, decision), readme_path, useBytes = TRUE)
  extra_paths <- c(
    phase145_variant_registry = app_joint_qvp_write_csv(variant_registry, file.path(out_dir, "phase145_variant_registry.csv")),
    gamma_chain_memory_summary = app_joint_qvp_write_csv(memory, file.path(out_dir, "gamma_chain_memory_summary.csv")),
    gamma_sigma_ridge_summary = app_joint_qvp_write_csv(ridge, file.path(out_dir, "gamma_sigma_ridge_summary.csv")),
    tail_gamma_region_summary = app_joint_qvp_write_csv(tail, file.path(out_dir, "tail_gamma_region_summary.csv")),
    phase145_decision_summary = app_joint_qvp_write_csv(decision, file.path(out_dir, "phase145_decision_summary.csv")),
    phase145_readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest_info <- app_joint_exqdesn_phase145_refresh_manifest(out_dir, extra_paths)
  list(
    out_dir = out_dir,
    phase136 = phase136,
    variant_registry = variant_registry,
    memory = memory,
    ridge = ridge,
    tail = tail,
    decision = decision,
    paths = c(phase136$paths[names(phase136$paths) != "artifact_manifest"], extra_paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest
  )
}
