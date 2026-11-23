# Full-development confirmation for the stronger-window challenger/parity packets.

app_joint_swcf_root <- function(root = app_joint_sw_default_root()) {
  file.path(root, "full_confirmation")
}

app_joint_swcf_worker_dir <- function(root, stage, id) {
  file.path(app_joint_swcf_root(root), paste0(stage, "_workers"),
    sprintf("worker_%04d", as.integer(id)))
}

app_joint_swcf_contract <- function() {
  data.frame(
    name = c("contract_version", "practical_noninferiority_margin",
      "chains_per_cell", "al_n_iter", "al_burn", "al_thin",
      "exal_n_iter", "exal_burn", "exal_thin", "mcmc_sentinel_al_n_iter",
      "mcmc_sentinel_al_burn", "mcmc_sentinel_exal_n_iter",
      "mcmc_sentinel_exal_burn", "mcmc_sentinel_thin",
      "canonical_forecast_policy", "sensitivity_forecast_policy",
      "independent_draw_coupling", "exal_mcmc_method"),
    value = c("joint_qdesn_stronger_window_confirmation_v1", "0.01", "3",
      "2000", "500", "2", "4000", "1000", "2", "400", "100",
      "800", "200", "2", "recursive_mean_state", "recursive_path",
      "matched_draw_index_with_frozen_permutations", "M0_v_collapsed_support_logit"),
    stringsAsFactors = FALSE
  )
}

app_joint_swcf_value <- function(contract, name, numeric = FALSE) {
  row <- contract[contract$name == name, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("Confirmation contract lacks '%s'.", name), call. = FALSE)
  if (numeric) as.numeric(row$value[[1L]]) else as.character(row$value[[1L]])
}

app_joint_swcf_prepare_sentinel <- function(root = app_joint_sw_default_root()) {
  root <- normalizePath(root, mustWork = TRUE)
  verified <- app_joint_shared_verify_manifest(root, file.path(root, "transfer_manifest.csv"))
  if (!all(verified$verified)) stop("Transfer manifest is not verified.", call. = FALSE)
  decision <- app_read_csv(file.path(root, "transfer_decision.csv"))
  if (decision$status[[1L]] !=
      "TRANSFER_COMPLETE_READY_FOR_FULL_DEVELOPMENT_IMPLEMENTATION_REVIEW") {
    stop("Transfer decision does not authorize confirmation preparation.", call. = FALSE)
  }
  out <- app_joint_swcf_root(root); app_ensure_dir(out)
  contract_path <- app_write_csv(app_joint_swcf_contract(),
    file.path(out, "confirmation_contract.csv"))
  plan <- app_read_csv(file.path(root, "transfer_worker_plan.csv"))
  block <- plan[plan$scenario_id == "persistent_heavy_tail" &
    plan$specification_role == "challenger" & plan$replicate_id == 1L, , drop = FALSE]
  models <- c("independent_qdesn_rhs", "joint_qdesn_rhs",
    "independent_exqdesn_rhs", "joint_exqdesn_rhs")
  rows <- lapply(models, function(model) {
    source <- if (model == "independent_qdesn_rhs") block[1L, , drop = FALSE] else
      block[block$model_id == model, , drop = FALSE][1L, , drop = FALSE]
    source$sentinel_model_id <- model
    source
  })
  sentinel <- app_bind_rows_fill(rows)
  sentinel$sentinel_worker_id <- seq_len(nrow(sentinel))
  sentinel$chain_seed <- 503611220L + sentinel$sentinel_worker_id * 1009L
  sentinel_path <- app_write_csv(sentinel, file.path(out, "mcmc_sentinel_plan.csv"))
  app_ensure_dir(file.path(out, "sentinel_workers"))
  gate <- data.frame(status = "NONPROTECTED_MCMC_SENTINEL_READY",
    workers = nrow(sentinel), protected_rows_available = 0L,
    article_fixtures_materialized = FALSE, downstream_launched = FALSE)
  gate_path <- app_write_csv(gate, file.path(out, "sentinel_readiness.csv"))
  app_joint_shared_write_manifest(out, c(contract = contract_path,
    plan = sentinel_path, transfer = file.path(root, "transfer_manifest.csv"),
    readiness = gate_path), filename = "sentinel_prepare_manifest.csv")
  gate
}

app_joint_swcf_load_transfer_packet <- function(root, row) {
  plan <- app_read_csv(file.path(root, "transfer_worker_plan.csv"))
  key <- plan$scenario_id == row$scenario_id &
    plan$candidate_id == row$candidate_id &
    abs(plan$rhs_tau0 - row$rhs_tau0) < 1e-14 &
    plan$replicate_id == row$replicate_id
  block <- plan[key, , drop = FALSE]
  ex <- block[block$model_id == "independent_exqdesn_rhs", , drop = FALSE]
  ex <- ex[order(ex$tau), , drop = FALSE]
  joint_al <- block[block$model_id == "joint_qdesn_rhs", , drop = FALSE]
  joint_ex <- block[block$model_id == "joint_exqdesn_rhs", , drop = FALSE]
  ex_fits <- lapply(ex$transfer_worker_id, function(id) readRDS(
    file.path(app_joint_swtx_worker_dir(root, id), "fit_initializer.rds")))
  list(
    independent_qdesn_rhs = app_joint_swtx_load_q1_fits(root, row),
    independent_exqdesn_rhs = list(
      fits = ex_fits,
      sigma_mean = vapply(ex_fits, function(x) x$sigma_mean[[1L]], numeric(1L)),
      gamma_mean = vapply(ex_fits, function(x) x$gamma_mean[[1L]], numeric(1L))),
    joint_qdesn_rhs = readRDS(file.path(app_joint_swtx_worker_dir(root,
      joint_al$transfer_worker_id[[1L]]), "fit_initializer.rds")),
    joint_exqdesn_rhs = readRDS(file.path(app_joint_swtx_worker_dir(root,
      joint_ex$transfer_worker_id[[1L]]), "fit_initializer.rds"))
  )
}

app_joint_swcf_complete_target <- function(model, design, normal, tau0) {
  metadata <- app_joint_swcf_model_metadata(model)
  controls <- app_joint_swq_controls(app_joint_sw_read_contract())
  joint <- identical(metadata$fit_structure, "joint")
  app_joint_posterior_contract(
    likelihood_family = metadata$likelihood_family,
    fit_structure = metadata$fit_structure,
    tau = design$tau,
    design_fingerprint = design$posterior_data_design_fingerprint,
    tau0 = as.numeric(tau0),
    zeta2 = normal$initializer$zeta2,
    slab_fixed = controls$rhs_slab_fixed,
    a_sigma = controls$a_sigma,
    b_sigma = controls$b_sigma,
    alpha_prior_mean = normal$initializer$alpha_mean,
    alpha_prior_sd = rep(normal$initializer$alpha_prior_sd, length(design$tau)),
    alpha_min_spacing = if (joint) controls$alpha_min_spacing else 0,
    sigma_bounds = c(0, Inf),
    kappa = 1,
    coefficient_hierarchy = if (joint) {
      "first_quantile_anchor_adjacent_differences"
    } else {
      "independent_quantile_specific_rhs"
    },
    ordered_intercepts = joint,
    gamma_prior_type = if (identical(metadata$likelihood_family, "exAL")) {
      "quantile_fixed_bounded_shape_support"
    } else {
      "none"
    },
    score_definition = "dgp_integrated_finite_grid_acrps",
    projection_rule = "weighted_isotonic_equal_weights",
    draw_coupling = "matched_draw_index_with_repeated_permutation_sensitivity",
    contract_version = "joint_qdesn_stronger_window_complete_target_v2"
  )
}

app_joint_swcf_sampler_control_contract <- function(model, n_iter = NULL,
    burn = NULL, thin = NULL) {
  metadata <- app_joint_swcf_model_metadata(model)
  precision <- app_joint_article_mcmc_precision_repair_controls()
  exal <- identical(metadata$likelihood_family, "exAL")
  frozen <- app_joint_swcf_contract()
  n_iter <- as.integer(n_iter %||% app_joint_swcf_value(frozen,
    if (exal) "exal_n_iter" else "al_n_iter", TRUE))
  burn <- as.integer(burn %||% app_joint_swcf_value(frozen,
    if (exal) "exal_burn" else "al_burn", TRUE))
  thin <- as.integer(thin %||% app_joint_swcf_value(frozen,
    if (exal) "exal_thin" else "al_thin", TRUE))
  if (any(!is.finite(c(n_iter, burn, thin))) || n_iter <= 0L || burn < 0L ||
      burn >= n_iter || thin <= 0L) {
    stop("Sampler-control iteration budget is invalid.", call. = FALSE)
  }
  fields <- data.frame(
    field = c(
      "contract_version", "likelihood_family", "fit_structure",
      "inference_method_id", "scale_update_id", "sigma_support",
      "n_iter", "burn", "thin",
      "max_dense_dim", "precision_repair", "precision_repair_start_rel",
      "precision_repair_max_rel", "precision_repair_growth",
      "gamma_slice_width", "gamma_slice_max_steps", "tau_seed_stride"
    ),
    value = c(
      "joint_qdesn_stronger_window_sampler_control_v1",
      metadata$likelihood_family,
      metadata$fit_structure,
      if (exal) "M0_v_collapsed_support_logit" else "AL_MCMC",
      if (exal) "exact_M0_v_collapsed_scale_shape" else
        "direct_inverse_gamma_unbounded_v1",
      "(0,Inf)",
      as.character(n_iter),
      as.character(burn),
      as.character(thin),
      "0",
      tolower(as.character(isTRUE(precision$precision_repair))),
      app_joint_posterior_format_numeric(precision$precision_repair_start_rel),
      app_joint_posterior_format_numeric(precision$precision_repair_max_rel),
      app_joint_posterior_format_numeric(precision$precision_repair_growth),
      if (exal) "1" else "NA",
      if (exal) "100" else "NA",
      if (identical(metadata$fit_structure, "independent")) "1009" else "NA"
    ),
    stringsAsFactors = FALSE
  )
  canonical <- paste(paste(fields$field, fields$value, sep = "="), collapse = "\n")
  list(fields = fields, hash = app_joint_qvp_sha256_text(canonical))
}

app_joint_swcf_chain_identity_audit <- function(summary, expected_chains = NULL) {
  required <- c(
    "model_cell_id", "model_id", "likelihood_family",
    "complete_posterior_target_sha256", "effective_sampler_control_sha256"
  )
  app_check_required_columns(summary, required, "corrected JOINT chain summary")
  hashes <- c("complete_posterior_target_sha256",
    "effective_sampler_control_sha256")
  for (field in hashes) {
    if (any(!grepl("^[0-9a-f]{64}$", as.character(summary[[field]])))) {
      stop(sprintf("%s must contain lowercase SHA-256 values.", field),
        call. = FALSE)
    }
  }
  groups <- split(seq_len(nrow(summary)), summary$model_cell_id)
  rows <- lapply(names(groups), function(cell_id) {
    idx <- groups[[cell_id]]
    invariant <- c("model_id", "likelihood_family", hashes)
    counts <- vapply(invariant, function(field) {
      length(unique(as.character(summary[[field]][idx])))
    }, integer(1L))
    if (any(counts != 1L)) {
      stop(sprintf(
        "Corrected chain artifacts for model cell '%s' have incompatible targets or kernels.",
        cell_id), call. = FALSE)
    }
    if (!is.null(expected_chains) && length(idx) != as.integer(expected_chains)) {
      stop(sprintf("Model cell '%s' has %d chains; expected %d.",
        cell_id, length(idx), as.integer(expected_chains)), call. = FALSE)
    }
    data.frame(
      model_cell_id = cell_id,
      model_id = summary$model_id[idx[[1L]]],
      likelihood_family = summary$likelihood_family[idx[[1L]]],
      n_chains = length(idx),
      complete_posterior_target_sha256 =
        summary$complete_posterior_target_sha256[idx[[1L]]],
      effective_sampler_control_sha256 =
        summary$effective_sampler_control_sha256[idx[[1L]]],
      verified = TRUE,
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_joint_swcf_mcmc_fit <- function(model, design, init, normal, tau0, seed,
    n_iter, burn, thin) {
  controls <- app_joint_swq_controls(app_joint_sw_read_contract())
  common <- list(
    y = design$y[design$train_local], Z = design$Z[design$train_local, , drop = FALSE],
    tau = design$tau, n_iter = as.integer(n_iter), burn = as.integer(burn),
    thin = as.integer(thin), seed = as.integer(seed), kappa = 1,
    tau0 = as.numeric(tau0), zeta2 = normal$initializer$zeta2,
    slab_fixed = controls$rhs_slab_fixed, a_sigma = controls$a_sigma,
    b_sigma = controls$b_sigma, alpha_prior_mean = normal$initializer$alpha_mean,
    alpha_prior_sd = rep(normal$initializer$alpha_prior_sd, length(design$tau)),
    alpha_min_spacing = if (startsWith(model, "joint_")) controls$alpha_min_spacing else 0,
    max_dense_dim = 0L,
    sigma_bounds = c(0, Inf), init = init)
  common <- c(common, app_joint_article_mcmc_precision_repair_controls())
  if (grepl("exqdesn", model, fixed = TRUE)) {
    common$gamma_init <- init$gamma_mean %||%
      vapply(init$fits, function(x) x$gamma_mean[[1L]], numeric(1L))
    common$gamma_slice_width <- 1
    common$gamma_slice_max_steps <- 100L
    if (startsWith(model, "joint_")) {
      return(do.call(app_joint_exqdesn_fit_mcmc_dispatch, c(
        list(method_id = "M0_v_collapsed_support_logit"), common)))
    }
    common$tau_seed_stride <- 1009L
    return(do.call(app_joint_exqdesn_fit_independent_mcmc_dispatch, c(
      list(method_id = "M0_v_collapsed_support_logit"), common)))
  }
  if (startsWith(model, "joint_")) return(do.call(app_joint_qvp_fit_al_mcmc_tiny, common))
  fits <- lapply(seq_along(design$tau), function(k) {
    one <- common; one$tau <- design$tau[[k]]; one$seed <- seed + 1009L * k
    one$alpha_prior_mean <- normal$initializer$alpha_mean[[k]]
    one$alpha_prior_sd <- normal$initializer$alpha_prior_sd
    one$alpha_min_spacing <- 0; one$init <- init$fits[[k]]
    do.call(app_joint_qvp_fit_al_mcmc_tiny, one)
  })
  app_joint_qdesn_phase122_combine_independent_chain(fits,
    design$Z[design$train_local, , drop = FALSE], design$tau, 1L, seed)
}

app_joint_swcf_run_sentinel <- function(root, worker_id) {
  root <- normalizePath(root, mustWork = TRUE); out_root <- app_joint_swcf_root(root)
  plan <- app_read_csv(file.path(out_root, "mcmc_sentinel_plan.csv"))
  row <- plan[plan$sentinel_worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("Sentinel worker is not unique.", call. = FALSE)
  out <- app_joint_swcf_worker_dir(root, "sentinel", worker_id)
  if (file.exists(file.path(out, "DONE"))) return(invisible(out))
  tmp <- paste0(out, ".tmp_", Sys.getpid()); unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp); started <- Sys.time()
  contract <- app_read_csv(file.path(out_root, "confirmation_contract.csv"))
  base <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  fixture <- readRDS(row$fixture_path[[1L]])
  design <- app_joint_pure_build_design(fixture, row, base, selector = TRUE)
  packet <- app_joint_swcf_load_transfer_packet(root, row)
  normal <- readRDS(file.path(app_joint_swq_worker_dir(root, "m1", row$m1_worker_id[[1L]]),
    "normal_initializer.rds"))
  model <- row$sentinel_model_id[[1L]]
  exal <- grepl("exqdesn", model, fixed = TRUE)
  n_iter <- app_joint_swcf_value(contract,
    if (exal) "mcmc_sentinel_exal_n_iter" else "mcmc_sentinel_al_n_iter", TRUE)
  burn <- app_joint_swcf_value(contract,
    if (exal) "mcmc_sentinel_exal_burn" else "mcmc_sentinel_al_burn", TRUE)
  captured <- tryCatch(app_joint_sw_capture_warnings(function() app_joint_swcf_mcmc_fit(
    model, design, packet[[model]], normal, row$rhs_tau0[[1L]], row$chain_seed[[1L]],
    n_iter, burn, app_joint_swcf_value(contract, "mcmc_sentinel_thin", TRUE))),
    error = function(e) e)
  if (inherits(captured, "error")) {
    app_ensure_dir(out); app_write_csv(data.frame(error_message = conditionMessage(captured)),
      file.path(out, "failure.csv")); writeLines("failed", file.path(out, "FAILED"));
    stop(conditionMessage(captured), call. = FALSE)
  }
  fit <- captured$value
  recursive <- app_joint_swtx_recursive_grid(design, fixture, fit, base)
  score <- app_joint_swtx_score_window(design, recursive$qhat, recursive$score_local,
    model, "calibration")
  draws <- app_joint_article_draw_frame(fit)
  finite <- all(is.finite(as.matrix(draws[, vapply(draws, is.numeric, logical(1L)), drop = FALSE])))
  summary <- data.frame(sentinel_worker_id = worker_id, model_id = model,
    inference_method_id = fit$inference_method_id %||% NA_character_,
    n_iter = n_iter, burn = burn, thin = app_joint_swcf_value(contract, "mcmc_sentinel_thin", TRUE),
    retained_draws = nrow(draws), finite_draws = finite,
    dgp_integrated_acrps = score$dgp_integrated_acrps,
    contract_crossing_pairs = score$contract_crossing_pairs,
    precision_repair_count = as.integer(fit$precision_repair_count %||% 0L),
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    warning_count = length(captured$warnings), protected_rows_loaded = 0L,
    stringsAsFactors = FALSE)
  files <- c(summary = app_write_csv(summary, file.path(tmp, "summary.csv")))
  fit_path <- file.path(tmp, "fit.rds"); saveRDS(fit, fit_path, version = 3L, compress = "xz")
  files <- c(files, fit = fit_path)
  app_joint_shared_write_manifest(tmp, files)
  if (!all(app_joint_shared_verify_manifest(tmp, file.path(tmp, "artifact_manifest.csv"))$verified))
    stop("Sentinel manifest verification failed.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE")); if (dir.exists(out)) unlink(out, recursive = TRUE)
  if (!file.rename(tmp, out)) stop("Could not publish sentinel atomically.", call. = FALSE)
  invisible(out)
}

app_joint_swcf_sentinel_health <- function(root) {
  plan <- app_read_csv(file.path(app_joint_swcf_root(root), "mcmc_sentinel_plan.csv"))
  dirs <- vapply(plan$sentinel_worker_id, function(id) app_joint_swcf_worker_dir(root,
    "sentinel", id), character(1L))
  done <- file.exists(file.path(dirs, "DONE")); failed <- file.exists(file.path(dirs, "FAILED"))
  data.frame(expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), stringsAsFactors = FALSE)
}

app_joint_swcf_prepare_vb <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); out <- app_joint_swcf_root(root)
  health <- app_joint_swcf_sentinel_health(root)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L)
    stop("Non-protected MCMC sentinel is not complete.", call. = FALSE)
  plan <- app_read_csv(file.path(out, "mcmc_sentinel_plan.csv"))
  summaries <- app_bind_rows_fill(lapply(plan$sentinel_worker_id, function(id) app_read_csv(
    file.path(app_joint_swcf_worker_dir(root, "sentinel", id), "summary.csv"))))
  if (any(!summaries$finite_draws) || any(summaries$contract_crossing_pairs != 0L) ||
      any(summaries$protected_rows_loaded != 0L) ||
      any(summaries$inference_method_id[grepl("exqdesn", summaries$model_id)] !=
        "M0_v_collapsed_support_logit")) stop("MCMC sentinel scientific gate failed.", call. = FALSE)
  app_write_csv(summaries, file.path(out, "mcmc_sentinel_summary.csv"))
  specs <- app_read_csv(file.path(root, "frozen_challenger_parity_specifications.csv"))
  registry <- app_joint_sw_read_registry(file.path(root, "frozen_registry.csv"))
  dgp <- app_joint_sw_derived_dgp_registry(app_joint_sw_read_contract(), registry)
  fixture_dir <- file.path(out, "fixtures"); app_ensure_dir(fixture_dir)
  fixture_rows <- lapply(seq_len(nrow(registry)), function(i) {
    row <- dgp[dgp$scenario_id == registry$scenario_id[[i]], , drop = FALSE]
    row$seed <- registry$article_seed[[i]]
    fixture <- app_joint_qdesn_fixture_from_registry_row(row)
    fixture$registry_row <- row
    if (is.null(fixture$registry_row$simulated_length) ||
        fixture$registry_row$simulated_length[[1L]] != length(fixture$y)) {
      stop("Article fixture registry metadata is missing or inconsistent.", call. = FALSE)
    }
    path <- file.path(fixture_dir, sprintf("%02d_%s_article.rds", registry$scenario_order[[i]],
      registry$scenario_id[[i]])); saveRDS(fixture, path, version = 3L, compress = "xz")
    data.frame(scenario_id = registry$scenario_id[[i]], article_seed = registry$article_seed[[i]],
      fixture_path = normalizePath(path), size_bytes = file.info(path)$size,
      sha256 = app_sha256_file(path), stringsAsFactors = FALSE)
  })
  fixtures <- app_bind_rows_fill(fixture_rows)
  vb <- merge(specs, fixtures, by = "scenario_id", all.x = TRUE, sort = FALSE)
  vb <- vb[order(vb$scenario_id, vb$specification_role), , drop = FALSE]
  vb$vb_worker_id <- seq_len(nrow(vb)); vb$component_seed <- 603611220L + vb$vb_worker_id * 1009L
  if (nrow(vb) != 16L || anyNA(vb$fixture_path)) stop("Full-development VB plan is malformed.", call. = FALSE)
  fixture_path <- app_write_csv(fixtures, file.path(out, "article_fixture_manifest.csv"))
  plan_path <- app_write_csv(vb, file.path(out, "full_vb_plan.csv"))
  gate <- data.frame(status = "FULL_DEVELOPMENT_VB_READY", expected_workers = nrow(vb),
    expected_components = nrow(vb) * 17L, mcmc_launched = FALSE,
    protected_scores_computed = FALSE, stringsAsFactors = FALSE)
  gate_path <- app_write_csv(gate, file.path(out, "full_vb_readiness.csv"))
  app_ensure_dir(file.path(out, "vb_workers"))
  app_joint_shared_write_manifest(out, c(sentinel = file.path(out, "mcmc_sentinel_summary.csv"),
    fixtures = fixture_path, plan = plan_path, readiness = gate_path),
    filename = "full_vb_prepare_manifest.csv")
  gate
}

app_joint_swcf_fit_vb_packet <- function(root, row) {
  base <- app_joint_sw_read_contract(file.path(root, "frozen_contract.csv"))
  controls <- app_joint_swq_controls(base); fixture <- readRDS(row$fixture_path[[1L]])
  design <- app_joint_pure_full_design(fixture, row, base)
  normal <- app_joint_swq_fit_normal_initializer(design, row, base, controls)
  fits <- vector("list", length(base$tau)); names(fits) <- format(base$tau, trim = TRUE)
  median_index <- match(0.5, base$tau)
  fits[[median_index]] <- app_joint_swq_fit_al(design, normal, controls, 0.5,
    app_joint_swq_single_init(normal, 0.5, design), controls$median_max_iter)
  targets <- c(0.25, 0.75, 0.10, 0.90, 0.05, 0.95)
  parents <- c(`0.25` = 0.5, `0.75` = 0.5, `0.1` = 0.25, `0.9` = 0.75,
    `0.05` = 0.10, `0.95` = 0.90)
  for (tau in targets) {
    parent <- fits[[match(parents[[as.character(tau)]], base$tau)]]
    init <- parent; k <- match(tau, base$tau)
    init$alpha_mean <- normal$initializer$alpha_mean[[k]]
    init$sigma_mean <- max(parent$sigma_mean[[1L]], normal$initializer$sigma_mean[[k]])
    fits[[k]] <- app_joint_swq_fit_al(design, normal, controls, tau, init,
      controls$quantile_max_iter)
  }
  exal <- lapply(seq_along(base$tau), function(k) app_joint_exqdesn_fit_vb_dispatch(
    method_id = controls$exal_vb_method, y = design$y[design$train_local],
    Z = design$Z[design$train_local, , drop = FALSE], tau = base$tau[[k]],
    max_iter = controls$quantile_max_iter, tol = controls$vb_tolerance, kappa = 1,
    tau0 = normal$rhs_tau0, zeta2 = normal$initializer$zeta2,
    slab_fixed = controls$rhs_slab_fixed, a_sigma = controls$a_sigma,
    b_sigma = controls$b_sigma, alpha_prior_mean = normal$initializer$alpha_mean[[k]],
    alpha_prior_sd = normal$initializer$alpha_prior_sd, alpha_min_spacing = 0,
    gamma_init = app_joint_qdesn_gamma_init_for_policy(base$tau[[k]],
      list(gamma_init_policy = controls$gamma_init_policy)), max_dense_dim = controls$max_dense_dim,
    rhs_vb_inner = controls$rhs_vb_inner, rhs_freeze_iters = controls$rhs_freeze_iters,
    diagnostic_stride = 20L, quadrature_nodes = c(4L, 8L, 12L),
    quadrature_tolerance = 1e-5, init = app_joint_shared_quantile_reset_init(fits[[k]])))
  joint_al_init <- app_joint_swtx_stack(fits, normal, design, controls)
  joint_al <- app_joint_qvp_fit_al_vb_tiny(y = design$y[design$train_local],
    Z = design$Z[design$train_local, , drop = FALSE], tau = base$tau,
    max_iter = controls$quantile_max_iter, tol = controls$vb_tolerance, kappa = 1,
    tau0 = normal$rhs_tau0, zeta2 = normal$initializer$zeta2,
    slab_fixed = controls$rhs_slab_fixed, a_sigma = controls$a_sigma,
    b_sigma = controls$b_sigma, alpha_prior_mean = normal$initializer$alpha_mean,
    alpha_prior_sd = normal$initializer$alpha_prior_sd,
    alpha_min_spacing = controls$alpha_min_spacing, max_dense_dim = controls$max_dense_dim,
    rhs_vb_inner = controls$rhs_vb_inner, rhs_freeze_iters = controls$rhs_freeze_iters,
    init = joint_al_init)
  joint_ex_init <- app_joint_swtx_stack(exal, normal, design, controls,
    rhs_state = joint_al$rhs_state)
  joint_ex <- app_joint_exqdesn_fit_vb_dispatch(method_id = controls$exal_vb_method,
    y = design$y[design$train_local], Z = design$Z[design$train_local, , drop = FALSE],
    tau = base$tau, max_iter = controls$quantile_max_iter, tol = controls$vb_tolerance,
    kappa = 1, tau0 = normal$rhs_tau0, zeta2 = normal$initializer$zeta2,
    slab_fixed = controls$rhs_slab_fixed, a_sigma = controls$a_sigma,
    b_sigma = controls$b_sigma, alpha_prior_mean = normal$initializer$alpha_mean,
    alpha_prior_sd = normal$initializer$alpha_prior_sd,
    alpha_min_spacing = controls$alpha_min_spacing,
    gamma_init = app_joint_qdesn_gamma_init_for_policy(base$tau,
      list(gamma_init_policy = controls$gamma_init_policy)), max_dense_dim = controls$max_dense_dim,
    rhs_vb_inner = controls$rhs_vb_inner, rhs_freeze_iters = controls$rhs_freeze_iters,
    diagnostic_stride = 20L, quadrature_nodes = c(4L, 8L, 12L),
    quadrature_tolerance = 1e-5, init = joint_ex_init)
  packet <- list(normal = normal,
    independent_qdesn_rhs = lapply(fits, app_joint_shared_quantile_compact_fit),
    independent_exqdesn_rhs = lapply(exal, app_joint_shared_quantile_compact_fit),
    joint_qdesn_rhs = app_joint_shared_quantile_compact_fit(joint_al),
    joint_exqdesn_rhs = app_joint_shared_quantile_compact_fit(joint_ex))
  list(packet = packet, design = design)
}

app_joint_swcf_run_vb <- function(root, worker_id) {
  root <- normalizePath(root, mustWork = TRUE); out_root <- app_joint_swcf_root(root)
  plan <- app_read_csv(file.path(out_root, "full_vb_plan.csv"))
  row <- plan[plan$vb_worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("Full VB worker is not unique.", call. = FALSE)
  out <- app_joint_swcf_worker_dir(root, "vb", worker_id)
  if (file.exists(file.path(out, "DONE"))) return(invisible(out))
  tmp <- paste0(out, ".tmp_", Sys.getpid()); unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp); started <- Sys.time(); set.seed(row$component_seed[[1L]])
  captured <- tryCatch(app_joint_sw_capture_warnings(function()
    app_joint_swcf_fit_vb_packet(root, row)), error = function(e) e)
  if (inherits(captured, "error")) {
    app_ensure_dir(out); app_write_csv(data.frame(error_message = conditionMessage(captured)),
      file.path(out, "failure.csv")); writeLines("failed", file.path(out, "FAILED"));
    stop(conditionMessage(captured), call. = FALSE)
  }
  packet <- captured$value$packet
  components <- c(packet$independent_qdesn_rhs, packet$independent_exqdesn_rhs,
    list(packet$joint_qdesn_rhs, packet$joint_exqdesn_rhs))
  model <- c(rep("independent_qdesn_rhs", 7), rep("independent_exqdesn_rhs", 7),
    "joint_qdesn_rhs", "joint_exqdesn_rhs")
  tau <- c(app_joint_sw_read_contract()$tau, app_joint_sw_read_contract()$tau, NA, NA)
  quantile_summary <- data.frame(vb_worker_id = worker_id, scenario_id = row$scenario_id,
    specification_role = row$specification_role, candidate_id = row$candidate_id,
    model_id = model, tau = tau,
    finite_output = vapply(components, function(x) all(is.finite(c(x$beta_mean,
      x$alpha_mean, x$sigma_mean, x$gamma_mean %||% numeric()))) && all(x$sigma_mean > 0), logical(1L)),
    converged = vapply(components, function(x) isTRUE(x$converged), logical(1L)),
    inference_method_id = vapply(components, function(x) x$inference_method_id %||%
      NA_character_, character(1L)), protected_rows_used_for_fit = 0L,
    protected_scores_computed = FALSE, warning_count = length(captured$warnings),
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    stringsAsFactors = FALSE)
  normal <- packet$normal
  normal_summary <- data.frame(vb_worker_id = worker_id, scenario_id = row$scenario_id,
    specification_role = row$specification_role, candidate_id = row$candidate_id,
    model_id = "gaussian_rhs_initializer", tau = NA_real_,
    finite_output = all(is.finite(c(normal$initializer$beta_mean,
      normal$initializer$alpha_mean, normal$initializer$sigma_mean))) &&
      all(normal$initializer$sigma_mean > 0),
    converged = isTRUE(normal$rhs_converged), inference_method_id = "gaussian_rhs_vb",
    protected_rows_used_for_fit = 0L, protected_scores_computed = FALSE,
    warning_count = length(captured$warnings),
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    stringsAsFactors = FALSE)
  summary <- rbind(normal_summary, quantile_summary)
  if (nrow(summary) != 17L || any(!summary$finite_output)) {
    stop("Full-development VB packet did not produce 17 finite components.", call. = FALSE)
  }
  packet_path <- file.path(tmp, "vb_packet.rds"); design_path <- file.path(tmp, "design.rds")
  saveRDS(packet, packet_path, version = 3L, compress = "xz")
  saveRDS(captured$value$design, design_path, version = 3L, compress = "xz")
  files <- c(summary = app_write_csv(summary, file.path(tmp, "summary.csv")),
    packet = packet_path, design = design_path)
  app_joint_shared_write_manifest(tmp, files)
  if (!all(app_joint_shared_verify_manifest(tmp, file.path(tmp, "artifact_manifest.csv"))$verified))
    stop("Full VB worker manifest failed verification.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE")); if (dir.exists(out)) unlink(out, recursive = TRUE)
  if (!file.rename(tmp, out)) stop("Could not publish full VB packet atomically.", call. = FALSE)
  invisible(out)
}

app_joint_swcf_vb_health <- function(root) {
  plan <- app_read_csv(file.path(app_joint_swcf_root(root), "full_vb_plan.csv"))
  dirs <- vapply(plan$vb_worker_id, function(id) app_joint_swcf_worker_dir(root, "vb", id), character(1L))
  done <- file.exists(file.path(dirs, "DONE")); failed <- file.exists(file.path(dirs, "FAILED"))
  data.frame(expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), stringsAsFactors = FALSE)
}

app_joint_swcf_model_metadata <- function(model_id) {
  data.frame(
    model_id = model_id,
    fit_structure = if (startsWith(model_id, "joint_")) "joint" else "independent",
    likelihood_family = if (grepl("exqdesn", model_id, fixed = TRUE)) "exAL" else "AL",
    stringsAsFactors = FALSE
  )
}

app_joint_swcf_packet_init <- function(packet, model_id) {
  init <- packet[[model_id]]
  if (startsWith(model_id, "independent_")) {
    fits <- init$fits %||% init
    init <- list(
      fits = fits,
      beta_mean = unlist(lapply(fits, `[[`, "beta_mean"), use.names = FALSE),
      alpha_mean = vapply(fits, function(x) x$alpha_mean[[1L]], numeric(1L)),
      sigma_mean = vapply(fits, function(x) x$sigma_mean[[1L]], numeric(1L))
    )
    if (grepl("exqdesn", model_id, fixed = TRUE)) {
      init$gamma_mean <- vapply(fits, function(x) x$gamma_mean[[1L]], numeric(1L))
    }
  }
  init
}

app_joint_swcf_finalize_vb <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); out <- app_joint_swcf_root(root)
  health <- app_joint_swcf_vb_health(root)
  if (health$completed[[1L]] != health$expected[[1L]] || health$failed[[1L]] != 0L) {
    stop("Full-development VB is not complete and failure-free.", call. = FALSE)
  }
  plan <- app_read_csv(file.path(out, "full_vb_plan.csv"))
  summaries <- lapply(plan$vb_worker_id, function(id) {
    worker <- app_joint_swcf_worker_dir(root, "vb", id)
    verified <- app_joint_shared_verify_manifest(worker,
      file.path(worker, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified)) {
      stop(sprintf("VB worker %d manifest is not verified.", id), call. = FALSE)
    }
    app_read_csv(file.path(worker, "summary.csv"))
  })
  summary <- app_bind_rows_fill(summaries)
  if (nrow(summary) != 272L || any(!summary$finite_output) ||
      any(summary$protected_rows_used_for_fit != 0L) ||
      any(app_as_bool_vec(summary$protected_scores_computed))) {
    stop("Full-development VB summary violates the frozen gate.", call. = FALSE)
  }
  summary_path <- app_write_csv(summary, file.path(out, "full_vb_summary.csv"))
  model_ids <- c("independent_qdesn_rhs", "joint_qdesn_rhs",
    "independent_exqdesn_rhs", "joint_exqdesn_rhs")
  cells <- app_bind_rows_fill(lapply(seq_len(nrow(plan)), function(i) {
    app_bind_rows_fill(lapply(model_ids, function(model_id) {
      row <- plan[i, , drop = FALSE]
      meta <- app_joint_swcf_model_metadata(model_id)
      row$model_id <- model_id
      row$fit_structure <- meta$fit_structure
      row$likelihood_family <- meta$likelihood_family
      row$model_cell_id <- paste(row$scenario_id, row$specification_role,
        model_id, sep = "__")
      row$vb_packet_path <- file.path(app_joint_swcf_worker_dir(root, "vb",
        row$vb_worker_id[[1L]]), "vb_packet.rds")
      row$design_path <- file.path(app_joint_swcf_worker_dir(root, "vb",
        row$vb_worker_id[[1L]]), "design.rds")
      row
    }))
  }))
  cells$cell_index <- seq_len(nrow(cells))
  if (nrow(cells) != 64L || anyDuplicated(cells$model_cell_id) ||
      any(!file.exists(cells$vb_packet_path)) || any(!file.exists(cells$design_path))) {
    stop("Full-development model-cell registry is malformed.", call. = FALSE)
  }
  contract <- app_read_csv(file.path(out, "confirmation_contract.csv"))
  chains <- as.integer(app_joint_swcf_value(contract, "chains_per_cell", TRUE))
  workers <- app_bind_rows_fill(lapply(seq_len(nrow(cells)), function(i) {
    app_bind_rows_fill(lapply(seq_len(chains), function(chain_id) {
      row <- cells[i, , drop = FALSE]
      row$chain_id <- chain_id
      row$chain_seed <- as.integer(703611220L + row$cell_index[[1L]] * 100000L +
        chain_id * 10000L)
      row$chain_start_seed <- as.integer(803611220L + row$cell_index[[1L]] * 100000L +
        chain_id * 10000L)
      exal <- identical(row$likelihood_family[[1L]], "exAL")
      row$n_iter <- as.integer(app_joint_swcf_value(contract,
        if (exal) "exal_n_iter" else "al_n_iter", TRUE))
      row$burn <- as.integer(app_joint_swcf_value(contract,
        if (exal) "exal_burn" else "al_burn", TRUE))
      row$thin <- as.integer(app_joint_swcf_value(contract,
        if (exal) "exal_thin" else "al_thin", TRUE))
      row$n_keep <- as.integer((row$n_iter - row$burn) / row$thin)
      row$tau_seed_stride <- 1009L
      row$inference_method_id <- if (exal) {
        app_joint_swcf_value(contract, "exal_mcmc_method")
      } else "AL_MCMC"
      row
    }))
  }))
  workers$worker_id <- seq_len(nrow(workers))
  component_seeds <- app_bind_rows_fill(lapply(seq_len(nrow(workers)), function(i) {
    row <- workers[i, , drop = FALSE]
    if (identical(row$fit_structure[[1L]], "joint")) {
      return(data.frame(worker_id = row$worker_id, model_cell_id = row$model_cell_id,
        chain_id = row$chain_id, quantile_index = NA_integer_, tau = NA_real_,
        component_seed = row$chain_seed, stringsAsFactors = FALSE))
    }
    data.frame(worker_id = row$worker_id, model_cell_id = row$model_cell_id,
      chain_id = row$chain_id, quantile_index = seq_along(app_joint_sw_read_contract()$tau),
      tau = app_joint_sw_read_contract()$tau,
      component_seed = as.integer(row$chain_seed[[1L]] +
        seq_along(app_joint_sw_read_contract()$tau) * row$tau_seed_stride[[1L]]),
      stringsAsFactors = FALSE)
  }))
  if (nrow(workers) != 192L || anyDuplicated(workers$worker_id) ||
      anyDuplicated(workers$chain_seed) || anyDuplicated(workers$chain_start_seed) ||
      anyDuplicated(component_seeds$component_seed) ||
      any(workers$likelihood_family == "exAL" &
        workers$inference_method_id != "M0_v_collapsed_support_logit")) {
    stop("Full-development MCMC plan or seed namespace is malformed.", call. = FALSE)
  }
  cells_path <- app_write_csv(cells, file.path(out, "model_cell_plan.csv"))
  worker_path <- app_write_csv(workers, file.path(out, "mcmc_worker_plan.csv"))
  seed_path <- app_write_csv(component_seeds, file.path(out, "mcmc_component_seed_plan.csv"))
  app_ensure_dir(file.path(out, "mcmc_workers"))
  readiness <- data.frame(status = "VB_COMPLETE_MCMC_READY_NOT_LAUNCHED",
    vb_workers = nrow(plan), vb_components = nrow(summary), model_cells = nrow(cells),
    mcmc_workers = nrow(workers), protected_scores_computed = FALSE,
    stringsAsFactors = FALSE)
  readiness_path <- app_write_csv(readiness, file.path(out, "mcmc_readiness.csv"))
  app_joint_shared_write_manifest(out, c(vb_summary = summary_path,
    model_cells = cells_path, mcmc_plan = worker_path, component_seeds = seed_path,
    readiness = readiness_path), filename = "full_vb_final_manifest.csv")
  readiness
}

app_joint_swcf_run_mcmc <- function(root, worker_id) {
  root <- normalizePath(root, mustWork = TRUE); out_root <- app_joint_swcf_root(root)
  plan <- app_read_csv(file.path(out_root, "mcmc_worker_plan.csv"))
  row <- plan[plan$worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("Full MCMC worker is not unique.", call. = FALSE)
  out <- app_joint_swcf_worker_dir(root, "mcmc", worker_id)
  if (file.exists(file.path(out, "DONE"))) return(invisible(out))
  tmp <- paste0(out, ".tmp_", Sys.getpid()); unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp); started <- Sys.time()
  design <- readRDS(row$design_path[[1L]])
  packet <- readRDS(row$vb_packet_path[[1L]])
  init <- app_joint_swcf_packet_init(packet, row$model_id[[1L]])
  complete_target <- app_joint_swcf_complete_target(
    row$model_id[[1L]], design, packet$normal, row$rhs_tau0[[1L]])
  sampler_control <- app_joint_swcf_sampler_control_contract(
    row$model_id[[1L]], row$n_iter[[1L]], row$burn[[1L]], row$thin[[1L]])
  init <- app_joint_article_overdispersed_start(init, row, design$tau)
  captured <- tryCatch(app_joint_sw_capture_warnings(function() app_joint_swcf_mcmc_fit(
    row$model_id[[1L]], design, init, packet$normal, row$rhs_tau0[[1L]],
    row$chain_seed[[1L]], row$n_iter[[1L]], row$burn[[1L]], row$thin[[1L]])),
    error = function(e) e)
  if (inherits(captured, "error")) {
    app_ensure_dir(out)
    app_write_csv(cbind(row, data.frame(error_message = conditionMessage(captured),
      stringsAsFactors = FALSE)), file.path(out, "failure.csv"))
    writeLines("failed", file.path(out, "FAILED"))
    stop(conditionMessage(captured), call. = FALSE)
  }
  fit <- captured$value; draws <- app_joint_article_draw_frame(fit)
  if (nrow(draws) != row$n_keep[[1L]] ||
      any(!is.finite(as.matrix(draws[, -1L, drop = FALSE])))) {
    stop("Full MCMC retained draws violate the frozen budget.", call. = FALSE)
  }
  qhat <- app_joint_qdesn_predict_fit(fit,
    design$Z[design$train_local, , drop = FALSE], design$tau)
  crossing <- app_joint_qdesn_apply_monotone_contract(qhat, design$tau)
  target_fields <- data.frame(
    posterior_data_design_fingerprint = design$posterior_data_design_fingerprint,
    rhs_tau0 = row$rhs_tau0, zeta2 = packet$normal$initializer$zeta2,
    a_sigma = app_joint_swq_controls(app_joint_sw_read_contract())$a_sigma,
    b_sigma = app_joint_swq_controls(app_joint_sw_read_contract())$b_sigma,
    slab_fixed = app_joint_swq_controls(app_joint_sw_read_contract())$rhs_slab_fixed,
    alpha_min_spacing = if (row$fit_structure[[1L]] == "joint")
      app_joint_swq_controls(app_joint_sw_read_contract())$alpha_min_spacing else 0,
    stringsAsFactors = FALSE)
  target_hash <- app_joint_qvp_sha256_text(paste(names(target_fields),
    format(unlist(target_fields), digits = 17L, scientific = TRUE), collapse = "|"))
  summary <- data.frame(worker_id = row$worker_id, model_cell_id = row$model_cell_id,
    scenario_id = row$scenario_id, specification_role = row$specification_role,
    model_id = row$model_id, fit_structure = row$fit_structure,
    likelihood_family = row$likelihood_family, chain_id = row$chain_id,
    chain_seed = row$chain_seed, chain_start_seed = row$chain_start_seed,
    n_iter = row$n_iter, burn = row$burn, thin = row$thin, n_keep = nrow(draws),
    inference_method_id = fit$inference_method_id %||% row$inference_method_id,
    finite_draws = TRUE,
    fit_raw_crossing_pairs = sum(crossing$raw_crossing$n_crossing_pairs),
    fit_contract_crossing_pairs = sum(crossing$contract_crossing$n_crossing_pairs),
    precision_repair_count = as.integer(fit$precision_repair_count %||% 0L),
    precision_repair_max_relative_jitter =
      as.numeric(fit$precision_repair_max_rel_used %||% 0),
    warning_count = length(captured$warnings), posterior_target_sha256 = target_hash,
    complete_posterior_target_sha256 = complete_target$hash,
    effective_sampler_control_sha256 = sampler_control$hash,
    sigma_support = "(0,Inf)",
    sigma_update_id = fit$sigma_update_id %||%
      if (row$likelihood_family[[1L]] == "exAL") {
        "exact_M0_v_collapsed_scale_shape"
      } else {
        "direct_inverse_gamma_unbounded_v1"
      },
    protected_scores_computed = FALSE,
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    stringsAsFactors = FALSE)
  warnings <- data.frame(warning_index = seq_along(captured$warnings),
    warning_message = as.character(captured$warnings), stringsAsFactors = FALSE)
  precision <- fit$precision_repair_diagnostics %||% data.frame()
  files <- c(
    posterior_draws = app_joint_article_write_gzip_csv(draws,
      file.path(tmp, "posterior_draws.csv.gz")),
    summary = app_write_csv(summary, file.path(tmp, "summary.csv")),
    target = app_write_csv(target_fields, file.path(tmp, "posterior_target_contract.csv")),
    complete_target = app_write_csv(complete_target$fields,
      file.path(tmp, "complete_posterior_target_contract.csv")),
    sampler_control = app_write_csv(sampler_control$fields,
      file.path(tmp, "effective_sampler_control_contract.csv")),
    warnings = app_write_csv(warnings, file.path(tmp, "warnings.csv")),
    precision = app_write_csv(precision, file.path(tmp, "precision_repair_diagnostics.csv")))
  app_joint_shared_write_manifest(tmp, files)
  if (!all(app_joint_shared_verify_manifest(tmp,
      file.path(tmp, "artifact_manifest.csv"))$verified)) {
    stop("Full MCMC worker manifest failed verification.", call. = FALSE)
  }
  writeLines("completed", file.path(tmp, "DONE")); if (dir.exists(out)) unlink(out, recursive = TRUE)
  if (!file.rename(tmp, out)) stop("Could not publish full MCMC worker atomically.", call. = FALSE)
  invisible(out)
}

app_joint_swcf_mcmc_health <- function(root) {
  plan <- app_read_csv(file.path(app_joint_swcf_root(root), "mcmc_worker_plan.csv"))
  dirs <- vapply(plan$worker_id, function(id) app_joint_swcf_worker_dir(root, "mcmc", id), character(1L))
  done <- file.exists(file.path(dirs, "DONE")); failed <- file.exists(file.path(dirs, "FAILED"))
  data.frame(expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), stringsAsFactors = FALSE)
}
