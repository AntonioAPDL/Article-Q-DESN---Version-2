# Fixed-architecture joint-prior calibration for the persistent-heavy-tail case.

app_joint_pht8_contract_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_v8_contract.csv")
}

app_joint_pht8_default_root <- function() {
  app_path("application/cache/joint_qdesn_persistent_tail_v8_joint_prior_calibration_20261126")
}

app_joint_pht8_read_contract <- function(path = app_joint_pht8_contract_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "persistent-tail V8 contract")
  value <- function(name) {
    row <- tab[tab$name == name, , drop = FALSE]
    if (nrow(row) != 1L) stop(sprintf("V8 contract requires one '%s'.", name), call. = FALSE)
    as.character(row$value[[1L]])
  }
  numvec <- function(name) as.numeric(strsplit(value(name), ";", fixed = TRUE)[[1L]])
  bool <- function(name) identical(tolower(value(name)), "true")
  out <- list(table = tab, version = value("contract_version"), run_tag = value("run_tag"),
    execution_branch = value("execution_branch"), v7_parent_head = value("v7_parent_head"),
    v6_decision_sha256 = value("v6_decision_sha256"),
    v6_finalists_sha256 = value("v6_finalists_sha256"),
    v6_aggregate_sha256 = value("v6_aggregate_sha256"), scenario_id = value("scenario_id"),
    candidate_id = value("candidate_id"), tau = numvec("quantile_grid"),
    weights = numvec("trapezoidal_weights"), anchor_tau0 = numvec("anchor_tau0_values"),
    innovation_tau0 = numvec("innovation_tau0_values"),
    slab_profiles = strsplit(value("slab_profiles"), ";", fixed = TRUE)[[1L]],
    baseline_anchor_tau0 = as.numeric(value("baseline_anchor_tau0")),
    baseline_innovation_tau0 = as.numeric(value("baseline_innovation_tau0")),
    baseline_anchor_zeta2 = as.numeric(value("baseline_anchor_zeta2")),
    baseline_innovation_zeta2 = as.numeric(value("baseline_innovation_zeta2")),
    required_hostname = value("required_hostname"), exal_method = value("exal_method"))
  integers <- c("sentinel_arm_count", "screen_replicates", "fit_frontier_count",
    "qualification_arm_count", "qualification_replicates", "mcmc_replicates",
    "screen_seed_offset", "qualification_seed_offset", "screen_max_iter",
    "qualification_max_iter", "screen_state_draws", "screen_score_draws",
    "qualification_state_draws", "qualification_score_draws", "score_chunk_size",
    "oracle_paths_per_shard", "oracle_max_shards", "chains_per_cell", "al_n_iter",
    "al_burn", "exal_n_iter", "exal_burn", "thin", "max_physical_workers")
  numerics <- c("screen_tolerance", "qualification_tolerance", "oracle_split_tolerance",
    "oracle_analytic_tolerance", "functional_rhat_review", "chain_relative_range_review",
    "min_data_free_gib", "min_available_memory_gib")
  for (name in integers) out[[name]] <- as.integer(value(name))
  for (name in numerics) out[[name]] <- as.numeric(value(name))
  for (name in c("protected_selection_forbidden", "architecture_changes_forbidden",
      "interval_overlap_is_equivalence", "scalar_mixing_is_hard_gate",
      "automatic_downstream_launch")) out[[name]] <- bool(name)
  hashes <- unlist(out[c("v6_decision_sha256", "v6_finalists_sha256",
    "v6_aggregate_sha256")])
  valid <- identical(out$version, "joint_qdesn_persistent_tail_v8_joint_prior_calibration") &&
    identical(out$tau, c(.05, .10, .25, .50, .75, .90, .95)) &&
    abs(sum(out$weights) - .9) < 1e-12 && length(out$anchor_tau0) == 5L &&
    length(out$innovation_tau0) == 7L && length(out$slab_profiles) == 3L &&
    out$sentinel_arm_count == 10L && out$screen_replicates == 3L &&
    out$qualification_replicates == 5L && out$chains_per_cell == 3L &&
    out$exal_method == "M0_v_collapsed_support_logit" &&
    out$protected_selection_forbidden && out$architecture_changes_forbidden &&
    !out$interval_overlap_is_equivalence && !out$scalar_mixing_is_hard_gate &&
    !out$automatic_downstream_launch && all(grepl("^[0-9a-f]{64}$", hashes))
  if (!valid) stop("Persistent-tail V8 contract is malformed.", call. = FALSE)
  out
}

app_joint_pht8_arms <- function(contract = app_joint_pht8_read_contract()) {
  slabs <- data.frame(slab_profile = contract$slab_profiles,
    anchor_zeta2 = c(.01, .01, .1), innovation_zeta2 = c(.01, .1, .1),
    stringsAsFactors = FALSE)
  out <- merge(expand.grid(anchor_tau0 = contract$anchor_tau0,
    innovation_tau0 = contract$innovation_tau0, KEEP.OUT.ATTRS = FALSE), slabs, by = NULL)
  out <- out[order(out$anchor_tau0, out$innovation_tau0, out$slab_profile), , drop = FALSE]
  out$arm_id <- sprintf("v8_prior_%03d", seq_len(nrow(out)))
  out$baseline <- abs(log(out$anchor_tau0 / contract$baseline_anchor_tau0)) < 1e-12 &
    abs(log(out$innovation_tau0 / contract$baseline_innovation_tau0)) < 1e-12 &
    out$anchor_zeta2 == contract$baseline_anchor_zeta2 &
    out$innovation_zeta2 == contract$baseline_innovation_zeta2
  out$sentinel <- out$baseline |
    (out$anchor_tau0 == 1e-7 & out$innovation_tau0 %in% c(1e-11, 1e-9, 1e-7, 1e-5, 1e-3, 1e-1) &
      out$slab_profile == "v7") |
    (out$anchor_tau0 %in% c(1e-9, 1e-5) & out$innovation_tau0 == 1e-7 &
      out$slab_profile == "v7") |
    (out$anchor_tau0 == 1e-7 & out$innovation_tau0 == 1e-7 &
      out$slab_profile == "innovation_wide")
  if (nrow(out) != 105L || sum(out$baseline) != 1L ||
      sum(out$sentinel) != contract$sentinel_arm_count) {
    stop("V8 prior-arm registry cardinality failed.", call. = FALSE)
  }
  out
}

app_joint_pht8_stage_spec <- function(stage) {
  switch(as.character(stage),
    sentinel_context = c(plan = "sentinel_context_plan.csv", id = "worker_id"),
    sentinel = c(plan = "sentinel_plan.csv", id = "worker_id"),
    screen_context = c(plan = "screen_context_plan.csv", id = "worker_id"),
    screen = c(plan = "screen_plan.csv", id = "worker_id"),
    qualification_context = c(plan = "qualification_context_plan.csv", id = "worker_id"),
    qualification = c(plan = "qualification_plan.csv", id = "worker_id"),
    mcmc = c(plan = "mcmc_plan.csv", id = "worker_id"),
    mcmc_score = c(plan = "mcmc_score_plan.csv", id = "worker_id"),
    stop("Unknown V8 stage.", call. = FALSE))
}

app_joint_pht8_worker_dir <- function(root, stage, id) {
  file.path(root, paste0(stage, "_workers"), sprintf("worker_%05d", as.integer(id)))
}

app_joint_pht8_freeze_plan <- function(root, stage, plan) {
  spec <- app_joint_pht8_stage_spec(stage)
  path <- app_write_csv(plan, file.path(root, spec[["plan"]]))
  writeLines(app_sha256_file(path), paste0(path, ".sha256"))
  app_ensure_dir(file.path(root, paste0(stage, "_workers")))
  path
}

app_joint_pht8_verify_plan <- function(root, stage) {
  spec <- app_joint_pht8_stage_spec(stage); path <- file.path(root, spec[["plan"]])
  receipt <- paste0(path, ".sha256")
  if (!file.exists(path) || !file.exists(receipt) ||
      app_sha256_file(path) != trimws(readLines(receipt, warn = FALSE)[[1L]])) {
    stop(sprintf("V8 %s plan hash failed.", stage), call. = FALSE)
  }
  invisible(path)
}

app_joint_pht8_health <- function(root, stage) {
  spec <- app_joint_pht8_stage_spec(stage); path <- file.path(root, spec[["plan"]])
  if (!file.exists(path)) return(data.frame(stage = stage, expected = 0L, completed = 0L,
    disqualified = 0L, failed = 0L, remaining = 0L, status = "not_prepared",
    stringsAsFactors = FALSE))
  app_joint_pht8_verify_plan(root, stage); plan <- app_read_csv(path)
  dirs <- vapply(plan[[spec[["id"]]]], function(id) app_joint_pht8_worker_dir(root, stage, id),
    character(1L))
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  disqualified <- file.exists(file.path(dirs, "DISQUALIFIED")) &
    file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  failed <- failed & !disqualified
  terminal <- done | disqualified | failed
  data.frame(stage = stage, expected = nrow(plan), completed = sum(done), failed = sum(failed),
    disqualified = sum(disqualified), remaining = sum(!terminal), status = if (any(failed))
      "failed" else if (all(terminal) && any(disqualified)) "complete_with_disqualifications"
      else if (all(done)) "complete" else if (any(terminal)) "running" else "ready",
    stringsAsFactors = FALSE)
}

app_joint_pht8_hash_check <- function(path, expected, label) {
  if (!file.exists(path) || app_sha256_file(path) != expected) {
    stop(sprintf("V8 %s hash verification failed.", label), call. = FALSE)
  }
  normalizePath(path, mustWork = TRUE)
}

app_joint_pht8_fixture_plan <- function(contract) {
  panels <- rbind(
    data.frame(panel = "sentinel", replicate_id = 1L,
      seed_offset = contract$screen_seed_offset - 100L),
    data.frame(panel = "screen", replicate_id = seq_len(contract$screen_replicates),
      seed_offset = contract$screen_seed_offset + seq_len(contract$screen_replicates) - 1L),
    data.frame(panel = "qualification", replicate_id = seq_len(contract$qualification_replicates),
      seed_offset = contract$qualification_seed_offset + seq_len(contract$qualification_replicates) - 1L))
  panels$context_id <- seq_len(nrow(panels)); panels
}

app_joint_pht8_internal_oracle_fixture <- function(fixture, selector) {
  end <- max(as.integer(selector$detailed_split$full_time_index))
  if (!is.finite(end) || end <= 0L || end > length(fixture$y)) {
    stop("V8 internal oracle boundary is invalid.", call. = FALSE)
  }
  vector_fields <- c("y", "mu", "sigma", "innovation", "innovation_raw")
  for (name in vector_fields) {
    if (!is.null(fixture[[name]])) fixture[[name]] <- fixture[[name]][seq_len(end)]
  }
  row_fields <- c("true_q", "detailed_split", "Z")
  for (name in row_fields) {
    if (!is.null(fixture[[name]])) {
      fixture[[name]] <- fixture[[name]][seq_len(end), , drop = FALSE]
    }
  }
  if (length(fixture$y) != end || nrow(fixture$true_q) != end ||
      nrow(fixture$detailed_split) != end ||
      any(fixture$detailed_split$role == "validation")) {
    stop("V8 internal oracle fixture retained protected or malformed rows.", call. = FALSE)
  }
  fixture
}

app_joint_pht8_prepare <- function(v6_root, root = app_joint_pht8_default_root()) {
  contract <- app_joint_pht8_read_contract()
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    stop("V8 preparation requires a new empty runtime root.", call. = FALSE)
  }
  sources <- c(v6_decision = app_joint_pht8_hash_check(file.path(v6_root, "v6_decision.csv"),
      contract$v6_decision_sha256, "V6 decision"),
    v6_finalists = app_joint_pht8_hash_check(file.path(v6_root, "frozen_seven_finalists.csv"),
      contract$v6_finalists_sha256, "V6 finalists"),
    v6_aggregate = app_joint_pht8_hash_check(file.path(v6_root, "seven_aggregate.csv"),
      contract$v6_aggregate_sha256, "V6 aggregate"))
  required <- c("frozen_contract.csv", "frozen_registry.csv", "derived_dgp_registry.csv")
  if (!all(file.exists(file.path(v6_root, required)))) stop("V8 V6 foundations are incomplete.", call. = FALSE)
  app_ensure_dir(root); app_ensure_dir(file.path(root, "imported_sources")); app_ensure_dir(file.path(root, "contexts"))
  for (path in c(sources, stats::setNames(file.path(v6_root, required), required))) {
    if (!file.copy(path, file.path(root, "imported_sources", basename(path)), overwrite = FALSE)) {
      stop("V8 could not copy a frozen source.", call. = FALSE)
    }
  }
  finalists <- app_read_csv(sources[["v6_finalists"]])
  candidate <- finalists[finalists$candidate_id == contract$candidate_id, , drop = FALSE]
  if (!nrow(candidate)) stop("V8 candidate is absent from V6 finalists.", call. = FALSE)
  candidate <- candidate[1L, , drop = FALSE]
  if (!app_as_bool_vec(candidate$joint_backend_eligible)) stop("V8 candidate is not joint eligible.", call. = FALSE)
  arms <- app_joint_pht8_arms(contract); fixtures <- app_joint_pht8_fixture_plan(contract)
  registry <- app_read_csv(file.path(root, "imported_sources", "frozen_registry.csv"))
  fixtures$dgp_seed <- as.integer(registry$selector_seed_base[registry$scenario_id == contract$scenario_id][[1L]]) +
    fixtures$seed_offset
  context_plan <- function(panel) {
    x <- fixtures[fixtures$panel == panel, , drop = FALSE]
    data.frame(worker_id = seq_len(nrow(x)), context_id = x$context_id, panel = x$panel,
      replicate_id = x$replicate_id, dgp_seed = x$dgp_seed, stringsAsFactors = FALSE)
  }
  sentinel_context <- context_plan("sentinel"); screen_context <- context_plan("screen")
  sentinel <- merge(expand.grid(context_id = sentinel_context$context_id,
    likelihood_family = c("AL", "exAL"), stringsAsFactors = FALSE),
    arms[arms$sentinel, ], by = NULL)
  sentinel$worker_id <- seq_len(nrow(sentinel))
  screen <- merge(expand.grid(context_id = screen_context$context_id,
    likelihood_family = "AL", stringsAsFactors = FALSE), arms, by = NULL)
  screen$worker_id <- seq_len(nrow(screen))
  if (nrow(sentinel) != 20L || nrow(screen) != 105L * contract$screen_replicates) {
    stop("V8 initial worker-plan cardinality failed.", call. = FALSE)
  }
  files <- c(contract = app_write_csv(contract$table, file.path(root, "frozen_contract.csv")),
    candidate = app_write_csv(candidate, file.path(root, "frozen_candidate.csv")),
    arms = app_write_csv(arms, file.path(root, "frozen_prior_arms.csv")),
    fixtures = app_write_csv(fixtures, file.path(root, "frozen_fixture_seed_plan.csv")),
    sentinel_context = app_joint_pht8_freeze_plan(root, "sentinel_context", sentinel_context),
    sentinel = app_joint_pht8_freeze_plan(root, "sentinel", sentinel),
    screen_context = app_joint_pht8_freeze_plan(root, "screen_context", screen_context),
    screen = app_joint_pht8_freeze_plan(root, "screen", screen),
    source_git_state = app_write_csv(app_joint_shared_git_state(), file.path(root, "source_git_state.csv")))
  source_tab <- data.frame(label = names(sources), source_path = unname(sources),
    sha256 = vapply(sources, app_sha256_file, character(1L)), stringsAsFactors = FALSE)
  files <- c(files, sources = app_write_csv(source_tab, file.path(root, "source_verification.csv")))
  readiness <- data.frame(status = "V8_PREPARED_SENTINEL_CONTEXT_READY",
    prior_arms = nrow(arms), sentinel_workers = nrow(sentinel), screen_workers = nrow(screen),
    protected_rows_used = 0L, article_assets_modified = FALSE, stringsAsFactors = FALSE)
  files <- c(files, readiness = app_write_csv(readiness, file.path(root, "launch_readiness.csv")))
  manifest <- app_joint_shared_write_manifest(root, files, filename = "preparation_manifest.csv")
  verified <- app_joint_shared_verify_manifest(root, manifest)
  if (!nrow(verified) || any(!verified$verified)) stop("V8 preparation manifest failed.", call. = FALSE)
  readiness
}

app_joint_pht8_materialize_fixture <- function(root, row) {
  contract <- app_joint_pht8_read_contract(file.path(root, "frozen_contract.csv"))
  derived <- app_read_csv(file.path(root, "imported_sources", "derived_dgp_registry.csv"))
  dgp <- derived[derived$scenario_id == contract$scenario_id, , drop = FALSE]
  dgp$seed <- as.integer(row$dgp_seed[[1L]])
  dgp$seed_role <- sprintf("persistent_tail_v8_%s_rep%02d", row$panel[[1L]], row$replicate_id[[1L]])
  fixture <- app_joint_qdesn_fixture_from_registry_row(dgp); fixture$registry_row <- dgp
  selector <- app_joint_pure_selector_fixture(fixture,
    app_joint_sw_read_contract(file.path(root, "imported_sources", "frozen_contract.csv")))
  keep <- fixture$detailed_split$role %in% c("desn_washout", "fit")
  selector$mu <- fixture$mu[keep]; selector$sigma <- fixture$sigma[keep]
  if (selector$protected_rows_persisted != 0L || any(selector$detailed_split$role == "validation")) {
    stop("V8 selector fixture contains protected rows.", call. = FALSE)
  }
  list(selector = selector,
    oracle_fixture = app_joint_pht8_internal_oracle_fixture(fixture, selector))
}

app_joint_pht8_internal_forecast_map <- function(design) {
  full_time <- as.integer(design$row_meta$full_time_index[design$calibration_local])
  origin_count <- 10L
  horizon_count <- 30L
  if (length(full_time) != origin_count * horizon_count ||
      any(!is.finite(full_time)) || any(diff(full_time) != 1L)) {
    stop("V8 internal forecast geometry must be 10 contiguous 30-step origins.",
      call. = FALSE)
  }
  data.frame(origin_index = rep(seq_len(origin_count), each = horizon_count),
    horizon = rep(seq_len(horizon_count), times = origin_count),
    full_time_index = full_time, stringsAsFactors = FALSE)
}

app_joint_pht8_fit_context <- function(root, fixtures) {
  contract <- app_joint_pht8_read_contract(file.path(root, "frozen_contract.csv"))
  candidate <- app_read_csv(file.path(root, "frozen_candidate.csv")); base <- app_joint_sw_read_contract()
  design <- app_joint_pure_build_design(fixtures$selector, candidate, base, selector = TRUE)
  if (length(design$train_local) != 1000L || length(design$calibration_local) != 300L ||
      design$diagnostic$protected_rows_loaded != 0L) stop("V8 selector design boundary failed.", call. = FALSE)
  design$forecast_map <- app_joint_pht8_internal_forecast_map(design)
  fixture <- fixtures$oracle_fixture
  if (max(design$forecast_map$full_time_index) > length(fixture$y) ||
      any(fixture$detailed_split$role == "validation")) {
    stop("V8 internal forecast map exceeds its non-protected oracle fixture.", call. = FALSE)
  }
  order <- app_joint_swq_continuation_order(); al <- exal <- normals <- profiles <- list()
  for (ii in seq_len(nrow(order))) {
    tau <- order$tau[[ii]]; key <- sprintf("%.2f", tau)
    level <- app_joint_pht7_level_controls(candidate, tau, base)
    level$controls$quantile_max_iter <- contract$qualification_max_iter
    level$controls$median_max_iter <- contract$qualification_max_iter
    level$controls$vb_tolerance <- contract$qualification_tolerance
    normal <- app_joint_pht3_fit_normal_initializer(design, level$prior, base, level$controls)
    init <- app_joint_swq_single_init(normal, tau, design)
    if (!is.na(order$parent_tau[[ii]])) {
      parent <- al[[sprintf("%.2f", order$parent_tau[[ii]])]]
      init$beta_mean <- parent$beta_mean; init$beta_cov <- parent$beta_cov
    }
    al[[key]] <- app_joint_swq_fit_al(design, normal, level$controls, tau, init,
      level$controls$quantile_max_iter)
    k <- match(tau, design$tau)
    exal[[key]] <- app_joint_exqdesn_fit_vb_dispatch(method_id = level$controls$exal_vb_method,
      y = design$y[design$train_local], Z = design$Z[design$train_local, , drop = FALSE],
      tau = tau, max_iter = level$controls$quantile_max_iter,
      tol = level$controls$vb_tolerance, kappa = 1, tau0 = normal$rhs_tau0,
      zeta2 = normal$initializer$zeta2, slab_fixed = level$controls$rhs_slab_fixed,
      a_sigma = level$controls$a_sigma, b_sigma = level$controls$b_sigma,
      alpha_prior_mean = normal$initializer$alpha_mean[[k]],
      alpha_prior_sd = normal$initializer$alpha_prior_sd, alpha_min_spacing = 0,
      gamma_init = app_joint_qdesn_gamma_init_for_policy(tau,
        list(gamma_init_policy = level$controls$gamma_init_policy)),
      max_dense_dim = max(1000L, level$controls$max_dense_dim),
      rhs_vb_inner = level$controls$rhs_vb_inner,
      rhs_freeze_iters = level$controls$rhs_freeze_iters, diagnostic_stride = 20L,
      quadrature_nodes = c(4L, 8L, 12L), quadrature_tolerance = 1e-5,
      init = app_joint_shared_quantile_reset_init(al[[key]]))
    normals[[key]] <- normal
    profiles[[key]] <- data.frame(tau = tau, rhs_tau0 = level$prior$rhs_tau0,
      rhs_zeta2 = normal$initializer$zeta2, stringsAsFactors = FALSE)
  }
  keys <- sprintf("%.2f", contract$tau)
  list(design = design, fixture = fixture, candidate = candidate,
    independent_al = app_joint_pht7_stack(al[keys]),
    independent_exal = app_joint_pht7_stack(exal[keys]),
    normals = normals[keys], prior_profile = app_bind_rows_fill(profiles[keys]))
}

app_joint_pht8_build_oracle <- function(context, contract, seed) {
  paths <- character(); directory <- tempfile("pht8_oracle_"); dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE, force = TRUE), add = TRUE)
  oracle <- NULL
  for (shard in seq_len(contract$oracle_max_shards)) {
    path <- file.path(directory, sprintf("shard_%02d.rds", shard))
    saveRDS(app_joint_recursive_dgp_shard(context$fixture, context$design$forecast_map,
      contract$oracle_paths_per_shard, as.integer(seed + shard * 1009L)), path)
    paths <- c(paths, path)
    if (shard %% 2L == 0L) {
      oracle <- app_joint_recursive_combine_oracle_shards(paths, context$fixture,
        contract$tau, contract$weights, contract$oracle_analytic_tolerance,
        contract$oracle_split_tolerance)
      if (oracle$diagnostics$status == "pass") break
    }
  }
  if (is.null(oracle) || oracle$diagnostics$status != "pass") {
    detail <- if (is.null(oracle)) "no paired-shard diagnostic" else sprintf(
      "paths=%d split_relative=%.8g analytic_relative=%.8g",
      oracle$n_paths, oracle$diagnostics$split_half_relative_difference[[1L]],
      oracle$diagnostics$horizon1_relative_difference[[1L]])
    stop(sprintf("V8 oracle failed after %d shards: %s.",
      contract$oracle_max_shards, detail), call. = FALSE)
  }
  oracle
}

app_joint_pht8_seal_worker <- function(tmp, out, files) {
  manifest <- app_joint_shared_write_manifest(tmp, files)
  verified <- app_joint_shared_verify_manifest(tmp, manifest)
  if (!nrow(verified) || any(!verified$verified)) stop("V8 worker manifest failed.", call. = FALSE)
  writeLines("completed", file.path(tmp, "DONE"))
  if (dir.exists(out)) unlink(out, recursive = TRUE, force = TRUE)
  if (!file.rename(tmp, out)) stop("V8 worker publication failed.", call. = FALSE)
  invisible(out)
}

app_joint_pht8_run_context <- function(root, stage, worker_id) {
  plan <- app_read_csv(file.path(root, app_joint_pht8_stage_spec(stage)[["plan"]]))
  row <- plan[plan$worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("V8 context worker is not unique.", call. = FALSE)
  out <- app_joint_pht8_worker_dir(root, stage, worker_id)
  if (file.exists(file.path(out, "DONE"))) return(invisible(out))
  tmp <- paste0(out, ".tmp_", Sys.getpid()); unlink(tmp, recursive = TRUE, force = TRUE); app_ensure_dir(tmp)
  started <- Sys.time(); captured <- tryCatch(app_joint_sw_capture_warnings(function() {
    fixtures <- app_joint_pht8_materialize_fixture(root, row)
    context <- app_joint_pht8_fit_context(root, fixtures)
    context$oracle <- app_joint_pht8_build_oracle(context,
      app_joint_pht8_read_contract(file.path(root, "frozen_contract.csv")), row$dgp_seed[[1L]] + 500000L)
    context
  }), error = function(e) e)
  if (inherits(captured, "error")) {
    app_ensure_dir(out); app_write_csv(data.frame(error_message = conditionMessage(captured)),
      file.path(out, "failure.csv")); writeLines("failed", file.path(out, "FAILED")); stop(conditionMessage(captured))
  }
  context <- captured$value
  context_path <- file.path(tmp, "context.rds"); saveRDS(context, context_path, version = 3L, compress = "xz")
  summary <- cbind(row, data.frame(train_rows = length(context$design$train_local),
    calibration_rows = length(context$design$calibration_local), p = ncol(context$design$Z),
    protected_rows_used = context$design$diagnostic$protected_rows_loaded,
    oracle_paths = context$oracle$n_paths, oracle_status = context$oracle$diagnostics$status,
    warning_count = length(captured$warnings), runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    stringsAsFactors = FALSE))
  summary_path <- app_write_csv(summary, file.path(tmp, "summary.csv"))
  oracle_path <- app_write_csv(context$oracle$diagnostics, file.path(tmp, "oracle_diagnostics.csv"))
  app_joint_pht8_seal_worker(tmp, out, c(context = context_path, summary = summary_path,
    oracle = oracle_path))
}

app_joint_pht8_context_path <- function(root, context_id) {
  stages <- c("sentinel_context", "screen_context", "qualification_context")
  for (stage in stages) {
    spec <- app_joint_pht8_stage_spec(stage); path <- file.path(root, spec[["plan"]])
    if (!file.exists(path)) next
    plan <- app_read_csv(path); row <- plan[plan$context_id == as.integer(context_id), , drop = FALSE]
    if (nrow(row) == 1L) {
      out <- app_joint_pht8_worker_dir(root, stage, row$worker_id[[1L]])
      if (!file.exists(file.path(out, "DONE"))) stop("V8 context is incomplete.", call. = FALSE)
      verified <- app_joint_shared_verify_manifest(out, file.path(out, "artifact_manifest.csv"))
      if (!nrow(verified) || any(!verified$verified)) stop("V8 context manifest failed.", call. = FALSE)
      return(file.path(out, "context.rds"))
    }
  }
  stop("V8 context ID is absent.", call. = FALSE)
}

app_joint_pht8_vb_controls <- function(context, arm, contract, stage) {
  base <- app_joint_swq_controls(app_joint_sw_read_contract())
  list(kappa = 1, tau0 = arm$innovation_tau0[[1L]], zeta2 = arm$innovation_zeta2[[1L]],
    anchor_tau0 = arm$anchor_tau0[[1L]], innovation_tau0 = arm$innovation_tau0[[1L]],
    anchor_init_tau = arm$anchor_tau0[[1L]], innovation_init_tau = arm$innovation_tau0[[1L]],
    anchor_zeta2 = arm$anchor_zeta2[[1L]], innovation_zeta2 = arm$innovation_zeta2[[1L]],
    slab_fixed = TRUE, a_sigma = base$a_sigma, b_sigma = base$b_sigma,
    alpha_prior_mean = vapply(seq_along(contract$tau), function(k)
      context$normals[[k]]$initializer$alpha_mean[[k]], numeric(1L)),
    alpha_prior_sd = vapply(context$normals,
      function(x) x$initializer$alpha_prior_sd, numeric(1L)),
    alpha_min_spacing = base$alpha_min_spacing,
    max_dense_dim = max(1000L, base$max_dense_dim), rhs_vb_inner = base$rhs_vb_inner,
    rhs_freeze_iters = base$rhs_freeze_iters,
    max_iter = if (stage == "qualification") contract$qualification_max_iter else contract$screen_max_iter,
    tol = if (stage == "qualification") contract$qualification_tolerance else contract$screen_tolerance)
}

app_joint_pht8_fit_joint_vb <- function(context, arm, family, contract, stage) {
  controls <- app_joint_pht8_vb_controls(context, arm, contract, stage)
  init <- if (family == "AL") context$independent_al else context$independent_exal
  common <- c(list(y = context$design$y[context$design$train_local],
    Z = context$design$Z[context$design$train_local, , drop = FALSE], tau = contract$tau), controls)
  if (family == "AL") {
    return(do.call(app_joint_qvp_fit_al_vb_tiny,
      c(common, list(init = app_joint_shared_quantile_reset_init(init)))))
  }
  do.call(app_joint_exqdesn_fit_vb_dispatch, c(list(method_id = "VB1_structured_v"), common,
    list(gamma_init = app_joint_qdesn_gamma_init_for_policy(contract$tau,
      list(gamma_init_policy = "zero")), diagnostic_stride = 20L,
      quadrature_nodes = c(4L, 8L, 12L), quadrature_tolerance = 1e-5,
      init = app_joint_shared_quantile_reset_init(init))))
}

app_joint_pht8_score_vb <- function(context, fit, row, contract, stage) {
  n_score <- if (stage == "qualification") contract$qualification_score_draws else
    contract$screen_score_draws
  n_state <- if (stage == "qualification") contract$qualification_state_draws else
    contract$screen_state_draws
  seed <- 861000000L + as.integer(row$context_id[[1L]]) * 10000L +
    if (row$likelihood_family[[1L]] == "exAL") 5000L else 0L
  beta <- app_joint_recursive_mvn_draws(fit$beta_mean, fit$beta_cov, n_score, seed)
  alpha <- matrix(rep(fit$alpha_mean, each = n_score), nrow = n_score)
  state_index <- app_joint_qdesn_postscore_even_indices(n_score, n_state)
  set.seed(seed + 101L)
  uniforms <- matrix(runif(length(state_index) * nrow(context$design$forecast_map)),
    nrow = length(state_index))
  mean_result <- app_joint_recursive_mean_design(context$design, context$fixture,
    context$candidate, beta[state_index, , drop = FALSE], alpha[state_index, , drop = FALSE],
    uniforms, half_assignment = rep(c(1L, 2L), length.out = length(state_index)))
  score_draws <- app_joint_recursive_score_draws(mean_result$mean_design, beta, alpha,
    context$oracle, contract$tau, contract$weights, contract$score_chunk_size)
  summary <- app_joint_recursive_draw_summary(score_draws, "vb")
  canonical <- app_joint_recursive_canonical_metrics(mean_result$mean_design,
    colMeans(beta), colMeans(alpha), context$oracle, contract$tau, contract$weights)
  fit_raw <- app_joint_qdesn_predict_fit(list(beta_mean = colMeans(beta),
    alpha_mean = colMeans(alpha)), context$design$Z[context$design$train_local, , drop = FALSE],
    contract$tau)
  fit_contract <- app_joint_qdesn_apply_monotone_contract(fit_raw, contract$tau)
  error <- abs(fit_contract$qhat_contract -
    context$design$true_q[context$design$train_local, , drop = FALSE])
  band <- c(rep("lower", 2L), rep("middle", 3L), rep("upper", 2L))
  band_mae <- tapply(colMeans(error), band, mean)
  cbind(summary, data.frame(
    canonical_score = canonical$origin_marginal_dgp_integrated_acrps,
    canonical_forecast_mae = canonical$origin_marginal_oracle_quantile_mae,
    fit_mae = mean(error), lower_fit_mae = band_mae[["lower"]],
    middle_fit_mae = band_mae[["middle"]], upper_fit_mae = band_mae[["upper"]],
    worst_band_fit_mae = max(band_mae), fit_raw_crossing_pairs =
      sum(fit_contract$raw_crossing$n_crossing_pairs), fit_contract_crossing_pairs =
      sum(fit_contract$contract_crossing$n_crossing_pairs),
    state_half_rms = mean_result$diagnostics$standardized_rms_half_difference,
    finite_functionals = all(is.finite(c(error, score_draws$origin_marginal_dgp_integrated_acrps,
      mean_result$mean_design))), stringsAsFactors = FALSE),
    setNames(canonical, paste0("canonical_", names(canonical))))
}

app_joint_pht8_run_vb <- function(root, stage, worker_id) {
  plan <- app_read_csv(file.path(root, app_joint_pht8_stage_spec(stage)[["plan"]]))
  row <- plan[plan$worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("V8 VB worker is not unique.", call. = FALSE)
  out <- app_joint_pht8_worker_dir(root, stage, worker_id)
  if (file.exists(file.path(out, "DONE"))) return(invisible(out))
  tmp <- paste0(out, ".tmp_", Sys.getpid()); unlink(tmp, recursive = TRUE, force = TRUE); app_ensure_dir(tmp)
  started <- Sys.time(); contract <- app_joint_pht8_read_contract(file.path(root, "frozen_contract.csv"))
  arms <- app_read_csv(file.path(root, "frozen_prior_arms.csv")); arm <- arms[arms$arm_id == row$arm_id, , drop = FALSE]
  captured <- tryCatch(app_joint_sw_capture_warnings(function() {
    context <- readRDS(app_joint_pht8_context_path(root, row$context_id[[1L]]))
    fit <- app_joint_pht8_fit_joint_vb(context, arm, row$likelihood_family[[1L]], contract, stage)
    score <- app_joint_pht8_score_vb(context, fit, row, contract, stage)
    list(context = context, fit = fit, score = score)
  }), error = function(e) e)
  if (inherits(captured, "error")) {
    if (stage == "screen") {
      failure_path <- app_write_csv(cbind(row,
        data.frame(error_message = conditionMessage(captured), stringsAsFactors = FALSE)),
        file.path(tmp, "failure.csv"))
      manifest <- app_joint_shared_write_manifest(tmp, c(failure = failure_path))
      verified <- app_joint_shared_verify_manifest(tmp, manifest)
      if (!nrow(verified) || any(!verified$verified)) {
        stop("V8 screen disqualification manifest failed.", call. = FALSE)
      }
      writeLines("disqualified", file.path(tmp, "DISQUALIFIED"))
      if (dir.exists(out)) unlink(out, recursive = TRUE, force = TRUE)
      if (!file.rename(tmp, out)) stop("V8 screen disqualification publication failed.", call. = FALSE)
      return(invisible(out))
    }
    app_ensure_dir(out); app_write_csv(cbind(row, data.frame(error_message = conditionMessage(captured))),
      file.path(out, "failure.csv")); writeLines("failed", file.path(out, "FAILED")); stop(conditionMessage(captured))
  }
  fit <- captured$value$fit; score <- captured$value$score
  summary <- cbind(row, arm[, c("anchor_tau0", "innovation_tau0", "anchor_zeta2",
    "innovation_zeta2", "baseline"), drop = FALSE], score,
    data.frame(converged = isTRUE(fit$converged),
      convergence_review_only = !isTRUE(fit$converged),
      iterations = as.integer(fit$iterations_completed %||% fit$iterations %||% NA_integer_),
      inference_method_id = fit$inference_method_id %||%
        if (row$likelihood_family[[1L]] == "exAL") "VB1_structured_v" else "AL_VB",
      protected_rows_used = 0L, warning_count = length(captured$warnings),
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE))
  fit_path <- file.path(tmp, "fit.rds"); saveRDS(app_joint_shared_quantile_compact_fit(fit),
    fit_path, version = 3L, compress = "xz")
  summary_path <- app_write_csv(summary, file.path(tmp, "summary.csv"))
  diagnostics_path <- app_write_csv(data.frame(warning_messages =
    if (length(captured$warnings)) paste(unique(captured$warnings), collapse = " | ") else "",
    stringsAsFactors = FALSE), file.path(tmp, "diagnostics.csv"))
  app_joint_pht8_seal_worker(tmp, out, c(fit = fit_path, summary = summary_path,
    diagnostics = diagnostics_path))
}

app_joint_pht8_collect <- function(root, stage) {
  health <- app_joint_pht8_health(root, stage)
  if (health$completed != health$expected || health$failed != 0L) {
    stop(sprintf("V8 %s is incomplete or failed.", stage), call. = FALSE)
  }
  plan <- app_read_csv(file.path(root, app_joint_pht8_stage_spec(stage)[["plan"]]))
  app_bind_rows_fill(lapply(plan$worker_id, function(id) {
    out <- app_joint_pht8_worker_dir(root, stage, id)
    verified <- app_joint_shared_verify_manifest(out, file.path(out, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified)) stop("V8 collected worker manifest failed.", call. = FALSE)
    app_read_csv(file.path(out, "summary.csv"))
  }))
}

app_joint_pht8_aggregate_vb <- function(scores) {
  groups <- split(scores, paste(scores$arm_id, scores$likelihood_family, sep = "::"))
  app_bind_rows_fill(lapply(groups, function(x) data.frame(arm_id = x$arm_id[[1L]],
    likelihood_family = x$likelihood_family[[1L]], replicate_count = nrow(x),
    fit_mae_mean = mean(x$fit_mae), lower_fit_mae_mean = mean(x$lower_fit_mae),
    middle_fit_mae_mean = mean(x$middle_fit_mae), upper_fit_mae_mean = mean(x$upper_fit_mae),
    worst_band_fit_mae_mean = mean(x$worst_band_fit_mae),
    posterior_score_mean = mean(x$posterior_score_mean),
    canonical_score_mean = mean(x$canonical_score),
    posterior_interval_width_mean = mean(x$posterior_score_interval_width),
    finite_all = all(app_as_bool_vec(x$finite_functionals)),
    contract_crossings = sum(x$contract_crossing_pairs) + sum(x$fit_contract_crossing_pairs),
    convergence_review_any = any(app_as_bool_vec(x$convergence_review_only)),
    stringsAsFactors = FALSE)))
}

app_joint_pht8_screen_eligibility <- function(scores, failures, expected_replicates) {
  bad_arms <- sort(unique(as.character(failures$arm_id)), method = "radix")
  eligible <- scores[!scores$arm_id %in% bad_arms, , drop = FALSE]
  counts <- table(eligible$arm_id)
  if (!length(counts) || any(counts != as.integer(expected_replicates))) {
    stop("V8 eligible screen arms must retain every matched replicate.", call. = FALSE)
  }
  disqualified <- if (length(bad_arms)) app_bind_rows_fill(lapply(bad_arms, function(id) {
    x <- failures[failures$arm_id == id, , drop = FALSE]
    data.frame(arm_id = id, disqualified_workers = nrow(x),
      failed_context_ids = paste(sort(unique(x$context_id)), collapse = ";"),
      error_messages = paste(sort(unique(x$error_message)), collapse = " | "),
      whole_arm_excluded = TRUE, stringsAsFactors = FALSE)
  })) else data.frame(arm_id = character(), disqualified_workers = integer(),
    failed_context_ids = character(), error_messages = character(),
    whole_arm_excluded = logical(), stringsAsFactors = FALSE)
  list(eligible = eligible, disqualified = disqualified, bad_arms = bad_arms)
}

app_joint_pht8_collect_screen <- function(root, contract) {
  health <- app_joint_pht8_health(root, "screen")
  if (health$completed + health$disqualified != health$expected ||
      health$failed != 0L || health$remaining != 0L) {
    stop("V8 screen is not terminal or contains an unclassified failure.", call. = FALSE)
  }
  plan <- app_read_csv(file.path(root, "screen_plan.csv"))
  successful <- failures <- list()
  for (id in plan$worker_id) {
    out <- app_joint_pht8_worker_dir(root, "screen", id)
    verified <- app_joint_shared_verify_manifest(out, file.path(out, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified)) {
      stop("V8 screen worker manifest failed.", call. = FALSE)
    }
    if (file.exists(file.path(out, "DONE"))) {
      successful[[length(successful) + 1L]] <- app_read_csv(file.path(out, "summary.csv"))
    } else if (file.exists(file.path(out, "DISQUALIFIED"))) {
      failures[[length(failures) + 1L]] <- app_read_csv(file.path(out, "failure.csv"))
    } else stop("V8 screen worker terminal state is invalid.", call. = FALSE)
  }
  successful <- app_bind_rows_fill(successful)
  failures <- if (length(failures)) app_bind_rows_fill(failures) else
    plan[FALSE, , drop = FALSE]
  if (!"error_message" %in% names(failures)) failures$error_message <- character()
  classified <- app_joint_pht8_screen_eligibility(successful, failures,
    contract$screen_replicates)
  c(classified, list(successful = successful, failures = failures, health = health))
}

app_joint_pht8_write_stage_manifest <- function(root, stage, files) {
  manifest <- app_joint_shared_write_manifest(root, files,
    filename = paste0(stage, "_finalization_manifest.csv"))
  verified <- app_joint_shared_verify_manifest(root, manifest)
  if (!nrow(verified) || any(!verified$verified)) stop("V8 stage finalization manifest failed.", call. = FALSE)
  app_write_csv(verified, file.path(root, paste0(stage, "_finalization_verification.csv")))
}

app_joint_pht8_finalize_sentinel <- function(root) {
  scores <- app_joint_pht8_collect(root, "sentinel"); contract <- app_joint_pht8_read_contract(file.path(root, "frozen_contract.csv"))
  aggregate <- app_joint_pht8_aggregate_vb(scores)
  baseline <- aggregate[aggregate$arm_id == app_read_csv(file.path(root, "frozen_prior_arms.csv"))$arm_id[
    app_as_bool_vec(app_read_csv(file.path(root, "frozen_prior_arms.csv"))$baseline)], , drop = FALSE]
  pass <- nrow(scores) == 2L * contract$sentinel_arm_count && all(app_as_bool_vec(scores$finite_functionals)) &&
    all(scores$contract_crossing_pairs == 0L) && all(scores$protected_rows_used == 0L) &&
    nrow(baseline) == 2L
  decision <- data.frame(status = if (pass) "V8_SENTINEL_COMPLETE_SCREEN_AUTHORIZED" else
      "V8_SENTINEL_FAILED_STOP", workers = nrow(scores), failures = sum(!app_as_bool_vec(scores$finite_functionals)),
    protected_rows_used = sum(scores$protected_rows_used), automatic_launch = FALSE,
    stringsAsFactors = FALSE)
  files <- c(scores = app_write_csv(scores, file.path(root, "sentinel_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "sentinel_aggregate.csv")),
    decision = app_write_csv(decision, file.path(root, "sentinel_decision.csv")))
  app_joint_pht8_write_stage_manifest(root, "sentinel", files); decision
}

app_joint_pht8_finalize_screen <- function(root) {
  sentinel <- app_read_csv(file.path(root, "sentinel_decision.csv"))
  if (sentinel$status != "V8_SENTINEL_COMPLETE_SCREEN_AUTHORIZED") stop("V8 screen is not authorized.", call. = FALSE)
  contract <- app_joint_pht8_read_contract(file.path(root, "frozen_contract.csv"))
  collected <- app_joint_pht8_collect_screen(root, contract)
  scores <- collected$eligible; aggregate <- app_joint_pht8_aggregate_vb(scores)
  if (any(aggregate$replicate_count != contract$screen_replicates) ||
      any(!aggregate$finite_all) || any(aggregate$contract_crossings != 0L)) {
    stop("V8 screen aggregate is incomplete or pathological.", call. = FALSE)
  }
  fit_frontier <- head(aggregate[order(aggregate$worst_band_fit_mae_mean,
    aggregate$fit_mae_mean, aggregate$arm_id), , drop = FALSE], contract$fit_frontier_count)
  selected <- head(fit_frontier[order(fit_frontier$canonical_score_mean,
    fit_frontier$worst_band_fit_mae_mean, fit_frontier$arm_id), , drop = FALSE],
    contract$qualification_arm_count)
  arms <- app_read_csv(file.path(root, "frozen_prior_arms.csv")); baseline <- arms[app_as_bool_vec(arms$baseline), ]
  selected_arms <- arms[arms$arm_id %in% unique(c(selected$arm_id, baseline$arm_id)), , drop = FALSE]
  fixtures <- app_read_csv(file.path(root, "frozen_fixture_seed_plan.csv"))
  contexts <- fixtures[fixtures$panel == "qualification", c("context_id", "panel", "replicate_id", "dgp_seed")]
  contexts$worker_id <- seq_len(nrow(contexts)); contexts <- contexts[, c("worker_id", "context_id", "panel", "replicate_id", "dgp_seed")]
  plan <- merge(expand.grid(context_id = contexts$context_id,
    likelihood_family = c("AL", "exAL"), stringsAsFactors = FALSE), selected_arms, by = NULL)
  plan$worker_id <- seq_len(nrow(plan))
  app_joint_pht8_freeze_plan(root, "qualification_context", contexts)
  app_joint_pht8_freeze_plan(root, "qualification", plan)
  selection_path <- app_write_csv(selected_arms, file.path(root, "frozen_qualification_arms.csv"))
  writeLines(app_sha256_file(selection_path), paste0(selection_path, ".sha256"))
  decision <- data.frame(status = "V8_SCREEN_COMPLETE_QUALIFICATION_AUTHORIZED",
    screen_workers = collected$health$expected, valid_workers = nrow(scores),
    disqualified_workers = collected$health$disqualified,
    disqualified_arms = length(collected$bad_arms), fit_frontier = nrow(fit_frontier),
    qualification_arms = nrow(selected_arms), qualification_workers = nrow(plan),
    automatic_launch = FALSE, stringsAsFactors = FALSE)
  files <- c(scores = app_write_csv(scores, file.path(root, "screen_scores.csv")),
    successful = app_write_csv(collected$successful,
      file.path(root, "screen_successful_worker_scores.csv")),
    failures = app_write_csv(collected$failures,
      file.path(root, "screen_failure_receipts.csv")),
    disqualified = app_write_csv(collected$disqualified,
      file.path(root, "screen_disqualified_arms.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "screen_aggregate.csv")),
    frontier = app_write_csv(fit_frontier, file.path(root, "screen_fit_frontier.csv")),
    selection = selection_path, decision = app_write_csv(decision, file.path(root, "screen_decision.csv")),
    qualification_context_plan = file.path(root, "qualification_context_plan.csv"),
    qualification_plan = file.path(root, "qualification_plan.csv"))
  app_joint_pht8_write_stage_manifest(root, "screen", files); decision
}

app_joint_pht8_finalize_qualification <- function(root) {
  screen <- app_read_csv(file.path(root, "screen_decision.csv"))
  if (screen$status != "V8_SCREEN_COMPLETE_QUALIFICATION_AUTHORIZED") {
    stop("V8 qualification is not authorized.", call. = FALSE)
  }
  contract <- app_joint_pht8_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_pht8_collect(root, "qualification")
  aggregate <- app_joint_pht8_aggregate_vb(scores)
  if (any(aggregate$replicate_count != contract$qualification_replicates) ||
      any(!aggregate$finite_all) || any(aggregate$contract_crossings != 0L)) {
    stop("V8 qualification aggregate is incomplete or pathological.", call. = FALSE)
  }
  arms <- app_read_csv(file.path(root, "frozen_prior_arms.csv")); baseline_id <- arms$arm_id[app_as_bool_vec(arms$baseline)]
  selections <- lapply(c("AL", "exAL"), function(family) {
    x <- aggregate[aggregate$likelihood_family == family, , drop = FALSE]
    base <- x[x$arm_id == baseline_id, , drop = FALSE]
    if (nrow(base) != 1L) stop("V8 qualification baseline is absent.", call. = FALSE)
    fit_frontier <- head(x[order(x$worst_band_fit_mae_mean, x$fit_mae_mean, x$arm_id), , drop = FALSE],
      min(4L, nrow(x)))
    better <- fit_frontier[fit_frontier$canonical_score_mean < base$canonical_score_mean &
      fit_frontier$worst_band_fit_mae_mean <= base$worst_band_fit_mae_mean, , drop = FALSE]
    chosen <- if (nrow(better)) better[order(better$canonical_score_mean,
      better$worst_band_fit_mae_mean), , drop = FALSE][1L, ] else base
    data.frame(likelihood_family = family, selected_arm_id = chosen$arm_id,
      baseline_arm_id = baseline_id, selected_fit = chosen$worst_band_fit_mae_mean,
      baseline_fit = base$worst_band_fit_mae_mean,
      selected_score = chosen$canonical_score_mean, baseline_score = base$canonical_score_mean,
      selected_is_baseline = chosen$arm_id == baseline_id,
      selection_rule = "top4_worst_band_fit_then_strict_canonical_score_improvement",
      stringsAsFactors = FALSE)
  })
  selection <- app_bind_rows_fill(selections)
  qplan <- app_read_csv(file.path(root, "qualification_plan.csv"))
  contexts <- app_read_csv(file.path(root, "qualification_context_plan.csv"))
  contexts <- contexts[contexts$replicate_id <= contract$mcmc_replicates, , drop = FALSE]
  rows <- list(); at <- 0L
  for (i in seq_len(nrow(selection))) {
    family <- selection$likelihood_family[[i]]
    ids <- unique(c(selection$selected_arm_id[[i]], selection$baseline_arm_id[[i]]))
    for (context_id in contexts$context_id) for (arm_id in ids) {
      source <- qplan[qplan$context_id == context_id & qplan$likelihood_family == family &
        qplan$arm_id == arm_id, , drop = FALSE]
      if (nrow(source) != 1L) stop("V8 MCMC initializer source is not unique.", call. = FALSE)
      for (chain in seq_len(contract$chains_per_cell)) {
        at <- at + 1L; row <- source
        row$vb_worker_id <- source$worker_id; row$chain_id <- chain
        row$chain_seed <- 871000000L + at * 1009L
        row$chain_start_seed <- 872000000L + at * 1013L
        row$n_iter <- if (family == "AL") contract$al_n_iter else contract$exal_n_iter
        row$burn <- if (family == "AL") contract$al_burn else contract$exal_burn
        row$thin <- contract$thin; row$n_keep <- ceiling((row$n_iter - row$burn) / row$thin)
        rows[[at]] <- row
      }
    }
  }
  plan <- app_bind_rows_fill(rows); plan$worker_id <- seq_len(nrow(plan))
  app_joint_pht8_freeze_plan(root, "mcmc", plan)
  selection_path <- app_write_csv(selection, file.path(root, "frozen_qualification_selection.csv"))
  writeLines(app_sha256_file(selection_path), paste0(selection_path, ".sha256"))
  decision <- data.frame(status = "V8_QUALIFICATION_COMPLETE_MCMC_AUTHORIZED",
    qualification_workers = nrow(scores), selected_rows = nrow(selection), mcmc_workers = nrow(plan),
    automatic_launch = FALSE, stringsAsFactors = FALSE)
  files <- c(scores = app_write_csv(scores, file.path(root, "qualification_scores.csv")),
    aggregate = app_write_csv(aggregate, file.path(root, "qualification_aggregate.csv")),
    selection = selection_path, mcmc_plan = file.path(root, "mcmc_plan.csv"),
    decision = app_write_csv(decision, file.path(root, "qualification_decision.csv")))
  app_joint_pht8_write_stage_manifest(root, "qualification", files); decision
}

app_joint_pht8_target_hash <- function(context, arm, family) {
  fields <- list(version = "joint_qdesn_persistent_tail_v8_target_v1",
    scenario_id = context$design$scenario_id, likelihood_family = family,
    fit_structure = "joint", quantile_grid = context$design$tau,
    design_fingerprint = context$design$design_fingerprint %||%
      digest::digest(context$design$Z[context$design$train_local, , drop = FALSE], algo = "sha256"),
    anchor_tau0 = arm$anchor_tau0, innovation_tau0 = arm$innovation_tau0,
    anchor_zeta2 = arm$anchor_zeta2, innovation_zeta2 = arm$innovation_zeta2,
    sigma_support = "(0,Inf)", hierarchy = "first_quantile_anchor_adjacent_differences")
  digest::digest(fields, algo = "sha256")
}

app_joint_pht8_fit_mcmc <- function(context, arm, family, init, row, contract) {
  base <- app_joint_swq_controls(app_joint_sw_read_contract())
  alpha_mean <- vapply(seq_along(contract$tau), function(k)
    context$normals[[k]]$initializer$alpha_mean[[k]], numeric(1L))
  alpha_sd <- vapply(context$normals, function(x) x$initializer$alpha_prior_sd, numeric(1L))
  start <- app_joint_article_overdispersed_start(init,
    data.frame(chain_start_seed = row$chain_start_seed[[1L]]), contract$tau)
  common <- list(y = context$design$y[context$design$train_local],
    Z = context$design$Z[context$design$train_local, , drop = FALSE], tau = contract$tau,
    n_iter = row$n_iter[[1L]], burn = row$burn[[1L]], thin = row$thin[[1L]],
    seed = row$chain_seed[[1L]], kappa = 1, tau0 = arm$innovation_tau0[[1L]],
    zeta2 = arm$innovation_zeta2[[1L]], anchor_tau0 = arm$anchor_tau0[[1L]],
    innovation_tau0 = arm$innovation_tau0[[1L]], anchor_zeta2 = arm$anchor_zeta2[[1L]],
    innovation_zeta2 = arm$innovation_zeta2[[1L]], slab_fixed = TRUE,
    a_sigma = base$a_sigma, b_sigma = base$b_sigma, alpha_prior_mean = alpha_mean,
    alpha_prior_sd = alpha_sd, alpha_min_spacing = base$alpha_min_spacing,
    max_dense_dim = 0L, sigma_bounds = c(0, Inf), init = start)
  common <- c(common, app_joint_article_mcmc_precision_repair_controls())
  if (family == "AL") return(do.call(app_joint_qvp_fit_al_mcmc_tiny, common))
  common$gamma_init <- start$gamma_mean; common$gamma_slice_width <- 1
  common$gamma_slice_max_steps <- 100L
  do.call(app_joint_exqdesn_fit_mcmc_dispatch,
    c(list(method_id = contract$exal_method), common))
}

app_joint_pht8_run_mcmc <- function(root, worker_id) {
  plan <- app_read_csv(file.path(root, "mcmc_plan.csv")); row <- plan[plan$worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("V8 MCMC worker is not unique.", call. = FALSE)
  out <- app_joint_pht8_worker_dir(root, "mcmc", worker_id)
  if (file.exists(file.path(out, "DONE"))) return(invisible(out))
  tmp <- paste0(out, ".tmp_", Sys.getpid()); unlink(tmp, recursive = TRUE, force = TRUE); app_ensure_dir(tmp)
  started <- Sys.time(); contract <- app_joint_pht8_read_contract(file.path(root, "frozen_contract.csv"))
  context <- readRDS(app_joint_pht8_context_path(root, row$context_id[[1L]]))
  arms <- app_read_csv(file.path(root, "frozen_prior_arms.csv")); arm <- arms[arms$arm_id == row$arm_id, , drop = FALSE]
  init_path <- file.path(app_joint_pht8_worker_dir(root, "qualification", row$vb_worker_id[[1L]]), "fit.rds")
  if (!file.exists(init_path)) stop("V8 MCMC initializer is absent.", call. = FALSE)
  captured <- tryCatch(app_joint_sw_capture_warnings(function()
    app_joint_pht8_fit_mcmc(context, arm, row$likelihood_family[[1L]], readRDS(init_path), row, contract)),
    error = function(e) e)
  if (inherits(captured, "error")) {
    app_ensure_dir(out); app_write_csv(cbind(row, data.frame(error_message = conditionMessage(captured))),
      file.path(out, "failure.csv")); writeLines("failed", file.path(out, "FAILED")); stop(conditionMessage(captured))
  }
  fit <- captured$value; draws <- app_joint_article_draw_frame(fit)
  if (nrow(draws) != row$n_keep[[1L]] || any(!is.finite(as.matrix(draws[, -1L, drop = FALSE])))) {
    stop("V8 retained MCMC draws violate the frozen budget.", call. = FALSE)
  }
  draws_path <- file.path(tmp, "posterior_draws.csv.gz"); app_joint_article_write_gzip_csv(draws, draws_path)
  observed_method <- fit$inference_method_id %||% if (row$likelihood_family[[1L]] == "exAL")
    contract$exal_method else "AL_latent_GIG_Gibbs"
  if (row$likelihood_family[[1L]] == "exAL" && observed_method != contract$exal_method) {
    stop("V8 exAL chain did not use exact M0.", call. = FALSE)
  }
  summary <- cbind(row, data.frame(retained_draws = nrow(draws), finite_draws = TRUE,
    inference_method_id = observed_method, complete_posterior_target_sha256 =
      app_joint_pht8_target_hash(context, arm, row$likelihood_family[[1L]]),
    sigma_support = "(0,Inf)", precision_repair_count = as.integer(fit$precision_repair_count %||% 0L),
    latent_support_redraw_count = as.integer(fit$truncnorm_support_redraw_count %||% 0L),
    warning_count = length(captured$warnings), runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    stringsAsFactors = FALSE))
  summary_path <- app_write_csv(summary, file.path(tmp, "summary.csv"))
  precision_path <- file.path(tmp, "precision_diagnostics.rds")
  saveRDS(fit$precision_repair_diagnostics %||% fit$manifest, precision_path)
  app_joint_pht8_seal_worker(tmp, out, c(draws = draws_path, summary = summary_path,
    precision = precision_path))
}

app_joint_pht8_finalize_mcmc <- function(root) {
  qualification <- app_read_csv(file.path(root, "qualification_decision.csv"))
  if (qualification$status != "V8_QUALIFICATION_COMPLETE_MCMC_AUTHORIZED") stop("V8 MCMC is not authorized.", call. = FALSE)
  summary <- app_joint_pht8_collect(root, "mcmc")
  plan <- app_read_csv(file.path(root, "mcmc_plan.csv"))
  keys <- unique(plan[, c("context_id", "likelihood_family", "arm_id"), drop = FALSE])
  keys <- keys[order(keys$context_id, keys$likelihood_family, keys$arm_id), , drop = FALSE]
  keys$worker_id <- seq_len(nrow(keys))
  keys$chain_worker_ids <- vapply(seq_len(nrow(keys)), function(i) paste(plan$worker_id[
    plan$context_id == keys$context_id[[i]] & plan$likelihood_family == keys$likelihood_family[[i]] &
      plan$arm_id == keys$arm_id[[i]]], collapse = ";"), character(1L))
  if (any(lengths(strsplit(keys$chain_worker_ids, ";", fixed = TRUE)) !=
      app_joint_pht8_read_contract(file.path(root, "frozen_contract.csv"))$chains_per_cell)) {
    stop("V8 MCMC score groups lack complete chains.", call. = FALSE)
  }
  app_joint_pht8_freeze_plan(root, "mcmc_score", keys)
  decision <- data.frame(status = "V8_MCMC_COMPLETE_SCORE_AUTHORIZED", mcmc_workers = nrow(summary),
    score_workers = nrow(keys), failures = 0L, automatic_launch = FALSE, stringsAsFactors = FALSE)
  files <- c(summary = app_write_csv(summary, file.path(root, "mcmc_summary.csv")),
    score_plan = file.path(root, "mcmc_score_plan.csv"),
    decision = app_write_csv(decision, file.path(root, "mcmc_decision.csv")))
  app_joint_pht8_write_stage_manifest(root, "mcmc", files); decision
}

app_joint_pht8_run_mcmc_score <- function(root, worker_id) {
  plan <- app_read_csv(file.path(root, "mcmc_score_plan.csv")); row <- plan[plan$worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L) stop("V8 MCMC score worker is not unique.", call. = FALSE)
  out <- app_joint_pht8_worker_dir(root, "mcmc_score", worker_id)
  if (file.exists(file.path(out, "DONE"))) return(invisible(out))
  tmp <- paste0(out, ".tmp_", Sys.getpid()); unlink(tmp, recursive = TRUE, force = TRUE); app_ensure_dir(tmp)
  contract <- app_joint_pht8_read_contract(file.path(root, "frozen_contract.csv"))
  context <- readRDS(app_joint_pht8_context_path(root, row$context_id[[1L]]))
  ids <- as.integer(strsplit(row$chain_worker_ids[[1L]], ";", fixed = TRUE)[[1L]])
  dirs <- vapply(ids, function(id) app_joint_pht8_worker_dir(root, "mcmc", id), character(1L))
  frames <- lapply(dirs, function(path) app_read_csv(file.path(path, "posterior_draws.csv.gz")))
  metadata <- app_bind_rows_fill(lapply(dirs, function(path) app_read_csv(file.path(path, "summary.csv"))))
  if (length(unique(metadata$complete_posterior_target_sha256)) != 1L ||
      length(unique(vapply(frames, nrow, integer(1L)))) != 1L ||
      any(metadata$likelihood_family != row$likelihood_family[[1L]]) ||
      any(metadata$arm_id != row$arm_id[[1L]])) stop("V8 incompatible MCMC chains cannot be scored together.", call. = FALSE)
  beta <- do.call(rbind, lapply(frames, app_joint_recursive_select_block, block = "beta"))
  alpha <- do.call(rbind, lapply(frames, app_joint_recursive_select_block, block = "alpha"))
  chain_id <- rep(seq_along(frames), vapply(frames, nrow, integer(1L)))
  source_index <- unlist(lapply(frames, function(x) x$draw_index), use.names = FALSE)
  per_chain <- min(contract$qualification_state_draws, vapply(frames, nrow, integer(1L)))
  state_rows <- unlist(lapply(split(seq_along(chain_id), chain_id), function(index)
    index[app_joint_qdesn_postscore_even_indices(length(index), per_chain)]), use.names = FALSE)
  seed <- 881000000L + row$context_id[[1L]] * 10000L +
    if (row$likelihood_family[[1L]] == "exAL") 5000L else 0L
  set.seed(seed); uniforms <- matrix(runif(length(state_rows) * nrow(context$design$forecast_map)),
    nrow = length(state_rows))
  mean_result <- app_joint_recursive_mean_design(context$design, context$fixture,
    context$candidate, beta[state_rows, , drop = FALSE], alpha[state_rows, , drop = FALSE],
    uniforms, half_assignment = app_joint_recursive_half_assignment(chain_id[state_rows]),
    diagnostic_group = chain_id[state_rows])
  score_draws <- app_joint_recursive_score_draws(mean_result$mean_design, beta, alpha,
    context$oracle, contract$tau, contract$weights, contract$score_chunk_size,
    chain_id, source_index)
  summary <- app_joint_recursive_draw_summary(score_draws, "mcmc")
  score_matrix <- do.call(cbind, split(score_draws$origin_marginal_dgp_integrated_acrps,
    score_draws$chain_id))
  modern <- app_joint_exqdesn_modern_diagnostics(score_matrix)
  parameter_diagnostics <- app_joint_prior_diagnostics(frames)
  functionals <- app_joint_prior_functional_diagnostics(frames, mean_result$mean_design, contract$tau)
  chain_means <- colMeans(score_matrix)
  canonical <- app_joint_recursive_canonical_metrics(mean_result$mean_design, colMeans(beta),
    colMeans(alpha), context$oracle, contract$tau, contract$weights)
  fit_raw <- app_joint_qdesn_predict_fit(list(beta_mean = colMeans(beta), alpha_mean = colMeans(alpha)),
    context$design$Z[context$design$train_local, , drop = FALSE], contract$tau)
  fit_contract <- app_joint_qdesn_apply_monotone_contract(fit_raw, contract$tau)
  error <- abs(fit_contract$qhat_contract - context$design$true_q[context$design$train_local, , drop = FALSE])
  band <- c(rep("lower", 2L), rep("middle", 3L), rep("upper", 2L)); band_mae <- tapply(colMeans(error), band, mean)
  output <- cbind(row, summary, data.frame(canonical_score = canonical$origin_marginal_dgp_integrated_acrps,
    fit_mae = mean(error), lower_fit_mae = band_mae[["lower"]], middle_fit_mae = band_mae[["middle"]],
    upper_fit_mae = band_mae[["upper"]], worst_band_fit_mae = max(band_mae),
    score_rank_rhat = modern$rank_rhat, score_folded_rhat = modern$folded_rhat,
    score_tail_ess = modern$tail_ess, score_mcse_mean = modern$mcse_mean,
    quantile_functional_max_rhat = max(functionals$rank_rhat, functionals$folded_rhat),
    chain_score_relative_range = diff(range(chain_means)) / mean(chain_means),
    state_half_rms = mean_result$diagnostics$standardized_rms_half_difference,
    fit_raw_crossing_pairs = sum(fit_contract$raw_crossing$n_crossing_pairs),
    fit_contract_crossing_pairs = sum(fit_contract$contract_crossing$n_crossing_pairs),
    target_sha256 = unique(metadata$complete_posterior_target_sha256), stringsAsFactors = FALSE),
    setNames(canonical, paste0("canonical_", names(canonical))))
  summary_path <- app_write_csv(output, file.path(tmp, "summary.csv"))
  pdiag_path <- app_write_csv(parameter_diagnostics, file.path(tmp, "parameter_diagnostics.csv"))
  fdiag_path <- app_write_csv(functionals, file.path(tmp, "functional_diagnostics.csv"))
  chain_path <- app_write_csv(data.frame(chain_id = seq_along(chain_means), score_mean = chain_means),
    file.path(tmp, "chain_scores.csv"))
  draw_path <- file.path(tmp, "score_draws.csv.gz"); app_joint_article_write_gzip_csv(score_draws, draw_path)
  app_joint_pht8_seal_worker(tmp, out, c(summary = summary_path, parameter = pdiag_path,
    functional = fdiag_path, chains = chain_path, draws = draw_path))
}

app_joint_pht8_transfer_inventory <- function(root) {
  files <- list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  files <- files[!dir.exists(files) & basename(files) != "transfer_inventory.csv"]
  relative <- substring(files, nchar(normalizePath(root)) + 2L)
  inventory <- data.frame(relative_path = relative, size_bytes = file.info(files)$size,
    sha256 = unname(tools::sha256sum(files)), stringsAsFactors = FALSE)
  inventory <- inventory[order(inventory$relative_path), , drop = FALSE]
  app_write_csv(inventory, file.path(root, "transfer_inventory.csv"))
}

app_joint_pht8_finalize_mcmc_score <- function(root) {
  mcmc <- app_read_csv(file.path(root, "mcmc_decision.csv"))
  if (mcmc$status != "V8_MCMC_COMPLETE_SCORE_AUTHORIZED") stop("V8 MCMC scoring is not authorized.", call. = FALSE)
  contract <- app_joint_pht8_read_contract(file.path(root, "frozen_contract.csv"))
  scores <- app_joint_pht8_collect(root, "mcmc_score")
  selection <- app_read_csv(file.path(root, "frozen_qualification_selection.csv"))
  verdicts <- lapply(seq_len(nrow(selection)), function(i) {
    family <- selection$likelihood_family[[i]]; selected_id <- selection$selected_arm_id[[i]]
    baseline_id <- selection$baseline_arm_id[[i]]
    x <- scores[scores$likelihood_family == family, , drop = FALSE]
    aggregate <- function(id) {
      z <- x[x$arm_id == id, , drop = FALSE]
      data.frame(arm_id = id, replicates = nrow(z), score_mean = mean(z$posterior_score_mean),
        canonical_mean = mean(z$canonical_score), worst_fit_mean = mean(z$worst_band_fit_mae),
        max_score_rhat = max(z$score_rank_rhat, z$score_folded_rhat),
        max_functional_rhat = max(z$quantile_functional_max_rhat),
        max_chain_range = max(z$chain_score_relative_range),
        contract_crossings = sum(z$contract_crossing_pairs) + sum(z$fit_contract_crossing_pairs),
        stringsAsFactors = FALSE)
    }
    candidate <- aggregate(selected_id); baseline <- aggregate(baseline_id)
    pathology <- candidate$max_score_rhat > contract$functional_rhat_review ||
      candidate$max_functional_rhat > contract$functional_rhat_review ||
      candidate$max_chain_range > contract$chain_relative_range_review ||
      candidate$contract_crossings != 0L
    improve <- candidate$score_mean < baseline$score_mean &&
      candidate$worst_fit_mean <= baseline$worst_fit_mean
    data.frame(likelihood_family = family, selected_arm_id = selected_id,
      baseline_arm_id = baseline_id, selected_score = candidate$score_mean,
      baseline_score = baseline$score_mean, selected_worst_fit = candidate$worst_fit_mean,
      baseline_worst_fit = baseline$worst_fit_mean, functional_pathology = pathology,
      promote_to_protected_confirmation = selected_id != baseline_id && improve && !pathology,
      decision = if (selected_id == baseline_id) "retain_v7_prior" else if (improve && !pathology)
        "joint_prior_candidate_qualifies_for_separate_protected_confirmation" else
        "retain_v7_prior_no_protected_rerun", stringsAsFactors = FALSE)
  })
  verdict <- app_bind_rows_fill(verdicts)
  status <- if (any(verdict$promote_to_protected_confirmation))
    "V8_COMPLETE_PROTECTED_CONFIRMATION_CANDIDATE_AVAILABLE" else
    "V8_COMPLETE_RETAIN_V7_PRIOR_STOP"
  decision <- data.frame(status = status, scenario_id = contract$scenario_id,
    likelihood_candidates = sum(verdict$promote_to_protected_confirmation),
    protected_scores_used_for_selection = FALSE, article_assets_modified = FALSE,
    next_action = if (any(verdict$promote_to_protected_confirmation))
      "freeze_separate_model_specific_protected_confirmation" else "stop_joint_prior_calibration",
    stringsAsFactors = FALSE)
  files <- c(scores = app_write_csv(scores, file.path(root, "v8_mcmc_score_summary.csv")),
    verdict = app_write_csv(verdict, file.path(root, "v8_prior_verdict.csv")),
    decision = app_write_csv(decision, file.path(root, "v8_final_decision.csv")))
  app_joint_pht8_write_stage_manifest(root, "mcmc_score", files)
  app_joint_pht8_transfer_inventory(root); decision
}

app_joint_pht8_finalize_stage <- function(root, stage) {
  switch(as.character(stage), sentinel = app_joint_pht8_finalize_sentinel(root),
    screen = app_joint_pht8_finalize_screen(root),
    qualification = app_joint_pht8_finalize_qualification(root),
    mcmc = app_joint_pht8_finalize_mcmc(root),
    mcmc_score = app_joint_pht8_finalize_mcmc_score(root),
    stop("V8 stage has no finalizer.", call. = FALSE))
}

app_joint_pht8_run_worker <- function(root, stage, worker_id) {
  app_joint_pht8_verify_plan(root, stage)
  if (grepl("_context$", stage)) return(app_joint_pht8_run_context(root, stage, worker_id))
  if (stage %in% c("sentinel", "screen", "qualification")) {
    return(app_joint_pht8_run_vb(root, stage, worker_id))
  }
  if (stage == "mcmc") return(app_joint_pht8_run_mcmc(root, worker_id))
  if (stage == "mcmc_score") return(app_joint_pht8_run_mcmc_score(root, worker_id))
  stop("Unknown V8 worker stage.", call. = FALSE)
}

app_joint_pht8_check <- function(root = app_joint_pht8_default_root()) {
  stages <- c("sentinel_context", "sentinel", "screen_context", "screen",
    "qualification_context", "qualification", "mcmc", "mcmc_score")
  health <- app_bind_rows_fill(lapply(stages, function(stage) app_joint_pht8_health(root, stage)))
  status <- if (any(health$failed > 0L)) "FAIL" else "PASS"
  cbind(health, overall_status = status)
}
