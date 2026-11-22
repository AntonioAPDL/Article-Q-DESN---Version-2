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
  list(
    independent_qdesn_rhs = app_joint_swtx_load_q1_fits(root, row),
    independent_exqdesn_rhs = lapply(ex$transfer_worker_id, function(id) readRDS(
      file.path(app_joint_swtx_worker_dir(root, id), "fit_initializer.rds"))),
    joint_qdesn_rhs = readRDS(file.path(app_joint_swtx_worker_dir(root,
      joint_al$transfer_worker_id[[1L]]), "fit_initializer.rds")),
    joint_exqdesn_rhs = readRDS(file.path(app_joint_swtx_worker_dir(root,
      joint_ex$transfer_worker_id[[1L]]), "fit_initializer.rds"))
  )
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
    sigma_bounds = c(1e-8, max(1, 10 * max(init$sigma_mean %||%
      vapply(init$fits, function(x) x$sigma_mean[[1L]], numeric(1L))))), init = init)
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
