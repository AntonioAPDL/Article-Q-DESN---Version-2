# Phase181 same-specification score-stability extension and mean promotion.

app_joint_qdesn_phase181_contract_path <- function() {
  app_path(
    "application/config",
    "joint_qdesn_phase181_score_stability_extension_contract_v1.csv"
  )
}

app_joint_qdesn_phase181_dirs <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root()
) {
  root <- normalizePath(cache_root, mustWork = FALSE)
  list(
    cache_root = root,
    parent_freeze = file.path(
      root, "joint_qdesn_phase180_balanced_dgp_score_freeze_20260824"
    ),
    parent_packet = file.path(
      root, "joint_qdesn_phase180_balanced_dgp_score_packet_20260824"
    ),
    freeze = file.path(
      root, "joint_qdesn_phase181_score_stability_extension_freeze_20260826"
    ),
    initialization_work = file.path(
      root, "joint_qdesn_phase181_score_stability_initialization_work_20260826"
    ),
    chains = file.path(
      root, "joint_qdesn_phase181_score_stability_extension_chains_20260826"
    ),
    orchestration = file.path(
      root,
      "joint_qdesn_phase181_score_stability_extension_20260826_orchestration"
    ),
    extension_score_work = file.path(
      root, "joint_qdesn_phase181_extension_score_work_20260826"
    ),
    selected_score_work = file.path(
      root, "joint_qdesn_phase181_selected_score_work_20260826"
    ),
    packet = file.path(
      root, "joint_qdesn_phase181_score_stability_extension_packet_20260826"
    ),
    article_staging = file.path(
      root, "joint_qdesn_phase181_article_assets_staging_20260826"
    ),
    handoff = file.path(
      root, "joint_qdesn_phase181_integration_handoff_20260826"
    )
  )
}

app_joint_qdesn_phase181_contract_value <- function(table, name) {
  row <- table[table$contract_name == name, , drop = FALSE]
  if (nrow(row) != 1L) {
    stop(sprintf("Phase181 contract requires one '%s' row.", name), call. = FALSE)
  }
  as.character(row$value[[1L]])
}

app_joint_qdesn_phase181_read_contract <- function(
  path = app_joint_qdesn_phase181_contract_path()
) {
  table <- app_read_csv(path)
  app_check_required_columns(
    table,
    c("contract_section", "contract_name", "value", "value_type", "rationale"),
    "Phase181 score-stability contract"
  )
  if (anyDuplicated(table$contract_name)) {
    stop("Phase181 contract names must be unique.", call. = FALSE)
  }
  get <- function(name) app_joint_qdesn_phase181_contract_value(table, name)
  int <- function(name) as.integer(get(name))
  num <- function(name) as.numeric(get(name))
  bool <- function(name) identical(tolower(get(name)), "true")
  nums <- function(name) as.numeric(strsplit(get(name), ",", fixed = TRUE)[[1L]])
  out <- list(
    table = table,
    path = normalizePath(path, mustWork = TRUE),
    version = get("contract_version"),
    parent_freeze_manifest_sha256 = get("parent_phase180_freeze_manifest_sha256"),
    parent_packet_manifest_sha256 = get("parent_phase180_packet_manifest_sha256"),
    expected_total_cells = int("expected_total_cells"),
    expected_extension_cells = int("expected_extension_cells"),
    expected_unaffected_cells = int("expected_unaffected_cells"),
    expected_al_extension_cells = int("expected_al_extension_cells"),
    expected_exal_extension_cells = int("expected_exal_extension_cells"),
    n_chains = int("n_chains_per_cell"),
    expected_workers = int("expected_extension_workers"),
    loo_threshold = num("chain_loo_relative_mean_shift_threshold"),
    promotion_metric = get("promotion_primary_metric"),
    promotion_rule = get("promotion_rule"),
    minimum_absolute_improvement = num("minimum_absolute_mean_improvement"),
    score_review_triggers = bool("score_functional_review_triggers_extension"),
    mixing_blocks_promotion = bool("mixing_blocks_promotion"),
    coherence_blocks_promotion = bool("raw_coherence_review_blocks_promotion"),
    global_specification_selected = bool("global_specification_selected"),
    retuning_allowed = bool("desn_or_tau0_retuning_allowed"),
    complete_manifests_required = bool("complete_chain_manifests_required"),
    finite_required = bool("finite_draws_and_scores_required"),
    zero_contract_crossings_required = bool("zero_contract_crossings_required"),
    source_hashes_required = bool("source_hashes_required"),
    al_n_iter = int("al_n_iter"), al_burn = int("al_burn"),
    al_thin = int("al_thin"), exal_n_iter = int("exal_n_iter"),
    exal_burn = int("exal_burn"), exal_thin = int("exal_thin"),
    sigma_upper_multiplier = num("sigma_upper_multiplier"),
    chain_seed_base = int("chain_seed_base"),
    tau_seed_stride = int("tau_seed_stride"),
    default_concurrent_workers = int("default_concurrent_workers"),
    score_draws_per_chain = int("score_draws_per_chain"),
    tau = nums("current_quantile_grid"),
    article_fixture_role = get("article_fixture_role"),
    claim_status = get("claim_status"),
    manuscript_mutation_allowed = bool("automatic_manuscript_mutation_allowed"),
    dense_grid_authorized = bool("dense_grid_authorized")
  )
  app_joint_qvp_validate_tau_grid(out$tau)
  if (out$expected_extension_cells + out$expected_unaffected_cells !=
        out$expected_total_cells ||
      out$expected_al_extension_cells + out$expected_exal_extension_cells !=
        out$expected_extension_cells ||
      out$expected_extension_cells * out$n_chains != out$expected_workers ||
      out$promotion_metric != "posterior_score_mean" ||
      out$promotion_rule != "strict_lower_finite_mean" ||
      out$minimum_absolute_improvement != 0 ||
      out$mixing_blocks_promotion || out$coherence_blocks_promotion ||
      out$global_specification_selected || out$retuning_allowed ||
      out$manuscript_mutation_allowed || out$dense_grid_authorized ||
      !all(c(
        out$complete_manifests_required, out$finite_required,
        out$zero_contract_crossings_required, out$source_hashes_required
      ))) {
    stop("Phase181 contract violates the frozen extension policy.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase181_verify_parent <- function(dirs, contract) {
  freeze_check <- app_joint_exqdesn_verify_manifest(
    dirs$parent_freeze, "phase181_parent_phase180_freeze"
  )
  packet_check <- app_joint_exqdesn_verify_manifest(
    dirs$parent_packet, "phase181_parent_phase180_packet"
  )
  freeze_hash <- app_sha256_file(file.path(dirs$parent_freeze, "artifact_manifest.csv"))
  packet_hash <- app_sha256_file(file.path(dirs$parent_packet, "artifact_manifest.csv"))
  if (any(freeze_check$status != "pass") || any(packet_check$status != "pass") ||
      freeze_hash != contract$parent_freeze_manifest_sha256 ||
      packet_hash != contract$parent_packet_manifest_sha256) {
    stop("Phase181 parent Phase180 identity or manifest failed.", call. = FALSE)
  }
  list(
    freeze = app_joint_qdesn_phase180_load_freeze(dirs$parent_freeze),
    freeze_check = freeze_check, packet_check = packet_check,
    freeze_hash = freeze_hash, packet_hash = packet_hash
  )
}

app_joint_qdesn_phase181_chain_loo_audit <- function(draws) {
  required <- c("case_id", "chain_id", "dgp_integrated_acrps")
  app_check_required_columns(draws, required, "Phase181 parent score draws")
  if (!nrow(draws) || any(!is.finite(draws$dgp_integrated_acrps))) {
    stop("Phase181 parent score draws are empty or nonfinite.", call. = FALSE)
  }
  rows <- lapply(split(draws, draws$case_id), function(x) {
    chains <- sort(unique(as.integer(x$chain_id)))
    full_mean <- mean(x$dgp_integrated_acrps)
    loo_mean <- vapply(chains, function(chain_id) {
      mean(x$dgp_integrated_acrps[x$chain_id != chain_id])
    }, numeric(1L))
    chain_mean <- vapply(chains, function(chain_id) {
      mean(x$dgp_integrated_acrps[x$chain_id == chain_id])
    }, numeric(1L))
    shift <- abs(loo_mean - full_mean)
    index <- which.max(shift)
    data.frame(
      case_id = x$case_id[[1L]], chains = length(chains),
      posterior_draws = nrow(x), full_score_mean = full_mean,
      dominant_chain_id = chains[[index]],
      dominant_chain_score_mean = chain_mean[[index]],
      dominant_chain_loo_mean = loo_mean[[index]],
      max_absolute_loo_mean_shift = shift[[index]],
      max_relative_loo_mean_shift = shift[[index]] /
        max(abs(full_mean), .Machine$double.eps),
      minimum_chain_score_mean = min(chain_mean),
      maximum_chain_score_mean = max(chain_mean),
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  out[order(out$case_id), , drop = FALSE]
}

app_joint_qdesn_phase181_extension_selection <- function(
  score_summary, loo_audit, contract
) {
  app_check_required_columns(
    score_summary,
    c(
      "case_id", "scenario_id", "source_model_id", "likelihood_family",
      "fit_structure", "score_functional_status", "posterior_score_mean"
    ),
    "Phase181 parent score summary"
  )
  out <- merge(score_summary, loo_audit, by = "case_id", all.x = TRUE, sort = FALSE)
  if (nrow(out) != contract$expected_total_cells || anyNA(out$full_score_mean) ||
      anyDuplicated(out$case_id) ||
      any(abs(out$posterior_score_mean - out$full_score_mean) > 1e-12)) {
    stop("Phase181 could not align the 32-cell parent score and draw summaries.",
         call. = FALSE)
  }
  out$score_review_trigger <- out$score_functional_status != "pass"
  out$chain_instability_trigger <-
    out$max_relative_loo_mean_shift > contract$loo_threshold
  out$extension_selected <- out$score_review_trigger |
    out$chain_instability_trigger
  out$extension_reason <- ifelse(
    out$score_review_trigger & out$chain_instability_trigger,
    "score_functional_review_and_chain_mean_instability",
    ifelse(
      out$score_review_trigger, "score_functional_review",
      ifelse(out$chain_instability_trigger, "chain_mean_instability", "not_selected")
    )
  )
  selected <- out[out$extension_selected, , drop = FALSE]
  if (nrow(selected) != contract$expected_extension_cells ||
      sum(selected$likelihood_family == "AL") !=
        contract$expected_al_extension_cells ||
      sum(selected$likelihood_family == "exAL") !=
        contract$expected_exal_extension_cells ||
      sum(!out$extension_selected) != contract$expected_unaffected_cells) {
    stop("Phase181 extension scope differs from the frozen 19-cell audit.",
         call. = FALSE)
  }
  out
}

app_joint_qdesn_phase181_worker_plan <- function(cells, dirs, contract) {
  rows <- list(); worker_id <- 0L
  for (ii in seq_len(nrow(cells))) {
    for (chain_id in seq_len(contract$n_chains)) {
      worker_id <- worker_id + 1L
      row <- cells[ii, , drop = FALSE]
      row$extension_cell_index <- ii
      row$worker_id <- worker_id
      row$chain_id <- chain_id
      row$wave_id <- as.integer(ceiling(
        worker_id / contract$default_concurrent_workers
      ))
      row$chain_seed <- as.integer(
        contract$chain_seed_base + ii * 250000L + chain_id * 10000L
      )
      row$tau_seed_stride <- contract$tau_seed_stride
      row$sigma_upper_multiplier <- contract$sigma_upper_multiplier
      row$seed_role <- "phase181_same_specification_extension_chain"
      row$n_chains <- contract$n_chains
      row$n_iter <- if (row$likelihood_family[[1L]] == "exAL") {
        contract$exal_n_iter
      } else contract$al_n_iter
      row$burn <- if (row$likelihood_family[[1L]] == "exAL") {
        contract$exal_burn
      } else contract$al_burn
      row$thin <- if (row$likelihood_family[[1L]] == "exAL") {
        contract$exal_thin
      } else contract$al_thin
      row$n_keep <- as.integer((row$n_iter - row$burn) / row$thin)
      row$inference_method_id <- if (row$likelihood_family[[1L]] == "exAL") {
        "M0_v_collapsed_support_logit"
      } else "AL_latent_GIG_Gibbs"
      row$worker_output_dir <- file.path(
        dirs$chains, "cases", row$mcmc_case_id[[1L]],
        sprintf("chain_%02d", chain_id)
      )
      rows[[worker_id]] <- row
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  if (nrow(out) != contract$expected_workers ||
      anyDuplicated(out$worker_id) || anyDuplicated(out$chain_seed) ||
      anyDuplicated(paste(out$mcmc_case_id, out$chain_id)) ||
      any(out$chain_seed >= .Machine$integer.max) ||
      any(table(out$mcmc_case_id) != contract$n_chains) ||
      any(out$n_keep != 5000L)) {
    stop("Phase181 worker plan has invalid counts, budgets, or seeds.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase181_load_freeze <- function(freeze_dir) {
  check <- app_joint_exqdesn_verify_manifest(freeze_dir, "phase181_freeze")
  if (any(check$status != "pass")) stop("Phase181 freeze manifest failed.", call. = FALSE)
  extension_contract <- app_joint_qdesn_phase181_read_contract(
    file.path(freeze_dir, "phase181_extension_contract.csv")
  )
  score_contract <- app_joint_qdesn_phase180_read_contract(
    file.path(freeze_dir, "phase180_score_contract.csv")
  )
  out <- list(
    dir = normalizePath(freeze_dir), verification = check,
    extension_contract = extension_contract, contract = score_contract,
    config = app_read_csv(file.path(freeze_dir, "run_config.csv")),
    registry = app_read_csv(file.path(freeze_dir, "extension_cell_registry.csv")),
    controls = app_read_csv(file.path(freeze_dir, "extension_cell_registry.csv")),
    selection = app_read_csv(file.path(
      freeze_dir, "extension_cell_selection_audit.csv"
    )),
    loo = app_read_csv(file.path(freeze_dir, "chain_leave_one_out_audit.csv")),
    plan = app_read_csv(file.path(freeze_dir, "worker_plan.csv")),
    components = app_read_csv(file.path(freeze_dir, "component_seed_plan.csv")),
    init = app_read_csv(file.path(freeze_dir, "vb_initialization.csv")),
    starts = app_read_csv(file.path(freeze_dir, "chain_start_values.csv")),
    readiness = app_read_csv(file.path(freeze_dir, "readiness_assessment.csv"))
  )
  if (nrow(out$registry) != extension_contract$expected_extension_cells ||
      nrow(out$plan) != extension_contract$expected_workers ||
      any(out$readiness$gate_status != "pass")) {
    stop("Phase181 freeze contents differ from the extension contract.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase181_prepare <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(), out_dir = NULL,
  n_vb_cores = 8L, force = FALSE
) {
  dirs <- app_joint_qdesn_phase181_dirs(cache_root)
  out_dir <- out_dir %||% dirs$freeze
  contract <- app_joint_qdesn_phase181_read_contract()
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- tryCatch(
      app_joint_exqdesn_verify_manifest(out_dir, "phase181_freeze"),
      error = function(e) NULL
    )
    if (!is.null(check) && all(check$status == "pass")) {
      freeze <- app_joint_qdesn_phase181_load_freeze(out_dir)
      return(list(
        out_dir = freeze$dir, plan = freeze$plan,
        readiness = freeze$readiness, reused = TRUE
      ))
    }
  }
  parent <- app_joint_qdesn_phase181_verify_parent(dirs, contract)
  score_summary <- app_read_csv(file.path(
    dirs$parent_packet, "posterior_dgp_integrated_acrps_summary.csv"
  ))
  score_draws <- app_read_csv(file.path(
    dirs$parent_packet, "posterior_dgp_integrated_acrps_draws.csv.gz"
  ))
  loo <- app_joint_qdesn_phase181_chain_loo_audit(score_draws)
  selection <- app_joint_qdesn_phase181_extension_selection(
    score_summary, loo, contract
  )
  selected_ids <- selection$case_id[selection$extension_selected]
  cells <- parent$freeze$registry[
    match(selected_ids, parent$freeze$registry$case_id), , drop = FALSE
  ]
  if (anyNA(cells$case_id) || any(cells$case_id != selected_ids)) {
    stop("Phase181 could not resolve selected cells in the parent freeze.", call. = FALSE)
  }
  cells$extension_role <- "same_specification_score_stability"
  cells$article_fixture_used_for_estimator_selection <- TRUE
  cells$desn_or_tau0_changed <- FALSE
  cells$source_control_row_sha256_parent <- cells$source_control_row_sha256
  plan <- app_joint_qdesn_phase181_worker_plan(cells, dirs, contract)
  components <- app_joint_qdesn_phase180_component_seed_plan(
    plan, parent$freeze$contract$tau
  )
  if (anyDuplicated(components$component_seed)) {
    stop("Phase181 component seed plan has collisions.", call. = FALSE)
  }
  initialize <- function(ii) try(
    app_joint_qdesn_phase180_initialize_cached(
      cells[ii, , drop = FALSE],
      parent$freeze$config$fixture_dir[[1L]],
      dirs$initialization_work,
      force = force
    ), silent = TRUE
  )
  initialization <- if (.Platform$OS.type != "windows" && n_vb_cores > 1L) {
    parallel::mclapply(
      seq_len(nrow(cells)), initialize,
      mc.cores = min(as.integer(n_vb_cores), nrow(cells)),
      mc.preschedule = FALSE
    )
  } else lapply(seq_len(nrow(cells)), initialize)
  failed <- vapply(initialization, inherits, logical(1L), "try-error")
  if (any(failed)) {
    stop(sprintf(
      "Phase181 initialization failed: %s",
      paste(vapply(initialization[failed], as.character, character(1L)),
            collapse = " | ")
    ), call. = FALSE)
  }
  init <- app_joint_qdesn_bind_rows(lapply(initialization, `[[`, "init"))
  init_audit <- app_joint_qdesn_bind_rows(lapply(initialization, `[[`, "audit"))
  start_contract <- list(n_chains = contract$n_chains, tau = parent$freeze$contract$tau)
  starts <- app_joint_qdesn_phase180_chain_starts(init, cells, start_contract)
  preflight <- app_joint_qdesn_phase180_m0_start_preflight(
    starts, plan, parent$freeze$contract$tau
  )
  if (any(init_audit$status != "pass") || any(preflight$status != "pass") ||
      length(unique(init$mcmc_case_id)) != contract$expected_extension_cells) {
    stop("Phase181 initialization or exAL start preflight failed.", call. = FALSE)
  }
  fixture_manifest <- app_sha256_file(file.path(
    parent$freeze$config$fixture_dir[[1L]], "artifact_manifest.csv"
  ))
  plan$fixture_manifest_sha256 <- fixture_manifest
  plan$code_commit <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "HEAD"))
  plan$source_control_file_sha256 <- NA_character_
  plan$source_control_row_sha256 <- cells$source_control_row_sha256[
    match(plan$mcmc_case_id, cells$mcmc_case_id)
  ]
  control_audit <- data.frame(
    case_id = cells$case_id,
    parent_control_row_sha256 = cells$source_control_row_sha256_parent,
    extension_control_row_sha256 = cells$source_control_row_sha256,
    desn_or_tau0_changed = FALSE,
    status = ifelse(
      cells$source_control_row_sha256_parent == cells$source_control_row_sha256,
      "pass", "fail"
    ), stringsAsFactors = FALSE
  )
  compute <- data.frame(
    likelihood_family = c("AL", "exAL"),
    extension_cells = c(
      sum(cells$likelihood_family == "AL"),
      sum(cells$likelihood_family == "exAL")
    ),
    chains_per_cell = contract$n_chains,
    workers = c(
      sum(plan$likelihood_family == "AL"),
      sum(plan$likelihood_family == "exAL")
    ),
    n_iter = c(contract$al_n_iter, contract$exal_n_iter),
    burn = c(contract$al_burn, contract$exal_burn),
    thin = c(contract$al_thin, contract$exal_thin),
    retained_draws_per_chain = 5000L,
    score_draws_per_chain = contract$score_draws_per_chain,
    stringsAsFactors = FALSE
  )
  readiness <- data.frame(
    phase_id = contract$version, gate_status = "pass",
    parent_cells = nrow(score_summary), extension_cells = nrow(cells),
    unaffected_cells = contract$expected_unaffected_cells,
    planned_workers = nrow(plan), planned_components = nrow(components),
    unique_chain_seeds = length(unique(plan$chain_seed)),
    unique_component_seeds = length(unique(components$component_seed)),
    case_specific_controls_preserved = all(control_audit$status == "pass"),
    mixing_blocks_promotion = contract$mixing_blocks_promotion,
    promotion_metric = contract$promotion_metric,
    recommendation = "launch_phase181_same_specification_extension",
    stringsAsFactors = FALSE
  )
  if (readiness$parent_cells != contract$expected_total_cells ||
      readiness$extension_cells != contract$expected_extension_cells ||
      readiness$planned_workers != contract$expected_workers ||
      any(control_audit$status != "pass")) {
    stop("Phase181 readiness differs from its frozen contract.", call. = FALSE)
  }

  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase181 score-stability extension freeze", "",
    "This freeze extends 19 deterministically audited Phase180 cells.",
    "No DESN, tau0, likelihood, prior, fixture, forecast, or quantile-grid control changes.",
    "Every exAL chain uses exact M0 with support-logit-v2 dispersed starts.",
    "A lower finite posterior score mean is promoted after hard gates.",
    "Mixing and raw coherence remain review diagnostics and do not veto promotion."
  ), readme, useBytes = TRUE)
  extension_contract_path <- file.path(tmp, "phase181_extension_contract.csv")
  score_contract_path <- file.path(tmp, "phase180_score_contract.csv")
  file.copy(contract$path, extension_contract_path, overwrite = TRUE)
  file.copy(
    file.path(parent$freeze$dir, "phase180_score_contract.csv"),
    score_contract_path, overwrite = TRUE
  )
  paths <- c(
    phase181_extension_contract = normalizePath(
      extension_contract_path, mustWork = TRUE
    ),
    phase180_score_contract = normalizePath(score_contract_path, mustWork = TRUE),
    parent_freeze_manifest_verification = write(
      parent$freeze_check, "parent_freeze_manifest_verification.csv"
    ),
    parent_packet_manifest_verification = write(
      parent$packet_check, "parent_packet_manifest_verification.csv"
    ),
    parent_identity = write(data.frame(
      parent_freeze_dir = normalizePath(dirs$parent_freeze),
      parent_freeze_manifest_sha256 = parent$freeze_hash,
      parent_packet_dir = normalizePath(dirs$parent_packet),
      parent_packet_manifest_sha256 = parent$packet_hash,
      stringsAsFactors = FALSE
    ), "parent_identity.csv"),
    chain_leave_one_out_audit = write(loo, "chain_leave_one_out_audit.csv"),
    extension_cell_selection_audit = write(
      selection, "extension_cell_selection_audit.csv"
    ),
    extension_cell_registry = write(cells, "extension_cell_registry.csv"),
    worker_plan = write(plan, "worker_plan.csv"),
    chain_seed_plan = write(
      plan[, c("worker_id", "mcmc_case_id", "chain_id", "chain_seed", "seed_role")],
      "chain_seed_plan.csv"
    ),
    component_seed_plan = write(components, "component_seed_plan.csv"),
    vb_initialization = write(init, "vb_initialization.csv"),
    vb_initialization_audit = write(
      init_audit, "vb_initialization_audit.csv"
    ),
    chain_start_values = write(starts, "chain_start_values.csv"),
    chain_start_preflight = write(preflight, "chain_start_preflight.csv"),
    control_identity_audit = write(control_audit, "control_identity_audit.csv"),
    compute_budget = write(compute, "compute_budget.csv"),
    readiness_assessment = write(readiness, "readiness_assessment.csv"),
    run_config = write(data.frame(
      phase_id = contract$version, cache_root = normalizePath(cache_root),
      parent_freeze_dir = normalizePath(dirs$parent_freeze),
      parent_packet_dir = normalizePath(dirs$parent_packet),
      fixture_dir = normalizePath(parent$freeze$config$fixture_dir[[1L]]),
      result_dir = dirs$chains,
      code_commit = unique(plan$code_commit),
      promotion_metric = contract$promotion_metric,
      mixing_blocks_promotion = FALSE,
      desn_or_tau0_retuning_allowed = FALSE,
      article_assets_modified = FALSE,
      stringsAsFactors = FALSE
    ), "run_config.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(
      final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S")
    )
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine prior Phase181 freeze.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, final_dir)) {
    stop("Could not publish Phase181 freeze.", call. = FALSE)
  }
  freeze <- app_joint_qdesn_phase181_load_freeze(final_dir)
  list(out_dir = freeze$dir, plan = freeze$plan, readiness = readiness, reused = FALSE)
}

app_joint_qdesn_phase181_run_worker <- function(
  freeze_dir, worker_id, reuse_completed = TRUE, failure_dir = NULL
) {
  freeze <- app_joint_qdesn_phase181_load_freeze(freeze_dir)
  worker_id <- as.integer(worker_id)[[1L]]
  job <- freeze$plan[freeze$plan$worker_id == worker_id, , drop = FALSE]
  if (nrow(job) != 1L) stop("Unknown Phase181 worker id.", call. = FALSE)
  current_commit <- app_joint_qdesn_phase180_git_output(c("rev-parse", "HEAD"))
  worktree_status <- app_joint_qdesn_phase180_git_output(c("status", "--porcelain"))
  if (is.na(current_commit) || current_commit != job$code_commit[[1L]] ||
      (!is.na(worktree_status) && nzchar(worktree_status))) {
    stop("Phase181 workers require the clean commit frozen by preparation.",
         call. = FALSE)
  }
  worker_dir <- job$worker_output_dir[[1L]]
  if (reuse_completed && app_joint_qdesn_phase180_worker_complete(worker_dir)) {
    return(list(
      worker_id = worker_id, status = "reused_verified", worker_dir = worker_dir
    ))
  }
  component <- freeze$components[
    freeze$components$worker_id == worker_id, , drop = FALSE
  ]
  expected <- if (job$fit_structure[[1L]] == "joint") {
    1L
  } else length(freeze$contract$tau)
  if (nrow(component) != expected || anyDuplicated(component$component_seed)) {
    stop("Malformed Phase181 component seed plan.", call. = FALSE)
  }
  has_checkpoint <- app_joint_qdesn_phase180_checkpoint_complete(worker_dir)
  if (!has_checkpoint && dir.exists(worker_dir) &&
      length(list.files(worker_dir, all.files = TRUE, no.. = TRUE))) {
    quarantine <- paste0(
      worker_dir, ".incomplete.", format(Sys.time(), "%Y%m%dT%H%M%S")
    )
    if (!file.rename(worker_dir, quarantine)) {
      stop("Could not quarantine incomplete Phase181 worker.", call. = FALSE)
    }
  }
  app_ensure_dir(worker_dir)
  tryCatch({
    control <- freeze$controls[
      freeze$controls$mcmc_case_id == job$mcmc_case_id[[1L]], , drop = FALSE
    ]
    if (nrow(control) != 1L ||
        control$source_control_row_sha256[[1L]] !=
          job$source_control_row_sha256[[1L]]) {
      stop("Phase181 worker could not resolve its frozen control.", call. = FALSE)
    }
    loaded <- app_joint_qdesn_phase180_load_fixture(
      job$scenario_id[[1L]], freeze$config$fixture_dir[[1L]]
    )
    fixture <- loaded$fixture
    K <- length(fixture$tau); p <- ncol(fixture$Z)
    init <- app_joint_qdesn_phase180_reconstruct_init(
      freeze$init, job$mcmc_case_id[[1L]], job$likelihood_family[[1L]],
      job$fit_structure[[1L]], K, p
    )
    init <- app_joint_qdesn_phase180_apply_chain_start(
      init, freeze$starts, job, K, p
    )
    checkpoint <- if (has_checkpoint) {
      app_joint_qdesn_phase180_load_checkpoint(
        worker_dir, fixture, job, component, freeze$dir
      )
    } else {
      started <- proc.time()[["elapsed"]]
      fit <- app_joint_qdesn_phase180_fit_chain(job, control, fixture, init)
      elapsed <- proc.time()[["elapsed"]] - started
      app_joint_qdesn_phase180_write_checkpoint(
        fit, fixture, job, component, elapsed, freeze$dir, worker_dir,
        checkpoint_role = "phase181_same_specification_extension_postfit_prescore"
      )
    }
    fit <- checkpoint$fit; draws <- checkpoint$draws
    meta <- app_joint_qdesn_phase180_score_meta(job)
    fit_score <- app_joint_qdesn_phase122_score_qhat(
      meta, fixture, app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau),
      "qhat", "phase181_chain_fit"
    )
    forecast_score <- app_joint_qdesn_phase122_forecast_scores(
      meta, loaded$artifacts, job$scenario_id[[1L]], fixture, fit,
      "qhat", "phase181_chain_forecast"
    )
    contract_crossings <- sum(fit_score$contract_crossing$n_crossing_pairs) +
      sum(forecast_score$contract_crossing$n_crossing_pairs)
    summary <- data.frame(
      phase_id = freeze$extension_contract$version,
      worker_id = worker_id, mcmc_case_id = job$mcmc_case_id[[1L]],
      case_id = job$case_id[[1L]], scenario_id = job$scenario_id[[1L]],
      source_model_id = job$source_model_id[[1L]],
      likelihood_family = job$likelihood_family[[1L]],
      fit_structure = job$fit_structure[[1L]],
      inference_method_id = job$inference_method_id[[1L]],
      chain_id = job$chain_id[[1L]], chain_seed = job$chain_seed[[1L]],
      n_iter = job$n_iter[[1L]], burn = job$burn[[1L]], thin = job$thin[[1L]],
      n_keep = nrow(draws),
      draws_all_finite = all(is.finite(as.matrix(draws[, -1L, drop = FALSE]))),
      fit_truth_mae = mean(fit_score$scored$truth_abs_error),
      forecast_truth_mae = mean(forecast_score$scored$truth_abs_error),
      fit_check_loss_mean = mean(fit_score$scored$check_loss),
      forecast_check_loss_mean = mean(forecast_score$scored$check_loss),
      fit_raw_crossing_pairs = sum(fit_score$raw_crossing$n_crossing_pairs),
      forecast_raw_crossing_pairs = sum(
        forecast_score$raw_crossing$n_crossing_pairs
      ),
      contract_crossing_pairs = contract_crossings,
      min_sigma = min(fit$sigma_draws), max_sigma = max(fit$sigma_draws),
      min_gamma = if (!is.null(fit$gamma_draws)) min(fit$gamma_draws) else NA_real_,
      max_gamma = if (!is.null(fit$gamma_draws)) max(fit$gamma_draws) else NA_real_,
      elapsed_seconds = checkpoint$metadata$elapsed_seconds[[1L]],
      stringsAsFactors = FALSE
    )
    if (!summary$draws_all_finite[[1L]] || contract_crossings != 0L) {
      stop("Phase181 worker failed the finite/noncrossing contract.", call. = FALSE)
    }
    readme <- file.path(worker_dir, "README.md")
    writeLines(c(
      sprintf("# Phase181 worker %d", worker_id), "",
      sprintf("- Cell: `%s`", job$mcmc_case_id[[1L]]),
      sprintf("- Chain: %d", job$chain_id[[1L]]),
      sprintf("- Likelihood/sampler: `%s` / `%s`",
              job$likelihood_family[[1L]], job$inference_method_id[[1L]]),
      "- DESN, tau0, prior, fixture, forecast, and quantile-grid controls are frozen.",
      "- Posterior draws use compressed CSV; no serialized R workspace is retained."
    ), readme, useBytes = TRUE)
    runtime <- summary[, c(
      "phase_id", "worker_id", "mcmc_case_id", "case_id", "chain_id",
      "chain_seed", "elapsed_seconds"
    ), drop = FALSE]
    paths <- c(
      checkpoint$paths,
      chain_summary = app_joint_qvp_write_csv(
        summary, file.path(worker_dir, "chain_summary.csv")
      ),
      runtime = app_joint_qvp_write_csv(
        runtime, file.path(worker_dir, "runtime.csv")
      ),
      provenance = app_joint_qvp_write_csv(
        app_joint_qvp_provenance_rows(), file.path(worker_dir, "provenance.csv")
      ),
      README = normalizePath(readme, mustWork = TRUE)
    )
    app_joint_exqdesn_write_manifest(paths, worker_dir)
    if (!app_joint_qdesn_phase180_worker_complete(worker_dir)) {
      stop("Phase181 worker manifest failed.", call. = FALSE)
    }
    stale <- c(
      file.path(worker_dir, "failure_receipt.csv"),
      if (!is.null(failure_dir) && nzchar(failure_dir)) {
        file.path(failure_dir, sprintf("worker_%04d.csv", worker_id))
      } else character()
    )
    if (any(file.exists(stale))) unlink(stale[file.exists(stale)], force = TRUE)
    list(worker_id = worker_id, status = "completed", worker_dir = worker_dir)
  }, error = function(e) {
    receipt <- data.frame(
      worker_id = worker_id, mcmc_case_id = job$mcmc_case_id[[1L]],
      case_id = job$case_id[[1L]], chain_id = job$chain_id[[1L]],
      message = conditionMessage(e),
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      stringsAsFactors = FALSE
    )
    app_joint_qvp_write_csv(receipt, file.path(worker_dir, "failure_receipt.csv"))
    if (!is.null(failure_dir) && nzchar(failure_dir)) {
      app_ensure_dir(failure_dir)
      app_joint_qvp_write_csv(
        receipt, file.path(failure_dir, sprintf("worker_%04d.csv", worker_id))
      )
    }
    stop(e)
  })
}

app_joint_qdesn_phase181_health <- function(
  freeze_dir, orchestration_dir = NULL
) {
  freeze <- app_joint_qdesn_phase181_load_freeze(freeze_dir)
  complete <- vapply(
    freeze$plan$worker_output_dir,
    app_joint_qdesn_phase180_worker_complete, logical(1L)
  )
  exits <- if (!is.null(orchestration_dir)) {
    file.path(
      orchestration_dir, "exits",
      sprintf("worker_%04d.exit", freeze$plan$worker_id)
    )
  } else rep("", nrow(freeze$plan))
  failed <- vapply(exits, function(path) {
    if (!nzchar(path) || !file.exists(path)) return(FALSE)
    value <- suppressWarnings(as.integer(readLines(path, warn = FALSE)[[1L]]))
    is.finite(value) && value != 0L
  }, logical(1L))
  state <- ifelse(complete, "complete", ifelse(failed, "failed", "remaining"))
  plan <- freeze$plan; plan$state <- state
  by_case <- app_joint_qdesn_bind_rows(lapply(
    split(plan, plan$mcmc_case_id), function(x) {
      data.frame(
        mcmc_case_id = x$mcmc_case_id[[1L]], case_id = x$case_id[[1L]],
        scenario_id = x$scenario_id[[1L]],
        source_model_id = x$source_model_id[[1L]],
        likelihood_family = x$likelihood_family[[1L]],
        planned = nrow(x), complete = sum(x$state == "complete"),
        failed = sum(x$state == "failed"),
        remaining = sum(x$state == "remaining"),
        stringsAsFactors = FALSE
      )
    }
  ))
  list(
    summary = data.frame(
      stage = "phase181_same_specification_score_stability_extension",
      planned = nrow(plan), complete = sum(complete),
      failed = sum(failed & !complete), remaining = sum(!complete & !failed),
      percent_complete = 100 * mean(complete),
      cells_complete = sum(by_case$complete == by_case$planned),
      cells_planned = nrow(by_case), stringsAsFactors = FALSE
    ),
    by_case = by_case, plan = plan
  )
}

app_joint_qdesn_phase181_score_cell_matches <- function(path, jobs) {
  if (!app_joint_qdesn_postscore_cell_complete(path)) return(FALSE)
  source_path <- file.path(path, "source_inventory.csv")
  if (!file.exists(source_path)) return(FALSE)
  actual <- tryCatch(app_read_csv(source_path), error = function(e) NULL)
  if (is.null(actual) || nrow(actual) != nrow(jobs)) return(FALSE)
  expected <- data.frame(
    chain_id = as.integer(jobs$chain_id),
    worker_output_dir = normalizePath(jobs$worker_output_dir),
    worker_manifest_sha256 = vapply(jobs$worker_output_dir, function(worker_dir) {
      app_sha256_file(file.path(worker_dir, "artifact_manifest.csv"))
    }, character(1L)), stringsAsFactors = FALSE
  )
  actual <- actual[order(actual$chain_id), c(
    "chain_id", "worker_output_dir", "worker_manifest_sha256"
  ), drop = FALSE]
  expected <- expected[order(expected$chain_id), , drop = FALSE]
  identical(
    lapply(actual, as.character),
    lapply(expected, as.character)
  )
}

app_joint_qdesn_phase181_score_cell <- function(
  jobs, freeze, contract, work_dir
) {
  path <- app_joint_qdesn_postscore_cell_dir(
    work_dir, jobs$mcmc_case_id[[1L]]
  )
  if (app_joint_qdesn_phase181_score_cell_matches(path, jobs)) {
    return(normalizePath(path))
  }
  if (dir.exists(path)) unlink(path, recursive = TRUE, force = TRUE)
  result <- app_joint_qdesn_postscore_case(
    jobs, freeze, contract,
    fixture_loader = app_joint_qdesn_phase180_score_fixture_loader,
    fit_loader = app_joint_qdesn_phase180_score_fit_loader
  )
  app_joint_qdesn_postscore_write_cell(result, path)
  normalizePath(path)
}

app_joint_qdesn_phase181_run_score_cells <- function(
  groups, freeze, contract, work_dir, cores = 8L
) {
  run <- function(index) try(
    app_joint_qdesn_phase181_score_cell(
      groups[[index]], freeze, contract, work_dir
    ), silent = TRUE
  )
  result <- if (.Platform$OS.type != "windows" && cores > 1L) {
    parallel::mclapply(
      seq_along(groups), run,
      mc.cores = min(as.integer(cores), length(groups)),
      mc.preschedule = FALSE
    )
  } else lapply(seq_along(groups), run)
  failed <- vapply(result, inherits, logical(1L), "try-error")
  if (any(failed)) {
    stop(sprintf(
      "Phase181 score reconstruction failed: %s",
      paste(vapply(result[failed], as.character, character(1L)), collapse = " | ")
    ), call. = FALSE)
  }
  paths <- unlist(result, use.names = FALSE)
  names(paths) <- names(groups)
  paths
}

app_joint_qdesn_phase181_merge_score_summary <- function(
  score, registry, case_order = registry$case_id
) {
  keys <- c(
    "mcmc_case_id", "phase178_template_id", "case_id", "scenario_id",
    "base_scenario_id", "dgp_replicate_id", "validation_partition",
    "fit_structure", "variant_id", "candidate_role", "design_role",
    "distribution_family", "dynamics_class"
  )
  summary <- merge(
    score$diagnostics, score$canonical, by = keys, all = FALSE, sort = FALSE
  )
  metadata <- registry[, c(
    "case_id", "source_model_id", "model_id", "display_label",
    "likelihood_family", "source_action", "source_phase"
  ), drop = FALSE]
  metadata <- metadata[!duplicated(metadata$case_id), , drop = FALSE]
  summary <- merge(summary, metadata, by = "case_id", all.x = TRUE, sort = FALSE)
  summary <- summary[match(case_order, summary$case_id), , drop = FALSE]
  if (nrow(summary) != length(case_order) || anyNA(summary$case_id) ||
      anyDuplicated(summary$case_id)) {
    stop("Phase181 score summary lost or duplicated a cell.", call. = FALSE)
  }
  summary
}

app_joint_qdesn_phase181_extension_source_plan <- function(freeze) {
  out <- freeze$plan
  out$source_kind <- "phase181_extension"
  out$source_worker_id <- out$worker_id
  out$selection_source_role <- "phase181_extension_candidate"
  out$worker_manifest_verified <- vapply(
    out$worker_output_dir, app_joint_qdesn_phase180_worker_complete, logical(1L)
  )
  out$worker_manifest_sha256 <- vapply(out$worker_output_dir, function(path) {
    manifest <- file.path(path, "artifact_manifest.csv")
    if (file.exists(manifest)) app_sha256_file(manifest) else NA_character_
  }, character(1L))
  if (nrow(out) != freeze$extension_contract$expected_workers ||
      any(!out$worker_manifest_verified) ||
      anyDuplicated(paste(out$case_id, out$chain_id))) {
    stop("Phase181 extension source plan is incomplete.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase181_promotion_decisions <- function(
  baseline_summary, extension_summary, selection_audit,
  extension_source_status = NULL
) {
  baseline <- baseline_summary[, c(
    "case_id", "posterior_score_mean", "posterior_score_median",
    "posterior_score_q025", "posterior_score_q975",
    "score_functional_status", "coherence_status", "contract_crossing_pairs"
  ), drop = FALSE]
  names(baseline)[-1L] <- paste0("baseline_", names(baseline)[-1L])
  extension <- extension_summary[, c(
    "case_id", "scenario_id", "source_model_id", "likelihood_family",
    "fit_structure", "posterior_score_mean", "posterior_score_median",
    "posterior_score_q025", "posterior_score_q975", "score_rank_rhat",
    "score_bulk_ess", "score_tail_ess", "score_functional_status",
    "coherence_status", "contract_crossing_pairs"
  ), drop = FALSE]
  names(extension)[!names(extension) %in% c(
    "case_id", "scenario_id", "source_model_id", "likelihood_family",
    "fit_structure"
  )] <- paste0("extension_", names(extension)[!names(extension) %in% c(
    "case_id", "scenario_id", "source_model_id", "likelihood_family",
    "fit_structure"
  )])
  out <- merge(extension, baseline, by = "case_id", all.x = TRUE, sort = FALSE)
  triggers <- selection_audit[, c(
    "case_id", "extension_reason", "max_relative_loo_mean_shift"
  ), drop = FALSE]
  out <- merge(out, triggers, by = "case_id", all.x = TRUE, sort = FALSE)
  source_pass <- if (is.null(extension_source_status)) {
    rep(TRUE, nrow(out))
  } else {
    status <- extension_source_status[, c("case_id", "source_status"), drop = FALSE]
    status <- status[!duplicated(status$case_id), , drop = FALSE]
    status$source_status[match(out$case_id, status$case_id)] == "pass"
  }
  out$extension_source_manifests_pass <- source_pass
  out$hard_eligible <- with(out,
    extension_source_manifests_pass &
      is.finite(extension_posterior_score_mean) &
      is.finite(baseline_posterior_score_mean) &
      extension_contract_crossing_pairs == 0L
  )
  out$absolute_mean_improvement <- with(out,
    baseline_posterior_score_mean - extension_posterior_score_mean
  )
  out$relative_mean_improvement <- with(out,
    absolute_mean_improvement /
      pmax(abs(baseline_posterior_score_mean), .Machine$double.eps)
  )
  out$mean_metric_improved <- out$absolute_mean_improvement > 0
  out$mixing_review <- out$extension_score_functional_status != "pass"
  out$coherence_review <- out$extension_coherence_status != "pass"
  out$mixing_blocks_promotion <- FALSE
  out$coherence_review_blocks_promotion <- FALSE
  out$promotion_decision <- ifelse(
    out$hard_eligible & out$mean_metric_improved,
    "promote_phase181_extension", "retain_phase180_baseline"
  )
  out$promotion_reason <- ifelse(
    !out$hard_eligible, "retain_hard_gate_not_eligible",
    ifelse(
      out$mean_metric_improved,
      "promote_strictly_lower_finite_mean_under_user_rule",
      "retain_extension_mean_not_lower"
    )
  )
  out$claim_status <- ifelse(
    out$mixing_review | out$coherence_review,
    "descriptive_review", "descriptive_hard_gates_pass"
  )
  out
}

app_joint_qdesn_phase181_source_complete <- function(row) {
  path <- row$worker_output_dir[[1L]]
  if (row$source_kind[[1L]] == "phase172_reuse") {
    app_joint_exqdesn_phase172_worker_complete(path)
  } else {
    app_joint_qdesn_phase180_worker_complete(path)
  }
}

app_joint_qdesn_phase181_selected_source_plan <- function(
  parent_plan, extension_plan, decisions, case_order, n_chains = 8L,
  verify_workers = TRUE
) {
  promoted <- decisions$case_id[
    decisions$promotion_decision == "promote_phase181_extension"
  ]
  parent <- parent_plan[!parent_plan$case_id %in% promoted, , drop = FALSE]
  extension <- extension_plan[extension_plan$case_id %in% promoted, , drop = FALSE]
  parent$selection_source_role <- ifelse(
    parent$case_id %in% decisions$case_id,
    "phase180_retained_after_extension_comparison",
    "phase180_unaffected_retained"
  )
  extension$selection_source_role <- "phase181_promoted_lower_mean"
  if (!"source_worker_id" %in% names(parent)) {
    parent$source_worker_id <- parent$worker_id
  }
  fields <- union(names(parent), names(extension))
  align <- function(x) {
    for (name in setdiff(fields, names(x))) x[[name]] <- NA
    x[, fields, drop = FALSE]
  }
  out <- rbind(align(parent), align(extension))
  out <- out[order(
    match(out$case_id, case_order), as.integer(out$chain_id)
  ), , drop = FALSE]
  out$selected_worker_id <- seq_len(nrow(out))
  out$worker_id <- out$selected_worker_id
  if (verify_workers) {
    complete <- vapply(seq_len(nrow(out)), function(ii) {
      app_joint_qdesn_phase181_source_complete(out[ii, , drop = FALSE])
    }, logical(1L))
    out$worker_manifest_verified <- complete
    out$worker_manifest_sha256 <- vapply(out$worker_output_dir, function(path) {
      manifest <- file.path(path, "artifact_manifest.csv")
      if (file.exists(manifest)) app_sha256_file(manifest) else NA_character_
    }, character(1L))
  } else {
    out$worker_manifest_verified <- TRUE
    out$worker_manifest_sha256 <- "test_manifest"
  }
  if (nrow(out) != length(case_order) * n_chains ||
      length(unique(out$case_id)) != length(case_order) ||
      any(table(out$case_id) != n_chains) ||
      anyDuplicated(paste(out$case_id, out$chain_id)) ||
      any(!out$worker_manifest_verified)) {
    stop("Phase181 selected source plan is incomplete or unverifiable.",
         call. = FALSE)
  }
  out
}

app_joint_qdesn_phase181_source_status <- function(score_source) {
  app_joint_qdesn_bind_rows(lapply(split(score_source, score_source$case_id), function(x) {
    data.frame(
      case_id = x$case_id[[1L]], expected_chains = 8L,
      source_chains = nrow(x),
      manifests_pass = all(x$worker_manifest_status == "pass"),
      source_status = if (
        nrow(x) == 8L && all(x$worker_manifest_status == "pass")
      ) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_phase181_collect_supplements <- function(
  groups, freeze, cores
) {
  result <- if (.Platform$OS.type != "windows" && cores > 1L) {
    parallel::mclapply(
      groups, app_joint_qdesn_phase180_case_supplement, freeze = freeze,
      mc.cores = min(as.integer(cores), length(groups)),
      mc.preschedule = FALSE
    )
  } else lapply(groups, app_joint_qdesn_phase180_case_supplement, freeze = freeze)
  list(
    oracle = app_joint_qdesn_bind_rows(lapply(result, `[[`, "oracle")),
    parameters = app_joint_qdesn_bind_rows(lapply(result, `[[`, "parameters"))
  )
}

app_joint_qdesn_phase181_score_inventory <- function(paths, role) {
  data.frame(
    score_role = role, case_id = names(paths),
    cell_dir = normalizePath(paths),
    manifest_sha256 = vapply(paths, function(path) {
      app_sha256_file(file.path(path, "artifact_manifest.csv"))
    }, character(1L)),
    status = "pass", stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase181_finalize <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  freeze_dir = NULL, out_dir = NULL, score_cores = 8L, force = FALSE
) {
  dirs <- app_joint_qdesn_phase181_dirs(cache_root)
  freeze_dir <- freeze_dir %||% dirs$freeze
  out_dir <- out_dir %||% dirs$packet
  freeze <- app_joint_qdesn_phase181_load_freeze(freeze_dir)
  parent <- app_joint_qdesn_phase181_verify_parent(
    dirs, freeze$extension_contract
  )
  health <- app_joint_qdesn_phase181_health(freeze_dir, dirs$orchestration)
  if (health$summary$failed[[1L]] > 0L || health$summary$remaining[[1L]] > 0L ||
      health$summary$complete[[1L]] != freeze$extension_contract$expected_workers) {
    stop("Phase181 cannot finalize before all 152 workers pass.", call. = FALSE)
  }
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- tryCatch(
      app_joint_exqdesn_verify_manifest(out_dir, "phase181_packet"),
      error = function(e) NULL
    )
    if (!is.null(check) && all(check$status == "pass")) {
      return(list(
        out_dir = normalizePath(out_dir),
        assessment = app_read_csv(file.path(out_dir, "final_gate_assessment.csv")),
        reused = TRUE
      ))
    }
  }

  extension_plan <- app_joint_qdesn_phase181_extension_source_plan(freeze)
  extension_groups <- split(
    extension_plan,
    factor(extension_plan$case_id, levels = freeze$registry$case_id)
  )
  extension_paths <- app_joint_qdesn_phase181_run_score_cells(
    extension_groups, freeze, freeze$contract, dirs$extension_score_work,
    as.integer(score_cores)
  )
  extension_score <- app_joint_qdesn_postscore_collect_cells(extension_paths)
  extension_source_status <- app_joint_qdesn_phase181_source_status(
    extension_score$source
  )
  if (nrow(extension_score$diagnostics) !=
        freeze$extension_contract$expected_extension_cells ||
      any(extension_score$diagnostics$contract_crossing_pairs != 0L) ||
      any(extension_score$previsibility$status != "pass") ||
      any(extension_source_status$source_status != "pass")) {
    stop("Phase181 extension score cells failed a hard gate.", call. = FALSE)
  }
  extension_summary <- app_joint_qdesn_phase181_merge_score_summary(
    extension_score, freeze$registry, freeze$registry$case_id
  )
  baseline_summary <- app_read_csv(file.path(
    dirs$parent_packet, "posterior_dgp_integrated_acrps_summary.csv"
  ))
  decisions <- app_joint_qdesn_phase181_promotion_decisions(
    baseline_summary, extension_summary, freeze$selection,
    extension_source_status
  )
  decisions <- decisions[match(freeze$registry$case_id, decisions$case_id), , drop = FALSE]
  if (nrow(decisions) != freeze$extension_contract$expected_extension_cells ||
      anyNA(decisions$promotion_decision)) {
    stop("Phase181 promotion decisions are incomplete.", call. = FALSE)
  }

  parent_plan <- app_read_csv(file.path(
    dirs$parent_packet, "final_source_registry.csv"
  ))
  parent_case_order <- parent$freeze$registry$case_id
  selected_plan <- app_joint_qdesn_phase181_selected_source_plan(
    parent_plan, extension_plan, decisions, parent_case_order,
    n_chains = freeze$extension_contract$n_chains,
    verify_workers = TRUE
  )
  selected_groups <- split(
    selected_plan,
    factor(selected_plan$case_id, levels = parent_case_order)
  )
  selected_paths <- app_joint_qdesn_phase181_run_score_cells(
    selected_groups, freeze, freeze$contract, dirs$selected_score_work,
    as.integer(score_cores)
  )
  selected_score <- app_joint_qdesn_postscore_collect_cells(selected_paths)
  selected_source_status <- app_joint_qdesn_phase181_source_status(
    selected_score$source
  )
  if (nrow(selected_score$diagnostics) !=
        freeze$extension_contract$expected_total_cells ||
      any(selected_score$diagnostics$contract_crossing_pairs != 0L) ||
      any(selected_score$previsibility$status != "pass") ||
      any(selected_source_status$source_status != "pass")) {
    stop("Phase181 recomposed 32-cell score packet failed a hard gate.",
         call. = FALSE)
  }
  selected_summary <- app_joint_qdesn_phase181_merge_score_summary(
    selected_score, parent$freeze$registry, parent_case_order
  )
  selected_summary$selected_source_role <- selected_plan$selection_source_role[
    match(selected_summary$case_id, selected_plan$case_id)
  ]
  selected_summary$phase181_promoted <- selected_summary$case_id %in%
    decisions$case_id[
      decisions$promotion_decision == "promote_phase181_extension"
    ]
  selected_summary$claim_status <- ifelse(
    selected_summary$score_functional_status == "pass" &
      selected_summary$coherence_status == "pass",
    "descriptive_hard_gates_pass", "descriptive_review"
  )
  promoted_ids <- selected_summary$case_id[selected_summary$phase181_promoted]
  if (length(promoted_ids)) {
    expected_promoted <- extension_summary$posterior_score_mean[
      match(promoted_ids, extension_summary$case_id)
    ]
    actual_promoted <- selected_summary$posterior_score_mean[
      match(promoted_ids, selected_summary$case_id)
    ]
    if (any(abs(expected_promoted - actual_promoted) > 1e-12)) {
      stop("Phase181 promoted source recomposition changed an extension score.",
           call. = FALSE)
    }
  }

  formula <- app_joint_qdesn_postscore_formula_audit(freeze$contract)
  oracle_minimum <- app_joint_qdesn_postscore_oracle_minimum_audit(freeze$contract)
  if (any(formula$analytic_status != "pass") ||
      any(formula$monte_carlo_status != "pass") ||
      any(oracle_minimum$status != "pass")) {
    stop("Phase181 DGP-score formula audit failed.", call. = FALSE)
  }
  pairing <- app_joint_qdesn_postscore_pairing_stability(
    selected_score$pairing_sensitivity, freeze$contract
  )
  contrast <- app_joint_qdesn_postscore_joint_independent_contrasts(
    selected_score$draws, freeze$contract
  )
  if (nrow(contrast$summary) != 16L) {
    stop("Phase181 must produce 16 joint/independent contrasts.", call. = FALSE)
  }
  extension_supplement <- app_joint_qdesn_phase181_collect_supplements(
    extension_groups, freeze, as.integer(score_cores)
  )
  selected_supplement <- app_joint_qdesn_phase181_collect_supplements(
    selected_groups, freeze, as.integer(score_cores)
  )
  runtime <- app_joint_qdesn_phase180_collect_runtime(selected_plan)
  crossing <- merge(
    selected_supplement$oracle[, c(
      "case_id", "window", "raw_crossing_pairs", "contract_crossing_pairs",
      "mean_abs_monotone_adjustment", "max_abs_monotone_adjustment"
    ), drop = FALSE],
    selected_summary[, c(
      "case_id", "raw_crossing_rate", "coherence_status"
    ), drop = FALSE],
    by = "case_id", all.x = TRUE, sort = FALSE
  )
  extension_pairing <- app_joint_qdesn_postscore_pairing_stability(
    extension_score$pairing_sensitivity, freeze$contract
  )
  compatibility <- selected_summary[, c(
    "case_id", "scenario_id", "source_model_id", "likelihood_family",
    "posterior_realized_acrps_mean", "canonical_action_realized_acrps",
    "posterior_score_mean", "canonical_action_dgp_integrated_acrps"
  ), drop = FALSE]
  phase174 <- app_read_csv(file.path(
    app_joint_qdesn_phase180_dirs(cache_root)$phase174,
    "final_mcmc_case_summary.csv"
  ))
  compatibility <- merge(
    compatibility,
    phase174[, c("scenario_id", "source_model_id", "mcmc_forecast_crps_grid")],
    by = c("scenario_id", "source_model_id"), all.x = TRUE, sort = FALSE
  )
  compatibility$canonical_realized_minus_phase174 <-
    compatibility$canonical_action_realized_acrps -
      compatibility$mcmc_forecast_crps_grid
  compatibility$comparison_role <-
    "secondary_realized_score_compatibility_not_primary_ranking"

  hard_fail <- nrow(selected_summary) != 32L ||
    any(!is.finite(selected_summary$posterior_score_mean)) ||
    any(!is.finite(selected_summary$canonical_action_dgp_integrated_acrps)) ||
    any(selected_summary$contract_crossing_pairs != 0L) ||
    any(!selected_plan$worker_manifest_verified) ||
    any(selected_score$previsibility$status != "pass")
  diagnostic_review <- any(selected_summary$score_functional_status != "pass") ||
    any(selected_summary$coherence_status != "pass") ||
    any(pairing$pairing_status == "review")
  gate <- if (hard_fail) "fail" else if (diagnostic_review) "review" else "pass"
  assessment <- data.frame(
    phase_id = freeze$extension_contract$version,
    gate_status = gate,
    implementation_hard_gates = if (hard_fail) "fail" else "pass",
    final_cells = nrow(selected_summary), extension_cells = nrow(decisions),
    promoted_extension_cells = sum(
      decisions$promotion_decision == "promote_phase181_extension"
    ),
    retained_after_extension_cells = sum(
      decisions$promotion_decision == "retain_phase180_baseline"
    ),
    unaffected_phase180_cells = freeze$extension_contract$expected_unaffected_cells,
    extension_workers_complete = health$summary$complete[[1L]],
    extension_workers_failed = health$summary$failed[[1L]],
    final_score_functional_pass = sum(
      selected_summary$score_functional_status == "pass"
    ),
    final_score_functional_review = sum(
      selected_summary$score_functional_status != "pass"
    ),
    final_coherence_review = sum(selected_summary$coherence_status != "pass"),
    contract_crossing_pairs = sum(selected_summary$contract_crossing_pairs),
    joint_independent_contrasts = nrow(contrast$summary),
    promotion_metric = freeze$extension_contract$promotion_metric,
    mixing_blocks_promotion = FALSE,
    case_specific_controls_preserved = TRUE,
    article_claim_status = "descriptive",
    article_assets_modified = FALSE,
    recommendation = if (hard_fail) {
      "repair_phase181_hard_failure"
    } else {
      "stage_mean_selected_packet_with_review_disclosure"
    },
    stringsAsFactors = FALSE
  )

  extension_inventory <- app_joint_qdesn_phase181_score_inventory(
    extension_paths, "extension_candidate"
  )
  selected_inventory <- app_joint_qdesn_phase181_score_inventory(
    selected_paths, "final_selected"
  )
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase181 mean-selected score-stability packet", "",
    "This packet compares 19 same-specification extensions with immutable Phase180 means.",
    "Any strictly lower finite extension mean is promoted after hard gates.",
    "Mixing and raw coherence are retained as review diagnostics, not promotion vetoes.",
    "The final selected source plan contains exactly 32 cells and eight chains per cell.",
    "All conclusions remain descriptive under the current seven-level quantile grid."
  ), readme, useBytes = TRUE)
  paths <- c(
    phase181_extension_contract = write(
      freeze$extension_contract$table, "phase181_extension_contract.csv"
    ),
    phase180_score_contract = write(
      freeze$contract$table, "phase180_score_contract.csv"
    ),
    parent_freeze_manifest_verification = write(
      parent$freeze_check, "parent_freeze_manifest_verification.csv"
    ),
    parent_packet_manifest_verification = write(
      parent$packet_check, "parent_packet_manifest_verification.csv"
    ),
    worker_health_summary = write(health$summary, "worker_health_summary.csv"),
    worker_health_by_case = write(health$by_case, "worker_health_by_case.csv"),
    chain_leave_one_out_audit = write(
      freeze$loo, "chain_leave_one_out_audit.csv"
    ),
    extension_cell_selection_audit = write(
      freeze$selection, "extension_cell_selection_audit.csv"
    ),
    extension_source_registry = write(
      extension_plan, "extension_source_registry.csv"
    ),
    extension_source_status = write(
      extension_source_status, "extension_source_status.csv"
    ),
    extension_posterior_draws = app_joint_qdesn_postscore_write_gzip_csv(
      extension_score$draws,
      file.path(tmp, "extension_posterior_dgp_integrated_acrps_draws.csv.gz")
    ),
    extension_posterior_summary = write(
      extension_summary,
      "extension_posterior_dgp_integrated_acrps_summary.csv"
    ),
    extension_score_functional_diagnostics = write(
      extension_score$diagnostics,
      "extension_score_functional_mcmc_diagnostics.csv"
    ),
    extension_pairing_sensitivity = write(
      extension_pairing, "extension_pairing_seed_sensitivity.csv"
    ),
    extension_parameter_diagnostics = write(
      extension_supplement$parameters,
      "extension_parameter_block_diagnostics.csv"
    ),
    extension_oracle_diagnostics = write(
      extension_supplement$oracle,
      "extension_oracle_recovery_diagnostics.csv"
    ),
    mean_metric_promotion_decisions = write(
      decisions, "mean_metric_promotion_decisions.csv"
    ),
    final_selected_source_registry = write(
      selected_plan, "final_selected_source_registry.csv"
    ),
    final_selected_source_status = write(
      selected_source_status, "final_selected_source_status.csv"
    ),
    posterior_dgp_integrated_acrps_draws = app_joint_qdesn_postscore_write_gzip_csv(
      selected_score$draws,
      file.path(tmp, "posterior_dgp_integrated_acrps_draws.csv.gz")
    ),
    posterior_dgp_integrated_acrps_summary = write(
      selected_summary, "posterior_dgp_integrated_acrps_summary.csv"
    ),
    canonical_action_dgp_integrated_acrps = write(
      selected_score$canonical, "canonical_action_dgp_integrated_acrps.csv"
    ),
    dgp_integrated_score_by_tau = write(
      selected_score$canonical_tau, "dgp_integrated_score_by_tau.csv"
    ),
    joint_independent_score_contrast_draws =
      app_joint_qdesn_postscore_write_gzip_csv(
        contrast$draws,
        file.path(tmp, "joint_independent_score_contrast_draws.csv.gz")
      ),
    joint_independent_score_contrast_summary = write(
      contrast$summary, "joint_independent_score_contrast_summary.csv"
    ),
    realized_expected_score_comparison = write(
      compatibility, "realized_expected_score_comparison.csv"
    ),
    oracle_recovery_diagnostics = write(
      selected_supplement$oracle, "oracle_recovery_diagnostics.csv"
    ),
    raw_contract_crossing_summary = write(
      crossing, "raw_contract_crossing_summary.csv"
    ),
    parameter_block_diagnostics = write(
      selected_supplement$parameters, "parameter_block_diagnostics.csv"
    ),
    score_functional_mcmc_diagnostics = write(
      selected_score$diagnostics, "score_functional_mcmc_diagnostics.csv"
    ),
    chain_allocation_sensitivity = write(
      selected_score$allocation, "chain_allocation_sensitivity.csv"
    ),
    independent_pairing_seed_sensitivity = write(
      pairing, "independent_pairing_seed_sensitivity.csv"
    ),
    forecast_previsibility_audit = write(
      selected_score$previsibility, "forecast_previsibility_audit.csv"
    ),
    dgp_family_parameterization_audit = write(
      formula, "dgp_family_parameterization_audit.csv"
    ),
    oracle_minimum_audit = write(
      oracle_minimum, "oracle_minimum_audit.csv"
    ),
    runtime_summary = write(runtime, "runtime_summary.csv"),
    score_cell_inventory = write(
      app_joint_qdesn_bind_rows(list(extension_inventory, selected_inventory)),
      "score_cell_inventory.csv"
    ),
    final_gate_assessment = write(
      assessment, "final_gate_assessment.csv"
    ),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(
      final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S")
    )
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine prior Phase181 packet.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, final_dir)) {
    stop("Could not publish Phase181 packet.", call. = FALSE)
  }
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase181_packet")
  if (any(check$status != "pass")) {
    stop("Phase181 packet manifest failed.", call. = FALSE)
  }
  list(out_dir = final_dir, assessment = assessment, decisions = decisions,
       reused = FALSE)
}

app_joint_qdesn_phase181_article_table_lines <- function(table) {
  scenarios <- unique(table$scenario_id)
  models <- c(
    "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
  )
  header <- c(
    "% Phase181 article-facing table staged from a hash-verified selected packet.",
    "\\begin{table}[!htbp]", "\\centering", "\\scriptsize",
    "\\resizebox{\\textwidth}{!}{%",
    "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.23\\textwidth}rrrr@{}}",
    "\\toprule",
    paste0(
      "Scenario & \\shortstack{Joint QDESN\\\\AL--RHS} & ",
      "\\shortstack{Independent QDESN\\\\AL--RHS} & ",
      "\\shortstack{Joint exQDESN\\\\exAL--RHS} & ",
      "\\shortstack{Independent exQDESN\\\\exAL--RHS} \\\\"
    ),
    "\\midrule"
  )
  body <- vapply(scenarios, function(scenario_id) {
    block <- table[table$scenario_id == scenario_id, , drop = FALSE]
    block <- block[match(models, block$source_model_id), , drop = FALSE]
    if (anyNA(block$source_model_id)) {
      stop("Phase181 article table lost a model cell.", call. = FALSE)
    }
    entries <- sprintf(
      "%.4f [%.4f, %.4f]",
      block$posterior_score_mean, block$posterior_score_q025,
      block$posterior_score_q975
    )
    entries[block$numerical_winner] <- paste0(
      "\\textbf{", entries[block$numerical_winner], "}"
    )
    paste0(
      paste(c(block$scenario_label[[1L]], entries), collapse = " & "),
      " \\\\"
    )
  }, character(1L))
  footer <- c(
    "\\bottomrule", "\\end{tabular}", "}%",
    paste0(
      "\\caption{Balanced MCMC comparison under the current seven-level quantile grid. ",
      "Entries are posterior means of the DGP-integrated finite-grid quantile score ",
      "with equal-tailed 95\\% credible intervals. Lower values are better, and ",
      "boldface marks the numerical minimum within each scenario. Phase181 replaces ",
      "a Phase180 source only when a complete same-specification extension has a lower ",
      "finite posterior score mean and passes all implementation, provenance, and ",
      "contract-noncrossing gates. Mixing and raw-coherence reviews remain disclosed; ",
      "numerical winners are descriptive.}"
    ),
    "\\label{tab:joint-qdesn-phase181-dgp-integrated-score}",
    "\\end{table}"
  )
  c(header, body, footer)
}

app_joint_qdesn_phase181_stage_article_assets <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  packet_dir = NULL, out_dir = NULL, force = FALSE
) {
  dirs <- app_joint_qdesn_phase181_dirs(cache_root)
  packet_dir <- packet_dir %||% dirs$packet
  out_dir <- out_dir %||% dirs$article_staging
  packet_check <- app_joint_exqdesn_verify_manifest(
    packet_dir, "phase181_packet"
  )
  assessment <- app_read_csv(file.path(packet_dir, "final_gate_assessment.csv"))
  if (any(packet_check$status != "pass") ||
      assessment$implementation_hard_gates[[1L]] != "pass" ||
      assessment$contract_crossing_pairs[[1L]] != 0L) {
    stop("Phase181 article staging requires all hard gates to pass.", call. = FALSE)
  }
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- tryCatch(
      app_joint_exqdesn_verify_manifest(out_dir, "phase181_article_staging"),
      error = function(e) NULL
    )
    if (!is.null(check) && all(check$status == "pass")) {
      return(list(
        out_dir = normalizePath(out_dir),
        table = app_read_csv(file.path(
          out_dir, "joint_qdesn_phase181_article_scenario_model_summary.csv"
        )),
        asset_manifest = app_read_csv(file.path(out_dir, "article_asset_inventory.csv")),
        reused = TRUE
      ))
    }
  }
  score <- app_read_csv(file.path(
    packet_dir, "posterior_dgp_integrated_acrps_summary.csv"
  ))
  decisions <- app_read_csv(file.path(
    packet_dir, "mean_metric_promotion_decisions.csv"
  ))
  oracle <- app_read_csv(file.path(packet_dir, "oracle_recovery_diagnostics.csv"))
  crossing <- app_read_csv(file.path(
    packet_dir, "raw_contract_crossing_summary.csv"
  ))
  contrast <- app_read_csv(file.path(
    packet_dir, "joint_independent_score_contrast_summary.csv"
  ))
  phase174 <- app_read_csv(file.path(
    app_joint_qdesn_phase180_dirs(cache_root)$phase174,
    "final_mcmc_case_summary.csv"
  ))
  labels <- unique(phase174[, c(
    "scenario_id", "scenario_label", "mechanism_detail", "scenario_order"
  ), drop = FALSE])
  table <- merge(score, labels, by = "scenario_id", all.x = TRUE, sort = FALSE)
  table <- table[order(table$scenario_order, table$source_model_id), , drop = FALSE]
  table$numerical_winner <- ave(
    table$posterior_score_mean, table$scenario_id,
    FUN = function(x) x == min(x)
  ) > 0
  table$headline_metric <- "DGP-integrated finite-grid quantile score"
  table$winner_interpretation <- "descriptive_numerical_minimum"
  table$mixing_is_promotion_veto <- FALSE
  table$scalar_predictive_density_claim <- FALSE
  if (nrow(table) != 32L || length(unique(table$scenario_id)) != 8L ||
      sum(table$numerical_winner) < 8L ||
      any(!is.finite(as.matrix(table[, c(
        "posterior_score_mean", "posterior_score_q025", "posterior_score_q975",
        "canonical_action_dgp_integrated_acrps"
      ), drop = FALSE])))) {
    stop("Phase181 article table failed its 32-row finite gate.", call. = FALSE)
  }
  winner <- table[table$numerical_winner, c(
    "scenario_id", "scenario_label", "source_model_id", "display_label",
    "posterior_score_mean", "posterior_score_q025", "posterior_score_q975",
    "score_functional_status", "coherence_status", "claim_status",
    "winner_interpretation"
  ), drop = FALSE]
  oracle_forecast <- oracle[oracle$window == "forecast", , drop = FALSE]
  supplemental <- merge(
    table[, c(
      "case_id", "scenario_id", "source_model_id", "display_label",
      "posterior_realized_acrps_mean", "canonical_action_realized_acrps",
      "phase181_promoted", "score_functional_status", "coherence_status"
    ), drop = FALSE],
    oracle_forecast[, c(
      "case_id", "oracle_quantile_mae", "oracle_quantile_rmse",
      "raw_crossing_pairs", "contract_crossing_pairs"
    ), drop = FALSE], by = "case_id", all.x = TRUE, sort = FALSE
  )
  guidance <- data.frame(
    topic = c(
      "headline_metric", "promotion", "mixing", "crossings",
      "oracle_recovery", "predictive_contract", "winner_language"
    ),
    required_wording = c(
      "DGP-integrated finite-grid quantile score is the main forecast comparison.",
      "A Phase181 source replaces Phase180 only after a strictly lower finite mean and hard-gate pass.",
      "R-hat and ESS reviews are disclosed but are not promotion vetoes under the frozen user rule.",
      "Raw crossings diagnose pre-contract coherence; reported contract crossings are zero.",
      "Fit and forecast MAE/RMSE compare issued paths with known oracle quantiles.",
      "The joint composite likelihood is not asserted to be a scalar predictive density.",
      "Numerical minima remain descriptive, especially for review-level diagnostics."
    ), stringsAsFactors = FALSE
  )
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  tex <- file.path(tmp, "joint_qdesn_phase181_dgp_integrated_score_table.tex")
  writeLines(app_joint_qdesn_phase181_article_table_lines(table), tex, useBytes = TRUE)
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase181 article-safe staging", "",
    "This directory does not edit the manuscript or publish Overleaf.",
    "The table contains 32 finite cells selected by the frozen lower-mean rule.",
    "Mixing and coherence reviews are retained in the CSV evidence and wording guide.",
    "An integration coordinator must review and project these assets."
  ), readme, useBytes = TRUE)
  paths <- c(
    source_packet_manifest_verification = write(
      packet_check, "source_packet_manifest_verification.csv"
    ),
    article_scenario_model_summary = write(
      table, "joint_qdesn_phase181_article_scenario_model_summary.csv"
    ),
    numerical_winner_summary = write(
      winner, "joint_qdesn_phase181_numerical_winner_summary.csv"
    ),
    mean_metric_promotion_decisions = write(
      decisions, "joint_qdesn_phase181_mean_metric_promotion_decisions.csv"
    ),
    joint_independent_contrast_summary = write(
      contrast, "joint_qdesn_phase181_joint_independent_contrast_summary.csv"
    ),
    supplemental_diagnostics = write(
      supplemental, "joint_qdesn_phase181_supplemental_diagnostics.csv"
    ),
    crossing_provenance = write(
      crossing, "joint_qdesn_phase181_crossing_provenance.csv"
    ),
    manuscript_wording_guidance = write(
      guidance, "joint_qdesn_phase181_manuscript_wording_guidance.csv"
    ),
    article_table = normalizePath(tex, mustWork = TRUE),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  asset_inventory <- data.frame(
    artifact_id = names(paths),
    relative_path = basename(unname(paths)),
    sha256 = vapply(unname(paths), app_sha256_file, character(1L)),
    size_bytes = as.numeric(file.info(unname(paths))$size),
    article_safe = !names(paths) %in% c(
      "source_packet_manifest_verification", "provenance", "README"
    ),
    stringsAsFactors = FALSE
  )
  paths <- c(
    paths,
    article_asset_inventory = write(
      asset_inventory, "article_asset_inventory.csv"
    )
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(
      final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S")
    )
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine prior Phase181 article staging.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, final_dir)) {
    stop("Could not publish Phase181 article staging.", call. = FALSE)
  }
  check <- app_joint_exqdesn_verify_manifest(
    final_dir, "phase181_article_staging"
  )
  if (any(check$status != "pass")) {
    stop("Phase181 article staging manifest failed.", call. = FALSE)
  }
  list(
    out_dir = final_dir, table = table, asset_manifest = asset_inventory,
    reused = FALSE
  )
}

app_joint_qdesn_phase181_freeze_handoff <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  out_dir = NULL, force = FALSE
) {
  dirs <- app_joint_qdesn_phase181_dirs(cache_root)
  out_dir <- out_dir %||% dirs$handoff
  packet_check <- app_joint_exqdesn_verify_manifest(
    dirs$packet, "phase181_packet"
  )
  stage_check <- app_joint_exqdesn_verify_manifest(
    dirs$article_staging, "phase181_article_staging"
  )
  freeze_check <- app_joint_exqdesn_verify_manifest(
    dirs$freeze, "phase181_freeze"
  )
  health <- app_joint_qdesn_phase181_health(dirs$freeze, dirs$orchestration)
  assessment <- app_read_csv(file.path(dirs$packet, "final_gate_assessment.csv"))
  branch <- app_joint_exqdesn_phase171_git_value(c(
    "rev-parse", "--abbrev-ref", "HEAD"
  ))
  head <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "HEAD"))
  upstream <- app_joint_exqdesn_phase171_git_value(c(
    "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"
  ))
  upstream_head <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "@{u}"))
  origin_main <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "origin/main"))
  merge_base <- app_joint_exqdesn_phase171_git_value(c(
    "merge-base", "HEAD", "origin/main"
  ))
  status <- app_joint_exqdesn_phase171_git_value(c(
    "status", "--porcelain", "--untracked-files=normal"
  ))
  clean <- is.na(status) || !nzchar(status)
  unique_commits <- app_joint_exqdesn_phase171_git_value(c(
    "log", "--format=%H%x09%s", "origin/main..HEAD"
  ))
  changed_files <- app_joint_exqdesn_phase171_git_value(c(
    "diff", "--name-only", "origin/main...HEAD"
  ))
  test_paths <- c(
    phase181 = file.path(dirs$orchestration, "test_phase181.log"),
    phase180_regression = file.path(dirs$orchestration, "test_phase180.log")
  )
  test_audit <- data.frame(
    test_id = names(test_paths), log_path = normalizePath(
      test_paths, mustWork = FALSE
    ),
    log_exists = file.exists(test_paths),
    log_sha256 = vapply(test_paths, function(path) {
      if (file.exists(path)) app_sha256_file(path) else NA_character_
    }, character(1L)),
    status = ifelse(file.exists(test_paths), "pass", "fail"),
    stringsAsFactors = FALSE
  )
  source_verification <- app_joint_qdesn_bind_rows(list(
    transform(freeze_check, source_id = "phase181_freeze"),
    transform(packet_check, source_id = "phase181_packet"),
    transform(stage_check, source_id = "phase181_article_staging")
  ))
  ready <- clean && identical(head, upstream_head) &&
    grepl("^work/joint-qdesn-phase181-", branch) &&
    all(source_verification$status == "pass") &&
    all(test_audit$status == "pass") &&
    assessment$implementation_hard_gates[[1L]] == "pass" &&
    health$summary$complete[[1L]] == health$summary$planned[[1L]] &&
    health$summary$failed[[1L]] == 0L && health$summary$remaining[[1L]] == 0L
  summary <- data.frame(
    lane = "joint_qdesn_phase181_score_stability_extension",
    branch = branch, upstream = upstream, head = head,
    upstream_head = upstream_head, origin_main = origin_main,
    merge_base_with_origin_main = merge_base,
    worktree_clean = clean,
    run_workers_planned = health$summary$planned[[1L]],
    run_workers_complete = health$summary$complete[[1L]],
    run_workers_failed = health$summary$failed[[1L]],
    final_cells = assessment$final_cells[[1L]],
    promoted_cells = assessment$promoted_extension_cells[[1L]],
    hard_gate_status = assessment$implementation_hard_gates[[1L]],
    diagnostic_gate_status = assessment$gate_status[[1L]],
    integration_state = if (ready) {
      "READY_FOR_INTEGRATION"
    } else "NOT_READY_FOR_INTEGRATION",
    stringsAsFactors = FALSE
  )
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(out_dir, "phase181_handoff")
    if (all(check$status == "pass")) {
      return(list(out_dir = normalizePath(out_dir), summary = summary, reused = TRUE))
    }
  }
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  stage_assets <- app_read_csv(file.path(
    dirs$article_staging, "article_asset_inventory.csv"
  ))
  commit_table <- if (is.na(unique_commits) || !nzchar(unique_commits)) {
    data.frame(commit = character(), subject = character())
  } else {
    fields <- strsplit(strsplit(unique_commits, "\n", fixed = TRUE)[[1L]], "\t")
    data.frame(
      commit = vapply(fields, `[`, character(1L), 1L),
      subject = vapply(fields, function(x) paste(x[-1L], collapse = "\t"), character(1L)),
      stringsAsFactors = FALSE
    )
  }
  file_table <- data.frame(
    path = if (is.na(changed_files) || !nzchar(changed_files)) {
      character()
    } else strsplit(changed_files, "\n", fixed = TRUE)[[1L]],
    stringsAsFactors = FALSE
  )
  exclusions <- data.frame(
    path = unlist(dirs[c(
      "freeze", "initialization_work", "chains", "orchestration",
      "extension_score_work", "selected_score_work", "packet",
      "article_staging", "handoff"
    )], use.names = FALSE),
    role = "runtime_generated_hash_manifested_evidence",
    publish_to_article_git = FALSE,
    stringsAsFactors = FALSE
  )
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase181 integration handoff", "",
    sprintf("- State: `%s`", summary$integration_state[[1L]]),
    sprintf("- Branch: `%s`", branch),
    sprintf("- HEAD: `%s`", head),
    sprintf("- Complete workers: %d/%d", summary$run_workers_complete[[1L]],
            summary$run_workers_planned[[1L]]),
    sprintf("- Promoted lower-mean cells: %d", summary$promoted_cells[[1L]]),
    "- Mixing and raw coherence remain disclosed review diagnostics.",
    "- Runtime caches remain excluded from git and Overleaf.",
    "- The integration coordinator owns main merge and article publication."
  ), readme, useBytes = TRUE)
  paths <- c(
    integration_handoff_summary = write(
      summary, "integration_handoff_summary.csv"
    ),
    unique_commits = write(commit_table, "unique_commits.csv"),
    changed_files = write(file_table, "changed_files.csv"),
    source_manifest_verification = write(
      source_verification, "source_manifest_verification.csv"
    ),
    test_audit = write(test_audit, "test_audit.csv"),
    article_safe_files = write(stage_assets, "article_safe_files.csv"),
    runtime_generated_exclusions = write(
      exclusions, "runtime_generated_exclusions.csv"
    ),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(
      final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S")
    )
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine prior Phase181 handoff.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, final_dir)) {
    stop("Could not publish Phase181 handoff.", call. = FALSE)
  }
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase181_handoff")
  if (any(check$status != "pass")) {
    stop("Phase181 handoff manifest failed.", call. = FALSE)
  }
  list(out_dir = final_dir, summary = summary, reused = FALSE)
}
