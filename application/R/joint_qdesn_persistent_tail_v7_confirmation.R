# Complete four-model confirmation for the V6 persistent-heavy-tail candidate.

app_joint_pht7_contract_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_v7_contract.csv")
}

app_joint_pht7_default_root <- function() {
  app_path("application/cache/joint_qdesn_persistent_tail_v7_full_confirmation_20261126")
}

app_joint_pht7_read_contract <- function(path = app_joint_pht7_contract_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "persistent-tail V7 contract")
  value <- function(name) {
    row <- tab[tab$name == name, , drop = FALSE]
    if (nrow(row) != 1L) stop(sprintf("V7 contract requires one '%s'.", name), call. = FALSE)
    as.character(row$value[[1L]])
  }
  numvec <- function(name) as.numeric(strsplit(value(name), ";", fixed = TRUE)[[1L]])
  out <- list(table = tab, version = value("contract_version"), run_tag = value("run_tag"),
    execution_branch = value("execution_branch"), v6_head = value("v6_head"),
    v6_decision_sha256 = value("v6_decision_sha256"),
    v6_finalists_sha256 = value("v6_finalists_sha256"),
    v6_aggregate_sha256 = value("v6_aggregate_sha256"),
    authority_selected_sha256 = value("authority_selected_sha256"),
    authority_decision_sha256 = value("authority_decision_sha256"),
    article_fixture_sha256 = value("article_fixture_sha256"),
    oracle_bank_sha256 = value("oracle_bank_sha256"), scenario_id = value("scenario_id"),
    candidate_id = value("candidate_id"), authority_role = value("authority_role"),
    tau = numvec("quantile_grid"), model_ids = strsplit(value("model_ids"), ";", fixed = TRUE)[[1L]],
    expected_components = as.integer(value("expected_components")),
    vb_max_iter = as.integer(value("max_iter")), vb_tolerance = as.numeric(value("tolerance")),
    joint_anchor_profile = value("joint_anchor_profile"),
    joint_innovation_profile = value("joint_innovation_profile"),
    chains_per_cell = as.integer(value("chains_per_cell")),
    al_n_iter = as.integer(value("al_n_iter")), al_burn = as.integer(value("al_burn")),
    al_thin = as.integer(value("al_thin")), exal_n_iter = as.integer(value("exal_n_iter")),
    exal_burn = as.integer(value("exal_burn")), exal_thin = as.integer(value("exal_thin")),
    exal_method = value("exal_method"), primary_score = value("primary_score"),
    practical_margin = as.numeric(value("practical_noninferiority_margin")),
    interval_overlap_is_equivalence = identical(tolower(value("interval_overlap_is_equivalence")), "true"),
    required_hostname = value("required_hostname"),
    max_physical_workers = as.integer(value("max_physical_workers")),
    min_data_free_gib = as.numeric(value("min_data_free_gib")),
    min_available_memory_gib = as.numeric(value("min_available_memory_gib")),
    automatic_downstream_launch = identical(tolower(value("automatic_downstream_launch")), "true"))
  hashes <- unlist(out[grep("sha256$", names(out))])
  valid <- identical(out$version, "joint_qdesn_persistent_tail_v7_full_confirmation") &&
    identical(out$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)) &&
    length(out$model_ids) == 4L && out$expected_components == 17L &&
    out$chains_per_cell == 3L && out$exal_method == "M0_v_collapsed_support_logit" &&
    out$joint_anchor_profile == "lower" && out$joint_innovation_profile == "median" &&
    all(grepl("^[0-9a-f]{64}$", hashes)) && !out$interval_overlap_is_equivalence &&
    !out$automatic_downstream_launch
  if (!valid) stop("Persistent-tail V7 contract is malformed.", call. = FALSE)
  out
}

app_joint_pht7_worker_dir <- function(root, stage, id) {
  file.path(root, "full_confirmation", paste0(stage, "_workers"),
    sprintf("worker_%04d", as.integer(id)))
}

app_joint_pht7_hash_check <- function(path, expected, label) {
  if (!file.exists(path) || app_sha256_file(path) != expected) {
    stop(sprintf("V7 %s hash verification failed.", label), call. = FALSE)
  }
  normalizePath(path, mustWork = TRUE)
}

app_joint_pht7_prepare <- function(v6_root, authority_root, fixture_path, oracle_path,
    root = app_joint_pht7_default_root()) {
  contract <- app_joint_pht7_read_contract()
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    stop("V7 preparation requires a new empty runtime root.", call. = FALSE)
  }
  app_ensure_dir(root); app_ensure_dir(file.path(root, "imported_sources"))
  app_ensure_dir(file.path(root, "full_confirmation", "vb_workers"))
  source_files <- c(
    v6_decision = app_joint_pht7_hash_check(file.path(v6_root, "v6_decision.csv"),
      contract$v6_decision_sha256, "V6 decision"),
    v6_finalists = app_joint_pht7_hash_check(file.path(v6_root, "frozen_seven_finalists.csv"),
      contract$v6_finalists_sha256, "V6 finalists"),
    v6_aggregate = app_joint_pht7_hash_check(file.path(v6_root, "seven_aggregate.csv"),
      contract$v6_aggregate_sha256, "V6 aggregate"),
    authority_selected = app_joint_pht7_hash_check(
      file.path(authority_root, "corrected_superfinal_selected_score_summary.csv"),
      contract$authority_selected_sha256, "authority selected packet"),
    authority_decision = app_joint_pht7_hash_check(file.path(authority_root, "final_decision.csv"),
      contract$authority_decision_sha256, "authority decision"),
    article_fixture = app_joint_pht7_hash_check(fixture_path,
      contract$article_fixture_sha256, "article fixture"),
    oracle_bank = app_joint_pht7_hash_check(oracle_path,
      contract$oracle_bank_sha256, "oracle bank"))
  destinations <- stats::setNames(
    file.path(root, "imported_sources", basename(source_files)),
    names(source_files))
  copied <- file.copy(source_files, destinations, overwrite = FALSE, copy.mode = TRUE)
  if (!all(copied)) stop("V7 could not copy all frozen sources.", call. = FALSE)
  observed <- vapply(destinations, app_sha256_file, character(1L))
  if (!identical(unname(observed), unname(vapply(source_files, app_sha256_file,
      character(1L))))) stop("V7 copied source hashes differ.", call. = FALSE)

  finalists <- app_read_csv(destinations[["v6_finalists"]])
  candidate <- finalists[finalists$candidate_id == contract$candidate_id, , drop = FALSE]
  candidate <- candidate[1L, , drop = FALSE]
  if (nrow(candidate) != 1L || candidate$scenario_id != contract$scenario_id ||
      !app_as_bool_vec(candidate$joint_backend_eligible)) {
    stop("V7 candidate is absent or joint-ineligible.", call. = FALSE)
  }
  authority <- app_read_csv(destinations[["authority_selected"]])
  authority <- authority[authority$scenario_id == contract$scenario_id &
    authority$specification_role == contract$authority_role &
    authority$inference_method == "mcmc", , drop = FALSE]
  if (nrow(authority) != 4L || !setequal(authority$model_id, contract$model_ids)) {
    stop("V7 authority comparator is not a complete four-model packet.", call. = FALSE)
  }
  fixture <- readRDS(destinations[["article_fixture"]])
  base <- app_joint_sw_read_contract()
  design <- app_joint_pure_build_design(fixture, candidate, base, selector = TRUE)
  if (design$diagnostic$protected_rows_loaded != 0L ||
      !identical(as.numeric(design$tau), contract$tau)) {
    stop("V7 design violates the training-only fit boundary or quantile grid.", call. = FALSE)
  }
  design_path <- file.path(root, "full_confirmation", "design.rds")
  fixture_copy <- file.path(root, "full_confirmation", "article_fixture.rds")
  oracle_copy <- file.path(root, "full_confirmation", "score_packet", "oracle_banks",
    paste0(contract$scenario_id, ".rds"))
  app_ensure_dir(dirname(oracle_copy))
  saveRDS(design, design_path, version = 3L, compress = "xz")
  file.copy(destinations[["article_fixture"]], fixture_copy, overwrite = TRUE)
  file.copy(destinations[["oracle_bank"]], oracle_copy, overwrite = TRUE)
  if (app_sha256_file(fixture_copy) != contract$article_fixture_sha256 ||
      app_sha256_file(oracle_copy) != contract$oracle_bank_sha256) {
    stop("V7 runtime fixture or oracle copy failed hash verification.", call. = FALSE)
  }
  candidate_path <- app_write_csv(candidate, file.path(root, "frozen_candidate.csv"))
  authority_path <- app_write_csv(authority, file.path(root, "frozen_authority_comparator.csv"))
  contract_path <- app_write_csv(contract$table, file.path(root, "frozen_contract.csv"))
  vb_plan <- data.frame(vb_worker_id = 1L, scenario_id = contract$scenario_id,
    candidate_id = contract$candidate_id, component_seed = 72611001L,
    design_path = normalizePath(design_path), fixture_path = normalizePath(fixture_copy),
    stringsAsFactors = FALSE)
  vb_plan_path <- app_write_csv(vb_plan,
    file.path(root, "full_confirmation", "vb_worker_plan.csv"))
  sources <- data.frame(label = names(source_files), source_path = unname(source_files),
    copied_path = normalizePath(destinations), size_bytes = file.info(destinations)$size,
    sha256 = observed, verified = TRUE, stringsAsFactors = FALSE)
  sources_path <- app_write_csv(sources, file.path(root, "source_verification.csv"))
  readiness <- data.frame(status = "V7_PREPARED_VB_READY_NOT_LAUNCHED",
    vb_workers = 1L, expected_components = contract$expected_components,
    mcmc_workers = 0L, score_workers = 0L, article_files_modified = FALSE,
    stringsAsFactors = FALSE)
  readiness_path <- app_write_csv(readiness, file.path(root, "launch_readiness.csv"))
  app_joint_shared_write_manifest(root, c(contract = contract_path, candidate = candidate_path,
    authority = authority_path, sources = sources_path, vb_plan = vb_plan_path,
    design = design_path, fixture = fixture_copy, oracle = oracle_copy,
    readiness = readiness_path), filename = "preparation_manifest.csv")
  readiness
}

app_joint_pht7_level_controls <- function(candidate, tau, base) {
  prior <- app_joint_pht6_prior_row(candidate, tau)
  controls <- app_joint_pht3_quantile_controls(base, prior)
  contract <- app_joint_pht7_read_contract()
  controls$quantile_max_iter <- contract$vb_max_iter
  controls$median_max_iter <- contract$vb_max_iter
  controls$vb_tolerance <- contract$vb_tolerance
  list(prior = prior, controls = controls)
}

app_joint_pht7_stack <- function(fits, rhs_state = NULL) {
  K <- length(fits); p <- length(fits[[1L]]$beta_mean)
  out <- list(beta_mean = unlist(lapply(fits, `[[`, "beta_mean"), use.names = FALSE),
    beta_cov = as.matrix(Matrix::bdiag(lapply(fits, function(x) as.matrix(x$beta_cov)))),
    alpha_mean = vapply(fits, function(x) x$alpha_mean[[1L]], numeric(1L)),
    sigma_mean = vapply(fits, function(x) x$sigma_mean[[1L]], numeric(1L)),
    fits = fits, iterations_completed = 0L)
  if (all(vapply(fits, function(x) length(x$gamma_mean %||% numeric()) == 1L, logical(1L)))) {
    out$gamma_mean <- vapply(fits, function(x) x$gamma_mean[[1L]], numeric(1L))
  }
  if (!is.null(rhs_state)) out$rhs_state <- rhs_state
  out
}

app_joint_pht7_fit_vb_packet <- function(root) {
  contract <- app_joint_pht7_read_contract(file.path(root, "frozen_contract.csv"))
  candidate <- app_read_csv(file.path(root, "frozen_candidate.csv"))
  design <- readRDS(file.path(root, "full_confirmation", "design.rds"))
  base <- app_joint_sw_read_contract()
  order <- app_joint_swq_continuation_order()
  al <- exal <- normals <- profiles <- list()
  for (ii in seq_len(nrow(order))) {
    tau <- order$tau[[ii]]; key <- sprintf("%.2f", tau)
    level <- app_joint_pht7_level_controls(candidate, tau, base)
    normal <- app_joint_pht3_fit_normal_initializer(design, level$prior, base, level$controls)
    init <- app_joint_swq_single_init(normal, tau, design)
    if (!is.na(order$parent_tau[[ii]])) {
      parent <- al[[sprintf("%.2f", order$parent_tau[[ii]])]]
      init$beta_mean <- parent$beta_mean; init$beta_cov <- parent$beta_cov
    }
    al[[key]] <- app_joint_swq_fit_al(design, normal, level$controls, tau, init,
      level$controls$quantile_max_iter)
    k <- match(tau, design$tau)
    exal[[key]] <- app_joint_exqdesn_fit_vb_dispatch(
      method_id = level$controls$exal_vb_method,
      y = design$y[design$train_local], Z = design$Z[design$train_local, , drop = FALSE],
      tau = tau, max_iter = level$controls$quantile_max_iter,
      tol = level$controls$vb_tolerance, kappa = 1, tau0 = normal$rhs_tau0,
      zeta2 = normal$initializer$zeta2, slab_fixed = level$controls$rhs_slab_fixed,
      a_sigma = level$controls$a_sigma, b_sigma = level$controls$b_sigma,
      alpha_prior_mean = normal$initializer$alpha_mean[[k]],
      alpha_prior_sd = normal$initializer$alpha_prior_sd, alpha_min_spacing = 0,
      gamma_init = app_joint_qdesn_gamma_init_for_policy(tau,
        list(gamma_init_policy = level$controls$gamma_init_policy)),
      max_dense_dim = level$controls$max_dense_dim,
      rhs_vb_inner = level$controls$rhs_vb_inner,
      rhs_freeze_iters = level$controls$rhs_freeze_iters,
      diagnostic_stride = 20L, quadrature_nodes = c(4L, 8L, 12L),
      quadrature_tolerance = 1e-5, init = app_joint_shared_quantile_reset_init(al[[key]]))
    normals[[key]] <- normal
    profiles[[key]] <- data.frame(tau = tau, normal_rhs_tau0 = normal$rhs_tau0,
      rhs_tau0 = as.numeric(level$prior$rhs_tau0[[1L]]),
      rhs_zeta2 = normal$initializer$zeta2, stringsAsFactors = FALSE)
  }
  al <- al[sprintf("%.2f", contract$tau)]; exal <- exal[sprintf("%.2f", contract$tau)]
  normals <- normals[sprintf("%.2f", contract$tau)]
  profile <- app_bind_rows_fill(profiles[sprintf("%.2f", contract$tau)])
  controls <- app_joint_swq_controls(base); controls$quantile_max_iter <- contract$vb_max_iter
  controls$vb_tolerance <- contract$vb_tolerance; controls$max_dense_dim <- max(1000L,
    controls$max_dense_dim)
  lower <- profile[profile$tau == 0.05, , drop = FALSE]
  middle <- profile[profile$tau == 0.50, , drop = FALSE]
  alpha_prior_mean <- vapply(seq_along(contract$tau), function(k)
    normals[[k]]$initializer$alpha_mean[[k]], numeric(1L))
  alpha_prior_sd <- vapply(normals, function(x) x$initializer$alpha_prior_sd, numeric(1L))
  joint_init <- app_joint_pht7_stack(al)
  joint_al <- app_joint_qvp_fit_al_vb_tiny(
    y = design$y[design$train_local], Z = design$Z[design$train_local, , drop = FALSE],
    tau = contract$tau, max_iter = controls$quantile_max_iter, tol = controls$vb_tolerance,
    kappa = 1, tau0 = middle$rhs_tau0, zeta2 = middle$rhs_zeta2,
    anchor_tau0 = lower$rhs_tau0, innovation_tau0 = middle$rhs_tau0,
    anchor_init_tau = lower$rhs_tau0, innovation_init_tau = middle$rhs_tau0,
    anchor_zeta2 = lower$rhs_zeta2, innovation_zeta2 = middle$rhs_zeta2,
    slab_fixed = TRUE, a_sigma = controls$a_sigma, b_sigma = controls$b_sigma,
    alpha_prior_mean = alpha_prior_mean, alpha_prior_sd = alpha_prior_sd,
    alpha_min_spacing = controls$alpha_min_spacing,
    max_dense_dim = controls$max_dense_dim, rhs_vb_inner = controls$rhs_vb_inner,
    rhs_freeze_iters = controls$rhs_freeze_iters, init = joint_init)
  joint_ex_init <- app_joint_pht7_stack(exal, rhs_state = joint_al$rhs_state)
  joint_exal <- app_joint_exqdesn_fit_vb_dispatch(
    method_id = controls$exal_vb_method,
    y = design$y[design$train_local], Z = design$Z[design$train_local, , drop = FALSE],
    tau = contract$tau, max_iter = controls$quantile_max_iter, tol = controls$vb_tolerance,
    kappa = 1, tau0 = middle$rhs_tau0, zeta2 = middle$rhs_zeta2,
    anchor_tau0 = lower$rhs_tau0, innovation_tau0 = middle$rhs_tau0,
    anchor_zeta2 = lower$rhs_zeta2, innovation_zeta2 = middle$rhs_zeta2,
    slab_fixed = TRUE, a_sigma = controls$a_sigma, b_sigma = controls$b_sigma,
    alpha_prior_mean = alpha_prior_mean, alpha_prior_sd = alpha_prior_sd,
    alpha_min_spacing = controls$alpha_min_spacing,
    gamma_init = app_joint_qdesn_gamma_init_for_policy(contract$tau,
      list(gamma_init_policy = controls$gamma_init_policy)),
    max_dense_dim = controls$max_dense_dim, rhs_vb_inner = controls$rhs_vb_inner,
    rhs_freeze_iters = controls$rhs_freeze_iters, diagnostic_stride = 20L,
    quadrature_nodes = c(4L, 8L, 12L), quadrature_tolerance = 1e-5,
    init = joint_ex_init)
  list(packet = list(
      independent_qdesn_rhs = lapply(al, app_joint_shared_quantile_compact_fit),
      independent_exqdesn_rhs = lapply(exal, app_joint_shared_quantile_compact_fit),
      joint_qdesn_rhs = app_joint_shared_quantile_compact_fit(joint_al),
      joint_exqdesn_rhs = app_joint_shared_quantile_compact_fit(joint_exal),
      normal_by_tau = normals, prior_profile = profile,
      joint_prior = data.frame(anchor_tau0 = lower$rhs_tau0,
        innovation_tau0 = middle$rhs_tau0, anchor_zeta2 = lower$rhs_zeta2,
        innovation_zeta2 = middle$rhs_zeta2, stringsAsFactors = FALSE)),
    design = design)
}

app_joint_pht7_run_vb <- function(root, worker_id = 1L) {
  root <- normalizePath(root, mustWork = TRUE)
  if (as.integer(worker_id) != 1L) stop("V7 has exactly one VB packet worker.", call. = FALSE)
  out <- app_joint_pht7_worker_dir(root, "vb", 1L)
  if (file.exists(file.path(out, "DONE"))) return(invisible(out))
  tmp <- paste0(out, ".tmp_", Sys.getpid()); unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp); started <- Sys.time(); set.seed(72611001L)
  captured <- tryCatch(app_joint_sw_capture_warnings(function()
    app_joint_pht7_fit_vb_packet(root)), error = function(e) e)
  if (inherits(captured, "error")) {
    app_ensure_dir(out); app_write_csv(data.frame(error_message = conditionMessage(captured)),
      file.path(out, "failure.csv")); writeLines("failed", file.path(out, "FAILED"))
    stop(conditionMessage(captured), call. = FALSE)
  }
  packet <- captured$value$packet
  components <- c(packet$independent_qdesn_rhs, packet$independent_exqdesn_rhs,
    list(packet$joint_qdesn_rhs, packet$joint_exqdesn_rhs))
  model <- c(rep("independent_qdesn_rhs", 7L), rep("independent_exqdesn_rhs", 7L),
    "joint_qdesn_rhs", "joint_exqdesn_rhs")
  tau <- c(app_joint_pht7_read_contract()$tau, app_joint_pht7_read_contract()$tau,
    NA_real_, NA_real_)
  summary <- data.frame(component_id = seq_along(components), model_id = model, tau = tau,
    finite_output = vapply(components, function(x) all(is.finite(c(x$beta_mean,
      x$alpha_mean, x$sigma_mean, x$gamma_mean %||% numeric()))) && all(x$sigma_mean > 0),
      logical(1L)), converged = vapply(components, function(x) isTRUE(x$converged), logical(1L)),
    inference_method_id = vapply(components, function(x) x$inference_method_id %||%
      if (is.null(x$gamma_mean)) "AL_VB" else "VB1_structured_v", character(1L)),
    protected_rows_used_for_fit = 0L, protected_scores_computed = FALSE,
    warning_count = length(captured$warnings),
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    stringsAsFactors = FALSE)
  if (nrow(summary) != 16L || any(!summary$finite_output)) {
    stop("V7 quantile VB packet is incomplete or nonfinite.", call. = FALSE)
  }
  normal_finite <- all(vapply(packet$normal_by_tau, function(x) all(is.finite(c(
    x$initializer$beta_mean, x$initializer$alpha_mean, x$initializer$sigma_mean))), logical(1L)))
  normal <- data.frame(component_id = 0L, model_id = "gaussian_rhs_initializer", tau = NA_real_,
    finite_output = normal_finite,
    converged = all(vapply(packet$normal_by_tau, function(x) isTRUE(x$rhs_converged), logical(1L))),
    inference_method_id = "level_specific_gaussian_rhs_vb",
    protected_rows_used_for_fit = 0L, protected_scores_computed = FALSE,
    warning_count = length(captured$warnings),
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    stringsAsFactors = FALSE)
  summary <- rbind(normal, summary)
  if (nrow(summary) != app_joint_pht7_read_contract()$expected_components ||
      any(!summary$finite_output)) stop("V7 17-component VB gate failed.", call. = FALSE)
  packet_path <- file.path(tmp, "vb_packet.rds")
  saveRDS(packet, packet_path, version = 3L, compress = "xz")
  warnings <- data.frame(warning_index = seq_along(captured$warnings),
    warning_message = as.character(captured$warnings), stringsAsFactors = FALSE)
  files <- c(summary = app_write_csv(summary, file.path(tmp, "summary.csv")),
    packet = packet_path, warnings = app_write_csv(warnings, file.path(tmp, "warnings.csv")))
  app_joint_shared_write_manifest(tmp, files)
  if (!all(app_joint_shared_verify_manifest(tmp,
      file.path(tmp, "artifact_manifest.csv"))$verified)) stop("V7 VB manifest failed.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE")); if (dir.exists(out)) unlink(out, recursive = TRUE)
  if (!file.rename(tmp, out)) stop("Could not publish V7 VB packet.", call. = FALSE)
  invisible(out)
}

app_joint_pht7_health <- function(root, stage) {
  plan_name <- switch(stage, vb = "vb_worker_plan.csv", mcmc = "mcmc_worker_plan.csv",
    score = "score_worker_plan.csv", stop("Unknown V7 stage.", call. = FALSE))
  id <- switch(stage, vb = "vb_worker_id", mcmc = "worker_id", score = "score_worker_id")
  plan_path <- if (stage == "score") file.path(root, "full_confirmation", "score_packet", plan_name) else
    file.path(root, "full_confirmation", plan_name)
  if (!file.exists(plan_path)) return(data.frame(stage = stage, expected = 0L, completed = 0L,
    failed = 0L, remaining = 0L, status = "not_prepared", stringsAsFactors = FALSE))
  plan <- app_read_csv(plan_path)
  dirs <- if (stage == "score") vapply(plan[[id]], function(x)
    app_joint_swscore_cell_dir(root, x), character(1L)) else vapply(plan[[id]], function(x)
      app_joint_pht7_worker_dir(root, stage, x), character(1L))
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  data.frame(stage = stage, expected = nrow(plan), completed = sum(done), failed = sum(failed),
    remaining = sum(!done & !failed), status = if (any(failed)) "failed" else if (all(done))
      "complete" else if (any(done)) "running" else "ready", stringsAsFactors = FALSE)
}

app_joint_pht7_model_metadata <- function(model_id) {
  data.frame(model_id = model_id,
    fit_structure = if (startsWith(model_id, "joint_")) "joint" else "independent",
    likelihood_family = if (grepl("exqdesn", model_id, fixed = TRUE)) "exAL" else "AL",
    stringsAsFactors = FALSE)
}

app_joint_pht7_finalize_vb <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pht7_read_contract(
    file.path(root, "frozen_contract.csv"))
  health <- app_joint_pht7_health(root, "vb")
  if (health$completed != 1L || health$failed != 0L) stop("V7 VB is incomplete.", call. = FALSE)
  worker <- app_joint_pht7_worker_dir(root, "vb", 1L)
  verified <- app_joint_shared_verify_manifest(worker, file.path(worker, "artifact_manifest.csv"))
  if (!nrow(verified) || any(!verified$verified)) stop("V7 VB manifest is not verified.", call. = FALSE)
  summary <- app_read_csv(file.path(worker, "summary.csv"))
  if (nrow(summary) != contract$expected_components || any(!summary$finite_output) ||
      any(summary$protected_rows_used_for_fit != 0L) ||
      any(app_as_bool_vec(summary$protected_scores_computed))) stop("V7 VB gate failed.", call. = FALSE)
  model_rows <- lapply(seq_along(contract$model_ids), function(i) {
    meta <- app_joint_pht7_model_metadata(contract$model_ids[[i]])
    data.frame(cell_index = i, scenario_id = contract$scenario_id,
      specification_role = "v6_candidate", candidate_id = contract$candidate_id,
      model_id = meta$model_id, fit_structure = meta$fit_structure,
      likelihood_family = meta$likelihood_family,
      model_cell_id = paste(contract$scenario_id, "v6_candidate", meta$model_id, sep = "__"),
      vb_packet_path = file.path(worker, "vb_packet.rds"),
      design_path = file.path(root, "full_confirmation", "design.rds"),
      fixture_path = file.path(root, "full_confirmation", "article_fixture.rds"),
      stringsAsFactors = FALSE)
  })
  cells <- app_bind_rows_fill(model_rows)
  workers <- app_bind_rows_fill(lapply(seq_len(nrow(cells)), function(i) {
    app_bind_rows_fill(lapply(seq_len(contract$chains_per_cell), function(chain_id) {
      row <- cells[i, , drop = FALSE]; exal <- row$likelihood_family == "exAL"
      row$chain_id <- chain_id
      row$chain_seed <- as.integer(92611000L + i * 100000L + chain_id * 10000L)
      row$chain_start_seed <- as.integer(102611000L + i * 100000L + chain_id * 10000L)
      row$n_iter <- if (exal) contract$exal_n_iter else contract$al_n_iter
      row$burn <- if (exal) contract$exal_burn else contract$al_burn
      row$thin <- if (exal) contract$exal_thin else contract$al_thin
      row$n_keep <- as.integer((row$n_iter - row$burn) / row$thin)
      row$tau_seed_stride <- 1009L
      row$inference_method_id <- if (exal) contract$exal_method else "AL_MCMC"
      row
    }))
  }))
  workers$worker_id <- seq_len(nrow(workers))
  if (nrow(cells) != 4L || nrow(workers) != 12L || anyDuplicated(workers$chain_seed) ||
      any(workers$likelihood_family == "exAL" & workers$inference_method_id != contract$exal_method)) {
    stop("V7 MCMC plan is malformed.", call. = FALSE)
  }
  out <- file.path(root, "full_confirmation"); app_ensure_dir(file.path(out, "mcmc_workers"))
  cells_path <- app_write_csv(cells, file.path(out, "model_cell_plan.csv"))
  workers_path <- app_write_csv(workers, file.path(out, "mcmc_worker_plan.csv"))
  summary_path <- app_write_csv(summary, file.path(out, "vb_summary.csv"))
  readiness <- data.frame(status = "V7_VB_COMPLETE_MCMC_READY_NOT_LAUNCHED",
    vb_components = nrow(summary), model_cells = nrow(cells), mcmc_workers = nrow(workers),
    protected_scores_computed = FALSE, stringsAsFactors = FALSE)
  readiness_path <- app_write_csv(readiness, file.path(out, "mcmc_readiness.csv"))
  app_joint_shared_write_manifest(out, c(vb_summary = summary_path, cells = cells_path,
    workers = workers_path, readiness = readiness_path), filename = "vb_final_manifest.csv")
  readiness
}

app_joint_pht7_target_contract <- function(row, packet, design) {
  profile <- packet$prior_profile[order(packet$prior_profile$tau), , drop = FALSE]
  joint <- packet$joint_prior[1L, , drop = FALSE]
  fields <- data.frame(field = c("contract_version", "scenario_id", "candidate_id",
    "model_id", "likelihood_family", "fit_structure", "design_fingerprint",
    "quantile_grid", "level_tau0", "level_zeta2", "anchor_tau0", "innovation_tau0",
    "anchor_zeta2", "innovation_zeta2", "a_sigma", "b_sigma", "sigma_support",
    "coefficient_hierarchy", "ordered_intercepts", "exal_method"), value = c(
      "joint_qdesn_persistent_tail_v7_target_v1", row$scenario_id[[1L]],
      row$candidate_id[[1L]], row$model_id[[1L]], row$likelihood_family[[1L]],
      row$fit_structure[[1L]], design$posterior_data_design_fingerprint,
      paste(format(design$tau, digits = 17), collapse = ";"),
      paste(format(profile$rhs_tau0, digits = 17, scientific = TRUE), collapse = ";"),
      paste(format(profile$rhs_zeta2, digits = 17, scientific = TRUE), collapse = ";"),
      if (row$fit_structure[[1L]] == "joint") format(joint$anchor_tau0, digits = 17,
        scientific = TRUE) else "NA",
      if (row$fit_structure[[1L]] == "joint") format(joint$innovation_tau0, digits = 17,
        scientific = TRUE) else "NA",
      if (row$fit_structure[[1L]] == "joint") format(joint$anchor_zeta2, digits = 17,
        scientific = TRUE) else "NA",
      if (row$fit_structure[[1L]] == "joint") format(joint$innovation_zeta2, digits = 17,
        scientific = TRUE) else "NA", "2", "1", "(0,Inf)",
      if (row$fit_structure[[1L]] == "joint")
        "first_quantile_anchor_adjacent_differences" else "independent_quantile_specific_rhs",
      tolower(as.character(row$fit_structure[[1L]] == "joint")),
      if (row$likelihood_family[[1L]] == "exAL")
        app_joint_pht7_read_contract()$exal_method else "NA"), stringsAsFactors = FALSE)
  canonical <- paste(paste(fields$field, fields$value, sep = "="), collapse = "\n")
  list(fields = fields, hash = app_joint_qvp_sha256_text(canonical))
}

app_joint_pht7_sampler_contract <- function(row) {
  fields <- data.frame(field = c("contract_version", "model_id", "likelihood_family",
    "fit_structure", "inference_method_id", "scale_update_id", "n_iter", "burn", "thin",
    "sigma_support", "precision_repair", "tau_seed_stride"), value = c(
      "joint_qdesn_persistent_tail_v7_sampler_v1", row$model_id[[1L]],
      row$likelihood_family[[1L]], row$fit_structure[[1L]], row$inference_method_id[[1L]],
      if (row$likelihood_family[[1L]] == "exAL") "exact_M0_v_collapsed_scale_shape" else
        "direct_inverse_gamma_unbounded_v1", row$n_iter[[1L]], row$burn[[1L]],
      row$thin[[1L]], "(0,Inf)", "true",
      if (row$fit_structure[[1L]] == "independent") row$tau_seed_stride[[1L]] else "NA"),
    stringsAsFactors = FALSE)
  canonical <- paste(paste(fields$field, fields$value, sep = "="), collapse = "\n")
  list(fields = fields, hash = app_joint_qvp_sha256_text(canonical))
}

app_joint_pht7_mcmc_fit <- function(row, packet, design, init) {
  controls <- app_joint_swq_controls(app_joint_sw_read_contract())
  profile <- packet$prior_profile[order(packet$prior_profile$tau), , drop = FALSE]
  normals <- packet$normal_by_tau
  alpha_mean <- vapply(seq_along(design$tau), function(k)
    normals[[k]]$initializer$alpha_mean[[k]], numeric(1L))
  alpha_sd <- vapply(normals, function(x) x$initializer$alpha_prior_sd, numeric(1L))
  common <- list(y = design$y[design$train_local],
    Z = design$Z[design$train_local, , drop = FALSE], tau = design$tau,
    n_iter = as.integer(row$n_iter[[1L]]), burn = as.integer(row$burn[[1L]]),
    thin = as.integer(row$thin[[1L]]), seed = as.integer(row$chain_seed[[1L]]),
    kappa = 1, a_sigma = controls$a_sigma, b_sigma = controls$b_sigma,
    alpha_prior_mean = alpha_mean, alpha_prior_sd = alpha_sd,
    alpha_min_spacing = if (row$fit_structure[[1L]] == "joint")
      controls$alpha_min_spacing else 0, max_dense_dim = 0L,
    sigma_bounds = c(0, Inf), init = init)
  common <- c(common, app_joint_article_mcmc_precision_repair_controls())
  exal <- row$likelihood_family[[1L]] == "exAL"
  joint <- row$fit_structure[[1L]] == "joint"
  if (joint) {
    jp <- packet$joint_prior[1L, , drop = FALSE]
    common$tau0 <- jp$innovation_tau0; common$zeta2 <- jp$innovation_zeta2
    common$anchor_tau0 <- jp$anchor_tau0; common$innovation_tau0 <- jp$innovation_tau0
    common$anchor_zeta2 <- jp$anchor_zeta2; common$innovation_zeta2 <- jp$innovation_zeta2
    common$slab_fixed <- TRUE
    if (exal) {
      common$gamma_init <- init$gamma_mean; common$gamma_slice_width <- 1
      common$gamma_slice_max_steps <- 100L
      return(do.call(app_joint_exqdesn_fit_mcmc_dispatch,
        c(list(method_id = app_joint_pht7_read_contract()$exal_method), common)))
    }
    return(do.call(app_joint_qvp_fit_al_mcmc_tiny, common))
  }
  fits <- lapply(seq_along(design$tau), function(k) {
    one <- common; one$tau <- design$tau[[k]]
    one$seed <- as.integer(row$chain_seed[[1L]] + k * row$tau_seed_stride[[1L]])
    one$tau0 <- profile$rhs_tau0[[k]]; one$zeta2 <- profile$rhs_zeta2[[k]]
    one$slab_fixed <- TRUE; one$alpha_prior_mean <- alpha_mean[[k]]
    one$alpha_prior_sd <- alpha_sd[[k]]; one$alpha_min_spacing <- 0
    one$init <- init$fits[[k]]
    if (exal) {
      one$gamma_init <- init$fits[[k]]$gamma_mean; one$gamma_slice_width <- 1
      one$gamma_slice_max_steps <- 100L
      return(do.call(app_joint_exqdesn_fit_mcmc_dispatch,
        c(list(method_id = app_joint_pht7_read_contract()$exal_method), one)))
    }
    do.call(app_joint_qvp_fit_al_mcmc_tiny, one)
  })
  app_joint_qdesn_phase122_combine_independent_chain(fits,
    design$Z[design$train_local, , drop = FALSE], design$tau,
    row$chain_id[[1L]], row$chain_seed[[1L]])
}

app_joint_pht7_run_mcmc <- function(root, worker_id) {
  root <- normalizePath(root, mustWork = TRUE); plan <- app_read_csv(file.path(root,
    "full_confirmation", "mcmc_worker_plan.csv"))
  row <- plan[plan$worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("V7 MCMC worker is not unique.", call. = FALSE)
  out <- app_joint_pht7_worker_dir(root, "mcmc", worker_id)
  if (file.exists(file.path(out, "DONE"))) return(invisible(out))
  tmp <- paste0(out, ".tmp_", Sys.getpid()); unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp); started <- Sys.time()
  design <- readRDS(row$design_path[[1L]]); packet <- readRDS(row$vb_packet_path[[1L]])
  init <- app_joint_swcf_packet_init(packet, row$model_id[[1L]])
  init <- app_joint_article_overdispersed_start(init, row, design$tau)
  target <- app_joint_pht7_target_contract(row, packet, design)
  sampler <- app_joint_pht7_sampler_contract(row)
  captured <- tryCatch(app_joint_sw_capture_warnings(function()
    app_joint_pht7_mcmc_fit(row, packet, design, init)), error = function(e) e)
  if (inherits(captured, "error")) {
    app_ensure_dir(out); app_write_csv(cbind(row, data.frame(
      error_message = conditionMessage(captured), stringsAsFactors = FALSE)),
      file.path(out, "failure.csv")); writeLines("failed", file.path(out, "FAILED"))
    stop(conditionMessage(captured), call. = FALSE)
  }
  fit <- captured$value; draws <- app_joint_article_draw_frame(fit)
  if (nrow(draws) != row$n_keep[[1L]] ||
      any(!is.finite(as.matrix(draws[, -1L, drop = FALSE])))) {
    stop("V7 MCMC retained draws violate the frozen budget.", call. = FALSE)
  }
  qhat <- app_joint_qdesn_predict_fit(fit, design$Z[design$train_local, , drop = FALSE], design$tau)
  crossing <- app_joint_qdesn_apply_monotone_contract(qhat, design$tau)
  summary <- data.frame(worker_id = row$worker_id, model_cell_id = row$model_cell_id,
    scenario_id = row$scenario_id, candidate_id = row$candidate_id, model_id = row$model_id,
    fit_structure = row$fit_structure, likelihood_family = row$likelihood_family,
    chain_id = row$chain_id, chain_seed = row$chain_seed,
    chain_start_seed = row$chain_start_seed, n_iter = row$n_iter, burn = row$burn,
    thin = row$thin, n_keep = nrow(draws),
    inference_method_id = fit$inference_method_id %||% row$inference_method_id,
    finite_draws = TRUE,
    fit_raw_crossing_pairs = sum(crossing$raw_crossing$n_crossing_pairs),
    fit_contract_crossing_pairs = sum(crossing$contract_crossing$n_crossing_pairs),
    precision_repair_count = as.integer(fit$precision_repair_count %||% 0L),
    complete_posterior_target_sha256 = target$hash,
    effective_sampler_control_sha256 = sampler$hash, sigma_support = "(0,Inf)",
    sigma_update_id = fit$sigma_update_id %||% if (row$likelihood_family[[1L]] == "exAL")
      "exact_M0_v_collapsed_scale_shape" else "direct_inverse_gamma_unbounded_v1",
    warning_count = length(captured$warnings), protected_scores_computed = FALSE,
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    stringsAsFactors = FALSE)
  warnings <- data.frame(warning_index = seq_along(captured$warnings),
    warning_message = as.character(captured$warnings), stringsAsFactors = FALSE)
  precision <- fit$precision_repair_diagnostics %||% data.frame()
  files <- c(posterior_draws = app_joint_article_write_gzip_csv(draws,
      file.path(tmp, "posterior_draws.csv.gz")),
    summary = app_write_csv(summary, file.path(tmp, "summary.csv")),
    target = app_write_csv(target$fields, file.path(tmp, "complete_posterior_target_contract.csv")),
    sampler = app_write_csv(sampler$fields, file.path(tmp, "effective_sampler_control_contract.csv")),
    warnings = app_write_csv(warnings, file.path(tmp, "warnings.csv")),
    precision = app_write_csv(precision, file.path(tmp, "precision_repair_diagnostics.csv")))
  app_joint_shared_write_manifest(tmp, files)
  if (!all(app_joint_shared_verify_manifest(tmp,
      file.path(tmp, "artifact_manifest.csv"))$verified)) stop("V7 MCMC manifest failed.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE")); if (dir.exists(out)) unlink(out, recursive = TRUE)
  if (!file.rename(tmp, out)) stop("Could not publish V7 MCMC worker.", call. = FALSE)
  invisible(out)
}

app_joint_pht7_finalize_mcmc <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pht7_read_contract(
    file.path(root, "frozen_contract.csv")); health <- app_joint_pht7_health(root, "mcmc")
  if (health$completed != 12L || health$failed != 0L) stop("V7 MCMC is incomplete.", call. = FALSE)
  plan <- app_read_csv(file.path(root, "full_confirmation", "mcmc_worker_plan.csv"))
  summaries <- app_bind_rows_fill(lapply(plan$worker_id, function(id) {
    worker <- app_joint_pht7_worker_dir(root, "mcmc", id)
    verified <- app_joint_shared_verify_manifest(worker, file.path(worker, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified)) stop("V7 MCMC worker manifest failed.", call. = FALSE)
    app_read_csv(file.path(worker, "summary.csv"))
  }))
  if (nrow(summaries) != 12L || any(!summaries$finite_draws) ||
      any(summaries$fit_contract_crossing_pairs != 0L) ||
      any(summaries$likelihood_family == "exAL" &
        summaries$inference_method_id != contract$exal_method) ||
      any(app_as_bool_vec(summaries$protected_scores_computed))) {
    stop("V7 MCMC scientific gate failed.", call. = FALSE)
  }
  identity <- app_joint_swcf_chain_identity_audit(summaries,
    expected_chains = contract$chains_per_cell)
  out <- app_joint_swscore_root(root); app_ensure_dir(file.path(out, "cells"))
  oracle <- file.path(out, "oracle_banks", paste0(contract$scenario_id, ".rds"))
  if (app_sha256_file(oracle) != contract$oracle_bank_sha256) {
    stop("V7 frozen oracle bank hash changed.", call. = FALSE)
  }
  cells <- app_read_csv(file.path(root, "full_confirmation", "model_cell_plan.csv"))
  score <- app_bind_rows_fill(lapply(seq_len(nrow(cells)), function(i) {
    app_bind_rows_fill(lapply(c("vb", "mcmc"), function(method) {
      row <- cells[i, , drop = FALSE]; row$inference_method <- method
      row$score_seed <- as.integer(112611000L + i * 10000L + if (method == "mcmc") 5000L else 0L)
      row$state_seed <- row$score_seed + 1009L; row$uniform_seed <- row$score_seed + 2018L
      row
    }))
  }))
  score$score_worker_id <- seq_len(nrow(score))
  if (nrow(score) != 8L || anyDuplicated(score[, c("model_cell_id", "inference_method")])) {
    stop("V7 score plan is malformed.", call. = FALSE)
  }
  contract_path <- app_write_csv(app_joint_swscore_contract(), file.path(out, "score_contract.csv"))
  summary_path <- app_write_csv(summaries, file.path(out, "mcmc_worker_summary.csv"))
  identity_path <- app_write_csv(identity, file.path(out, "complete_chain_identity_audit.csv"))
  score_path <- app_write_csv(score, file.path(out, "score_worker_plan.csv"))
  readiness <- data.frame(status = "V7_MCMC_COMPLETE_SCORE_READY_NOT_LAUNCHED",
    mcmc_workers = nrow(summaries), compatible_model_cells = nrow(identity),
    score_workers = nrow(score), oracle_reused_by_hash = TRUE, stringsAsFactors = FALSE)
  readiness_path <- app_write_csv(readiness, file.path(out, "score_launch_readiness.csv"))
  app_joint_shared_write_manifest(out, c(contract = contract_path, mcmc = summary_path,
    identities = identity_path, score_plan = score_path, oracle = oracle,
    readiness = readiness_path), filename = "score_prepare_manifest.csv")
  readiness
}

app_joint_pht7_run_score <- function(root, worker_id) {
  app_joint_swscore_run_cell(root, worker_id)
}

app_joint_pht7_interval_overlap <- function(a_lo, a_hi, b_lo, b_hi) {
  as.numeric(a_lo) <= as.numeric(b_hi) && as.numeric(b_lo) <= as.numeric(a_hi)
}

app_joint_pht7_finalize_score <- function(root) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pht7_read_contract(
    file.path(root, "frozen_contract.csv")); out <- app_joint_swscore_root(root)
  health <- app_joint_pht7_health(root, "score")
  if (health$completed != 8L || health$failed != 0L) stop("V7 scores are incomplete.", call. = FALSE)
  plan <- app_read_csv(file.path(out, "score_worker_plan.csv"))
  summaries <- app_bind_rows_fill(lapply(plan$score_worker_id, function(id) {
    worker <- app_joint_swscore_cell_dir(root, id)
    verified <- app_joint_shared_verify_manifest(worker, file.path(worker, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified)) stop("V7 score manifest failed.", call. = FALSE)
    app_read_csv(file.path(worker, "summary.csv"))
  }))
  required <- c("posterior_score_mean", "posterior_score_q025", "posterior_score_q975",
    "canonical_origin_marginal_dgp_integrated_acrps", "fit_oracle_quantile_mae")
  if (nrow(summaries) != 8L || any(!is.finite(as.matrix(summaries[required]))) ||
      any(summaries$canonical_contract_crossing_pairs != 0L)) {
    stop("V7 score packet violates the final functional gate.", call. = FALSE)
  }
  candidate <- summaries[summaries$inference_method == "mcmc", , drop = FALSE]
  authority <- app_read_csv(file.path(root, "frozen_authority_comparator.csv"))
  comparison <- app_bind_rows_fill(lapply(contract$model_ids, function(model_id) {
    left <- candidate[candidate$model_id == model_id, , drop = FALSE]
    right <- authority[authority$model_id == model_id, , drop = FALSE]
    if (nrow(left) != 1L || nrow(right) != 1L) stop("V7 comparison pair is malformed.", call. = FALSE)
    data.frame(scenario_id = contract$scenario_id, model_id = model_id,
      likelihood_family = left$likelihood_family, fit_structure = left$fit_structure,
      candidate_mean = left$posterior_score_mean, authority_mean = right$posterior_score_mean,
      candidate_minus_authority = left$posterior_score_mean - right$posterior_score_mean,
      relative_improvement = (right$posterior_score_mean - left$posterior_score_mean) /
        right$posterior_score_mean,
      candidate_q025 = left$posterior_score_q025, candidate_q975 = left$posterior_score_q975,
      authority_q025 = right$posterior_score_q025, authority_q975 = right$posterior_score_q975,
      marginal_intervals_overlap = app_joint_pht7_interval_overlap(left$posterior_score_q025,
        left$posterior_score_q975, right$posterior_score_q025, right$posterior_score_q975),
      practically_noninferior = left$posterior_score_mean <=
        right$posterior_score_mean * (1 + contract$practical_margin),
      candidate_fit_mae = left$fit_oracle_quantile_mae,
      authority_fit_mae = right$fit_oracle_quantile_mae,
      score_rank_rhat = left$score_rank_rhat,
      score_folded_rhat = left$score_folded_rhat,
      score_tail_ess = left$score_tail_ess,
      functional_pathology = (!is.na(left$score_rank_rhat) && left$score_rank_rhat > 1.25) ||
        (!is.na(left$score_folded_rhat) && left$score_folded_rhat > 1.25) ||
        (!is.na(left$score_tail_ess) && left$score_tail_ess < 50),
      contract_crossing_pairs = left$canonical_contract_crossing_pairs,
      stringsAsFactors = FALSE)
  }))
  promote <- any(comparison$candidate_minus_authority < 0) &&
    all(comparison$practically_noninferior) && !any(comparison$functional_pathology) &&
    all(comparison$contract_crossing_pairs == 0L)
  decision <- data.frame(status = "V7_COMPLETE_FOUR_MODEL_PACKET_CLOSED",
    scenario_id = contract$scenario_id, candidate_id = contract$candidate_id,
    target_models_improved = sum(comparison$candidate_minus_authority < 0),
    all_four_practically_noninferior = all(comparison$practically_noninferior),
    functional_pathology_any = any(comparison$functional_pathology),
    promote_complete_candidate_packet = promote,
    decision = if (promote) "promote_v6_candidate_complete_packet" else
      "retain_current_authority_complete_packet",
    interval_overlap_is_equivalence = FALSE, article_assets_modified = FALSE,
    stringsAsFactors = FALSE)
  summary_path <- app_write_csv(summaries, file.path(out, "v7_score_summary.csv"))
  comparison_path <- app_write_csv(comparison, file.path(out, "v7_authority_comparison.csv"))
  decision_path <- app_write_csv(decision, file.path(out, "v7_final_decision.csv"))
  app_joint_shared_write_manifest(out, c(summary = summary_path, comparison = comparison_path,
    decision = decision_path), filename = "v7_score_final_manifest.csv")
  decision
}

app_joint_pht7_transfer_inventory <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  files <- list.files(root, recursive = TRUE, full.names = TRUE, all.files = FALSE)
  files <- files[file.info(files)$isdir %in% FALSE]
  files <- files[basename(files) != "transfer_inventory.csv"]
  relative <- substring(files, nchar(root) + 2L)
  inventory <- data.frame(relative_path = relative, size_bytes = file.info(files)$size,
    sha256 = vapply(files, app_sha256_file, character(1L)), stringsAsFactors = FALSE)
  app_write_csv(inventory, file.path(root, "transfer_inventory.csv"))
  inventory
}

app_joint_pht7_check <- function(root = app_joint_pht7_default_root()) {
  root <- normalizePath(root, mustWork = TRUE); contract <- app_joint_pht7_read_contract(
    file.path(root, "frozen_contract.csv"))
  prep <- app_joint_shared_verify_manifest(root, file.path(root, "preparation_manifest.csv"))
  if (!nrow(prep) || any(!prep$verified)) stop("V7 preparation manifest failed.", call. = FALSE)
  health <- app_bind_rows_fill(lapply(c("vb", "mcmc", "score"), function(stage)
    app_joint_pht7_health(root, stage)))
  data.frame(contract_version = contract$version, scenario_id = contract$scenario_id,
    candidate_id = contract$candidate_id, expected_vb = health$expected[health$stage == "vb"],
    completed_vb = health$completed[health$stage == "vb"],
    expected_mcmc = health$expected[health$stage == "mcmc"],
    completed_mcmc = health$completed[health$stage == "mcmc"],
    expected_score = health$expected[health$stage == "score"],
    completed_score = health$completed[health$stage == "score"],
    failures = sum(health$failed), stringsAsFactors = FALSE)
}
