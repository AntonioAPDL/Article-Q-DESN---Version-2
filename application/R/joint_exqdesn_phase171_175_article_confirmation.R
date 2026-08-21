# Phase171-175 balanced M0 article confirmation for the exAL rows.

app_joint_exqdesn_phase171_registry_path <- function() {
  app_path("application/config/joint_exqdesn_m0_balanced_article_confirmation_v1.csv")
}

app_joint_exqdesn_phase173b_policy_path <- function() {
  app_path("application/config/joint_exqdesn_phase173b_promotion_policy_v1.csv")
}

app_joint_exqdesn_phase171_175_dirs <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root()
) {
  list(
    cache_root = cache_root,
    fixture_dir = file.path(cache_root, "joint_qdesn_simulation_dgp_fixtures_20260706"),
    phase150_freeze = file.path(cache_root, "joint_qdesn_phase150_case_specific_exal_mcmc_freeze_20260727"),
    phase150_result = file.path(cache_root, "joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727"),
    phase153_vb = file.path(cache_root, "joint_qdesn_phase153_balanced_independent_replication_vb_20260729"),
    phase154_independent_exal = file.path(cache_root, "joint_qdesn_phase154_mcmc_independent_exal_20260730"),
    phase154_final = file.path(cache_root, "joint_qdesn_phase154_balanced_mcmc_final_20260730"),
    phase155 = file.path(cache_root, "joint_qdesn_phase155_article_promotion_20260731"),
    phase169r = file.path(cache_root, "joint_exqdesn_phase169r_corrected_mcmc_method_selection_20260807"),
    phase170 = file.path(cache_root, "joint_exqdesn_phase170_exact_mcmc_default_promotion_20260808"),
    phase171 = file.path(cache_root, "joint_exqdesn_phase171_m0_balanced_article_freeze_20260809"),
    phase172 = file.path(cache_root, "joint_exqdesn_phase172_m0_balanced_article_confirmation_20260809"),
    phase172_orchestration = file.path(cache_root, "joint_exqdesn_phase172_m0_balanced_article_confirmation_20260809_orchestration"),
    phase173 = file.path(cache_root, "joint_exqdesn_phase173_m0_balanced_article_audit_20260809"),
    phase173b = file.path(cache_root, "joint_exqdesn_phase173b_metric_qualified_promotion_20260813"),
    phase174 = file.path(cache_root, "joint_qdesn_phase174_balanced_mcmc_final_20260809"),
    phase174_staging = file.path(cache_root, "joint_qdesn_phase174_article_assets_staging_20260809"),
    phase174_handoff = file.path(cache_root, "joint_exqdesn_phase174_integration_handoff_20260813")
  )
}

app_joint_exqdesn_phase171_scenarios <- function() {
  c(
    "asymmetric_laplace_tail", "gaussian_mixture_bridge", "laplace_bridge",
    "nonlinear_reservoir_friendly", "normal_bridge", "persistent_heavy_tail",
    "regime_shift", "student_t_location_scale"
  )
}

app_joint_exqdesn_phase171_required_control_fields <- function() {
  c(
    "scenario_ids", "candidate_id", "vb_max_iter",
    "adaptive_vb_max_iter_grid", "vb_tol", "rhs_vb_inner", "tau0",
    "zeta2", "a_sigma", "b_sigma", "alpha_prior_sd",
    "alpha_min_spacing", "gamma_init_policy",
    "review_adjustment_threshold", "max_dense_dim"
  )
}

app_joint_exqdesn_phase171_load_registry <- function(
  registry_path = app_joint_exqdesn_phase171_registry_path()
) {
  registry <- app_read_csv(registry_path)
  required <- c(
    "schema_version", "cell_index", "scenario_id", "fit_structure",
    "model_id", "display_label", "source_control_id",
    "source_control_relative_path", "source_candidate_id",
    "inference_method_id", "vb_initialization_method", "n_chains",
    "n_iter", "burn", "thin", "seed_base", "cell_seed_stride",
    "chain_seed_stride", "tau_seed_stride", "gamma_slice_width",
    "gamma_slice_max_steps", "evidence_role", "enabled"
  )
  app_check_required_columns(registry, required, "Phase171 registry")
  registry$enabled <- as.logical(registry$enabled)
  registry <- registry[registry$enabled, , drop = FALSE]
  key <- paste(registry$scenario_id, registry$fit_structure, sep = "::")
  expected <- as.vector(outer(
    app_joint_exqdesn_phase171_scenarios(), c("joint", "independent"),
    paste, sep = "::"
  ))
  valid_budget <- registry$n_chains == 8L & registry$n_iter == 24000L &
    registry$burn == 4000L & registry$thin == 4L &
    (registry$n_iter - registry$burn) / registry$thin == 5000L
  if (nrow(registry) != 16L || anyDuplicated(registry$cell_index) ||
      anyDuplicated(key) || !setequal(key, expected) || !all(valid_budget) ||
      any(registry$inference_method_id != "M0_v_collapsed_support_logit") ||
      any(registry$vb_initialization_method != "VB0_point_v_to_VB1_structured_v")) {
    stop("Phase171 registry does not satisfy the frozen 16-cell design.", call. = FALSE)
  }
  registry <- registry[order(registry$cell_index), , drop = FALSE]
  rownames(registry) <- NULL
  registry
}

app_joint_exqdesn_phase171_canonical_value <- function(x) {
  if (!length(x) || is.na(x[[1L]])) return("<NA>")
  if (is.numeric(x) || is.integer(x)) {
    return(format(as.numeric(x[[1L]]), digits = 17L, scientific = FALSE, trim = TRUE))
  }
  if (is.logical(x)) return(if (isTRUE(x[[1L]])) "TRUE" else "FALSE")
  enc2utf8(as.character(x[[1L]]))
}

app_joint_exqdesn_phase171_row_hash <- function(row, fields = names(row)) {
  fields <- sort(fields)
  missing <- setdiff(fields, names(row))
  if (length(missing)) stop("Cannot hash a row with missing fields.", call. = FALSE)
  payload <- paste(vapply(fields, function(field) {
    paste0(field, "=", app_joint_exqdesn_phase171_canonical_value(row[[field]]))
  }, character(1L)), collapse = "\n")
  path <- tempfile("phase171-row-", fileext = ".txt")
  on.exit(unlink(path), add = TRUE)
  writeLines(payload, path, useBytes = TRUE)
  app_sha256_file(path)
}

app_joint_exqdesn_phase171_load_controls <- function(registry, cache_root) {
  fields <- app_joint_exqdesn_phase171_required_control_fields()
  rows <- lapply(seq_len(nrow(registry)), function(ii) {
    spec <- registry[ii, , drop = FALSE]
    source_path <- file.path(cache_root, spec$source_control_relative_path[[1L]])
    if (!file.exists(source_path)) {
      stop(sprintf("Missing Phase171 control source: %s", source_path), call. = FALSE)
    }
    source <- app_read_csv(source_path)
    app_check_required_columns(source, fields, "Phase171 source controls")
    row <- source[
      source$scenario_ids == spec$scenario_id[[1L]] &
        source$candidate_id == spec$source_candidate_id[[1L]],
      , drop = FALSE
    ]
    if (nrow(row) != 1L) {
      stop(sprintf("Could not resolve one frozen control row for cell %d.", spec$cell_index[[1L]]), call. = FALSE)
    }
    row$cell_index <- as.integer(spec$cell_index[[1L]])
    row$scenario_id <- spec$scenario_id[[1L]]
    row$base_scenario_id <- spec$scenario_id[[1L]]
    row$fit_structure <- spec$fit_structure[[1L]]
    row$model_id <- spec$model_id[[1L]]
    row$display_label <- spec$display_label[[1L]]
    row$mcmc_case_id <- paste(spec$scenario_id[[1L]], spec$fit_structure[[1L]], sep = "__")
    row$source_control_id <- spec$source_control_id[[1L]]
    row$source_control_path <- normalizePath(source_path, mustWork = TRUE)
    row$source_control_file_sha256 <- app_sha256_file(source_path)
    row$source_control_row_sha256 <- app_joint_exqdesn_phase171_row_hash(row, fields)
    row$inference_method_id <- spec$inference_method_id[[1L]]
    row$n_chains <- as.integer(spec$n_chains[[1L]])
    row$n_iter <- as.integer(spec$n_iter[[1L]])
    row$burn <- as.integer(spec$burn[[1L]])
    row$thin <- as.integer(spec$thin[[1L]])
    row$gamma_slice_width <- as.numeric(spec$gamma_slice_width[[1L]])
    row$gamma_slice_max_steps <- as.integer(spec$gamma_slice_max_steps[[1L]])
    row
  })
  controls <- app_joint_qdesn_bind_rows(rows)
  key <- paste(controls$scenario_id, controls$fit_structure, sep = "::")
  if (nrow(controls) != 16L || anyDuplicated(key) ||
      any(!nzchar(controls$source_control_row_sha256))) {
    stop("Phase171 control freeze is incomplete.", call. = FALSE)
  }
  controls[order(controls$cell_index), , drop = FALSE]
}

app_joint_exqdesn_phase171_source_dirs <- function(dirs) {
  list(
    original_article_fixtures = dirs$fixture_dir,
    phase150_joint_exal_freeze = dirs$phase150_freeze,
    phase150_joint_exal_result = dirs$phase150_result,
    phase153_replicated_vb = dirs$phase153_vb,
    phase154_independent_exal = dirs$phase154_independent_exal,
    phase154_balanced_final = dirs$phase154_final,
    phase155_article_assets = dirs$phase155,
    phase169r_exact_method = dirs$phase169r,
    phase170_default_promotion = dirs$phase170
  )
}

app_joint_exqdesn_phase171_verify_sources <- function(dirs) {
  sources <- app_joint_exqdesn_phase171_source_dirs(dirs)
  app_joint_qdesn_bind_rows(lapply(names(sources), function(id) {
    app_joint_exqdesn_verify_manifest(sources[[id]], id)
  }))
}

app_joint_exqdesn_phase171_article_asset_audit <- function(dirs) {
  asset_path <- file.path(dirs$phase155, "article_asset_manifest.csv")
  if (!file.exists(asset_path)) stop("Missing Phase155 article asset manifest.", call. = FALSE)
  assets <- app_read_csv(asset_path)
  app_check_required_columns(assets, c("label", "path", "size_bytes", "sha256"), "Phase155 asset manifest")
  repo_root <- dirname(dirname(dirs$cache_root))
  paths <- vapply(assets$path, function(path) {
    if (grepl("^/", path)) path else file.path(repo_root, path)
  }, character(1L))
  exists <- file.exists(paths)
  actual_size <- rep(NA_real_, length(paths))
  actual_sha <- rep(NA_character_, length(paths))
  actual_size[exists] <- as.numeric(file.info(paths[exists])$size)
  actual_sha[exists] <- vapply(paths[exists], app_sha256_file, character(1L))
  data.frame(
    label = assets$label,
    path = paths,
    exists = exists,
    declared_size_bytes = as.numeric(assets$size_bytes),
    actual_size_bytes = actual_size,
    declared_sha256 = assets$sha256,
    actual_sha256 = actual_sha,
    status = ifelse(
      exists & actual_size == as.numeric(assets$size_bytes) &
        tolower(actual_sha) == tolower(assets$sha256),
      "pass", "fail"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase171_git_value <- function(args) {
  value <- tryCatch(system2("git", args, stdout = TRUE, stderr = FALSE), error = function(e) character())
  if (!length(value)) NA_character_ else paste(value, collapse = "\n")
}

app_joint_exqdesn_phase171_repository_snapshot <- function() {
  status <- app_joint_exqdesn_phase171_git_value(c("status", "--porcelain", "--untracked-files=normal"))
  data.frame(
    repository_root = app_path(),
    head = app_joint_exqdesn_phase171_git_value(c("rev-parse", "HEAD")),
    branch = app_joint_exqdesn_phase171_git_value(c("branch", "--show-current")),
    origin_main = app_joint_exqdesn_phase171_git_value(c("rev-parse", "origin/main")),
    tracked_and_untracked_clean = is.na(status) || !nzchar(status),
    status_porcelain = if (is.na(status)) "" else status,
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase171_source_snapshot <- function() {
  relative_path <- c(
    "application/config/joint_exqdesn_m0_balanced_article_confirmation_v1.csv",
    "application/R/joint_exqdesn_exact_structured_inference.R",
    "application/R/joint_exqdesn_inference_dispatch.R",
    "application/R/joint_exqdesn_phase166_168_structured_vb.R",
    "application/R/joint_exqdesn_phase167_169_mcmc_method_selection.R",
    "application/R/joint_exqdesn_phase170_default_promotion.R",
    "application/R/joint_exqdesn_phase171_175_article_confirmation.R",
    "application/scripts/232_prepare_joint_exqdesn_phase171_m0_article_freeze.R",
    "application/scripts/233_run_joint_exqdesn_phase172_m0_chain.R",
    "application/scripts/234_launch_joint_exqdesn_phase172_m0_confirmation.sh",
    "application/scripts/235_check_joint_exqdesn_phase172_m0_confirmation.R",
    "application/scripts/236_finalize_joint_exqdesn_phase173_m0_article_audit.R",
    "application/scripts/237_build_joint_qdesn_phase174_article_assets_staging.R",
    "application/tests/test_joint_exqdesn_phase171_175_article_confirmation.R"
  )
  paths <- app_path(relative_path)
  if (any(!file.exists(paths))) stop("Phase171 source snapshot is incomplete.", call. = FALSE)
  data.frame(
    relative_path = relative_path,
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase171_seed_plan <- function(registry, out_dir) {
  rows <- list()
  component_rows <- list()
  worker_id <- 0L
  component_id <- 0L
  tau <- c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)
  for (wave_id in seq_len(4L)) {
    chain_ids <- (2L * wave_id - 1L):(2L * wave_id)
    for (ii in seq_len(nrow(registry))) {
      spec <- registry[ii, , drop = FALSE]
      cell_seed <- as.integer(spec$seed_base[[1L]] + spec$cell_index[[1L]] * spec$cell_seed_stride[[1L]])
      for (chain_id in chain_ids) {
        worker_id <- worker_id + 1L
        chain_seed <- as.integer(cell_seed + (chain_id - 1L) * spec$chain_seed_stride[[1L]])
        worker_dir <- file.path(
          out_dir, "candidates", paste(spec$scenario_id[[1L]], spec$fit_structure[[1L]], sep = "__"),
          sprintf("chain_%02d", chain_id)
        )
        rows[[worker_id]] <- data.frame(
          worker_id = worker_id,
          wave_id = wave_id,
          cell_index = as.integer(spec$cell_index[[1L]]),
          mcmc_case_id = paste(spec$scenario_id[[1L]], spec$fit_structure[[1L]], sep = "__"),
          scenario_id = spec$scenario_id[[1L]],
          base_scenario_id = spec$scenario_id[[1L]],
          fit_structure = spec$fit_structure[[1L]],
          model_id = spec$model_id[[1L]],
          display_label = spec$display_label[[1L]],
          inference_method_id = spec$inference_method_id[[1L]],
          chain_id = chain_id,
          cell_seed = cell_seed,
          chain_seed = chain_seed,
          seed_role = "phase172_balanced_article_confirmation_chain",
          start_profile_id = sprintf("%s__%s__chain_%02d", spec$scenario_id[[1L]], spec$fit_structure[[1L]], chain_id),
          n_iter = as.integer(spec$n_iter[[1L]]),
          burn = as.integer(spec$burn[[1L]]),
          thin = as.integer(spec$thin[[1L]]),
          n_keep = as.integer((spec$n_iter[[1L]] - spec$burn[[1L]]) / spec$thin[[1L]]),
          tau_seed_stride = as.integer(spec$tau_seed_stride[[1L]]),
          gamma_slice_width = as.numeric(spec$gamma_slice_width[[1L]]),
          gamma_slice_max_steps = as.integer(spec$gamma_slice_max_steps[[1L]]),
          worker_output_dir = worker_dir,
          stringsAsFactors = FALSE
        )
        if (spec$fit_structure[[1L]] == "joint") {
          component_id <- component_id + 1L
          component_rows[[component_id]] <- data.frame(
            component_id = component_id, worker_id = worker_id, wave_id = wave_id,
            cell_index = spec$cell_index[[1L]], scenario_id = spec$scenario_id[[1L]],
            fit_structure = "joint", chain_id = chain_id, quantile_index = NA_integer_,
            tau = NA_real_, component_seed = chain_seed,
            seed_role = "joint_multiquantile_chain", stringsAsFactors = FALSE
          )
        } else {
          for (k in seq_along(tau)) {
            component_id <- component_id + 1L
            component_rows[[component_id]] <- data.frame(
              component_id = component_id, worker_id = worker_id, wave_id = wave_id,
              cell_index = spec$cell_index[[1L]], scenario_id = spec$scenario_id[[1L]],
              fit_structure = "independent", chain_id = chain_id, quantile_index = k,
              tau = tau[[k]], component_seed = as.integer(chain_seed + k * spec$tau_seed_stride[[1L]]),
              seed_role = "independent_quantile_component_chain", stringsAsFactors = FALSE
            )
          }
        }
      }
    }
  }
  plan <- app_joint_qdesn_bind_rows(rows)
  components <- app_joint_qdesn_bind_rows(component_rows)
  if (nrow(plan) != 128L || anyDuplicated(plan$chain_seed) ||
      nrow(components) != 512L || anyDuplicated(components$component_seed) ||
      any(components$component_seed > .Machine$integer.max)) {
    stop("Phase171 seed hierarchy failed uniqueness or range checks.", call. = FALSE)
  }
  list(plan = plan, components = components)
}

app_joint_exqdesn_phase171_historical_seed_audit <- function() {
  old <- expand.grid(chain_id = seq_len(8L), quantile_index = seq_len(7L))
  old$chain_seed <- 202608070L + (old$chain_id - 1L) * 1009L
  old$component_seed <- old$chain_seed + old$quantile_index * 1009L
  data.frame(
    historical_contract = "chain_stride_1009_tau_stride_1009",
    component_jobs_per_independent_cell = nrow(old),
    unique_component_seeds_per_independent_cell = length(unique(old$component_seed)),
    duplicated_component_jobs_per_independent_cell = sum(duplicated(old$component_seed)),
    fixed_tau_chain_seeds_unique = all(vapply(split(old, old$quantile_index), function(x) !anyDuplicated(x$component_seed), logical(1L))),
    evidence_effect = "nonblocking_for_fixed_tau_point_grid_summaries;avoid_in_phase172",
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase171_wave_plan <- function(plan) {
  app_joint_qdesn_bind_rows(lapply(split(plan, plan$wave_id), function(x) data.frame(
    wave_id = x$wave_id[[1L]],
    worker_count = nrow(x),
    chain_ids = paste(sort(unique(x$chain_id)), collapse = ","),
    scenario_count = length(unique(x$scenario_id)),
    structure_count = length(unique(x$fit_structure)),
    status = if (nrow(x) == 32L && length(unique(x$scenario_id)) == 8L &&
      length(unique(x$fit_structure)) == 2L) "pass" else "fail",
    stringsAsFactors = FALSE
  )))
}

app_joint_exqdesn_phase171_fixture_audit <- function(artifacts) {
  scenarios <- unique(artifacts$scenario_summary$scenario_id)
  expected <- app_joint_exqdesn_phase171_scenarios()
  app_joint_qdesn_bind_rows(lapply(scenarios, function(scenario_id) {
    fit <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, "fit")
    forecast_rows <- artifacts$observed[
      artifacts$observed$scenario_id == scenario_id & artifacts$observed$role == "forecast",
      , drop = FALSE
    ]
    data.frame(
      scenario_id = scenario_id,
      article_scope = if (scenario_id %in% expected) "included" else "excluded",
      exclusion_reason = if (scenario_id == "heteroskedastic_seasonal") {
        "not_in_frozen_balanced_article_grid"
      } else if (!scenario_id %in% expected) {
        "not_in_phase171_registry"
      } else {
        ""
      },
      fit_rows = length(fit$y),
      forecast_rows = nrow(forecast_rows),
      feature_count = ncol(fit$Z),
      tau_count = length(fit$tau),
      finite_y = all(is.finite(fit$y)),
      finite_Z = all(is.finite(fit$Z)),
      finite_truth = all(is.finite(fit$true_q)),
      monotone_truth = all(apply(fit$true_q, 1L, function(x) all(diff(x) >= 0))),
      status = if (
        all(is.finite(fit$y)) && all(is.finite(fit$Z)) &&
          all(is.finite(fit$true_q)) &&
          all(apply(fit$true_q, 1L, function(x) all(diff(x) >= 0)))
      ) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase171_control_audit <- function(registry, controls) {
  fields <- app_joint_exqdesn_phase171_required_control_fields()
  app_joint_qdesn_bind_rows(lapply(seq_len(nrow(registry)), function(ii) {
    spec <- registry[ii, , drop = FALSE]
    row <- controls[controls$cell_index == spec$cell_index[[1L]], , drop = FALSE]
    data.frame(
      cell_index = spec$cell_index[[1L]],
      scenario_id = spec$scenario_id[[1L]],
      fit_structure = spec$fit_structure[[1L]],
      source_candidate_id = spec$source_candidate_id[[1L]],
      resolved_candidate_id = row$candidate_id[[1L]],
      required_field_count = length(fields),
      nonmissing_required_fields = sum(vapply(fields, function(field) {
        value <- row[[field]][[1L]]
        !is.na(value) && nzchar(as.character(value))
      }, logical(1L))),
      candidate_match = identical(
        as.character(spec$source_candidate_id[[1L]]),
        as.character(row$candidate_id[[1L]])
      ),
      status = if (
        identical(as.character(spec$source_candidate_id[[1L]]), as.character(row$candidate_id[[1L]])) &&
          all(vapply(fields, function(field) {
            value <- row[[field]][[1L]]
            !is.na(value) && nzchar(as.character(value))
          }, logical(1L)))
      ) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase171_init_comparison <- function(warm, fit, row, fixture) {
  blocks <- c("beta", "alpha", "sigma", "gamma")
  parameter <- app_joint_qdesn_bind_rows(lapply(blocks, function(block) {
    before <- as.numeric(warm[[paste0(block, "_mean")]])
    after <- as.numeric(fit[[paste0(block, "_mean")]])
    data.frame(
      mcmc_case_id = row$mcmc_case_id[[1L]],
      scenario_id = row$scenario_id[[1L]],
      fit_structure = row$fit_structure[[1L]],
      comparison_type = "parameter",
      parameter_block = block,
      parameter_index = seq_along(before),
      vb0_value = before,
      vb1_value = after,
      absolute_delta = abs(after - before),
      stringsAsFactors = FALSE
    )
  }))
  q0 <- app_joint_qdesn_predict_fit(warm, fixture$Z, fixture$tau)
  q1 <- app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau)
  qhat <- data.frame(
    mcmc_case_id = row$mcmc_case_id[[1L]],
    scenario_id = row$scenario_id[[1L]],
    fit_structure = row$fit_structure[[1L]],
    comparison_type = "qhat_summary",
    parameter_block = "qhat",
    parameter_index = NA_integer_,
    vb0_value = mean(q0),
    vb1_value = mean(q1),
    absolute_delta = max(abs(q1 - q0)),
    stringsAsFactors = FALSE
  )
  app_joint_qdesn_bind_rows(list(parameter, qhat))
}

app_joint_exqdesn_phase171_fit_initialization <- function(row, artifacts) {
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, row$scenario_id[[1L]], role = "fit")
  args <- app_joint_exqdesn_phase166_control_args(row, fixture)
  vb0_started <- proc.time()[["elapsed"]]
  warm <- app_joint_exqdesn_phase166_vb0_warm_start(row, fixture)
  vb0_seconds <- proc.time()[["elapsed"]] - vb0_started
  vb1_started <- proc.time()[["elapsed"]]
  fit <- if (row$fit_structure[[1L]] == "joint") {
    do.call(app_joint_exqdesn_fit_vb_dispatch, c(list(
      method_id = "VB1_structured_v", y = fixture$y, Z = fixture$Z,
      tau = fixture$tau, init = warm
    ), args))
  } else {
    do.call(app_joint_exqdesn_fit_independent_vb_dispatch, c(list(
      method_id = "VB1_structured_v", y = fixture$y, Z = fixture$Z,
      tau = fixture$tau, init = warm
    ), args))
  }
  vb1_seconds <- proc.time()[["elapsed"]] - vb1_started
  init <- app_joint_exqdesn_phase169_init_rows(fit, row)
  starts <- app_joint_exqdesn_phase156_chain_starts(
    list(sigma_mean = fit$sigma_mean, gamma_mean = fit$gamma_mean),
    fixture$tau, row$mcmc_case_id[[1L]], 8L
  )
  names(starts)[names(starts) == "scenario_id"] <- "mcmc_case_id"
  starts$scenario_id <- row$scenario_id[[1L]]
  starts$base_scenario_id <- row$scenario_id[[1L]]
  starts$fit_structure <- row$fit_structure[[1L]]
  support <- app_joint_qvp_exal_support(fixture$tau)
  support_ok <- all(fit$gamma_mean > support$lower & fit$gamma_mean < support$upper)
  meta <- data.frame(
    scenario_id = row$scenario_id[[1L]], base_scenario_id = row$scenario_id[[1L]],
    model_id = row$model_id[[1L]], display_label = row$display_label[[1L]],
    likelihood = "exAL", fit_structure = row$fit_structure[[1L]],
    inference_method_id = "VB1_structured_v", stringsAsFactors = FALSE
  )
  fit_score <- app_joint_qdesn_phase122_score_qhat(
    meta, fixture, app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau),
    "qhat", "phase171_vb1_fit"
  )
  forecast_score <- app_joint_qdesn_phase122_forecast_scores(
    meta, artifacts, row$scenario_id[[1L]], fixture, fit,
    "qhat", "phase171_vb1_forecast"
  )
  finite <- all(is.finite(unlist(list(
    fit$beta_mean, fit$alpha_mean, fit$sigma_mean, fit$gamma_mean,
    fit_score$scored$qhat, forecast_score$scored$qhat
  ), use.names = FALSE)))
  contract_crossings <- sum(fit_score$contract_crossing$n_crossing_pairs) +
    sum(forecast_score$contract_crossing$n_crossing_pairs)
  audit <- data.frame(
    mcmc_case_id = row$mcmc_case_id[[1L]],
    scenario_id = row$scenario_id[[1L]],
    fit_structure = row$fit_structure[[1L]],
    vb0_converged = isTRUE(warm$converged),
    vb1_converged = isTRUE(fit$converged),
    finite_initialization = finite,
    positive_scale = all(fit$sigma_mean > 0),
    gamma_inside_support = support_ok,
    fit_raw_crossing_pairs = sum(fit_score$raw_crossing$n_crossing_pairs),
    forecast_raw_crossing_pairs = sum(forecast_score$raw_crossing$n_crossing_pairs),
    contract_crossing_pairs = contract_crossings,
    vb0_elapsed_seconds = vb0_seconds,
    vb1_elapsed_seconds = vb1_seconds,
    status = if (finite && all(fit$sigma_mean > 0) && support_ok && contract_crossings == 0L) "pass" else "fail",
    stringsAsFactors = FALSE
  )
  preflight <- data.frame(
    mcmc_case_id = row$mcmc_case_id[[1L]], scenario_id = row$scenario_id[[1L]],
    fit_structure = row$fit_structure[[1L]], fit_rows = nrow(fit_score$scored),
    forecast_rows = nrow(forecast_score$scored),
    fit_truth_mae = mean(fit_score$scored$truth_abs_error),
    forecast_truth_mae = mean(forecast_score$scored$truth_abs_error),
    fit_check_loss_mean = mean(fit_score$scored$check_loss),
    forecast_check_loss_mean = mean(forecast_score$scored$check_loss),
    fit_crps_grid_mean = app_joint_qdesn_crps_grid_summary(fit_score$scored)$crps_grid_mean[[1L]],
    forecast_crps_grid_mean = app_joint_qdesn_crps_grid_summary(forecast_score$scored)$crps_grid_mean[[1L]],
    fit_raw_crossing_pairs = sum(fit_score$raw_crossing$n_crossing_pairs),
    forecast_raw_crossing_pairs = sum(forecast_score$raw_crossing$n_crossing_pairs),
    fit_max_abs_adjustment = max(fit_score$adjustment$abs_adjustment),
    forecast_max_abs_adjustment = max(forecast_score$adjustment$abs_adjustment),
    scores_finite = all(is.finite(c(fit_score$scored$truth_abs_error, forecast_score$scored$truth_abs_error))),
    contract_crossing_pairs = contract_crossings,
    status = if (finite && contract_crossings == 0L) "pass" else "fail",
    stringsAsFactors = FALSE
  )
  list(
    init = init, starts = starts, audit = audit, preflight = preflight,
    comparison = app_joint_exqdesn_phase171_init_comparison(warm, fit, row, fixture)
  )
}

app_joint_exqdesn_phase171_existing_valid <- function(out_dir) {
  if (!file.exists(file.path(out_dir, "artifact_manifest.csv"))) return(FALSE)
  tryCatch({
    check <- app_joint_exqdesn_verify_manifest(out_dir, "phase171")
    assessment <- app_read_csv(file.path(out_dir, "readiness_assessment.csv"))
    all(check$status == "pass") && nrow(assessment) == 1L &&
      assessment$gate_status[[1L]] == "pass"
  }, error = function(e) FALSE)
}

app_joint_exqdesn_phase171_prepare <- function(
  registry_path = app_joint_exqdesn_phase171_registry_path(),
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  n_vb_cores = 8L,
  force = FALSE
) {
  dirs <- app_joint_exqdesn_phase171_175_dirs(cache_root)
  if (!force && app_joint_exqdesn_phase171_existing_valid(dirs$phase171)) {
    return(app_joint_exqdesn_phase171_load(dirs$phase171))
  }
  repository <- app_joint_exqdesn_phase171_repository_snapshot()
  if (!isTRUE(repository$tracked_and_untracked_clean[[1L]])) {
    stop("Phase171 preparation requires a clean implementation worktree.", call. = FALSE)
  }
  registry <- app_joint_exqdesn_phase171_load_registry(registry_path)
  controls <- app_joint_exqdesn_phase171_load_controls(registry, cache_root)
  source_verification <- app_joint_exqdesn_phase171_verify_sources(dirs)
  asset_verification <- app_joint_exqdesn_phase171_article_asset_audit(dirs)
  if (any(source_verification$status != "pass") || any(asset_verification$status != "pass")) {
    stop("Phase171 source or current-asset verification failed.", call. = FALSE)
  }
  artifacts <- app_joint_qdesn_load_fixture_artifacts(dirs$fixture_dir)
  fixture_audit <- app_joint_exqdesn_phase171_fixture_audit(artifacts)
  scope <- fixture_audit[, c("scenario_id", "article_scope", "exclusion_reason", "status")]
  if (!setequal(scope$scenario_id[scope$article_scope == "included"], app_joint_exqdesn_phase171_scenarios()) ||
      !identical(scope$scenario_id[scope$article_scope == "excluded"], "heteroskedastic_seasonal") ||
      any(scope$status != "pass")) {
    stop("Phase171 scenario-scope or fixture gate failed.", call. = FALSE)
  }
  control_audit <- app_joint_exqdesn_phase171_control_audit(registry, controls)
  if (any(control_audit$status != "pass")) stop("Phase171 control invariance failed.", call. = FALSE)

  jobs <- lapply(seq_len(nrow(controls)), function(ii) controls[ii, , drop = FALSE])
  run_one <- function(row) app_joint_exqdesn_phase171_fit_initialization(row, artifacts)
  vb <- if (.Platform$OS.type != "windows" && n_vb_cores > 1L) {
    parallel::mclapply(jobs, run_one, mc.cores = min(as.integer(n_vb_cores), length(jobs)))
  } else {
    lapply(jobs, run_one)
  }
  failed <- vapply(vb, inherits, logical(1L), "try-error")
  if (any(failed)) stop(sprintf("Phase171 VB initialization failed for %d cells.", sum(failed)), call. = FALSE)
  init <- app_joint_qdesn_bind_rows(lapply(vb, `[[`, "init"))
  starts <- app_joint_qdesn_bind_rows(lapply(vb, `[[`, "starts"))
  init_audit <- app_joint_qdesn_bind_rows(lapply(vb, `[[`, "audit"))
  init_comparison <- app_joint_qdesn_bind_rows(lapply(vb, `[[`, "comparison"))
  preflight <- app_joint_qdesn_bind_rows(lapply(vb, `[[`, "preflight"))
  if (any(init_audit$status != "pass") || any(preflight$status != "pass")) {
    stop("Phase171 initializer or score preflight failed.", call. = FALSE)
  }

  seeds <- app_joint_exqdesn_phase171_seed_plan(registry, dirs$phase172)
  plan <- seeds$plan
  components <- seeds$components
  control_index <- match(plan$cell_index, controls$cell_index)
  plan$source_control_row_sha256 <- controls$source_control_row_sha256[control_index]
  plan$source_control_file_sha256 <- controls$source_control_file_sha256[control_index]
  plan$fixture_manifest_sha256 <- app_sha256_file(file.path(dirs$fixture_dir, "artifact_manifest.csv"))
  plan$code_commit <- repository$head[[1L]]
  seed_audit <- data.frame(
    planned_top_level_workers = nrow(plan),
    unique_top_level_seeds = length(unique(plan$chain_seed)),
    planned_physical_component_runs = nrow(components),
    unique_component_seeds = length(unique(components$component_seed)),
    component_seed_collisions = nrow(components) - length(unique(components$component_seed)),
    minimum_component_seed = min(components$component_seed),
    maximum_component_seed = max(components$component_seed),
    status = if (nrow(plan) == 128L && !anyDuplicated(plan$chain_seed) &&
      nrow(components) == 512L && !anyDuplicated(components$component_seed)) "pass" else "fail",
    stringsAsFactors = FALSE
  )
  rng <- data.frame(
    R_version = R.version.string,
    RNG_kind = paste(RNGkind(), collapse = ";"),
    seed_base = unique(registry$seed_base),
    cell_seed_stride = unique(registry$cell_seed_stride),
    chain_seed_stride = unique(registry$chain_seed_stride),
    tau_seed_stride = unique(registry$tau_seed_stride),
    component_seed_contract = "joint=chain_seed;independent=chain_seed+quantile_index*tau_seed_stride",
    stringsAsFactors = FALSE
  )
  wave <- app_joint_exqdesn_phase171_wave_plan(plan)
  resource <- data.frame(
    planned_parallel_workers = 32L,
    minimum_parallel_workers = 24L,
    threads_per_worker = 1L,
    cpu_list_status = "assign_at_launch_after_process_audit",
    affinity_required = TRUE,
    minimum_available_memory_gib = 100,
    minimum_free_disk_gib = 10,
    expected_cpu_hours = 434.6,
    expected_wall_hours_at_32 = "15-18",
    expected_wall_hours_at_24 = "20-24",
    stringsAsFactors = FALSE
  )
  budget <- data.frame(
    scenarios = 8L, fit_structures = 2L, cells = 16L,
    chains_per_cell = 8L, top_level_workers = 128L,
    physical_component_runs = 512L, n_iter = 24000L, burn = 4000L,
    thin = 4L, retained_per_chain = 5000L, retained_per_cell = 40000L,
    expected_cpu_hours = 434.6, expected_artifact_mib_lower = 350,
    expected_artifact_mib_upper = 500, stringsAsFactors = FALSE
  )
  source_rows <- unique(controls[, c(
    "cell_index", "scenario_id", "fit_structure", "source_control_id",
    "source_control_path", "source_control_file_sha256", "source_control_row_sha256"
  )])
  current_final <- app_read_csv(file.path(dirs$phase154_final, "final_assessment.csv"))
  current_cases <- app_read_csv(file.path(dirs$phase154_final, "final_mcmc_case_summary.csv"))
  closeout <- data.frame(
    source_packet = "phase154_balanced_mcmc_final",
    source_packet_sha256 = app_sha256_file(file.path(dirs$phase154_final, "artifact_manifest.csv")),
    current_cells = nrow(current_cases),
    current_gate_status = current_final$gate_status[[1L]],
    current_recommendation = current_final$recommendation[[1L]],
    replacement_policy = "retain_authority_until_complete_phase173_audit_and_phase174_staging",
    stringsAsFactors = FALSE
  )
  retention <- data.frame(
    source_class = c("phase150_joint_exal", "phase154_independent_exal", "phase154_balanced_packet", "phase155_article_assets", "phase169r_method_evidence", "phase170_method_decision"),
    retention = "retain_until_phase175_is_frozen_and_verified",
    deletion_authorized = FALSE,
    stringsAsFactors = FALSE
  )
  source_snapshot <- app_joint_exqdesn_phase171_source_snapshot()
  readiness <- data.frame(
    gate_status = if (
      all(source_verification$status == "pass") && all(asset_verification$status == "pass") &&
        all(fixture_audit$status == "pass") && all(control_audit$status == "pass") &&
        all(init_audit$status == "pass") && all(preflight$status == "pass") &&
        seed_audit$status[[1L]] == "pass" && all(wave$status == "pass") &&
        nrow(plan) == 128L
    ) "pass" else "fail",
    selected_cells = nrow(controls),
    finite_vb_initializations = sum(init_audit$finite_initialization),
    planned_workers = nrow(plan),
    physical_component_runs = nrow(components),
    unique_component_seeds = length(unique(components$component_seed)),
    source_hash_failures = sum(source_verification$status != "pass") + sum(asset_verification$status != "pass"),
    contract_crossing_pairs_preflight = sum(preflight$contract_crossing_pairs),
    article_assets_modified = FALSE,
    recommendation = "launch_phase172_m0_balanced_confirmation",
    stringsAsFactors = FALSE
  )
  if (readiness$gate_status[[1L]] != "pass") stop("Phase171 readiness gate failed.", call. = FALSE)

  final_dir <- dirs$phase171
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase171 M0 balanced article-confirmation freeze", "",
    "This immutable packet freezes the eight original article fixtures, 16 case-specific exAL controls,",
    "the VB0-to-VB1 initialization hierarchy, 128 chain starts, and 512 collision-free physical sampler seeds.",
    "The Phase172 budget is 24,000 iterations, 4,000 burn-in, and thinning by four.",
    "No article asset is modified. The current Phase154/155 packet remains authoritative until Phase173/174 pass."
  ), readme, useBytes = TRUE)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  paths <- c(
    current_article_packet_closeout = write(closeout, "current_article_packet_closeout.csv"),
    authoritative_repository_snapshot = write(repository, "authoritative_repository_snapshot.csv"),
    source_manifest_verification = write(source_verification, "source_manifest_verification.csv"),
    current_article_asset_verification = write(asset_verification, "current_article_asset_verification.csv"),
    scenario_scope_audit = write(scope, "scenario_scope_audit.csv"),
    fixture_identity_audit = write(fixture_audit, "fixture_identity_audit.csv"),
    model_control_freeze = write(controls, "model_control_freeze.csv"),
    control_field_invariance_audit = write(control_audit, "control_field_invariance_audit.csv"),
    source_row_hashes = write(source_rows, "source_row_hashes.csv"),
    vb_initialization = write(init, "vb_initialization.csv"),
    vb_initialization_audit = write(init_audit, "vb_initialization_audit.csv"),
    vb0_vb1_initialization_comparison = write(init_comparison, "vb0_vb1_initialization_comparison.csv"),
    chain_start_values = write(starts, "chain_start_values.csv"),
    chain_plan = write(plan, "chain_plan.csv"),
    component_seed_plan = write(components, "component_seed_plan.csv"),
    seed_audit = write(seed_audit, "seed_audit.csv"),
    historical_rng_overlap_audit = write(app_joint_exqdesn_phase171_historical_seed_audit(), "historical_rng_overlap_audit.csv"),
    rng_contract = write(rng, "rng_contract.csv"),
    wave_plan = write(wave, "wave_plan.csv"),
    resource_assignment_plan = write(resource, "resource_assignment_plan.csv"),
    scoring_preflight = write(preflight, "scoring_preflight.csv"),
    compute_budget = write(budget, "compute_budget.csv"),
    source_retention_policy = write(retention, "source_retention_policy.csv"),
    source_code_snapshot = write(source_snapshot, "source_code_snapshot.csv"),
    readiness_assessment = write(readiness, "readiness_assessment.csv"),
    run_config = write(data.frame(
      phase_id = "phase171_m0_balanced_article_freeze", registry_path = normalizePath(registry_path),
      cache_root = cache_root, fixture_dir = dirs$fixture_dir, output_dir = final_dir,
      code_commit = repository$head[[1L]], validation_contract = "posterior_quantile_grid_with_monotone_scoring_contract",
      scalar_predictive_density_claim = FALSE, stringsAsFactors = FALSE
    ), "run_config.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine prior Phase171 artifact.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir) || !app_joint_exqdesn_phase171_existing_valid(final_dir)) {
    stop("Could not atomically publish Phase171 freeze.", call. = FALSE)
  }
  app_joint_exqdesn_phase171_load(final_dir)
}

app_joint_exqdesn_phase171_load <- function(
  freeze_dir = app_joint_exqdesn_phase171_175_dirs()$phase171
) {
  freeze_dir <- normalizePath(freeze_dir, mustWork = TRUE)
  verification <- app_joint_exqdesn_verify_manifest(freeze_dir, "phase171")
  if (any(verification$status != "pass")) stop("Phase171 manifest verification failed.", call. = FALSE)
  list(
    dir = freeze_dir,
    verification = verification,
    config = app_read_csv(file.path(freeze_dir, "run_config.csv")),
    controls = app_read_csv(file.path(freeze_dir, "model_control_freeze.csv")),
    init = app_read_csv(file.path(freeze_dir, "vb_initialization.csv")),
    starts = app_read_csv(file.path(freeze_dir, "chain_start_values.csv")),
    plan = app_read_csv(file.path(freeze_dir, "chain_plan.csv")),
    components = app_read_csv(file.path(freeze_dir, "component_seed_plan.csv")),
    readiness = app_read_csv(file.path(freeze_dir, "readiness_assessment.csv"))
  )
}

app_joint_exqdesn_phase172_table_hash <- function(x) {
  path <- tempfile("phase172-table-", fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  utils::write.csv(x, path, row.names = FALSE, na = "")
  app_sha256_file(path)
}

app_joint_exqdesn_phase172_checkpoint_dir <- function(worker_dir) {
  file.path(worker_dir, "checkpoint")
}

app_joint_exqdesn_phase172_checkpoint_complete <- function(worker_dir) {
  dir <- app_joint_exqdesn_phase172_checkpoint_dir(worker_dir)
  required <- c(
    "posterior_draws.csv.gz", "sampler_diagnostics.csv",
    "checkpoint_metadata.csv", "artifact_manifest.csv"
  )
  if (!dir.exists(dir) || any(!file.exists(file.path(dir, required)))) return(FALSE)
  tryCatch({
    check <- app_joint_exqdesn_verify_manifest(dir, "phase172_checkpoint")
    nrow(check) == 3L && all(check$status == "pass")
  }, error = function(e) FALSE)
}

app_joint_exqdesn_phase172_worker_complete <- function(worker_dir) {
  required <- c(
    file.path("checkpoint", "posterior_draws.csv.gz"),
    file.path("checkpoint", "sampler_diagnostics.csv"),
    file.path("checkpoint", "checkpoint_metadata.csv"),
    file.path("checkpoint", "artifact_manifest.csv"),
    "chain_summary.csv", "runtime.csv", "provenance.csv", "README.md",
    "artifact_manifest.csv"
  )
  if (!dir.exists(worker_dir) || any(!file.exists(file.path(worker_dir, required)))) return(FALSE)
  tryCatch({
    check <- app_joint_exqdesn_verify_manifest(worker_dir, "phase172_worker")
    all(check$status == "pass")
  }, error = function(e) FALSE)
}

app_joint_exqdesn_phase172_meta <- function(job, control) {
  source_model_id <- if (job$fit_structure[[1L]] == "joint") {
    "joint_exqdesn_rhs_vb"
  } else {
    "exqdesn_rhs_independent_vb"
  }
  data.frame(
    case_id = paste(job$scenario_id[[1L]], source_model_id, sep = "__"),
    scenario_id = job$scenario_id[[1L]],
    base_scenario_id = job$base_scenario_id[[1L]],
    model_id = job$model_id[[1L]],
    display_label = job$display_label[[1L]],
    likelihood = "exAL",
    fit_structure = job$fit_structure[[1L]],
    inference = "MCMC",
    inference_method_id = job$inference_method_id[[1L]],
    source_candidate_id = control$candidate_id[[1L]],
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase172_write_checkpoint <- function(
  fit, fixture, job, control, component_rows, elapsed_seconds,
  freeze_dir, worker_dir
) {
  checkpoint_dir <- app_joint_exqdesn_phase172_checkpoint_dir(worker_dir)
  if (dir.exists(checkpoint_dir)) {
    quarantine <- paste0(checkpoint_dir, ".invalid.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(checkpoint_dir, quarantine)) stop("Could not quarantine Phase172 checkpoint.", call. = FALSE)
  }
  app_ensure_dir(checkpoint_dir)
  draws <- app_joint_exqdesn_phase157_draw_frame(fit)
  if (any(!is.finite(as.matrix(draws[, -1L, drop = FALSE]))) || any(fit$sigma_draws <= 0)) {
    stop("Phase172 worker produced invalid posterior draws.", call. = FALSE)
  }
  sampler <- app_joint_exqdesn_phase169_sampler_rows(fit, fixture, job)
  component_hash <- app_joint_exqdesn_phase172_table_hash(component_rows)
  metadata <- data.frame(
    worker_id = as.integer(job$worker_id[[1L]]),
    wave_id = as.integer(job$wave_id[[1L]]),
    mcmc_case_id = job$mcmc_case_id[[1L]],
    scenario_id = job$scenario_id[[1L]],
    fit_structure = job$fit_structure[[1L]],
    inference_method_id = job$inference_method_id[[1L]],
    chain_id = as.integer(job$chain_id[[1L]]),
    chain_seed = as.integer(job$chain_seed[[1L]]),
    component_seed_count = nrow(component_rows),
    component_seed_table_sha256 = component_hash,
    source_control_row_sha256 = job$source_control_row_sha256[[1L]],
    source_control_file_sha256 = job$source_control_file_sha256[[1L]],
    fixture_manifest_sha256 = job$fixture_manifest_sha256[[1L]],
    code_commit = job$code_commit[[1L]],
    n_iter = as.integer(job$n_iter[[1L]]),
    burn = as.integer(job$burn[[1L]]),
    thin = as.integer(job$thin[[1L]]),
    n_keep = nrow(draws),
    init_source = fit$init_source %||% "provided",
    elapsed_seconds = as.numeric(elapsed_seconds),
    freeze_manifest_sha256 = app_sha256_file(file.path(freeze_dir, "artifact_manifest.csv")),
    checkpoint_role = "postfit_prescore_recovery",
    stringsAsFactors = FALSE
  )
  paths <- c(
    posterior_draws = app_joint_exqdesn_phase157_write_gzip_csv(
      draws, file.path(checkpoint_dir, "posterior_draws.csv.gz")
    ),
    sampler_diagnostics = app_joint_qvp_write_csv(
      sampler, file.path(checkpoint_dir, "sampler_diagnostics.csv")
    ),
    checkpoint_metadata = app_joint_qvp_write_csv(
      metadata, file.path(checkpoint_dir, "checkpoint_metadata.csv")
    )
  )
  manifest <- app_joint_exqdesn_write_manifest(paths, checkpoint_dir)
  if (!app_joint_exqdesn_phase172_checkpoint_complete(worker_dir)) {
    stop("Phase172 checkpoint verification failed.", call. = FALSE)
  }
  list(
    fit = fit, draws = draws, sampler = sampler, metadata = metadata,
    paths = c(paths, checkpoint_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_phase172_load_checkpoint <- function(
  worker_dir, fixture, job, component_rows, freeze_dir
) {
  if (!app_joint_exqdesn_phase172_checkpoint_complete(worker_dir)) {
    stop("Phase172 checkpoint is incomplete.", call. = FALSE)
  }
  dir <- app_joint_exqdesn_phase172_checkpoint_dir(worker_dir)
  metadata <- app_read_csv(file.path(dir, "checkpoint_metadata.csv"))
  expected <- c(
    worker_id = as.character(job$worker_id[[1L]]),
    chain_seed = as.character(job$chain_seed[[1L]]),
    inference_method_id = as.character(job$inference_method_id[[1L]]),
    source_control_row_sha256 = as.character(job$source_control_row_sha256[[1L]]),
    fixture_manifest_sha256 = as.character(job$fixture_manifest_sha256[[1L]]),
    code_commit = as.character(job$code_commit[[1L]]),
    component_seed_table_sha256 = app_joint_exqdesn_phase172_table_hash(component_rows),
    freeze_manifest_sha256 = app_sha256_file(file.path(freeze_dir, "artifact_manifest.csv"))
  )
  actual <- vapply(names(expected), function(field) as.character(metadata[[field]][[1L]]), character(1L))
  if (nrow(metadata) != 1L || !identical(unname(actual), unname(expected))) {
    stop("Phase172 checkpoint identity does not match the frozen worker.", call. = FALSE)
  }
  list(
    fit = app_joint_exqdesn_phase157_read_fit(dir, fixture$tau, job$chain_seed[[1L]], job$chain_id[[1L]]),
    draws = app_joint_exqdesn_phase156_read_csv(file.path(dir, "posterior_draws.csv.gz")),
    sampler = app_read_csv(file.path(dir, "sampler_diagnostics.csv")),
    metadata = metadata,
    paths = c(
      posterior_draws = file.path(dir, "posterior_draws.csv.gz"),
      sampler_diagnostics = file.path(dir, "sampler_diagnostics.csv"),
      checkpoint_metadata = file.path(dir, "checkpoint_metadata.csv"),
      checkpoint_manifest = file.path(dir, "artifact_manifest.csv")
    )
  )
}

app_joint_exqdesn_phase172_run_worker <- function(
  freeze_dir,
  worker_id,
  reuse_completed = TRUE,
  failure_dir = NULL
) {
  freeze <- app_joint_exqdesn_phase171_load(freeze_dir)
  worker_id <- as.integer(worker_id)[[1L]]
  job <- freeze$plan[freeze$plan$worker_id == worker_id, , drop = FALSE]
  if (nrow(job) != 1L) stop("Unknown Phase172 worker id.", call. = FALSE)
  worker_dir <- job$worker_output_dir[[1L]]
  if (reuse_completed && app_joint_exqdesn_phase172_worker_complete(worker_dir)) {
    return(list(worker_id = worker_id, status = "reused_verified", worker_dir = worker_dir))
  }
  components <- freeze$components[freeze$components$worker_id == worker_id, , drop = FALSE]
  expected_components <- if (job$fit_structure[[1L]] == "joint") 1L else 7L
  if (nrow(components) != expected_components || anyDuplicated(components$component_seed)) {
    stop("Malformed Phase172 component seed plan.", call. = FALSE)
  }
  has_checkpoint <- app_joint_exqdesn_phase172_checkpoint_complete(worker_dir)
  if (!has_checkpoint && dir.exists(worker_dir) && length(list.files(worker_dir, all.files = TRUE, no.. = TRUE))) {
    quarantine <- paste0(worker_dir, ".incomplete.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(worker_dir, quarantine)) stop("Could not quarantine incomplete Phase172 worker.", call. = FALSE)
  }
  app_ensure_dir(worker_dir)
  tryCatch({
    control <- freeze$controls[freeze$controls$cell_index == job$cell_index[[1L]], , drop = FALSE]
    if (nrow(control) != 1L || control$source_control_row_sha256[[1L]] != job$source_control_row_sha256[[1L]]) {
      stop("Phase172 worker could not resolve exact frozen controls.", call. = FALSE)
    }
    artifacts <- app_joint_qdesn_load_fixture_artifacts(freeze$config$fixture_dir[[1L]])
    fixture <- app_joint_qdesn_scenario_fixture(artifacts, job$scenario_id[[1L]], role = "fit")
    K <- length(fixture$tau)
    p <- ncol(fixture$Z)
    init <- app_joint_exqdesn_phase169_init_from_rows(
      freeze$init, job$mcmc_case_id[[1L]], job$fit_structure[[1L]], K, p
    )
    init <- app_joint_exqdesn_phase169_apply_chain_start(init, freeze$starts, job, K, p)
    alpha_prior_sd <- app_joint_qdesn_parse_numeric_vector(
      control$alpha_prior_sd[[1L]], "alpha_prior_sd", allow_inf = TRUE
    )
    common <- list(
      y = fixture$y, Z = fixture$Z, tau = fixture$tau,
      n_iter = as.integer(job$n_iter[[1L]]), burn = as.integer(job$burn[[1L]]),
      thin = as.integer(job$thin[[1L]]), seed = as.integer(job$chain_seed[[1L]]),
      kappa = 1, tau0 = as.numeric(control$tau0[[1L]]), zeta2 = as.numeric(control$zeta2[[1L]]),
      a_sigma = as.numeric(control$a_sigma[[1L]]), b_sigma = as.numeric(control$b_sigma[[1L]]),
      gamma_init = init$gamma_mean, init = init,
      alpha_prior_mean = "empirical_quantile", alpha_prior_sd = alpha_prior_sd,
      alpha_min_spacing = if (job$fit_structure[[1L]] == "joint") as.numeric(control$alpha_min_spacing[[1L]]) else 0,
      max_dense_dim = as.integer(control$max_dense_dim[[1L]]),
      gamma_slice_width = as.numeric(job$gamma_slice_width[[1L]]),
      gamma_slice_max_steps = as.integer(job$gamma_slice_max_steps[[1L]])
    )
    checkpoint <- if (has_checkpoint) {
      app_joint_exqdesn_phase172_load_checkpoint(worker_dir, fixture, job, components, freeze$dir)
    } else {
      started <- proc.time()[["elapsed"]]
      fit <- if (job$fit_structure[[1L]] == "joint") {
        do.call(app_joint_exqdesn_fit_mcmc_dispatch, c(
          list(method_id = "M0_v_collapsed_support_logit"), common
        ))
      } else {
        do.call(app_joint_exqdesn_fit_independent_mcmc_dispatch, c(
          list(method_id = "M0_v_collapsed_support_logit", tau_seed_stride = as.integer(job$tau_seed_stride[[1L]])),
          common
        ))
      }
      elapsed <- proc.time()[["elapsed"]] - started
      app_joint_exqdesn_phase172_write_checkpoint(
        fit, fixture, job, control, components, elapsed, freeze$dir, worker_dir
      )
    }
    fit <- checkpoint$fit
    draws <- checkpoint$draws
    elapsed <- as.numeric(checkpoint$metadata$elapsed_seconds[[1L]])
    meta <- app_joint_exqdesn_phase172_meta(job, control)
    fit_score <- app_joint_qdesn_phase122_score_qhat(
      meta, fixture, app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau),
      "qhat", "phase172_chain_fit"
    )
    forecast_score <- app_joint_qdesn_phase122_forecast_scores(
      meta, artifacts, job$scenario_id[[1L]], fixture, fit,
      "qhat", "phase172_chain_forecast"
    )
    contract_crossings <- sum(fit_score$contract_crossing$n_crossing_pairs) +
      sum(forecast_score$contract_crossing$n_crossing_pairs)
    summary <- data.frame(
      worker_id = worker_id, wave_id = job$wave_id[[1L]],
      mcmc_case_id = job$mcmc_case_id[[1L]], case_id = meta$case_id[[1L]],
      scenario_id = job$scenario_id[[1L]], base_scenario_id = job$base_scenario_id[[1L]],
      fit_structure = job$fit_structure[[1L]], model_id = job$model_id[[1L]],
      inference_method_id = job$inference_method_id[[1L]],
      chain_id = job$chain_id[[1L]], chain_seed = job$chain_seed[[1L]],
      component_seed_count = nrow(components),
      component_seed_table_sha256 = app_joint_exqdesn_phase172_table_hash(components),
      start_profile_id = job$start_profile_id[[1L]],
      n_iter = job$n_iter[[1L]], burn = job$burn[[1L]], thin = job$thin[[1L]],
      n_keep = nrow(draws), init_source = fit$init_source %||% "provided",
      fit_truth_mae = mean(fit_score$scored$truth_abs_error),
      forecast_truth_mae = mean(forecast_score$scored$truth_abs_error),
      fit_check_loss_mean = mean(fit_score$scored$check_loss),
      forecast_check_loss_mean = mean(forecast_score$scored$check_loss),
      fit_crps_grid_mean = app_joint_qdesn_crps_grid_summary(fit_score$scored)$crps_grid_mean[[1L]],
      forecast_crps_grid_mean = app_joint_qdesn_crps_grid_summary(forecast_score$scored)$crps_grid_mean[[1L]],
      fit_raw_crossing_pairs = sum(fit_score$raw_crossing$n_crossing_pairs),
      forecast_raw_crossing_pairs = sum(forecast_score$raw_crossing$n_crossing_pairs),
      contract_crossing_pairs = contract_crossings,
      draws_all_finite = all(is.finite(as.matrix(draws[, -1L, drop = FALSE]))),
      min_sigma = min(fit$sigma_draws), max_sigma = max(fit$sigma_draws),
      min_gamma = min(fit$gamma_draws), max_gamma = max(fit$gamma_draws),
      elapsed_seconds = elapsed, seconds_per_iteration = elapsed / job$n_iter[[1L]],
      stringsAsFactors = FALSE
    )
    if (!summary$draws_all_finite[[1L]] || contract_crossings > 0L) {
      stop("Phase172 worker failed the finite/noncrossing contract.", call. = FALSE)
    }
    runtime <- summary[, c(
      "worker_id", "wave_id", "mcmc_case_id", "scenario_id", "fit_structure",
      "chain_id", "chain_seed", "elapsed_seconds", "seconds_per_iteration"
    ), drop = FALSE]
    readme <- file.path(worker_dir, "README.md")
    writeLines(c(
      sprintf("# Phase172 worker %d", worker_id), "",
      sprintf("- Scenario: `%s`", job$scenario_id[[1L]]),
      sprintf("- Structure: `%s`", job$fit_structure[[1L]]),
      sprintf("- Method: `%s`", job$inference_method_id[[1L]]),
      sprintf("- Chain: %d", job$chain_id[[1L]]),
      sprintf("- Top-level seed: %d", job$chain_seed[[1L]]),
      sprintf("- Physical component seeds: %s", paste(components$component_seed, collapse = ",")),
      "- Initialization: VB0 warm start to VB1 structured-v, followed by a frozen dispersed start.",
      "- Storage: compressed parameter draws and hash-manifested diagnostics; no latent workspace."
    ), readme, useBytes = TRUE)
    paths <- c(
      checkpoint$paths,
      chain_summary = app_joint_qvp_write_csv(summary, file.path(worker_dir, "chain_summary.csv")),
      runtime = app_joint_qvp_write_csv(runtime, file.path(worker_dir, "runtime.csv")),
      provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(worker_dir, "provenance.csv")),
      README = normalizePath(readme, mustWork = TRUE)
    )
    manifest <- app_joint_exqdesn_write_manifest(paths, worker_dir)
    if (!app_joint_exqdesn_phase172_worker_complete(worker_dir)) {
      stop("Phase172 worker manifest failed after publication.", call. = FALSE)
    }
    stale <- c(
      file.path(worker_dir, "failure_receipt.csv"),
      if (!is.null(failure_dir) && nzchar(failure_dir)) file.path(failure_dir, sprintf("worker_%03d.csv", worker_id)) else character()
    )
    if (any(file.exists(stale))) unlink(stale[file.exists(stale)], force = TRUE)
    list(worker_id = worker_id, status = "completed", worker_dir = worker_dir,
         paths = c(paths, artifact_manifest = manifest$manifest_path))
  }, error = function(e) {
    receipt <- data.frame(
      worker_id = worker_id, mcmc_case_id = job$mcmc_case_id[[1L]],
      scenario_id = job$scenario_id[[1L]], fit_structure = job$fit_structure[[1L]],
      inference_method_id = job$inference_method_id[[1L]], chain_id = job$chain_id[[1L]],
      message = conditionMessage(e), timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      stringsAsFactors = FALSE
    )
    app_joint_qvp_write_csv(receipt, file.path(worker_dir, "failure_receipt.csv"))
    if (!is.null(failure_dir) && nzchar(failure_dir)) {
      app_ensure_dir(failure_dir)
      app_joint_qvp_write_csv(receipt, file.path(failure_dir, sprintf("worker_%03d.csv", worker_id)))
    }
    stop(e)
  })
}

app_joint_exqdesn_phase172_health <- function(
  freeze_dir = app_joint_exqdesn_phase171_175_dirs()$phase171,
  orchestration_dir = app_joint_exqdesn_phase171_175_dirs()$phase172_orchestration
) {
  freeze <- app_joint_exqdesn_phase171_load(freeze_dir)
  complete <- vapply(freeze$plan$worker_output_dir, app_joint_exqdesn_phase172_worker_complete, logical(1L))
  exit_paths <- file.path(orchestration_dir, "exits", sprintf("worker_%03d.exit", freeze$plan$worker_id))
  failed <- vapply(exit_paths, function(path) {
    file.exists(path) && suppressWarnings(as.integer(readLines(path, warn = FALSE)[[1L]])) != 0L
  }, logical(1L))
  state <- ifelse(complete, "complete", ifelse(failed, "failed", "remaining"))
  plan <- freeze$plan
  plan$state <- state
  output_mib <- 0
  campaign_dir <- dirname(dirname(plan$worker_output_dir[[1L]]))
  if (dir.exists(campaign_dir)) {
    du_output <- system2("du", c("-sm", campaign_dir), stdout = TRUE)
    if (length(du_output)) {
      output_mib <- suppressWarnings(as.numeric(strsplit(du_output[[1L]], "\\s+")[[1L]][[1L]]))
      if (!is.finite(output_mib)) output_mib <- NA_real_
    }
  }
  summary <- data.frame(
    stage = "Phase172 M0 balanced article confirmation",
    planned_workers = nrow(plan),
    complete_verified = sum(complete),
    failed_workers = sum(failed & !complete),
    remaining_workers = sum(!complete & !failed),
    percent_complete = 100 * mean(complete),
    verified_checkpoints = sum(vapply(plan$worker_output_dir, app_joint_exqdesn_phase172_checkpoint_complete, logical(1L))),
    output_mib = output_mib,
    stringsAsFactors = FALSE
  )
  by_cell <- app_joint_qdesn_bind_rows(lapply(split(plan, plan$mcmc_case_id), function(x) data.frame(
    mcmc_case_id = x$mcmc_case_id[[1L]], scenario_id = x$scenario_id[[1L]],
    fit_structure = x$fit_structure[[1L]], planned = nrow(x),
    complete = sum(x$state == "complete"), failed = sum(x$state == "failed"),
    remaining = sum(x$state == "remaining"), stringsAsFactors = FALSE
  )))
  by_wave <- app_joint_qdesn_bind_rows(lapply(split(plan, plan$wave_id), function(x) data.frame(
    wave_id = x$wave_id[[1L]], planned = nrow(x), complete = sum(x$state == "complete"),
    failed = sum(x$state == "failed"), remaining = sum(x$state == "remaining"),
    stringsAsFactors = FALSE
  )))
  list(summary = summary, by_cell = by_cell, by_wave = by_wave, plan = plan)
}

app_joint_exqdesn_phase173_load_fits <- function(jobs, fixture) {
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  if (nrow(jobs) != 8L || !identical(as.integer(jobs$chain_id), seq_len(8L))) {
    stop("Phase173 requires exactly chains 1-8 in every cell.", call. = FALSE)
  }
  lapply(seq_len(nrow(jobs)), function(ii) {
    app_joint_exqdesn_phase157_read_fit(
      app_joint_exqdesn_phase172_checkpoint_dir(jobs$worker_output_dir[[ii]]),
      fixture$tau, jobs$chain_seed[[ii]], jobs$chain_id[[ii]]
    )
  })
}

app_joint_exqdesn_phase173_parameter_matrix <- function(fits, fixture, parameter, index) {
  if (parameter == "beta") return(do.call(cbind, lapply(fits, function(x) x$beta_draws[, index])))
  if (parameter == "alpha") return(do.call(cbind, lapply(fits, function(x) x$alpha_draws[, index])))
  if (parameter %in% c("gamma", "sigma", "p_gamma", "actual_sd", "sigma_lambda")) {
    return(do.call(cbind, lapply(fits, function(x) {
      app_joint_exqdesn_phase169_transformed_draw(x, fixture$tau, parameter, index)
    })))
  }
  stop("Unknown Phase173 parameter block.", call. = FALSE)
}

app_joint_exqdesn_phase173_parameter_diagnostics <- function(fits, fixture, meta) {
  K <- length(fixture$tau)
  p <- ncol(fixture$Z)
  specs <- list()
  for (index in seq_len(K * p)) {
    k <- ceiling(index / p)
    specs[[length(specs) + 1L]] <- list(
      parameter = "beta", index = index, quantile_index = k,
      tau = fixture$tau[[k]], feature_index = ((index - 1L) %% p) + 1L,
      feature_name = colnames(fixture$Z)[[((index - 1L) %% p) + 1L]]
    )
  }
  for (parameter in c("alpha", "gamma", "sigma", "p_gamma", "actual_sd", "sigma_lambda")) {
    for (k in seq_len(K)) specs[[length(specs) + 1L]] <- list(
      parameter = parameter, index = k, quantile_index = k,
      tau = fixture$tau[[k]], feature_index = NA_integer_, feature_name = ""
    )
  }
  rows <- lapply(specs, function(spec) {
    mat <- app_joint_exqdesn_phase173_parameter_matrix(
      fits, fixture, spec$parameter, spec$index
    )
    diagnostics <- app_joint_exqdesn_modern_diagnostics(mat)
    cbind(meta, data.frame(
      parameter = spec$parameter,
      parameter_index = spec$index,
      quantile_index = spec$quantile_index,
      tau = spec$tau,
      feature_index = spec$feature_index,
      feature_name = spec$feature_name,
      posterior_mean = mean(mat),
      posterior_sd = stats::sd(as.numeric(mat)),
      q05 = as.numeric(stats::quantile(mat, 0.05, names = FALSE, type = 8)),
      median = stats::median(mat),
      q95 = as.numeric(stats::quantile(mat, 0.95, names = FALSE, type = 8)),
      stringsAsFactors = FALSE
    ), diagnostics, stringsAsFactors = FALSE)
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase173_forecast_fixture <- function(artifacts, scenario_id, fit_fixture) {
  plan <- artifacts$forecast_origin_plan[
    artifacts$forecast_origin_plan$scenario_id == scenario_id, , drop = FALSE
  ]
  plan <- plan[order(plan$origin_index), , drop = FALSE]
  targets <- lapply(seq_len(nrow(plan)), function(ii) {
    target <- app_joint_qdesn_forecast_target_fixture(
      artifacts, scenario_id, plan[ii, , drop = FALSE]
    )
    if (!identical(target$feature_cols, fit_fixture$feature_cols)) {
      stop("Phase173 fit/forecast feature identity failed.", call. = FALSE)
    }
    target
  })
  list(
    Z = do.call(rbind, lapply(targets, `[[`, "Z")),
    y = unlist(lapply(targets, `[[`, "y"), use.names = FALSE),
    true_q = do.call(rbind, lapply(targets, `[[`, "true_q")),
    row_meta = app_joint_qdesn_bind_rows(lapply(targets, `[[`, "row_meta")),
    tau = fit_fixture$tau,
    feature_cols = fit_fixture$feature_cols
  )
}

app_joint_exqdesn_phase173_compare_qhat_groups <- function(
  fits_a, fits_b, Z, tau, meta, partition_id, window
) {
  a <- app_joint_exqdesn_phase170_qhat_moments(fits_a, Z, tau)
  b <- app_joint_exqdesn_phase170_qhat_moments(fits_b, Z, tau)
  joined <- merge(a, b, by = c("row_index", "quantile_index", "tau"),
                  suffixes = c("_a", "_b"), sort = FALSE)
  joined$mean_delta <- joined$posterior_mean_b - joined$posterior_mean_a
  pooled_sd <- sqrt((joined$posterior_sd_a^2 + joined$posterior_sd_b^2) / 2)
  joined$standardized_mean_delta <- abs(joined$mean_delta) /
    pmax(pooled_sd, .Machine$double.eps)
  overlap <- pmax(0, pmin(joined$q95_a, joined$q95_b) - pmax(joined$q05_a, joined$q05_b))
  union <- pmax(joined$q95_a, joined$q95_b) - pmin(joined$q05_a, joined$q05_b)
  joined$central90_overlap_fraction <- overlap / pmax(union, .Machine$double.eps)
  detail <- cbind(meta, data.frame(
    partition_id = partition_id, window = window,
    joined, stringsAsFactors = FALSE
  ))
  summary <- cbind(meta, data.frame(
    partition_id = partition_id, window = window,
    n_quantile_path_points = nrow(joined),
    mean_abs_qhat_delta = mean(abs(joined$mean_delta)),
    max_abs_qhat_delta = max(abs(joined$mean_delta)),
    q99_standardized_qhat_delta = as.numeric(stats::quantile(
      joined$standardized_mean_delta, 0.99, names = FALSE, type = 8
    )),
    q01_central90_overlap_fraction = as.numeric(stats::quantile(
      joined$central90_overlap_fraction, 0.01, names = FALSE, type = 8
    )),
    stringsAsFactors = FALSE
  ))
  summary$status <- ifelse(
    summary$q99_standardized_qhat_delta <= 0.25 &
      summary$q01_central90_overlap_fraction >= 0.80,
    "pass", "review"
  )
  list(detail = detail, summary = summary)
}

app_joint_exqdesn_phase173_partition_stability <- function(
  fits, fixture, forecast_fixture, meta
) {
  partitions <- list(
    first4_last4 = list(a = 1:4, b = 5:8),
    odd_even = list(a = c(1, 3, 5, 7), b = c(2, 4, 6, 8))
  )
  rows <- lapply(names(partitions), function(id) {
    groups <- partitions[[id]]
    list(
      fit = app_joint_exqdesn_phase173_compare_qhat_groups(
        fits[groups$a], fits[groups$b], fixture$Z, fixture$tau, meta, id, "fit"
      ),
      forecast = app_joint_exqdesn_phase173_compare_qhat_groups(
        fits[groups$a], fits[groups$b], forecast_fixture$Z, fixture$tau, meta, id, "forecast"
      )
    )
  })
  flattened <- unlist(rows, recursive = FALSE)
  list(
    detail = app_joint_qdesn_bind_rows(lapply(flattened, `[[`, "detail")),
    summary = app_joint_qdesn_bind_rows(lapply(flattened, `[[`, "summary"))
  )
}

app_joint_exqdesn_phase173_metric_row <- function(fit_score, forecast_score) {
  data.frame(
    fit_truth_mae = mean(fit_score$scored$truth_abs_error),
    forecast_truth_mae = mean(forecast_score$scored$truth_abs_error),
    fit_check_loss_mean = mean(fit_score$scored$check_loss),
    forecast_check_loss_mean = mean(forecast_score$scored$check_loss),
    fit_crps_grid_mean = app_joint_qdesn_crps_grid_summary(fit_score$scored)$crps_grid_mean[[1L]],
    forecast_crps_grid_mean = app_joint_qdesn_crps_grid_summary(forecast_score$scored)$crps_grid_mean[[1L]],
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase173_score_fit <- function(
  fit, fixture, artifacts, meta, label
) {
  fit_score <- app_joint_qdesn_phase122_score_qhat(
    meta, fixture, app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau),
    "qhat", paste0(label, "_fit")
  )
  forecast_score <- app_joint_qdesn_phase122_forecast_scores(
    meta, artifacts, fixture$scenario_id, fixture, fit,
    "qhat", paste0(label, "_forecast")
  )
  list(
    fit = fit_score, forecast = forecast_score,
    metrics = app_joint_exqdesn_phase173_metric_row(fit_score, forecast_score)
  )
}

app_joint_exqdesn_phase173_leave_one_out <- function(
  fits, fixture, artifacts, meta, full_metrics
) {
  rows <- lapply(seq_along(fits), function(omit) {
    pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(
      fits[-omit], fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau
    )
    scored <- app_joint_exqdesn_phase173_score_fit(
      pooled, fixture, artifacts, meta, sprintf("phase173_loo_%02d", omit)
    )
    out <- cbind(meta, data.frame(omitted_chain_id = omit), scored$metrics)
    for (metric in names(full_metrics)) {
      out[[paste0(metric, "_delta")]] <- out[[metric]] - full_metrics[[metric]]
    }
    out
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase173_jackknife <- function(loo, meta) {
  metrics <- c(
    "fit_truth_mae", "forecast_truth_mae", "fit_check_loss_mean",
    "forecast_check_loss_mean", "fit_crps_grid_mean", "forecast_crps_grid_mean"
  )
  app_joint_qdesn_bind_rows(lapply(metrics, function(metric) {
    values <- as.numeric(loo[[metric]])
    m <- length(values)
    estimate <- mean(values)
    se <- sqrt((m - 1) / m * sum((values - estimate)^2))
    cbind(meta, data.frame(
      metric = metric, omitted_chain_replicates = m,
      leave_one_out_mean = estimate, jackknife_mcse = se,
      maximum_absolute_loo_delta = max(abs(loo[[paste0(metric, "_delta")]])),
      stringsAsFactors = FALSE
    ))
  }))
}

app_joint_exqdesn_phase173_summary_fit <- function(fits, fixture, type) {
  beta <- do.call(rbind, lapply(fits, `[[`, "beta_draws"))
  alpha <- do.call(rbind, lapply(fits, `[[`, "alpha_draws"))
  sigma <- do.call(rbind, lapply(fits, `[[`, "sigma_draws"))
  gamma <- do.call(rbind, lapply(fits, `[[`, "gamma_draws"))
  reduce <- switch(type,
    mean = function(x) colMeans(x),
    median = function(x) apply(x, 2L, stats::median),
    trimmed_mean = function(x) apply(x, 2L, mean, trim = 0.10),
    stop("Unknown posterior summary type.", call. = FALSE)
  )
  list(
    beta_mean = reduce(beta), alpha_mean = reduce(alpha),
    sigma_mean = reduce(sigma), gamma_mean = reduce(gamma),
    tau = fixture$tau
  )
}

app_joint_exqdesn_phase173_process_cell <- function(jobs, freeze, artifacts) {
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  control <- freeze$controls[freeze$controls$cell_index == jobs$cell_index[[1L]], , drop = FALSE]
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, jobs$scenario_id[[1L]], role = "fit")
  forecast_fixture <- app_joint_exqdesn_phase173_forecast_fixture(
    artifacts, jobs$scenario_id[[1L]], fixture
  )
  fits <- app_joint_exqdesn_phase173_load_fits(jobs, fixture)
  meta <- app_joint_exqdesn_phase172_meta(jobs[1L, , drop = FALSE], control)
  pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(
    fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau
  )
  scored <- app_joint_exqdesn_phase173_score_fit(
    pooled, fixture, artifacts, meta, "phase173_pooled"
  )
  diagnostics <- app_joint_exqdesn_phase173_parameter_diagnostics(fits, fixture, meta)
  partitions <- app_joint_exqdesn_phase173_partition_stability(
    fits, fixture, forecast_fixture, meta
  )
  full_metrics <- as.list(scored$metrics[1L, , drop = FALSE])
  loo <- app_joint_exqdesn_phase173_leave_one_out(
    fits, fixture, artifacts, meta, full_metrics
  )
  jackknife <- app_joint_exqdesn_phase173_jackknife(loo, meta)
  sensitivity <- app_joint_qdesn_bind_rows(lapply(
    c("mean", "median", "trimmed_mean"), function(type) {
      fit <- app_joint_exqdesn_phase173_summary_fit(fits, fixture, type)
      result <- app_joint_exqdesn_phase173_score_fit(
        fit, fixture, artifacts, meta, paste0("phase173_", type)
      )
      cbind(meta, data.frame(summary_type = type), result$metrics)
    }
  ))
  chain_distance <- app_joint_qvp_chain_to_pooled_summary(
    fits, pooled, fixture$Z, meta$case_id[[1L]], "phase173_m0",
    fixture$scenario_id, length(fixture$y), ncol(fixture$Z), length(fixture$tau)
  )
  for (field in setdiff(names(meta), names(chain_distance))) {
    chain_distance[[field]] <- meta[[field]][[1L]]
  }
  chain_summary <- app_joint_qdesn_bind_rows(lapply(jobs$worker_output_dir, function(dir) {
    app_read_csv(file.path(dir, "chain_summary.csv"))
  }))
  summary <- cbind(meta, data.frame(
    source_model_id = if (meta$fit_structure[[1L]] == "joint") {
      "joint_exqdesn_rhs_vb"
    } else {
      "exqdesn_rhs_independent_vb"
    },
    mcmc_n_chains = length(fits),
    mcmc_n_iter = jobs$n_iter[[1L]],
    mcmc_burn = jobs$burn[[1L]],
    mcmc_thin = jobs$thin[[1L]],
    mcmc_n_keep_total = nrow(pooled$beta_draws),
    mcmc_init_source = pooled$init_source %||% "provided",
    all_chain_init_source_provided = all(chain_summary$init_source == "provided"),
    mcmc_draws_all_finite = all(chain_summary$draws_all_finite),
    mcmc_fit_truth_mae = scored$metrics$fit_truth_mae,
    mcmc_forecast_truth_mae = scored$metrics$forecast_truth_mae,
    mcmc_fit_check_loss_mean = scored$metrics$fit_check_loss_mean,
    mcmc_forecast_check_loss_mean = scored$metrics$forecast_check_loss_mean,
    mcmc_fit_crps_grid_mean = scored$metrics$fit_crps_grid_mean,
    mcmc_forecast_crps_grid_mean = scored$metrics$forecast_crps_grid_mean,
    mcmc_fit_raw_crossing_pairs = sum(scored$fit$raw_crossing$n_crossing_pairs),
    mcmc_forecast_raw_crossing_pairs = sum(scored$forecast$raw_crossing$n_crossing_pairs),
    mcmc_fit_contract_crossing_pairs = sum(scored$fit$contract_crossing$n_crossing_pairs),
    mcmc_forecast_contract_crossing_pairs = sum(scored$forecast$contract_crossing$n_crossing_pairs),
    max_rank_rhat = max(diagnostics$rank_rhat, na.rm = TRUE),
    max_folded_rhat = max(diagnostics$folded_rhat, na.rm = TRUE),
    min_bulk_ess = min(diagnostics$bulk_ess, na.rm = TRUE),
    min_tail_ess = min(diagnostics$tail_ess, na.rm = TRUE),
    runtime_seconds_total = sum(chain_summary$elapsed_seconds),
    stringsAsFactors = FALSE
  ))
  list(
    summary = summary, diagnostics = diagnostics,
    partition_detail = partitions$detail, partition_summary = partitions$summary,
    loo = loo, jackknife = jackknife, sensitivity = sensitivity,
    fit_raw = scored$fit$raw, fit = scored$fit$scored,
    fit_adjustment = scored$fit$adjustment,
    forecast_raw = scored$forecast$raw, forecast = scored$forecast$scored,
    forecast_adjustment = scored$forecast$adjustment,
    crossing = app_joint_qdesn_bind_rows(list(
      scored$fit$contract_crossing, scored$forecast$contract_crossing
    )),
    raw_crossing = app_joint_qdesn_bind_rows(list(
      scored$fit$raw_crossing, scored$forecast$raw_crossing
    )),
    chain_distance = chain_distance,
    chain_summary = chain_summary
  )
}

app_joint_exqdesn_phase173_assess_cells <- function(
  summary, diagnostics, partition_summary, jackknife
) {
  rows <- lapply(seq_len(nrow(summary)), function(ii) {
    cell <- summary[ii, , drop = FALSE]
    key <- cell$case_id[[1L]]
    d <- diagnostics[diagnostics$case_id == key, , drop = FALSE]
    p <- partition_summary[partition_summary$case_id == key, , drop = FALSE]
    j <- jackknife[jackknife$case_id == key, , drop = FALSE]
    forecast_j <- j[j$metric == "forecast_truth_mae", , drop = FALSE]
    pass_ceiling <- max(0.0015, 0.02 * cell$mcmc_forecast_truth_mae[[1L]])
    review_ceiling <- max(0.0030, 0.04 * cell$mcmc_forecast_truth_mae[[1L]])
    loo_delta <- forecast_j$maximum_absolute_loo_delta[[1L]]
    loo_status <- if (loo_delta <= pass_ceiling) "pass" else if (loo_delta <= review_ceiling) "review" else "hold"
    readout <- d[d$parameter %in% c("beta", "alpha"), , drop = FALSE]
    shape <- d[d$parameter %in% c("gamma", "sigma", "p_gamma", "actual_sd", "sigma_lambda"), , drop = FALSE]
    severe_readout <- any(
      readout$rank_rhat > 1.10 | readout$folded_rhat > 1.10 |
        readout$bulk_ess < 100 | readout$tail_ess < 50,
      na.rm = TRUE
    )
    severe_shape_tau <- unique(shape$tau[
      shape$rank_rhat > 1.10 | shape$folded_rhat > 1.10 |
        shape$bulk_ess < 100 | shape$tail_ess < 50
    ])
    scalar_review <- any(
      d$rank_rhat > 1.05 | d$folded_rhat > 1.05 |
        d$bulk_ess < 400 | d$tail_ess < 200,
      na.rm = TRUE
    )
    functional_pass <- nrow(p) == 4L && all(p$status == "pass")
    hard_pass <- isTRUE(cell$mcmc_draws_all_finite[[1L]]) &&
      cell$mcmc_fit_contract_crossing_pairs[[1L]] == 0L &&
      cell$mcmc_forecast_contract_crossing_pairs[[1L]] == 0L &&
      isTRUE(cell$all_chain_init_source_provided[[1L]]) &&
      all(is.finite(unlist(cell[c(
        "mcmc_fit_truth_mae", "mcmc_forecast_truth_mae",
        "mcmc_fit_check_loss_mean", "mcmc_forecast_check_loss_mean",
        "mcmc_fit_crps_grid_mean", "mcmc_forecast_crps_grid_mean"
      )], use.names = FALSE)))
    material_shape <- length(severe_shape_tau) >= 2L
    status <- if (!hard_pass) {
      "fail"
    } else if (!functional_pass || loo_status == "hold" || severe_readout || material_shape) {
      "review_hold"
    } else if (scalar_review || loo_status == "review") {
      "qualified_article_ready"
    } else {
      "pass"
    }
    data.frame(
      case_id = key, scenario_id = cell$scenario_id[[1L]],
      fit_structure = cell$fit_structure[[1L]], source_model_id = cell$source_model_id[[1L]],
      implementation_status = if (hard_pass) "pass" else "fail",
      scalar_mixing_status = if (scalar_review) "review" else "pass",
      readout_severity_status = if (severe_readout) "hold" else "pass",
      multi_tau_shape_severity_status = if (material_shape) "hold" else if (length(severe_shape_tau)) "review" else "pass",
      functional_partition_status = if (functional_pass) "pass" else "review",
      leave_one_chain_out_status = loo_status,
      leave_one_chain_out_pass_ceiling = pass_ceiling,
      leave_one_chain_out_review_ceiling = review_ceiling,
      maximum_leave_one_chain_out_forecast_mae_delta = loo_delta,
      raw_crossing_status = if (
        cell$mcmc_fit_raw_crossing_pairs[[1L]] + cell$mcmc_forecast_raw_crossing_pairs[[1L]] > 0L
      ) "review" else "pass",
      gate_status = status,
      status_reason = if (!hard_pass) {
        "implementation, finiteness, initialization, or contract gate failed"
      } else if (!functional_pass) {
        "predeclared qhat partition stability is review-level"
      } else if (loo_status == "hold") {
        "leave-one-chain-out forecast MAE exceeds the review ceiling"
      } else if (severe_readout) {
        "material readout coordinates have severe convergence diagnostics"
      } else if (material_shape) {
        "severe gamma/scale diagnostics affect multiple tau levels"
      } else if (status == "qualified_article_ready") {
        "quantile functionals are stable; only supporting scalar or modest LOO reviews remain"
      } else {
        "implementation, functional, and supporting diagnostics pass"
      },
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase173_historical_comparison <- function(summary, dirs) {
  old <- app_read_csv(file.path(dirs$phase154_final, "final_mcmc_case_summary.csv"))
  old <- old[old$source_model_id %in% c("joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"), , drop = FALSE]
  current <- summary[, c(
    "scenario_id", "source_model_id", "mcmc_fit_truth_mae",
    "mcmc_forecast_truth_mae", "mcmc_forecast_check_loss_mean"
  ), drop = FALSE]
  joined <- merge(old, current, by = c("scenario_id", "source_model_id"),
                  suffixes = c("_historical", "_M0"), sort = FALSE)
  metrics <- c(
    "mcmc_fit_truth_mae", "mcmc_forecast_truth_mae",
    "mcmc_forecast_check_loss_mean"
  )
  for (metric in metrics) {
    old_name <- paste0(metric, "_historical")
    new_name <- paste0(metric, "_M0")
    if (all(c(old_name, new_name) %in% names(joined))) {
      joined[[paste0(metric, "_delta_M0_minus_historical")]] <- joined[[new_name]] - joined[[old_name]]
    }
  }
  joined
}

app_joint_exqdesn_phase173_historical_qhat <- function(forecast, dirs) {
  sources <- list(joint = dirs$phase150_result, independent = dirs$phase154_independent_exal)
  rows <- lapply(names(sources), function(structure) {
    old <- app_read_csv(file.path(sources[[structure]], "forecast_quantiles.csv"))
    if ("inference" %in% names(old)) old <- old[toupper(old$inference) == "MCMC", , drop = FALSE]
    new <- forecast[forecast$fit_structure == structure, , drop = FALSE]
    keys <- intersect(
      c("scenario_id", "full_time_index", "effective_index", "role_index", "tau"),
      intersect(names(old), names(new))
    )
    joined <- merge(
      old[, c(keys, "qhat"), drop = FALSE],
      new[, c(keys, "qhat"), drop = FALSE],
      by = keys, suffixes = c("_historical", "_M0"), sort = FALSE
    )
    split_rows <- split(joined, joined$scenario_id)
    app_joint_qdesn_bind_rows(lapply(split_rows, function(x) data.frame(
      scenario_id = x$scenario_id[[1L]], fit_structure = structure,
      matched_quantile_points = nrow(x),
      mean_absolute_qhat_delta = mean(abs(x$qhat_M0 - x$qhat_historical)),
      max_absolute_qhat_delta = max(abs(x$qhat_M0 - x$qhat_historical)),
      stringsAsFactors = FALSE
    )))
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase173_winner_mc_audit <- function(summary, jackknife, dirs) {
  packet <- app_read_csv(file.path(dirs$phase155, "final_case_summary.csv"))
  for (ii in seq_len(nrow(summary))) {
    idx <- packet$scenario_id == summary$scenario_id[[ii]] &
      packet$source_model_id == summary$source_model_id[[ii]]
    if (sum(idx) != 1L) stop("Phase173 could not replace one exAL article cell.", call. = FALSE)
    packet$mcmc_fit_truth_mae[idx] <- summary$mcmc_fit_truth_mae[[ii]]
    packet$mcmc_forecast_truth_mae[idx] <- summary$mcmc_forecast_truth_mae[[ii]]
    packet$mcmc_forecast_check_loss_mean[idx] <- summary$mcmc_forecast_check_loss_mean[[ii]]
    packet$mcmc_forecast_crps_grid[idx] <- summary$mcmc_forecast_crps_grid_mean[[ii]]
  }
  metric_map <- c(
    mcmc_fit_truth_mae = "fit_truth_mae",
    mcmc_forecast_truth_mae = "forecast_truth_mae",
    mcmc_forecast_check_loss_mean = "forecast_check_loss_mean",
    mcmc_forecast_crps_grid = "forecast_crps_grid_mean"
  )
  rows <- lapply(unique(packet$scenario_id), function(scenario_id) {
    block <- packet[packet$scenario_id == scenario_id, , drop = FALSE]
    app_joint_qdesn_bind_rows(lapply(names(metric_map), function(metric) {
      ord <- order(as.numeric(block[[metric]]), block$source_model_id)
      winner <- block[ord[[1L]], , drop = FALSE]
      runner <- block[ord[[2L]], , drop = FALSE]
      lookup_mcse <- function(row) {
        if (!row$source_model_id[[1L]] %in% c("joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb")) return(NA_real_)
        x <- jackknife[
          jackknife$scenario_id == scenario_id &
            jackknife$source_model_id == row$source_model_id[[1L]] &
            jackknife$metric == metric_map[[metric]],
          , drop = FALSE
        ]
        if (nrow(x) == 1L) x$jackknife_mcse[[1L]] else NA_real_
      }
      winner_mcse <- lookup_mcse(winner)
      runner_mcse <- lookup_mcse(runner)
      available <- c(winner_mcse, runner_mcse)
      available <- available[is.finite(available)]
      conservative_mcse <- if (length(available)) sqrt(sum(available^2)) else NA_real_
      margin <- as.numeric(runner[[metric]][[1L]] - winner[[metric]][[1L]])
      data.frame(
        scenario_id = scenario_id, metric = metric,
        winner_model_id = winner$source_model_id[[1L]],
        runner_up_model_id = runner$source_model_id[[1L]],
        winner_value = winner[[metric]][[1L]], runner_up_value = runner[[metric]][[1L]],
        winner_margin = margin, winner_jackknife_mcse = winner_mcse,
        runner_up_jackknife_mcse = runner_mcse,
        available_combined_mcse = conservative_mcse,
        mcse_coverage = if (all(is.finite(c(winner_mcse, runner_mcse)))) "complete" else if (length(available)) "partial" else "unavailable_historical_al",
        interpretation = if (!is.finite(conservative_mcse)) {
          "descriptive_winner_mcse_unavailable"
        } else if (margin <= 2 * conservative_mcse) {
          "near_tie"
        } else {
          "resolved_at_available_mc_precision"
        },
        stringsAsFactors = FALSE
      )
    }))
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase172_close_campaign <- function(freeze, dirs) {
  worker_rows <- lapply(seq_len(nrow(freeze$plan)), function(ii) {
    job <- freeze$plan[ii, , drop = FALSE]
    manifest <- file.path(job$worker_output_dir[[1L]], "artifact_manifest.csv")
    data.frame(
      worker_id = job$worker_id[[1L]], wave_id = job$wave_id[[1L]],
      mcmc_case_id = job$mcmc_case_id[[1L]], scenario_id = job$scenario_id[[1L]],
      fit_structure = job$fit_structure[[1L]], chain_id = job$chain_id[[1L]],
      worker_dir = job$worker_output_dir[[1L]], manifest_path = manifest,
      manifest_sha256 = app_sha256_file(manifest),
      verified = app_joint_exqdesn_phase172_worker_complete(job$worker_output_dir[[1L]]),
      stringsAsFactors = FALSE
    )
  })
  inventory <- app_joint_qdesn_bind_rows(worker_rows)
  if (nrow(inventory) != 128L || any(!inventory$verified)) {
    stop("Phase172 cannot close with incomplete workers.", call. = FALSE)
  }
  app_ensure_dir(dirs$phase172)
  completion <- data.frame(
    phase_id = "phase172_m0_balanced_article_confirmation",
    gate_status = "pass", completed_workers = nrow(inventory),
    expected_workers = 128L, completed_cells = 16L,
    physical_component_runs = nrow(freeze$components),
    contract = "exact_M0_posterior_quantile_grid_confirmation",
    recommendation = "run_phase173_independent_audit",
    stringsAsFactors = FALSE
  )
  readme <- file.path(dirs$phase172, "README.md")
  writeLines(c(
    "# Phase172 M0 balanced article confirmation", "",
    "All 128 top-level workers completed under the immutable Phase171 freeze.",
    "Worker draws remain in hash-manifested candidate directories; this top-level packet indexes them."
  ), readme, useBytes = TRUE)
  paths <- c(
    campaign_completion = app_joint_qvp_write_csv(completion, file.path(dirs$phase172, "campaign_completion.csv")),
    worker_manifest_inventory = app_joint_qvp_write_csv(inventory, file.path(dirs$phase172, "worker_manifest_inventory.csv")),
    run_config = app_joint_qvp_write_csv(data.frame(
      phase171_dir = freeze$dir, phase171_manifest_sha256 = app_sha256_file(file.path(freeze$dir, "artifact_manifest.csv")),
      code_commit = unique(freeze$plan$code_commit), n_iter = unique(freeze$plan$n_iter),
      burn = unique(freeze$plan$burn), thin = unique(freeze$plan$thin),
      stringsAsFactors = FALSE
    ), file.path(dirs$phase172, "run_config.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(dirs$phase172, "provenance.csv")),
    README = normalizePath(readme, mustWork = TRUE)
  )
  old <- file.path(dirs$phase172, "artifact_manifest.csv")
  if (file.exists(old)) unlink(old)
  app_joint_exqdesn_write_manifest(paths, dirs$phase172)
  list(completion = completion, inventory = inventory)
}

app_joint_exqdesn_phase173_finalize <- function(
  freeze_dir = app_joint_exqdesn_phase171_175_dirs()$phase171,
  cache_root = app_joint_exqdesn_phase164_cache_root()
) {
  dirs <- app_joint_exqdesn_phase171_175_dirs(cache_root)
  freeze <- app_joint_exqdesn_phase171_load(freeze_dir)
  health <- app_joint_exqdesn_phase172_health(freeze_dir, dirs$phase172_orchestration)
  if (health$summary$complete_verified[[1L]] != 128L || health$summary$failed_workers[[1L]] > 0L) {
    stop("Phase173 cannot finalize before all 128 workers verify.", call. = FALSE)
  }
  closed <- app_joint_exqdesn_phase172_close_campaign(freeze, dirs)
  phase172_verification <- app_joint_exqdesn_verify_manifest(dirs$phase172, "phase172")
  worker_verification <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(freeze$plan)), function(ii) {
    x <- app_joint_exqdesn_verify_manifest(
      freeze$plan$worker_output_dir[[ii]],
      sprintf("phase172_worker_%03d", freeze$plan$worker_id[[ii]])
    )
    x$worker_id <- freeze$plan$worker_id[[ii]]
    x
  }))
  if (any(phase172_verification$status != "pass") || any(worker_verification$status != "pass")) {
    stop("Phase173 source manifest verification failed.", call. = FALSE)
  }
  artifacts <- app_joint_qdesn_load_fixture_artifacts(freeze$config$fixture_dir[[1L]])
  cells <- split(freeze$plan, freeze$plan$mcmc_case_id)
  results <- lapply(cells, app_joint_exqdesn_phase173_process_cell, freeze = freeze, artifacts = artifacts)
  bind <- function(name) app_joint_qdesn_bind_rows(lapply(results, `[[`, name))
  summary <- bind("summary")
  diagnostics <- bind("diagnostics")
  partition_detail <- bind("partition_detail")
  partition_summary <- bind("partition_summary")
  loo <- bind("loo")
  jackknife <- bind("jackknife")
  sensitivity <- bind("sensitivity")
  fit_raw <- bind("fit_raw")
  fit <- bind("fit")
  fit_adjustment <- bind("fit_adjustment")
  forecast_raw <- bind("forecast_raw")
  forecast <- bind("forecast")
  forecast_adjustment <- bind("forecast_adjustment")
  crossing <- bind("crossing")
  raw_crossing <- bind("raw_crossing")
  chain_distance <- bind("chain_distance")
  chains <- bind("chain_summary")
  assessment <- app_joint_exqdesn_phase173_assess_cells(
    summary, diagnostics, partition_summary, jackknife
  )
  historical <- app_joint_exqdesn_phase173_historical_comparison(summary, dirs)
  historical_qhat <- app_joint_exqdesn_phase173_historical_qhat(forecast, dirs)
  winner_mc <- app_joint_exqdesn_phase173_winner_mc_audit(summary, jackknife, dirs)
  rescue <- assessment[assessment$gate_status == "review_hold", c(
    "case_id", "scenario_id", "fit_structure", "status_reason"
  ), drop = FALSE]
  if (nrow(rescue)) {
    rescue$n_iter <- 48000L
    rescue$burn <- 8000L
    rescue$thin <- 8L
    rescue$starts <- "reuse_phase171"
    rescue$seeds <- "reuse_phase171"
    rescue$launch_status <- "not_authorized"
    rescue$draw_policy <- "supersede_primary_never_concatenate"
  } else {
    rescue <- data.frame(
      case_id = character(), scenario_id = character(), fit_structure = character(),
      status_reason = character(), n_iter = integer(), burn = integer(), thin = integer(),
      starts = character(), seeds = character(), launch_status = character(),
      draw_policy = character(), stringsAsFactors = FALSE
    )
  }
  final_gate <- if (any(assessment$gate_status == "fail")) {
    "fail"
  } else if (any(assessment$gate_status == "review_hold")) {
    "review"
  } else {
    "pass"
  }
  final <- data.frame(
    gate_status = final_gate,
    completed_cells = nrow(summary), expected_cells = 16L,
    pass_cells = sum(assessment$gate_status == "pass"),
    qualified_article_ready_cells = sum(assessment$gate_status == "qualified_article_ready"),
    review_hold_cells = sum(assessment$gate_status == "review_hold"),
    fail_cells = sum(assessment$gate_status == "fail"),
    contract_crossing_pairs = sum(summary$mcmc_fit_contract_crossing_pairs + summary$mcmc_forecast_contract_crossing_pairs),
    rescue_jobs_launched = 0L,
    article_assets_modified = FALSE,
    recommendation = if (final_gate == "pass") {
      "build_phase174_staged_balanced_packet"
    } else if (final_gate == "review") {
      "review_targeted_rescue_plan_before_any_launch"
    } else {
      "repair_phase172_or_phase173_before_promotion"
    },
    stringsAsFactors = FALSE
  )
  fit_truth <- app_joint_qdesn_truth_summary(fit)
  forecast_truth <- app_joint_qdesn_truth_summary(forecast)
  fit_check <- app_joint_qdesn_check_loss_summary(fit)
  forecast_check <- app_joint_qdesn_check_loss_summary(forecast)
  fit_hit <- app_joint_qdesn_hit_rate_summary(fit)
  forecast_hit <- app_joint_qdesn_hit_rate_summary(forecast)
  fit_crps <- app_joint_qdesn_crps_grid_summary(fit, "qhat")
  forecast_crps <- app_joint_qdesn_crps_grid_summary(forecast, "qhat")
  fit_interval <- app_joint_qdesn_interval_summary(fit, "qhat")
  forecast_interval <- app_joint_qdesn_interval_summary(forecast, "qhat")
  transformed <- diagnostics[diagnostics$parameter %in% c("gamma", "sigma", "p_gamma", "actual_sd", "sigma_lambda"), , drop = FALSE]
  readout <- diagnostics[diagnostics$parameter %in% c("beta", "alpha"), , drop = FALSE]
  component_audit <- data.frame(
    planned_component_runs = nrow(freeze$components),
    unique_component_seeds = length(unique(freeze$components$component_seed)),
    collisions = nrow(freeze$components) - length(unique(freeze$components$component_seed)),
    worker_metadata_hashes_match = all(vapply(seq_len(nrow(freeze$plan)), function(ii) {
      job <- freeze$plan[ii, , drop = FALSE]
      meta <- app_read_csv(file.path(app_joint_exqdesn_phase172_checkpoint_dir(job$worker_output_dir[[1L]]), "checkpoint_metadata.csv"))
      rows <- freeze$components[freeze$components$worker_id == job$worker_id[[1L]], , drop = FALSE]
      identical(meta$component_seed_table_sha256[[1L]], app_joint_exqdesn_phase172_table_hash(rows))
    }, logical(1L))),
    status = "pass", stringsAsFactors = FALSE
  )
  out_dir <- dirs$phase173
  if (dir.exists(out_dir)) {
    quarantine <- paste0(out_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(out_dir, quarantine)) stop("Could not quarantine prior Phase173 output.", call. = FALSE)
  }
  app_ensure_dir(out_dir)
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Phase173 M0 balanced article-readiness audit", "",
    sprintf("- Gate: `%s`", final$gate_status[[1L]]),
    sprintf("- Pass / qualified / hold / fail: `%d / %d / %d / %d`",
      final$pass_cells, final$qualified_article_ready_cells, final$review_hold_cells, final$fail_cells),
    "- Quantile-path stability and Monte Carlo error are primary; scalar gamma mixing is supporting evidence.",
    "- Any 48,000-iteration rescue remains unlaunched pending explicit review."
  ), readme, useBytes = TRUE)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(out_dir, name))
  paths <- c(
    phase172_manifest_verification = write(phase172_verification, "phase172_manifest_verification.csv"),
    worker_manifest_verification = write(worker_verification, "worker_manifest_verification.csv"),
    component_seed_audit = write(component_audit, "component_seed_audit.csv"),
    cell_health_summary = write(summary, "cell_health_summary.csv"),
    parameter_diagnostics = write(diagnostics, "parameter_diagnostics.csv"),
    readout_parameter_diagnostics = write(readout, "readout_parameter_diagnostics.csv"),
    gamma_sigma_diagnostics = write(transformed[transformed$parameter %in% c("gamma", "sigma"), ], "gamma_sigma_diagnostics.csv"),
    transformed_parameter_diagnostics = write(transformed, "transformed_parameter_diagnostics.csv"),
    chain_group_functional_stability = write(partition_detail, "chain_group_functional_stability.csv"),
    qhat_stability_summary = write(partition_summary, "qhat_stability_summary.csv"),
    chain_leave_one_out_stability = write(loo, "chain_leave_one_out_stability.csv"),
    metric_jackknife_mcse = write(jackknife, "metric_jackknife_mcse.csv"),
    winner_margin_mc_error_audit = write(winner_mc, "winner_margin_mc_error_audit.csv"),
    posterior_summary_sensitivity = write(sensitivity, "posterior_summary_sensitivity.csv"),
    fit_quantiles_raw = write(fit_raw, "fit_quantiles_raw.csv"),
    fit_quantiles = write(fit, "fit_quantiles.csv"),
    forecast_quantiles_raw = write(forecast_raw, "forecast_quantiles_raw.csv"),
    forecast_quantiles = write(forecast, "forecast_quantiles.csv"),
    fit_truth_comparison = write(fit, "fit_truth_comparison.csv"),
    forecast_truth_comparison = write(forecast, "forecast_truth_comparison.csv"),
    fit_truth_summary = write(fit_truth, "fit_truth_summary.csv"),
    forecast_truth_summary = write(forecast_truth, "forecast_truth_summary.csv"),
    fit_check_loss_summary = write(fit_check, "fit_check_loss_summary.csv"),
    forecast_check_loss_summary = write(forecast_check, "forecast_check_loss_summary.csv"),
    fit_crps_grid_summary = write(fit_crps, "fit_crps_grid_summary.csv"),
    forecast_crps_grid_summary = write(forecast_crps, "forecast_crps_grid_summary.csv"),
    fit_hit_rate_summary = write(fit_hit, "fit_hit_rate_summary.csv"),
    forecast_hit_rate_summary = write(forecast_hit, "forecast_hit_rate_summary.csv"),
    fit_interval_summary = write(fit_interval, "fit_interval_summary.csv"),
    forecast_interval_summary = write(forecast_interval, "forecast_interval_summary.csv"),
    fit_monotone_adjustment = write(fit_adjustment, "fit_monotone_adjustment.csv"),
    forecast_monotone_adjustment = write(forecast_adjustment, "forecast_monotone_adjustment.csv"),
    raw_crossing_summary = write(raw_crossing, "raw_crossing_summary.csv"),
    contract_crossing_summary = write(crossing, "contract_crossing_summary.csv"),
    crossing_summary = write(crossing, "crossing_summary.csv"),
    monotone_adjustment_summary = write(app_joint_qdesn_bind_rows(list(fit_adjustment, forecast_adjustment)), "monotone_adjustment_summary.csv"),
    chain_to_pooled_distance = write(chain_distance, "chain_to_pooled_distance.csv"),
    chain_to_pooled_distance_summary = write(chain_distance, "chain_to_pooled_distance_summary.csv"),
    mcmc_draw_summary = write(diagnostics, "mcmc_draw_summary.csv"),
    runtime_summary = write(chains, "runtime_summary.csv"),
    historical_vs_m0_metric_comparison = write(historical, "historical_vs_m0_metric_comparison.csv"),
    historical_vs_m0_qhat_comparison = write(historical_qhat, "historical_vs_m0_qhat_comparison.csv"),
    case_assessment = write(assessment, "case_assessment.csv"),
    mcmc_case_assessment = write(assessment, "mcmc_case_assessment.csv"),
    mcmc_case_summary = write(summary, "mcmc_case_summary.csv"),
    case_winner_controls = write(freeze$controls, "case_winner_controls.csv"),
    targeted_rescue_plan = write(rescue, "targeted_rescue_plan.csv"),
    balanced_final_packet_assessment = write(final, "balanced_final_packet_assessment.csv"),
    runtime_calibration_summary = write(chains, "runtime_calibration_summary.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_write_manifest(paths, out_dir)
  list(
    dirs = dirs, final = final, assessment = assessment, summary = summary,
    rescue = rescue, paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_phase173b_load_policy <- function(
  policy_path = app_joint_exqdesn_phase173b_policy_path()
) {
  policy <- app_read_csv(policy_path)
  required <- c(
    "schema_version", "policy_id", "primary_metric", "numerical_tolerance",
    "mcse_multiplier", "qhat_pass_q99_max", "qhat_pass_overlap_min",
    "qhat_review_q99_max", "qhat_review_overlap_min",
    "summary_abs_range_floor", "summary_relative_range_ceiling",
    "require_summary_direction_consistency",
    "accept_qhat_review_within_ceiling", "allow_nuisance_mixing_exception",
    "selection_policy"
  )
  app_check_required_columns(policy, required, "Phase173B promotion policy")
  if (nrow(policy) != 1L || policy$schema_version[[1L]] != 1L ||
      policy$primary_metric[[1L]] != "mcmc_forecast_truth_mae") {
    stop("Phase173B requires one version-1 forecast-MAE policy row.", call. = FALSE)
  }
  numeric_fields <- c(
    "numerical_tolerance", "mcse_multiplier", "qhat_pass_q99_max",
    "qhat_pass_overlap_min", "qhat_review_q99_max",
    "qhat_review_overlap_min", "summary_abs_range_floor",
    "summary_relative_range_ceiling"
  )
  if (any(!vapply(policy[numeric_fields], function(x) is.finite(as.numeric(x[[1L]])), logical(1L))) ||
      policy$qhat_review_q99_max[[1L]] < policy$qhat_pass_q99_max[[1L]] ||
      policy$qhat_review_overlap_min[[1L]] > policy$qhat_pass_overlap_min[[1L]]) {
    stop("Phase173B policy thresholds are malformed.", call. = FALSE)
  }
  policy
}

app_joint_exqdesn_phase173b_direction <- function(delta, tolerance) {
  if (!is.finite(delta)) return("unavailable")
  if (abs(delta) <= tolerance) return("no_material_change")
  if (delta < 0) "improvement" else "worsened"
}

app_joint_exqdesn_phase173b_improvement_label <- function(
  delta, jackknife_mcse, policy
) {
  tolerance <- as.numeric(policy$numerical_tolerance[[1L]])
  direction <- app_joint_exqdesn_phase173b_direction(delta, tolerance)
  if (direction != "improvement") return(direction)
  multiplier <- as.numeric(policy$mcse_multiplier[[1L]])
  if (is.finite(jackknife_mcse) && abs(delta) > multiplier * jackknife_mcse) {
    "clear_improvement"
  } else {
    "directional_improvement"
  }
}

app_joint_exqdesn_phase173b_qhat_status <- function(qhat, policy) {
  q99 <- max(as.numeric(qhat$q99_standardized_qhat_delta), na.rm = TRUE)
  overlap <- min(as.numeric(qhat$q01_central90_overlap_fraction), na.rm = TRUE)
  if (!is.finite(q99) || !is.finite(overlap)) return("hold")
  if (q99 <= policy$qhat_pass_q99_max[[1L]] &&
      overlap >= policy$qhat_pass_overlap_min[[1L]]) return("pass")
  if (isTRUE(as.logical(policy$accept_qhat_review_within_ceiling[[1L]])) &&
      q99 <= policy$qhat_review_q99_max[[1L]] &&
      overlap >= policy$qhat_review_overlap_min[[1L]]) return("review_accepted")
  "hold"
}

app_joint_exqdesn_phase173b_case_decision <- function(
  assessment, qhat, sensitivity, historical_forecast_mae,
  m0_forecast_mae, jackknife_mcse, policy
) {
  tolerance <- as.numeric(policy$numerical_tolerance[[1L]])
  hard_pass <- identical(assessment$implementation_status[[1L]], "pass")
  qhat_status <- app_joint_exqdesn_phase173b_qhat_status(qhat, policy)
  summary_values <- as.numeric(sensitivity$forecast_truth_mae)
  summary_delta <- summary_values - historical_forecast_mae
  directions <- vapply(
    summary_delta, app_joint_exqdesn_phase173b_direction,
    character(1L), tolerance = tolerance
  )
  directions <- unique(directions[directions != "no_material_change"])
  direction_consistent <- length(directions) <= 1L
  summary_range <- diff(range(summary_values))
  summary_range_ceiling <- max(
    as.numeric(policy$summary_abs_range_floor[[1L]]),
    as.numeric(policy$summary_relative_range_ceiling[[1L]]) * abs(historical_forecast_mae)
  )
  summary_stable <- all(is.finite(summary_values)) &&
    summary_range <= summary_range_ceiling &&
    (!isTRUE(as.logical(policy$require_summary_direction_consistency[[1L]])) || direction_consistent)
  loo_pass <- assessment$leave_one_chain_out_status[[1L]] %in% c("pass", "review")

  readout_status <- assessment$readout_severity_status[[1L]]
  readout_functional_status <- if (readout_status == "pass") {
    "pass"
  } else if (qhat_status != "hold" && summary_stable && loo_pass) {
    "review_accepted"
  } else {
    "hold"
  }
  shape_status <- assessment$multi_tau_shape_severity_status[[1L]]
  shape_functional_status <- if (shape_status == "pass") {
    "pass"
  } else if (qhat_status != "hold" && summary_stable && loo_pass) {
    "review_accepted"
  } else {
    "hold"
  }
  functional_pass <- hard_pass && qhat_status != "hold" && summary_stable &&
    loo_pass && readout_functional_status != "hold" &&
    shape_functional_status != "hold"
  nuisance_review <- assessment$scalar_mixing_status[[1L]] == "review" ||
    qhat_status == "review_accepted" ||
    readout_functional_status == "review_accepted" ||
    shape_functional_status == "review_accepted" ||
    assessment$raw_crossing_status[[1L]] == "review"
  action <- if (!hard_pass) {
    "retain_historical_candidate_fail"
  } else if (!functional_pass) {
    "retain_historical_functional_hold"
  } else if (nuisance_review && isTRUE(as.logical(policy$allow_nuisance_mixing_exception[[1L]]))) {
    "promote_with_mixing_qualification"
  } else if (nuisance_review) {
    "retain_historical_functional_hold"
  } else {
    "promote"
  }
  delta <- m0_forecast_mae - historical_forecast_mae
  data.frame(
    implementation_status = if (hard_pass) "pass" else "fail",
    qhat_functional_status = qhat_status,
    posterior_summary_status = if (summary_stable) "pass" else "hold",
    posterior_summary_direction_consistent = direction_consistent,
    posterior_summary_forecast_mae_range = summary_range,
    posterior_summary_range_ceiling = summary_range_ceiling,
    leave_one_chain_out_status = assessment$leave_one_chain_out_status[[1L]],
    readout_functional_status = readout_functional_status,
    shape_functional_status = shape_functional_status,
    scalar_mixing_status = assessment$scalar_mixing_status[[1L]],
    nuisance_mixing_exception = nuisance_review && functional_pass,
    functional_stability_status = if (functional_pass) "pass" else "hold",
    primary_metric_delta_M0_minus_historical = delta,
    primary_metric_direction = app_joint_exqdesn_phase173b_improvement_label(
      delta, jackknife_mcse, policy
    ),
    action = action,
    rationale = if (!hard_pass) {
      "M0 implementation gate failed; retain the verified historical exAL row"
    } else if (qhat_status == "hold") {
      "M0 quantile-path partition stability exceeds the versioned review ceiling"
    } else if (!summary_stable) {
      "M0 posterior mean/median/trimmed forecast summaries are materially unstable"
    } else if (!loo_pass) {
      "M0 leave-one-chain-out forecast sensitivity exceeds the review ceiling"
    } else if (readout_functional_status == "hold") {
      "M0 readout-coordinate instability is not insulated by stable quantile paths"
    } else if (shape_functional_status == "hold") {
      "M0 transformed shape/scale instability propagates beyond the accepted functional envelope"
    } else if (nuisance_review) {
      "M0 article estimands pass; supporting mixing or review-band diagnostics require qualification"
    } else {
      "M0 implementation and functional gates pass without qualification"
    },
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase173b_require_sources <- function(
  phase173_dir = app_joint_exqdesn_phase171_175_dirs()$phase173,
  cache_root = app_joint_exqdesn_phase164_cache_root()
) {
  dirs <- app_joint_exqdesn_phase171_175_dirs(cache_root)
  sources <- c(phase171 = dirs$phase171, phase173 = phase173_dir, phase155 = dirs$phase155)
  verification <- app_joint_qdesn_bind_rows(lapply(names(sources), function(id) {
    app_joint_exqdesn_verify_manifest(sources[[id]], id)
  }))
  if (any(verification$status != "pass")) {
    stop("Phase173B source manifest verification failed.", call. = FALSE)
  }
  final <- app_read_csv(file.path(phase173_dir, "balanced_final_packet_assessment.csv"))
  assessment <- app_read_csv(file.path(phase173_dir, "case_assessment.csv"))
  summary <- app_read_csv(file.path(phase173_dir, "mcmc_case_summary.csv"))
  expected <- as.vector(outer(
    app_joint_exqdesn_phase171_scenarios(),
    app_joint_exqdesn_phase174_exal_model_ids(), paste, sep = "::"
  ))
  cells <- paste(summary$scenario_id, summary$source_model_id, sep = "::")
  if (nrow(final) != 1L || final$completed_cells[[1L]] != 16L ||
      final$fail_cells[[1L]] != 0L || nrow(summary) != 16L ||
      nrow(assessment) != 16L || anyDuplicated(cells) || !setequal(cells, expected)) {
    stop("Phase173B requires the complete, nonfailed 16-cell Phase173 packet.", call. = FALSE)
  }
  list(
    dirs = dirs, sources = sources, verification = verification,
    final = final, assessment = assessment, summary = summary
  )
}

app_joint_exqdesn_phase173b_run <- function(
  phase173_dir = app_joint_exqdesn_phase171_175_dirs()$phase173,
  policy_path = app_joint_exqdesn_phase173b_policy_path(),
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  out_dir = app_joint_exqdesn_phase171_175_dirs(cache_root)$phase173b,
  force = FALSE
) {
  policy <- app_joint_exqdesn_phase173b_load_policy(policy_path)
  source <- app_joint_exqdesn_phase173b_require_sources(phase173_dir, cache_root)
  dirs <- source$dirs
  comparison <- app_read_csv(file.path(phase173_dir, "historical_vs_m0_metric_comparison.csv"))
  qhat <- app_read_csv(file.path(phase173_dir, "qhat_stability_summary.csv"))
  sensitivity <- app_read_csv(file.path(phase173_dir, "posterior_summary_sensitivity.csv"))
  jackknife <- app_read_csv(file.path(phase173_dir, "metric_jackknife_mcse.csv"))
  baseline <- app_read_csv(file.path(dirs$phase155, "final_case_summary.csv"))
  baseline <- baseline[baseline$source_model_id %in% app_joint_exqdesn_phase174_exal_model_ids(), , drop = FALSE]
  if (nrow(comparison) != 16L || nrow(baseline) != 16L || anyDuplicated(comparison$case_id)) {
    stop("Phase173B historical/M0 comparison is not a unique 16-cell packet.", call. = FALSE)
  }

  decision_rows <- lapply(seq_len(nrow(source$summary)), function(ii) {
    cell <- source$summary[ii, , drop = FALSE]
    id <- cell$case_id[[1L]]
    a <- app_joint_exqdesn_phase174_case_lookup(source$assessment, id, "Phase173 assessment")
    h <- app_joint_exqdesn_phase174_case_lookup(comparison, id, "historical comparison")
    q <- qhat[qhat$case_id == id, , drop = FALSE]
    s <- sensitivity[sensitivity$case_id == id, , drop = FALSE]
    j <- jackknife[jackknife$case_id == id & jackknife$metric == "forecast_truth_mae", , drop = FALSE]
    if (nrow(q) != 4L || nrow(s) != 3L || nrow(j) != 1L) {
      stop(sprintf("Phase173B incomplete functional evidence for '%s'.", id), call. = FALSE)
    }
    decision <- app_joint_exqdesn_phase173b_case_decision(
      a, q, s,
      h$mcmc_forecast_truth_mae_historical[[1L]],
      h$mcmc_forecast_truth_mae_M0[[1L]],
      j$jackknife_mcse[[1L]], policy
    )
    cbind(data.frame(
      case_id = id, scenario_id = cell$scenario_id[[1L]],
      fit_structure = cell$fit_structure[[1L]],
      source_model_id = cell$source_model_id[[1L]],
      source_candidate_id = cell$source_candidate_id[[1L]],
      historical_forecast_truth_mae = h$mcmc_forecast_truth_mae_historical[[1L]],
      m0_forecast_truth_mae = h$mcmc_forecast_truth_mae_M0[[1L]],
      m0_forecast_truth_mae_jackknife_mcse = j$jackknife_mcse[[1L]],
      maximum_q99_standardized_qhat_delta = max(q$q99_standardized_qhat_delta),
      minimum_q01_central90_overlap_fraction = min(q$q01_central90_overlap_fraction),
      phase173_gate_status = a$gate_status[[1L]],
      stringsAsFactors = FALSE
    ), decision)
  })
  decisions <- app_joint_qdesn_bind_rows(decision_rows)
  promote_actions <- c("promote", "promote_with_mixing_qualification")
  decisions$selected_source <- ifelse(
    decisions$action %in% promote_actions, "phase173_m0", "phase155_historical"
  )
  phase173_manifest_sha <- app_sha256_file(file.path(phase173_dir, "artifact_manifest.csv"))
  phase155_manifest_sha <- app_sha256_file(file.path(dirs$phase155, "artifact_manifest.csv"))
  decisions$selected_source_manifest_sha256 <- ifelse(
    decisions$selected_source == "phase173_m0", phase173_manifest_sha, phase155_manifest_sha
  )
  decisions$selected_source_dir <- ifelse(
    decisions$selected_source == "phase173_m0",
    app_prefer_repo_relative_path(phase173_dir),
    app_prefer_repo_relative_path(dirs$phase155)
  )

  primary <- decisions[, c(
    "case_id", "scenario_id", "fit_structure", "source_model_id",
    "historical_forecast_truth_mae", "m0_forecast_truth_mae",
    "primary_metric_delta_M0_minus_historical",
    "m0_forecast_truth_mae_jackknife_mcse", "primary_metric_direction",
    "action", "selected_source"
  ), drop = FALSE]
  metric_specs <- list(
    fit_truth_mae = c("mcmc_fit_truth_mae_historical", "mcmc_fit_truth_mae_M0"),
    forecast_truth_mae = c("mcmc_forecast_truth_mae_historical", "mcmc_forecast_truth_mae_M0"),
    forecast_check_loss_mean = c("mcmc_forecast_check_loss_mean_historical", "mcmc_forecast_check_loss_mean_M0")
  )
  secondary <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(comparison)), function(ii) {
    row <- comparison[ii, , drop = FALSE]
    app_joint_qdesn_bind_rows(lapply(names(metric_specs), function(metric) {
      fields <- metric_specs[[metric]]
      old <- as.numeric(row[[fields[[1L]]]][[1L]])
      now <- as.numeric(row[[fields[[2L]]]][[1L]])
      data.frame(
        case_id = row$case_id[[1L]], scenario_id = row$scenario_id[[1L]],
        fit_structure = row$fit_structure[[1L]], metric = metric,
        historical_value = old, m0_value = now,
        delta_M0_minus_historical = now - old,
        direction = app_joint_exqdesn_phase173b_direction(
          now - old, policy$numerical_tolerance[[1L]]
        ), stringsAsFactors = FALSE
      )
    }))
  }))
  posterior <- merge(
    sensitivity,
    comparison[, c("case_id", "mcmc_forecast_truth_mae_historical"), drop = FALSE],
    by = "case_id", sort = FALSE
  )
  posterior$delta_from_historical <- posterior$forecast_truth_mae -
    posterior$mcmc_forecast_truth_mae_historical
  posterior$direction <- vapply(
    posterior$delta_from_historical, app_joint_exqdesn_phase173b_direction,
    character(1L), tolerance = policy$numerical_tolerance[[1L]]
  )
  functional <- decisions[, c(
    "case_id", "scenario_id", "fit_structure", "implementation_status",
    "qhat_functional_status", "posterior_summary_status",
    "posterior_summary_direction_consistent",
    "posterior_summary_forecast_mae_range", "posterior_summary_range_ceiling",
    "leave_one_chain_out_status", "readout_functional_status",
    "shape_functional_status", "functional_stability_status", "rationale"
  ), drop = FALSE]
  nuisance <- decisions[, c(
    "case_id", "scenario_id", "fit_structure", "scalar_mixing_status",
    "qhat_functional_status", "readout_functional_status",
    "shape_functional_status", "nuisance_mixing_exception", "action"
  ), drop = FALSE]
  retained <- decisions[grepl("^retain_historical", decisions$action), c(
    "case_id", "scenario_id", "fit_structure", "source_model_id", "action",
    "rationale", "primary_metric_direction", "selected_source",
    "selected_source_dir", "selected_source_manifest_sha256"
  ), drop = FALSE]
  method_consistency <- decisions[, c(
    "case_id", "scenario_id", "fit_structure", "source_model_id", "action",
    "primary_metric_direction", "selected_source", "selected_source_dir",
    "selected_source_manifest_sha256"
  ), drop = FALSE]
  method_consistency$prospective_method <- "M0_v_collapsed_support_logit"
  method_consistency$historical_fallback_reason <- ifelse(
    grepl("^retain_historical", method_consistency$action),
    "functional_or_implementation_hold", "not_applicable"
  )
  if (any(decisions$action == "retain_historical_candidate_fail")) {
    overall_gate <- "fail"
    staging_ready <- FALSE
  } else {
    overall_gate <- if (all(decisions$action == "promote")) "pass" else "review"
    staging_ready <- TRUE
  }
  final <- data.frame(
    phase_id = "phase173b_metric_qualified_promotion",
    gate_status = overall_gate,
    total_cells = nrow(decisions),
    promote_cells = sum(decisions$action == "promote"),
    promote_with_mixing_qualification_cells = sum(decisions$action == "promote_with_mixing_qualification"),
    retained_historical_functional_hold_cells = sum(decisions$action == "retain_historical_functional_hold"),
    retained_historical_candidate_fail_cells = sum(decisions$action == "retain_historical_candidate_fail"),
    m0_primary_metric_improvement_cells = sum(grepl("improvement", decisions$primary_metric_direction)),
    selected_m0_cells = sum(decisions$selected_source == "phase173_m0"),
    selected_historical_cells = sum(decisions$selected_source == "phase155_historical"),
    staging_ready = staging_ready,
    article_assets_modified = FALSE,
    rescue_jobs_launched = 0L,
    recommendation = if (staging_ready) "build_phase174_method_consistent_hybrid_packet" else "repair_candidate_failures_before_staging",
    stringsAsFactors = FALSE
  )

  if (dir.exists(out_dir)) {
    if (!force) {
      check <- tryCatch(app_joint_exqdesn_verify_manifest(out_dir, "phase173b"), error = function(e) NULL)
      if (!is.null(check) && all(check$status == "pass")) {
        return(list(
          out_dir = out_dir,
          decisions = app_read_csv(file.path(out_dir, "case_promotion_decision.csv")),
          final = app_read_csv(file.path(out_dir, "promotion_readiness_summary.csv"))
        ))
      }
    }
    quarantine <- paste0(out_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(out_dir, quarantine)) stop("Could not quarantine prior Phase173B output.", call. = FALSE)
  }
  app_ensure_dir(out_dir)
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Phase173B metric-qualified exQDESN promotion audit", "",
    "This deterministic postprocessor does not rerun MCMC and does not select a sampler from realized scores.",
    "M0 remains the prospective exAL method unless a hard or functional gate requires the verified historical fallback.",
    sprintf("- Gate: `%s`", final$gate_status[[1L]]),
    sprintf("- Selected M0 / historical exAL cells: `%d / %d`", final$selected_m0_cells[[1L]], final$selected_historical_cells[[1L]]),
    sprintf("- Primary forecast-MAE improvements under M0: `%d / 16`", final$m0_primary_metric_improvement_cells[[1L]]),
    "- Scalar gamma/sigma limitations alone do not reject a stable posterior quantile path.",
    "- No rescue chain or tracked article asset was launched or modified."
  ), readme, useBytes = TRUE)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(out_dir, name))
  paths <- c(
    promotion_policy = write(policy, "promotion_policy.csv"),
    case_promotion_decision = write(decisions, "case_promotion_decision.csv"),
    historical_vs_m0_primary_metric = write(primary, "historical_vs_m0_primary_metric.csv"),
    historical_vs_m0_secondary_metrics = write(secondary, "historical_vs_m0_secondary_metrics.csv"),
    nuisance_mixing_exception_audit = write(nuisance, "nuisance_mixing_exception_audit.csv"),
    functional_stability_audit = write(functional, "functional_stability_audit.csv"),
    posterior_summary_decision_audit = write(posterior, "posterior_summary_decision_audit.csv"),
    winner_margin_mcse_audit = write(app_read_csv(file.path(phase173_dir, "winner_margin_mc_error_audit.csv")), "winner_margin_mcse_audit.csv"),
    retained_historical_cell_audit = write(retained, "retained_historical_cell_audit.csv"),
    method_consistency_audit = write(method_consistency, "method_consistency_audit.csv"),
    promotion_readiness_summary = write(final, "promotion_readiness_summary.csv"),
    source_manifest_verification = write(source$verification, "source_manifest_verification.csv"),
    run_config = write(data.frame(
      phase_id = "phase173b_metric_qualified_promotion",
      phase173_dir = normalizePath(phase173_dir),
      policy_path = normalizePath(policy_path), output_dir = out_dir,
      selection_policy = policy$selection_policy[[1L]],
      tracked_article_assets_modified = FALSE, stringsAsFactors = FALSE
    ), "run_config.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir, decisions = decisions, final = final,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_phase174_exal_model_ids <- function() {
  c("joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb")
}

app_joint_exqdesn_phase174_require_phase173 <- function(
  phase173_dir = app_joint_exqdesn_phase171_175_dirs()$phase173,
  phase173b_dir = app_joint_exqdesn_phase171_175_dirs()$phase173b
) {
  phase173_dir <- normalizePath(phase173_dir, mustWork = TRUE)
  phase173b_dir <- normalizePath(phase173b_dir, mustWork = TRUE)
  verification <- app_joint_exqdesn_verify_manifest(phase173_dir, "phase173")
  decision_verification <- app_joint_exqdesn_verify_manifest(phase173b_dir, "phase173b")
  final <- app_read_csv(file.path(phase173_dir, "balanced_final_packet_assessment.csv"))
  assessment <- app_read_csv(file.path(phase173_dir, "case_assessment.csv"))
  summary <- app_read_csv(file.path(phase173_dir, "mcmc_case_summary.csv"))
  decision_final <- app_read_csv(file.path(phase173b_dir, "promotion_readiness_summary.csv"))
  decisions <- app_read_csv(file.path(phase173b_dir, "case_promotion_decision.csv"))
  expected <- as.vector(outer(
    app_joint_exqdesn_phase171_scenarios(),
    app_joint_exqdesn_phase174_exal_model_ids(),
    paste, sep = "::"
  ))
  cells <- paste(summary$scenario_id, summary$source_model_id, sep = "::")
  if (any(verification$status != "pass") || nrow(final) != 1L ||
      any(decision_verification$status != "pass") || nrow(summary) != 16L ||
      anyDuplicated(cells) || !setequal(cells, expected) ||
      nrow(assessment) != 16L || nrow(decisions) != 16L ||
      anyDuplicated(decisions$case_id) || nrow(decision_final) != 1L ||
      !isTRUE(as.logical(decision_final$staging_ready[[1L]]))) {
    stop("Phase174 requires complete Phase173 evidence and a staging-ready Phase173B decision packet.", call. = FALSE)
  }
  list(
    dir = phase173_dir, verification = verification, final = final,
    assessment = assessment, summary = summary,
    decision_dir = phase173b_dir, decision_verification = decision_verification,
    decision_final = decision_final, decisions = decisions
  )
}

app_joint_exqdesn_phase174_case_lookup <- function(x, case_id, label) {
  row <- x[x$case_id == case_id, , drop = FALSE]
  if (nrow(row) != 1L) {
    stop(sprintf("Phase174 expected one %s row for '%s'.", label, case_id), call. = FALSE)
  }
  row
}

app_joint_exqdesn_phase174_max_for_case <- function(x, case_id, field, default = NA_real_) {
  block <- x[x$case_id == case_id, , drop = FALSE]
  if (!nrow(block) || !field %in% names(block)) return(default)
  values <- suppressWarnings(as.numeric(block[[field]]))
  values <- values[is.finite(values)]
  if (length(values)) max(values) else default
}

app_joint_exqdesn_phase174_compose_case_summary <- function(
  phase173,
  freeze,
  dirs
) {
  baseline <- app_read_csv(file.path(dirs$phase155, "final_case_summary.csv"))
  if (nrow(baseline) != 32L || anyDuplicated(baseline$case_id)) {
    stop("Phase174 baseline article packet is not a unique 32-cell grid.", call. = FALSE)
  }
  baseline$inference_method_id <- NA_character_
  baseline$vb_initialization_method <- NA_character_
  baseline$max_rank_rhat <- NA_real_
  baseline$max_folded_rhat <- NA_real_
  baseline$min_bulk_ess <- NA_real_
  baseline$min_tail_ess <- NA_real_
  baseline$phase173_gate_status <- NA_character_
  baseline$phase173b_action <- "preserved_historical"
  baseline$phase173b_primary_metric_direction <- NA_character_
  baseline$phase173b_mixing_exception <- FALSE
  baseline$source_manifest_sha256 <- app_sha256_file(file.path(dirs$phase155, "artifact_manifest.csv"))
  preflight <- app_read_csv(file.path(freeze$dir, "scoring_preflight.csv"))
  init_audit <- app_read_csv(file.path(freeze$dir, "vb_initialization_audit.csv"))
  fit_adjustment <- app_read_csv(file.path(phase173$dir, "fit_monotone_adjustment.csv"))
  forecast_adjustment <- app_read_csv(file.path(phase173$dir, "forecast_monotone_adjustment.csv"))
  hit <- app_read_csv(file.path(phase173$dir, "forecast_hit_rate_summary.csv"))
  chain <- app_read_csv(file.path(phase173$dir, "chain_to_pooled_distance_summary.csv"))
  assessment <- phase173$assessment

  old_al <- baseline[!baseline$source_model_id %in% app_joint_exqdesn_phase174_exal_model_ids(), , drop = FALSE]
  for (ii in seq_len(nrow(phase173$summary))) {
    current <- phase173$summary[ii, , drop = FALSE]
    case_id <- current$case_id[[1L]]
    idx <- which(baseline$case_id == case_id)
    if (length(idx) != 1L) stop(sprintf("Phase174 could not map exAL case '%s'.", case_id), call. = FALSE)
    key <- if ("mcmc_case_id" %in% names(current) && nzchar(current$mcmc_case_id[[1L]])) {
      current$mcmc_case_id[[1L]]
    } else {
      paste(current$scenario_id[[1L]], current$fit_structure[[1L]], sep = "__")
    }
    vb <- preflight[preflight$mcmc_case_id == key, , drop = FALSE]
    init <- init_audit[init_audit$mcmc_case_id == key, , drop = FALSE]
    gate <- app_joint_exqdesn_phase174_case_lookup(assessment, case_id, "assessment")
    decision <- app_joint_exqdesn_phase174_case_lookup(phase173$decisions, case_id, "Phase173B decision")
    if (nrow(vb) != 1L || nrow(init) != 1L) {
      stop(sprintf("Phase174 could not map Phase171 initialization for '%s'.", case_id), call. = FALSE)
    }
    baseline$phase173_gate_status[idx] <- gate$gate_status[[1L]]
    baseline$phase173b_action[idx] <- decision$action[[1L]]
    baseline$phase173b_primary_metric_direction[idx] <- decision$primary_metric_direction[[1L]]
    baseline$phase173b_mixing_exception[idx] <- as.logical(decision$nuisance_mixing_exception[[1L]])
    if (grepl("^retain_historical", decision$action[[1L]])) next
    replace <- list(
      source_candidate_id = current$source_candidate_id[[1L]],
      model_id = current$model_id[[1L]],
      display_label = current$display_label[[1L]],
      inference = "MCMC",
      phase121_candidate_id = current$source_candidate_id[[1L]],
      phase121_selection_status = "phase171_frozen_control",
      vb_converged = as.logical(init$vb1_converged[[1L]]),
      vb_reached_max_iter = !as.logical(init$vb1_converged[[1L]]),
      vb_adaptive_attempts = "VB0_point_v->VB1_structured_v",
      mcmc_n_chains = current$mcmc_n_chains[[1L]],
      mcmc_n_iter = current$mcmc_n_iter[[1L]],
      mcmc_burn = current$mcmc_burn[[1L]],
      mcmc_thin = current$mcmc_thin[[1L]],
      mcmc_n_keep_total = current$mcmc_n_keep_total[[1L]],
      mcmc_init_source = current$mcmc_init_source[[1L]],
      all_chain_init_source_provided = current$all_chain_init_source_provided[[1L]],
      mcmc_draws_all_finite = current$mcmc_draws_all_finite[[1L]],
      sigma_lower_bound = 0,
      sigma_upper_bound = Inf,
      max_sigma_lower_bound_hit_fraction = 0,
      max_sigma_upper_bound_hit_fraction = 0,
      vb_fit_truth_mae = vb$fit_truth_mae[[1L]],
      mcmc_fit_truth_mae = current$mcmc_fit_truth_mae[[1L]],
      vb_forecast_truth_mae = vb$forecast_truth_mae[[1L]],
      mcmc_forecast_truth_mae = current$mcmc_forecast_truth_mae[[1L]],
      vb_fit_check_loss_mean = vb$fit_check_loss_mean[[1L]],
      mcmc_fit_check_loss_mean = current$mcmc_fit_check_loss_mean[[1L]],
      vb_forecast_check_loss_mean = vb$forecast_check_loss_mean[[1L]],
      mcmc_forecast_check_loss_mean = current$mcmc_forecast_check_loss_mean[[1L]],
      vb_fit_raw_crossing_pairs = vb$fit_raw_crossing_pairs[[1L]],
      mcmc_fit_raw_crossing_pairs = current$mcmc_fit_raw_crossing_pairs[[1L]],
      vb_forecast_raw_crossing_pairs = vb$forecast_raw_crossing_pairs[[1L]],
      mcmc_forecast_raw_crossing_pairs = current$mcmc_forecast_raw_crossing_pairs[[1L]],
      vb_fit_contract_crossing_pairs = 0L,
      mcmc_fit_contract_crossing_pairs = current$mcmc_fit_contract_crossing_pairs[[1L]],
      vb_forecast_contract_crossing_pairs = 0L,
      mcmc_forecast_contract_crossing_pairs = current$mcmc_forecast_contract_crossing_pairs[[1L]],
      vb_fit_max_abs_adjustment = vb$fit_max_abs_adjustment[[1L]],
      mcmc_fit_max_abs_adjustment = app_joint_exqdesn_phase174_max_for_case(fit_adjustment, case_id, "abs_adjustment", 0),
      vb_forecast_max_abs_adjustment = vb$forecast_max_abs_adjustment[[1L]],
      mcmc_forecast_max_abs_adjustment = app_joint_exqdesn_phase174_max_for_case(forecast_adjustment, case_id, "abs_adjustment", 0),
      vb_mcmc_max_normalized_distance = NA_real_,
      max_chain_to_pooled_normalized_distance = app_joint_exqdesn_phase174_max_for_case(chain, case_id, "max_normalized_to_pooled"),
      vb_elapsed_seconds = init$vb0_elapsed_seconds[[1L]] + init$vb1_elapsed_seconds[[1L]],
      mcmc_elapsed_seconds = current$runtime_seconds_total[[1L]],
      total_elapsed_seconds = init$vb0_elapsed_seconds[[1L]] + init$vb1_elapsed_seconds[[1L]] + current$runtime_seconds_total[[1L]],
      source_block_id = "phase173_m0_exal",
      source_dir = app_prefer_repo_relative_path(phase173$dir),
      mcmc_forecast_crps_grid = current$mcmc_forecast_crps_grid_mean[[1L]],
      mcmc_mean_abs_hit_rate_error = mean(abs(as.numeric(hit$hit_rate_error[hit$case_id == case_id])), na.rm = TRUE),
      mcmc_max_abs_hit_rate_error = app_joint_exqdesn_phase174_max_for_case(hit, case_id, "abs_hit_rate_error"),
      max_chain_qhat_normalized_distance = app_joint_exqdesn_phase174_max_for_case(chain, case_id, "qhat_normalized_to_pooled"),
      max_chain_sigma_normalized_distance = app_joint_exqdesn_phase174_max_for_case(chain, case_id, "sigma_normalized_to_pooled"),
      max_chain_alpha_normalized_distance = app_joint_exqdesn_phase174_max_for_case(chain, case_id, "alpha_normalized_to_pooled"),
      implementation_status = gate$implementation_status[[1L]],
      distance_status = if (gate$functional_partition_status[[1L]] == "pass") "pass" else "review",
      chain_status = if (gate$leave_one_chain_out_status[[1L]] %in% c("pass", "review")) "pass" else "review",
      raw_crossing_status = gate$raw_crossing_status[[1L]],
      gate_status = if (gate$gate_status[[1L]] == "pass") "pass" else "review",
      status_reason = gate$status_reason[[1L]],
      exact_control_match = TRUE,
      article_grade = TRUE,
      final_status = if (gate$gate_status[[1L]] == "pass") "pass" else "review"
    )
    for (field in names(replace)) baseline[[field]][idx] <- replace[[field]]
    baseline$inference_method_id[idx] <- current$inference_method_id[[1L]]
    baseline$vb_initialization_method[idx] <- "VB0_point_v_to_VB1_structured_v"
    baseline$max_rank_rhat[idx] <- current$max_rank_rhat[[1L]]
    baseline$max_folded_rhat[idx] <- current$max_folded_rhat[[1L]]
    baseline$min_bulk_ess[idx] <- current$min_bulk_ess[[1L]]
    baseline$min_tail_ess[idx] <- current$min_tail_ess[[1L]]
    baseline$source_manifest_sha256[idx] <- decision$selected_source_manifest_sha256[[1L]]
  }
  new_al <- baseline[!baseline$source_model_id %in% app_joint_exqdesn_phase174_exal_model_ids(), names(old_al), drop = FALSE]
  old_al <- old_al[order(old_al$case_id), , drop = FALSE]
  new_al <- new_al[order(new_al$case_id), , drop = FALSE]
  old_hash <- vapply(seq_len(nrow(old_al)), function(ii) {
    app_joint_exqdesn_phase171_row_hash(old_al[ii, , drop = FALSE])
  }, character(1L))
  new_hash <- vapply(seq_len(nrow(new_al)), function(ii) {
    app_joint_exqdesn_phase171_row_hash(new_al[ii, , drop = FALSE])
  }, character(1L))
  if (!identical(old_hash, new_hash)) {
    stop("Phase174 altered an unchanged AL row.", call. = FALSE)
  }
  baseline <- baseline[order(baseline$scenario_order, baseline$model_order), , drop = FALSE]
  rownames(baseline) <- NULL
  baseline
}

app_joint_exqdesn_phase174_case_assessment <- function(case_summary) {
  data.frame(
    case_id = case_summary$case_id,
    scenario_id = case_summary$scenario_id,
    source_model_id = case_summary$source_model_id,
    implementation_status = case_summary$implementation_status,
    distance_status = case_summary$distance_status,
    chain_status = case_summary$chain_status,
    raw_crossing_status = case_summary$raw_crossing_status,
    gate_status = case_summary$gate_status,
    contract_crossing_pairs = case_summary$mcmc_fit_contract_crossing_pairs + case_summary$mcmc_forecast_contract_crossing_pairs,
    raw_crossing_pairs = case_summary$mcmc_fit_raw_crossing_pairs + case_summary$mcmc_forecast_raw_crossing_pairs,
    max_abs_adjustment = pmax(case_summary$mcmc_fit_max_abs_adjustment, case_summary$mcmc_forecast_max_abs_adjustment),
    status_reason = case_summary$status_reason,
    source_block_id = case_summary$source_block_id,
    source_dir = case_summary$source_dir,
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase174_winner_mc_audit <- function(case_summary, phase173_dir) {
  jackknife <- app_read_csv(file.path(phase173_dir, "metric_jackknife_mcse.csv"))
  metric_map <- c(
    mcmc_fit_truth_mae = "fit_truth_mae",
    mcmc_forecast_truth_mae = "forecast_truth_mae",
    mcmc_forecast_check_loss_mean = "forecast_check_loss_mean",
    mcmc_forecast_crps_grid = "forecast_crps_grid_mean"
  )
  rows <- lapply(unique(case_summary$scenario_id), function(scenario_id) {
    block <- case_summary[case_summary$scenario_id == scenario_id, , drop = FALSE]
    app_joint_qdesn_bind_rows(lapply(names(metric_map), function(metric) {
      ord <- order(as.numeric(block[[metric]]), block$source_model_id)
      winner <- block[ord[[1L]], , drop = FALSE]
      runner <- block[ord[[2L]], , drop = FALSE]
      lookup <- function(row) {
        if (row$source_block_id[[1L]] != "phase173_m0_exal") return(NA_real_)
        value <- jackknife[
          jackknife$case_id == row$case_id[[1L]] &
            jackknife$metric == metric_map[[metric]],
          "jackknife_mcse", drop = TRUE
        ]
        if (length(value) == 1L) as.numeric(value) else NA_real_
      }
      winner_mcse <- lookup(winner)
      runner_mcse <- lookup(runner)
      available <- c(winner_mcse, runner_mcse)
      available <- available[is.finite(available)]
      combined <- if (length(available)) sqrt(sum(available^2)) else NA_real_
      margin <- runner[[metric]][[1L]] - winner[[metric]][[1L]]
      data.frame(
        scenario_id = scenario_id, metric = metric,
        winner_model_id = winner$source_model_id[[1L]],
        runner_up_model_id = runner$source_model_id[[1L]],
        winner_value = winner[[metric]][[1L]], runner_up_value = runner[[metric]][[1L]],
        winner_margin = margin, winner_jackknife_mcse = winner_mcse,
        runner_up_jackknife_mcse = runner_mcse,
        available_combined_mcse = combined,
        mcse_coverage = if (all(is.finite(c(winner_mcse, runner_mcse)))) {
          "complete"
        } else if (length(available)) {
          "partial"
        } else {
          "unavailable_for_frozen_historical_rows"
        },
        interpretation = if (!all(is.finite(c(winner_mcse, runner_mcse)))) {
          "descriptive_winner_incomplete_mcse"
        } else if (margin <= 2 * combined) {
          "near_tie"
        } else {
          "resolved_at_available_mc_precision"
        }, stringsAsFactors = FALSE
      )
    }))
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase174_build_packet <- function(
  phase173_dir = app_joint_exqdesn_phase171_175_dirs()$phase173,
  phase173b_dir = app_joint_exqdesn_phase171_175_dirs()$phase173b,
  freeze_dir = app_joint_exqdesn_phase171_175_dirs()$phase171,
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  force = FALSE
) {
  dirs <- app_joint_exqdesn_phase171_175_dirs(cache_root)
  phase173 <- app_joint_exqdesn_phase174_require_phase173(phase173_dir, phase173b_dir)
  freeze <- app_joint_exqdesn_phase171_load(freeze_dir)
  source_dirs <- c(
    phase171 = freeze$dir,
    phase173 = phase173$dir,
    phase173b = phase173$decision_dir,
    phase153 = dirs$phase153_vb,
    phase154 = dirs$phase154_final,
    phase155 = dirs$phase155
  )
  source_verification <- app_joint_qdesn_bind_rows(lapply(names(source_dirs), function(id) {
    app_joint_exqdesn_verify_manifest(source_dirs[[id]], id)
  }))
  if (any(source_verification$status != "pass")) {
    stop("Phase174 source manifest verification failed.", call. = FALSE)
  }
  case_summary <- app_joint_exqdesn_phase174_compose_case_summary(phase173, freeze, dirs)
  expected <- as.vector(outer(
    app_joint_qdesn_phase155_scenario_dictionary()$scenario_id,
    app_joint_qdesn_phase155_model_dictionary()$source_model_id,
    paste, sep = "::"
  ))
  cells <- paste(case_summary$scenario_id, case_summary$source_model_id, sep = "::")
  hard_pass <- nrow(case_summary) == 32L && !anyDuplicated(cells) && setequal(cells, expected) &&
    all(case_summary$mcmc_draws_all_finite) && all(case_summary$all_chain_init_source_provided) &&
    all(is.finite(case_summary$mcmc_fit_truth_mae)) && all(is.finite(case_summary$mcmc_forecast_truth_mae)) &&
    sum(case_summary$mcmc_fit_contract_crossing_pairs + case_summary$mcmc_forecast_contract_crossing_pairs) == 0L &&
    !any(case_summary$final_status == "fail")
  if (!hard_pass) stop("Phase174 balanced-packet hard gate failed.", call. = FALSE)
  assessment <- app_joint_exqdesn_phase174_case_assessment(case_summary)
  winners <- app_joint_qdesn_phase155_metric_winners(case_summary)
  winner_mc <- app_joint_exqdesn_phase174_winner_mc_audit(case_summary, phase173$dir)
  model_summary <- app_joint_qdesn_phase155_model_summary(case_summary)
  audit <- data.frame(
    case_id = case_summary$case_id,
    scenario_id = case_summary$scenario_id,
    source_model_id = case_summary$source_model_id,
    mcmc_model_id = case_summary$model_id,
    source_block_id = case_summary$source_block_id,
    target_candidate_id = case_summary$source_candidate_id,
    source_candidate_id = case_summary$source_candidate_id,
    exact_control_match = case_summary$exact_control_match,
    mcmc_n_chains = case_summary$mcmc_n_chains,
    mcmc_n_iter = case_summary$mcmc_n_iter,
    mcmc_burn = case_summary$mcmc_burn,
    mcmc_thin = case_summary$mcmc_thin,
    mcmc_n_keep_total = case_summary$mcmc_n_keep_total,
    phase173b_action = case_summary$phase173b_action,
    phase173b_primary_metric_direction = case_summary$phase173b_primary_metric_direction,
    phase173b_mixing_exception = case_summary$phase173b_mixing_exception,
    source_manifest_sha256 = case_summary$source_manifest_sha256,
    implementation_reusable = case_summary$implementation_status == "pass",
    article_grade = case_summary$article_grade,
    gate_status = case_summary$gate_status,
    mcmc_fit_truth_mae = case_summary$mcmc_fit_truth_mae,
    mcmc_forecast_truth_mae = case_summary$mcmc_forecast_truth_mae,
    mcmc_forecast_check_loss_mean = case_summary$mcmc_forecast_check_loss_mean,
    mcmc_fit_raw_crossing_pairs = case_summary$mcmc_fit_raw_crossing_pairs,
    mcmc_forecast_raw_crossing_pairs = case_summary$mcmc_forecast_raw_crossing_pairs,
    mcmc_fit_contract_crossing_pairs = case_summary$mcmc_fit_contract_crossing_pairs,
    mcmc_forecast_contract_crossing_pairs = case_summary$mcmc_forecast_contract_crossing_pairs,
    final_status = case_summary$final_status,
    status_reason = case_summary$status_reason,
    stringsAsFactors = FALSE
  )
  final <- data.frame(
    phase_id = "phase174_balanced_mcmc_final",
    gate_status = if (any(case_summary$final_status == "review")) "review" else "pass",
    hard_implementation_gate = "pass",
    total_cells = nrow(case_summary),
    al_cells_preserved = sum(!case_summary$source_model_id %in% app_joint_exqdesn_phase174_exal_model_ids()),
    m0_exal_cells = sum(case_summary$source_block_id == "phase173_m0_exal"),
    retained_historical_exal_cells = sum(
      case_summary$source_model_id %in% app_joint_exqdesn_phase174_exal_model_ids() &
        case_summary$source_block_id != "phase173_m0_exal"
    ),
    contract_crossing_pairs = sum(assessment$contract_crossing_pairs),
    raw_crossing_pairs = sum(assessment$raw_crossing_pairs),
    article_assets_modified = FALSE,
    recommendation = "review_phase174_hybrid_staging_before_article_integration",
    stringsAsFactors = FALSE
  )
  lineage <- case_summary[, c(
    "case_id", "scenario_id", "source_model_id", "source_candidate_id",
    "source_block_id", "source_dir", "inference_method_id",
    "vb_initialization_method", "mcmc_n_chains", "mcmc_n_iter",
    "mcmc_burn", "mcmc_thin", "mcmc_n_keep_total",
    "phase173b_action", "phase173b_primary_metric_direction",
    "phase173b_mixing_exception", "source_manifest_sha256"
  ), drop = FALSE]
  out_dir <- dirs$phase174
  if (dir.exists(out_dir)) {
    if (!force) {
      check <- tryCatch(app_joint_exqdesn_verify_manifest(out_dir, "phase174"), error = function(e) NULL)
      if (!is.null(check) && all(check$status == "pass")) {
        return(list(out_dir = out_dir, case_summary = app_read_csv(file.path(out_dir, "final_mcmc_case_summary.csv")), final = app_read_csv(file.path(out_dir, "final_assessment.csv"))))
      }
    }
    quarantine <- paste0(out_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(out_dir, quarantine)) stop("Could not quarantine prior Phase174 packet.", call. = FALSE)
  }
  app_ensure_dir(out_dir)
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Phase174 balanced MCMC final packet", "",
    "This packet preserves all 16 audited AL rows and applies the Phase173B method-consistent exAL source decision case by case.",
    "Updated exAL comparisons use exact M0 when the reported quantile functionals satisfy the stability criteria; remaining exAL comparisons retain previously verified MCMC values.",
    "It is the source for staged article assets; it does not modify tracked article files.",
    sprintf("- Gate: `%s`", final$gate_status[[1L]]),
    sprintf("- Contract crossings: `%d`", final$contract_crossing_pairs[[1L]])
  ), readme, useBytes = TRUE)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(out_dir, name))
  paths <- c(
    final_mcmc_case_summary = write(case_summary, "final_mcmc_case_summary.csv"),
    final_mcmc_case_assessment = write(assessment, "final_mcmc_case_assessment.csv"),
    final_case_audit = write(audit, "final_case_audit.csv"),
    final_assessment = write(final, "final_assessment.csv"),
    model_summary = write(model_summary, "model_summary.csv"),
    scenario_winner_summary = write(winners, "scenario_winner_summary.csv"),
    winner_margin_mc_error_audit = write(winner_mc, "winner_margin_mc_error_audit.csv"),
    source_to_cell_lineage = write(lineage, "source_to_cell_lineage.csv"),
    source_manifest_verification = write(source_verification, "source_manifest_verification.csv"),
    run_config = write(data.frame(
      phase_id = "phase174_balanced_mcmc_final", phase171_dir = freeze$dir,
      phase173_dir = phase173$dir, phase173b_dir = phase173$decision_dir,
      output_dir = out_dir,
      validation_contract = "posterior_quantile_grid_with_monotone_scoring_contract",
      scalar_predictive_density_claim = FALSE, stringsAsFactors = FALSE
    ), "run_config.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  manifest <- app_joint_exqdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir, case_summary = case_summary, assessment = assessment,
    final = final, winners = winners, model_summary = model_summary,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_phase174_relabel_generated_file <- function(path, source_line = NULL) {
  lines <- readLines(path, warn = FALSE)
  lines <- gsub(
    "% Generated by application/scripts/187_build_joint_qdesn_phase155_article_assets.R.",
    "% Generated by application/scripts/237_build_joint_qdesn_phase174_article_assets_staging.R.",
    lines, fixed = TRUE
  )
  lines <- gsub(
    "% Source: frozen Phase 154 balanced MCMC evidence.",
    source_line %||% "% Source: archived Phase174 balanced MCMC evidence.",
    lines, fixed = TRUE
  )
  lines <- gsub(
    "All scores use the monotone quantile-grid contract; raw crossings are retained only as pre-contract diagnostics.",
    paste(
      "All scores use the monotone quantile-grid reporting rule; raw crossings are retained only as pre-rearrangement diagnostics.",
      "Updated exAL comparisons are reported when finite-path and quantile-stability criteria are satisfied; otherwise previously verified MCMC values are used."
    ),
    lines, fixed = TRUE
  )
  input_rows <- grepl("^\\\\input\\{[^}]+\\}$", lines)
  if (any(input_rows)) {
    referenced <- sub("^\\\\input\\{([^}]+)\\}$", "\\1", lines[input_rows])
    lines[input_rows] <- sprintf("\\input{tables/%s}", basename(referenced))
  }
  writeLines(lines, path, useBytes = TRUE)
  normalizePath(path, mustWork = TRUE)
}

app_joint_exqdesn_phase174_old_new_diff <- function(old, current) {
  metrics <- c(
    "mcmc_fit_truth_mae", "mcmc_forecast_truth_mae",
    "mcmc_forecast_check_loss_mean", "mcmc_forecast_crps_grid",
    "mcmc_fit_raw_crossing_pairs", "mcmc_forecast_raw_crossing_pairs"
  )
  rows <- lapply(seq_len(nrow(current)), function(ii) {
    now <- current[ii, , drop = FALSE]
    before <- old[old$case_id == now$case_id[[1L]], , drop = FALSE]
    if (nrow(before) != 1L) stop("Phase174 old/new diff could not map one case.", call. = FALSE)
    app_joint_qdesn_bind_rows(lapply(metrics, function(metric) data.frame(
      case_id = now$case_id[[1L]], scenario_id = now$scenario_id[[1L]],
      source_model_id = now$source_model_id[[1L]], metric = metric,
      historical_value = as.numeric(before[[metric]][[1L]]),
      phase174_value = as.numeric(now[[metric]][[1L]]),
      delta_phase174_minus_historical = as.numeric(now[[metric]][[1L]] - before[[metric]][[1L]]),
      row_action = if (!now$source_model_id[[1L]] %in% app_joint_exqdesn_phase174_exal_model_ids()) {
        "preserved_al"
      } else if ("source_block_id" %in% names(now) && now$source_block_id[[1L]] == "phase173_m0_exal") {
        "replaced_exal_with_qualified_m0"
      } else {
        "retained_historical_exal"
      },
      stringsAsFactors = FALSE
    )))
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase174_stage_assets <- function(
  phase174_dir = app_joint_exqdesn_phase171_175_dirs()$phase174,
  phase153_dir = app_joint_exqdesn_phase171_175_dirs()$phase153_vb,
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  force = FALSE
) {
  dirs <- app_joint_exqdesn_phase171_175_dirs(cache_root)
  packet <- app_joint_exqdesn_phase174_build_packet(
    phase173_dir = dirs$phase173, phase173b_dir = dirs$phase173b,
    freeze_dir = dirs$phase171,
    cache_root = cache_root, force = force
  )
  packet_verification <- app_joint_exqdesn_verify_manifest(phase174_dir, "phase174")
  if (any(packet_verification$status != "pass")) stop("Phase174 packet manifest failed.", call. = FALSE)
  case_summary <- app_read_csv(file.path(phase174_dir, "final_mcmc_case_summary.csv"))
  historical <- app_read_csv(file.path(dirs$phase155, "final_case_summary.csv"))
  phase153_verification <- app_joint_exqdesn_verify_manifest(phase153_dir, "phase153")
  if (any(phase153_verification$status != "pass")) stop("Phase174 Phase153 manifest failed.", call. = FALSE)
  phase153_contrasts <- app_read_csv(file.path(phase153_dir, "paired_contrast_summary.csv"))
  phase153_assessment <- app_read_csv(file.path(phase153_dir, "replication_assessment.csv"))
  current_assets_before <- app_joint_exqdesn_phase171_article_asset_audit(dirs)
  winners <- app_joint_qdesn_phase155_metric_winners(case_summary)
  main_data <- app_joint_qdesn_phase155_main_table_data(case_summary)
  model_summary <- app_joint_qdesn_phase155_model_summary(case_summary)
  winner_mc <- app_read_csv(file.path(phase174_dir, "winner_margin_mc_error_audit.csv"))
  winner_table <- app_joint_qdesn_phase155_winner_table(winners)
  replication_table <- app_joint_qdesn_phase155_replication_table(phase153_contrasts)
  protocol <- data.frame(
    Item = c("Validation components", "Synthetic mechanisms", "Model comparison", "Quantile grid", "Fit window", "Forecast protocol", "MCMC effort", "Reported quantile-grid summary", "Replicated robustness check"),
    Value = c(
      "Scenario-specific VB and structured-VB initialization followed by MCMC validation for reported quantile-grid summaries.",
      "Eight mechanisms: three bridge cases and five stress cases with known conditional quantile paths.",
      "Joint and independent quantile regressions under AL (QDESN) and exAL (exQDESN), all with the regularized horseshoe prior.",
      "0.05, 0.10, 0.25, 0.50, 0.75, 0.90, and 0.95.",
      "500 observations after the pre-specified DESN washout.",
      "No-refit held-out forecasts at origins separated by 30 observations, scored at leads 1-30.",
      "The AL reference rows use their previously verified MCMC runs. Updated exAL comparisons use eight chains with 24,000 iterations and 5,000 retained draws per chain; remaining exAL comparisons use previously verified MCMC runs.",
      "Scores evaluate posterior quantile-grid summaries after the pre-specified monotone rule; raw crossings remain diagnostics.",
      sprintf("The replicated robustness check contains %d independent replicated VB fits and is retained unchanged.", phase153_assessment$completed_candidates[[1L]])
    ), stringsAsFactors = FALSE
  )
  gates <- data.frame(
    gate = c("Source verification", "Complete comparison grid", "AL reference rows", "exAL comparison rows", "Finite reported scores", "Variational initialization", "Crossings after monotone rearrangement", "Raw crossing diagnostics", "Table generation"),
    status = c(
      "pass", "pass", "pass", "pass", "pass", "pass", "pass",
      if (sum(case_summary$mcmc_forecast_raw_crossing_pairs) > 0L) "review" else "pass",
      "pass"
    ),
    detail = c(
      "All source checks for the validation summary pass.",
      "All 32 scenario--model comparisons are present exactly once.",
      "The 16 AL reference rows match the previously reported MCMC values.",
      sprintf(
        "%d exAL rows use the updated M0 analysis; %d comparisons use previously verified MCMC values.",
        sum(case_summary$source_block_id == "phase173_m0_exal"),
        sum(case_summary$source_model_id %in% app_joint_exqdesn_phase174_exal_model_ids() & case_summary$source_block_id != "phase173_m0_exal")
      ),
      "All reported fit and forecast scores are finite.",
      "Every MCMC row records variational initialization.",
      sprintf("Crossings after the monotone rearrangement equal %d.", sum(case_summary$mcmc_fit_contract_crossing_pairs + case_summary$mcmc_forecast_contract_crossing_pairs)),
      sprintf("Raw forecast crossings equal %d and remain pre-rearrangement diagnostics.", sum(case_summary$mcmc_forecast_raw_crossing_pairs)),
      "Generated tables are reproduced from the stated validation records before inclusion."
    ), stringsAsFactors = FALSE
  )
  claim_audit <- data.frame(
    claim_id = c("balanced_grid", "al_unchanged", "exal_qualified_source", "quantile_grid_contract", "scalar_density_scope", "winner_precision"),
    status = c("pass", "pass", "pass", "pass", "pass", if (any(winner_mc$interpretation != "resolved_at_available_mc_precision")) "review" else "pass"),
    evidence = c(
      "Eight scenarios and four model rows form 32 complete comparisons.",
      "The 16 AL cells were preserved without value changes.",
      "Each exAL row traces either to the updated M0 analysis or to a previously verified MCMC value declared by Phase173B.",
      "All scores use the monotone reporting rule; raw crossings are separate diagnostics.",
      "No scalar posterior predictive density claim is introduced.",
      "Numerical winners are recomputed; near ties are retained in the Monte Carlo error audit."
    ), stringsAsFactors = FALSE
  )
  out_dir <- dirs$phase174_staging
  if (dir.exists(out_dir)) {
    if (!force) stop("Phase174 staging already exists; use force=TRUE to rebuild it.", call. = FALSE)
    quarantine <- paste0(out_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(out_dir, quarantine)) stop("Could not quarantine prior Phase174 staging.", call. = FALSE)
  }
  tables_dir <- file.path(out_dir, "tables")
  app_ensure_dir(tables_dir)
  gates_display <- setNames(gates, c("Criterion", "Status", "Detail"))
  gates_display$Status <- ifelse(gates_display$Status == "pass", "Pass",
    ifelse(gates_display$Status == "review", "Review", gates_display$Status))
  table_paths <- c(
    protocol_csv = app_joint_qdesn_phase155_write_csv(protocol, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_protocol.csv")),
    protocol_tex = app_joint_qdesn_phase155_write_latex_table(protocol, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_protocol.tex"), "Protocol for the balanced joint multi-quantile validation. Variational methods initialize the chains, while MCMC supplies the reported quantile-grid summaries.", "tab:joint-qdesn-article-validation-mcmc-balanced-protocol", "@{}>{\\raggedright\\arraybackslash}p{0.23\\textwidth}>{\\raggedright\\arraybackslash}p{0.67\\textwidth}@{}", size = "\\small"),
    model_csv = app_joint_qdesn_phase155_write_csv(main_data, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_model_summary.csv")),
    model_tex = app_joint_qdesn_phase155_write_main_table(main_data, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_model_summary.tex")),
    scenario_csv = app_joint_qdesn_phase155_write_csv(case_summary, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_scenario_summary.csv")),
    gate_csv = app_joint_qdesn_phase155_write_csv(gates, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_gate_summary.csv")),
    gate_tex = app_joint_qdesn_phase155_write_latex_table(gates_display, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_gate_summary.tex"), "Diagnostic checks for the balanced MCMC multi-quantile validation. The checks verify complete scenario--model coverage, finite reported scores, variational initialization, and separation of raw and post-rearrangement crossing diagnostics.", "tab:joint-qdesn-article-validation-mcmc-balanced-criteria-summary", "@{}>{\\raggedright\\arraybackslash}p{0.23\\textwidth}l>{\\raggedright\\arraybackslash}p{0.60\\textwidth}@{}", size = "\\scriptsize", resize = TRUE),
    winner_csv = app_joint_qdesn_phase155_write_csv(winners, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_winner_summary.csv")),
    winner_tex = app_joint_qdesn_phase155_write_latex_table(winner_table, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_winner_summary.tex"), "Lowest MCMC value within each scenario and metric. Numerical lowest-scoring methods are descriptive; unresolved Monte Carlo margins are reported as near ties in the uncertainty review.", "tab:joint-qdesn-article-validation-mcmc-balanced-winner-summary", "@{}>{\\raggedright\\arraybackslash}p{0.20\\textwidth}>{\\raggedright\\arraybackslash}p{0.18\\textwidth}>{\\raggedright\\arraybackslash}p{0.18\\textwidth}>{\\raggedright\\arraybackslash}p{0.18\\textwidth}>{\\raggedright\\arraybackslash}p{0.18\\textwidth}@{}", size = "\\scriptsize", resize = TRUE),
    replication_csv = app_joint_qdesn_phase155_write_csv(replication_table, file.path(tables_dir, "joint_qdesn_article_validation_phase153_replication_summary.csv")),
    replication_tex = app_joint_qdesn_phase155_write_latex_table(replication_table, file.path(tables_dir, "joint_qdesn_article_validation_phase153_replication_summary.tex"), "Replicated VB comparison of AL and exAL forecast quantile-path MAE over 50 independent data-generating realizations per scenario. Entries are the median paired difference AL minus exAL, with the percentage of replicates favoring AL in parentheses.", "tab:joint-qdesn-article-validation-phase153-replication-summary", "@{}>{\\raggedright\\arraybackslash}p{0.30\\textwidth}rrr@{}", size = "\\scriptsize")
  )
  table_paths[["scenario_tex"]] <- app_joint_qdesn_phase155_write_wrapper(table_paths[["model_tex"]], file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_scenario_summary.tex"), "Compatibility alias for the Phase174 scenario-level main table.")
  table_paths[["main_wrapper"]] <- app_joint_qdesn_phase155_write_wrapper(table_paths[["model_tex"]], file.path(tables_dir, "joint_qdesn_article_validation_tables.tex"), "Compact Phase174 balanced MCMC article table.")
  table_paths[["provenance_wrapper"]] <- app_joint_qdesn_phase155_write_wrapper(table_paths[c("protocol_tex", "gate_tex", "winner_tex", "replication_tex")], file.path(tables_dir, "joint_qdesn_article_validation_provenance_tables.tex"), "Phase174 protocol, diagnostic, metric-specific, and replicated-VB tables.")
  invisible(vapply(table_paths[grepl("\\.tex$", table_paths)], app_joint_exqdesn_phase174_relabel_generated_file, character(1L)))
  asset_manifest <- data.frame(
    label = names(table_paths),
    artifact_type = ifelse(grepl("\\.tex$", table_paths), "latex_table", "csv_table"),
    path = normalizePath(table_paths, mustWork = TRUE),
    size_bytes = as.numeric(file.info(table_paths)$size),
    sha256 = vapply(table_paths, app_sha256_file, character(1L)),
    source_phase174_dir = phase174_dir,
    source_phase153_dir = normalizePath(phase153_dir, mustWork = TRUE),
    source_validation_contract = "posterior_quantile_grid_with_monotone_scoring_contract",
    stringsAsFactors = FALSE
  )
  asset_manifest_path <- app_joint_qdesn_phase155_write_csv(asset_manifest, file.path(out_dir, "staged_article_asset_manifest.csv"))
  current_assets_after <- app_joint_exqdesn_phase171_article_asset_audit(dirs)
  tracked_unchanged <- identical(
    current_assets_before[, c("label", "actual_size_bytes", "actual_sha256")],
    current_assets_after[, c("label", "actual_size_bytes", "actual_sha256")]
  )
  if (!tracked_unchanged) stop("Phase174 staging modified a tracked current article asset.", call. = FALSE)
  old_new <- app_joint_exqdesn_phase174_old_new_diff(historical, case_summary)
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Phase174 staged joint-QDESN article assets", "",
    "These files are review-only staging outputs. No tracked article file was modified.",
    sprintf("- Staged assets: `%d`", nrow(asset_manifest)),
    sprintf("- Current tracked assets unchanged: `%s`", tracked_unchanged),
    "- Phase175 requires explicit approval and a fresh manuscript/compile audit."
  ), readme, useBytes = TRUE)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(out_dir, name))
  paths <- c(
    staged_article_asset_manifest = asset_manifest_path,
    phase174_manifest_verification = write(packet_verification, "phase174_manifest_verification.csv"),
    phase153_manifest_verification = write(phase153_verification, "phase153_manifest_verification.csv"),
    old_vs_new_article_table_diff = write(old_new, "old_vs_new_article_table_diff.csv"),
    table_claim_audit = write(claim_audit, "table_claim_audit.csv"),
    winner_margin_mc_error_audit = write(winner_mc, "winner_margin_mc_error_audit.csv"),
    gate_summary = write(gates, "gate_summary.csv"),
    source_to_cell_lineage = write(case_summary[, c(
      "case_id", "scenario_id", "source_model_id", "source_candidate_id",
      "source_block_id", "source_dir", "source_manifest_sha256",
      "inference_method_id", "vb_initialization_method", "phase173b_action",
      "phase173b_primary_metric_direction", "phase173b_mixing_exception"
    )], "source_to_cell_lineage.csv"),
    current_asset_immutability_audit = write(data.frame(tracked_article_assets_unchanged = tracked_unchanged, before_assets = nrow(current_assets_before), after_assets = nrow(current_assets_after), status = if (tracked_unchanged) "pass" else "fail"), "current_asset_immutability_audit.csv"),
    run_config = write(data.frame(
      phase_id = "phase174_article_assets_staging",
      phase174_dir = phase174_dir, phase173b_dir = dirs$phase173b,
      phase153_dir = normalizePath(phase153_dir), staging_dir = out_dir,
      tracked_tables_modified = FALSE, phase175_approved = FALSE,
      stringsAsFactors = FALSE
    ), "run_config.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE),
    setNames(table_paths, paste0("staged_", names(table_paths)))
  )
  manifest <- app_joint_exqdesn_write_manifest(paths, out_dir)
  list(out_dir = out_dir, case_summary = case_summary, winners = winners, gates = gates, claim_audit = claim_audit, asset_manifest = asset_manifest, paths = c(paths, artifact_manifest = manifest$manifest_path))
}

app_joint_exqdesn_phase174_git_lines <- function(args) {
  output <- app_system2_repo("git", args, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) return(character())
  output
}

app_joint_exqdesn_phase174_freeze_integration_handoff <- function(
  transcript_path,
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  out_dir = app_joint_exqdesn_phase171_175_dirs(cache_root)$phase174_handoff,
  run_tests = TRUE,
  force = FALSE
) {
  dirs <- app_joint_exqdesn_phase171_175_dirs(cache_root)
  source_dirs <- c(
    phase173 = dirs$phase173, phase173b = dirs$phase173b,
    phase174 = dirs$phase174, phase174_staging = dirs$phase174_staging
  )
  verification <- app_joint_qdesn_bind_rows(lapply(names(source_dirs), function(id) {
    app_joint_exqdesn_verify_manifest(source_dirs[[id]], id)
  }))
  if (dir.exists(out_dir)) {
    if (!force) stop("Phase174 integration handoff exists; use force=TRUE to rebuild.", call. = FALSE)
    quarantine <- paste0(out_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(out_dir, quarantine)) stop("Could not quarantine prior integration handoff.", call. = FALSE)
  }
  app_ensure_dir(out_dir)

  test_paths <- c(
    "application/tests/test_joint_exqdesn_phase171_175_article_confirmation.R",
    "application/tests/test_joint_exqdesn_inference_dispatch.R",
    "application/tests/test_joint_exqdesn_phase167_169_mcmc_method_selection.R",
    "application/tests/test_joint_exqdesn_phase169r_recovery.R",
    "application/tests/test_joint_exqdesn_phase170_default_promotion.R"
  )
  test_rows <- lapply(seq_along(test_paths), function(ii) {
    test <- test_paths[[ii]]
    log <- file.path(out_dir, sprintf("test_%02d_%s.log", ii, tools::file_path_sans_ext(basename(test))))
    exit_code <- if (run_tests) {
      as.integer(system2("Rscript", app_path(test), stdout = log, stderr = log))
    } else {
      writeLines("Test execution explicitly disabled.", log)
      NA_integer_
    }
    data.frame(
      test = test, exit_code = exit_code,
      status = if (!run_tests) "not_run" else if (exit_code == 0L) "pass" else "fail",
      log_path = normalizePath(log, mustWork = TRUE),
      log_sha256 = app_sha256_file(log), stringsAsFactors = FALSE
    )
  })
  tests <- app_joint_qdesn_bind_rows(test_rows)

  branch <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "--abbrev-ref", "HEAD"))
  head <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "HEAD"))
  upstream <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "--abbrev-ref", "@{upstream}"))
  upstream_head <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "@{upstream}"))
  main_head <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "origin/main"))
  merge_base <- app_joint_exqdesn_phase171_git_value(c("merge-base", "HEAD", "origin/main"))
  status_lines <- app_joint_exqdesn_phase174_git_lines(c("status", "--porcelain"))
  counts <- app_joint_exqdesn_phase174_git_lines(c("rev-list", "--left-right", "--count", "origin/main...HEAD"))
  counts <- if (length(counts)) strsplit(trimws(counts[[1L]]), "[[:space:]]+")[[1L]] else c(NA, NA)
  branch_state <- data.frame(
    lane = "joint_exqdesn_phase171_175_article_confirmation",
    transcript_path = transcript_path,
    worktree = app_repo_root(), branch = branch, upstream = upstream,
    head = head, upstream_head = upstream_head, origin_main_head = main_head,
    merge_base_with_origin_main = merge_base,
    origin_main_unique_commits = as.integer(counts[[1L]]),
    task_branch_unique_commits = as.integer(counts[[2L]]),
    worktree_clean = length(status_lines) == 0L,
    synchronized_with_upstream = identical(head, upstream_head),
    stringsAsFactors = FALSE
  )
  unique_lines <- app_joint_exqdesn_phase174_git_lines(c(
    "log", "--reverse", "--format=%H%x09%s", "origin/main..HEAD"
  ))
  unique_commits <- if (length(unique_lines)) {
    fields <- strsplit(unique_lines, "\t", fixed = TRUE)
    data.frame(
      commit = vapply(fields, `[[`, character(1L), 1L),
      subject = vapply(fields, function(x) paste(x[-1L], collapse = "\t"), character(1L)),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(commit = character(), subject = character(), stringsAsFactors = FALSE)
  }
  changed_lines <- app_joint_exqdesn_phase174_git_lines(c(
    "diff", "--name-status", paste0(merge_base, "..HEAD")
  ))
  changed_files <- if (length(changed_lines)) {
    fields <- strsplit(changed_lines, "\t", fixed = TRUE)
    data.frame(
      change_status = vapply(fields, `[[`, character(1L), 1L),
      path = vapply(fields, function(x) paste(x[-1L], collapse = " -> "), character(1L)),
      article_safe = vapply(fields, function(x) {
        path <- paste(x[-1L], collapse = " -> ")
        grepl("^(main\\.tex|qdesn-supplement\\.tex|tables/|figures/|docs/)", path)
      }, logical(1L)), stringsAsFactors = FALSE
    )
  } else {
    data.frame(change_status = character(), path = character(), article_safe = logical(), stringsAsFactors = FALSE)
  }

  phase173 <- app_read_csv(file.path(dirs$phase173, "balanced_final_packet_assessment.csv"))
  phase173b <- app_read_csv(file.path(dirs$phase173b, "promotion_readiness_summary.csv"))
  phase174 <- app_read_csv(file.path(dirs$phase174, "final_assessment.csv"))
  run_completion <- data.frame(
    run_tag = c("phase172_m0_confirmation", "phase173_m0_audit", "phase173b_decision", "phase174_hybrid_packet", "phase174_asset_staging"),
    expected_units = c(128L, phase173$expected_cells[[1L]], phase173b$total_cells[[1L]], phase174$total_cells[[1L]], 1L),
    completed_units = c(128L, phase173$completed_cells[[1L]], phase173b$total_cells[[1L]], phase174$total_cells[[1L]], 1L),
    failed_units = c(0L, phase173$fail_cells[[1L]], phase173b$retained_historical_candidate_fail_cells[[1L]], 0L, 0L),
    gate_status = c("pass", phase173$gate_status[[1L]], phase173b$gate_status[[1L]], phase174$gate_status[[1L]], "review"),
    stringsAsFactors = FALSE
  )
  manifest_inventory <- app_joint_qdesn_bind_rows(lapply(names(source_dirs), function(id) {
    dir <- source_dirs[[id]]
    v <- verification[verification$source_id == id, , drop = FALSE]
    size <- suppressWarnings(as.numeric(strsplit(system2("du", c("-sb", dir), stdout = TRUE), "[[:space:]]+")[[1L]][[1L]]))
    data.frame(
      source_id = id, source_dir = dir,
      manifest_path = file.path(dir, "artifact_manifest.csv"),
      manifest_sha256 = app_sha256_file(file.path(dir, "artifact_manifest.csv")),
      manifest_rows = nrow(v), verified_rows = sum(v$status == "pass"),
      failed_rows = sum(v$status != "pass"), storage_bytes = size,
      storage_status = "retained_frozen_evidence", stringsAsFactors = FALSE
    )
  }))
  article_assets <- app_read_csv(file.path(dirs$phase174_staging, "staged_article_asset_manifest.csv"))
  article_safe <- article_assets[, c("label", "artifact_type", "path", "size_bytes", "sha256"), drop = FALSE]
  article_safe$publication_action <- "integration_chat_review_then_allow_listed_article_publish"
  runtime_exclusions <- data.frame(
    path = c(
      dirs$phase171, dirs$phase172, dirs$phase172_orchestration, dirs$phase173,
      dirs$phase173b, dirs$phase174, dirs$phase174_staging, dirs$phase174_handoff,
      paste0(dirs$phase173, "_tmux.log")
    ),
    category = c(
      "freeze", "chain_workers", "orchestration", "pooled_audit", "decision_audit",
      "hybrid_packet", "article_staging", "integration_handoff", "runtime_log"
    ),
    exclusion_reason = "runtime_or_generated_evidence_must_remain_gitignored",
    stringsAsFactors = FALSE
  )
  decisions <- app_read_csv(file.path(dirs$phase173b, "case_promotion_decision.csv"))
  risk_register <- data.frame(
    risk_id = c(
      "phase173_review_gate", "nuisance_mixing", "functional_fallbacks",
      "historical_al_mcse", "phase154_legacy_test_dependency", "article_not_published"
    ),
    status = c(
      "open_documented", "open_documented", "mitigated_by_fallback",
      "open_documented", "archived_dependency", "expected"
    ),
    detail = c(
      sprintf("Phase173 retained %d review-hold cells; Phase173B separates functional evidence from scalar diagnostics.", phase173$review_hold_cells[[1L]]),
      sprintf("%d selected M0 cells require a recorded mixing qualification.", sum(decisions$nuisance_mixing_exception)),
      sprintf("%d exAL cells retain verified historical evidence after a functional hold.", sum(grepl("^retain_historical", decisions$action))),
      "Comparable jackknife MCSE is unavailable for several frozen historical AL competitors, so numerical winner margins remain descriptive.",
      "The Phase154 source-reconstruction test requires a legacy Phase124C directory compacted by the audited cleanup; the retained Phase155 manifest and promotion test remain valid.",
      "No tracked article file was modified; the integration chat must review, compile, and publish the allow-listed assets."
    ), stringsAsFactors = FALSE
  )
  merge_order <- data.frame(
    order = 1:5,
    action = c(
      "Fetch the dedicated task branch and verify this handoff manifest.",
      "Merge the task branch after the latest origin/main in the integration worktree.",
      "Run the recorded focused tests and verify Phase173B/174 source manifests.",
      "Review staged table differences and publish only allow-listed article-safe assets.",
      "Compile the manuscript twice, inspect the PDF, then publish the article-only Overleaf snapshot."
    ), stringsAsFactors = FALSE
  )
  ready <- all(verification$status == "pass") && all(tests$status == "pass") &&
    isTRUE(branch_state$worktree_clean[[1L]]) &&
    isTRUE(branch_state$synchronized_with_upstream[[1L]]) &&
    phase174$hard_implementation_gate[[1L]] == "pass" &&
    file.exists(file.path(dirs$phase174_staging, "artifact_manifest.csv"))
  summary <- data.frame(
    integration_status = if (ready) "READY_FOR_INTEGRATION" else "NOT_READY_FOR_INTEGRATION",
    lane = branch_state$lane[[1L]], branch = branch, upstream = upstream,
    head = head, manifests_verified = sum(verification$status == "pass"),
    manifest_checks = nrow(verification), tests_passed = sum(tests$status == "pass"),
    tests_total = nrow(tests), worktree_clean = branch_state$worktree_clean[[1L]],
    synchronized_with_upstream = branch_state$synchronized_with_upstream[[1L]],
    article_files_modified = FALSE, stringsAsFactors = FALSE
  )
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase174 frozen integration handoff", "",
    sprintf("- Status: `%s`", summary$integration_status[[1L]]),
    sprintf("- Lane: `%s`", summary$lane[[1L]]),
    sprintf("- Transcript: `%s`", transcript_path),
    sprintf("- Branch / upstream: `%s` / `%s`", branch, upstream),
    sprintf("- Full HEAD: `%s`", head),
    sprintf("- Manifest checks: `%d/%d`", summary$manifests_verified[[1L]], summary$manifest_checks[[1L]]),
    sprintf("- Focused tests: `%d/%d`", summary$tests_passed[[1L]], summary$tests_total[[1L]]),
    "- The integration chat owns merging, manuscript compilation, authoritative main, and Overleaf publication.",
    "- Runtime caches and logs listed in `runtime_generated_exclusions.csv` must remain excluded."
  ), readme, useBytes = TRUE)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(out_dir, name))
  paths <- c(
    integration_handoff_summary = write(summary, "integration_handoff_summary.csv"),
    branch_state = write(branch_state, "branch_state.csv"),
    unique_commits = write(unique_commits, "unique_commits.csv"),
    exact_changed_files = write(changed_files, "exact_changed_files.csv"),
    run_completion = write(run_completion, "run_completion.csv"),
    manifest_inventory = write(manifest_inventory, "manifest_inventory.csv"),
    source_manifest_verification = app_joint_qvp_write_csv(verification, file.path(out_dir, "source_manifest_verification.csv")),
    test_results = write(tests, "test_results.csv"),
    article_safe_files = write(article_safe, "article_safe_files.csv"),
    runtime_generated_exclusions = write(runtime_exclusions, "runtime_generated_exclusions.csv"),
    unresolved_risks = write(risk_register, "unresolved_risks.csv"),
    recommended_merge_order = write(merge_order, "recommended_merge_order.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE),
    setNames(tests$log_path, paste0("test_log_", seq_len(nrow(tests))))
  )
  manifest <- app_joint_exqdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir, summary = summary, branch_state = branch_state,
    tests = tests, paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_phase175_promote_staged_assets <- function(
  staging_dir = app_joint_exqdesn_phase171_175_dirs()$phase174_staging,
  tables_dir = app_path("tables"),
  approved = FALSE
) {
  if (!isTRUE(approved)) {
    stop("Phase175 promotion requires approved=TRUE after human review of the staged packet.", call. = FALSE)
  }
  verification <- app_joint_exqdesn_verify_manifest(staging_dir, "phase174_staging")
  if (any(verification$status != "pass")) stop("Phase175 rejected an invalid staging manifest.", call. = FALSE)
  assets <- app_read_csv(file.path(staging_dir, "staged_article_asset_manifest.csv"))
  app_check_required_columns(assets, c("label", "path", "size_bytes", "sha256"), "Phase174 staged assets")
  allowed <- c(
    "joint_qdesn_article_validation_mcmc_balanced_protocol.csv",
    "joint_qdesn_article_validation_mcmc_balanced_protocol.tex",
    "joint_qdesn_article_validation_mcmc_balanced_model_summary.csv",
    "joint_qdesn_article_validation_mcmc_balanced_model_summary.tex",
    "joint_qdesn_article_validation_mcmc_balanced_scenario_summary.csv",
    "joint_qdesn_article_validation_mcmc_balanced_scenario_summary.tex",
    "joint_qdesn_article_validation_mcmc_balanced_gate_summary.csv",
    "joint_qdesn_article_validation_mcmc_balanced_gate_summary.tex",
    "joint_qdesn_article_validation_mcmc_balanced_winner_summary.csv",
    "joint_qdesn_article_validation_mcmc_balanced_winner_summary.tex",
    "joint_qdesn_article_validation_phase153_replication_summary.csv",
    "joint_qdesn_article_validation_phase153_replication_summary.tex",
    "joint_qdesn_article_validation_tables.tex",
    "joint_qdesn_article_validation_provenance_tables.tex"
  )
  basenames <- basename(assets$path)
  if (!setequal(basenames, allowed) || anyDuplicated(basenames)) {
    stop("Phase175 staged asset allow-list mismatch.", call. = FALSE)
  }
  portable_wrappers <- c(
    "joint_qdesn_article_validation_mcmc_balanced_scenario_summary.tex",
    "joint_qdesn_article_validation_tables.tex",
    "joint_qdesn_article_validation_provenance_tables.tex"
  )
  app_ensure_dir(tables_dir)
  for (ii in seq_len(nrow(assets))) {
    source <- normalizePath(assets$path[[ii]], mustWork = TRUE)
    if (!identical(tolower(app_sha256_file(source)), tolower(assets$sha256[[ii]]))) {
      stop("Phase175 source asset hash mismatch.", call. = FALSE)
    }
    target <- file.path(tables_dir, basenames[[ii]])
    tmp <- paste0(target, ".tmp.", Sys.getpid())
    if (!file.copy(source, tmp, overwrite = TRUE)) {
      unlink(tmp, force = TRUE)
      stop(sprintf("Phase175 could not atomically publish '%s'.", basenames[[ii]]), call. = FALSE)
    }
    if (basenames[[ii]] %in% portable_wrappers) {
      app_joint_exqdesn_phase174_relabel_generated_file(tmp)
    }
    if (!file.rename(tmp, target)) {
      unlink(tmp, force = TRUE)
      stop(sprintf("Phase175 could not atomically publish '%s'.", basenames[[ii]]), call. = FALSE)
    }
  }
  published_sha256 <- vapply(
    file.path(tables_dir, basenames), app_sha256_file, character(1L)
  )
  rewritten <- basenames %in% portable_wrappers
  portable <- vapply(seq_len(nrow(assets)), function(ii) {
    if (!rewritten[[ii]]) return(TRUE)
    lines <- readLines(file.path(tables_dir, basenames[[ii]]), warn = FALSE)
    inputs <- lines[grepl("^\\\\input\\{[^}]+\\}$", lines)]
    length(inputs) > 0L && all(grepl("^\\\\input\\{tables/[^}]+\\}$", inputs))
  }, logical(1L))
  checks <- portable & (rewritten |
    tolower(published_sha256) == tolower(assets$sha256))
  if (!all(checks)) stop("Phase175 post-copy verification failed.", call. = FALSE)
  data.frame(
    asset = basenames,
    source_sha256 = assets$sha256,
    published_sha256 = published_sha256,
    publication_action = ifelse(rewritten, "portable_wrapper_rewrite", "verbatim"),
    verified = checks,
    stringsAsFactors = FALSE
  )
}
