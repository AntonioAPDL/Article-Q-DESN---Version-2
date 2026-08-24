# Phase 179 fresh-seed confirmation under the prospective DGP-score contract.

app_joint_qdesn_phase179_policy_path <- function() {
  app_path("application/config/joint_qdesn_phase179_dgp_score_confirmation_policy_v1.csv")
}

app_joint_qdesn_phase179_dirs <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root()
) {
  list(
    cache_root = cache_root,
    selection_freeze = file.path(
      cache_root, "joint_qdesn_phase179_dgp_score_selection_freeze_20260819"
    ),
    confirmation_freeze = file.path(
      cache_root, "joint_qdesn_phase179_dgp_score_confirmation_freeze_20260819"
    ),
    confirmation = file.path(
      cache_root, "joint_qdesn_phase179_dgp_score_confirmation_20260819"
    ),
    orchestration = file.path(
      cache_root, "joint_qdesn_phase179_dgp_score_confirmation_20260819_orchestration"
    ),
    score_work = file.path(
      cache_root, "joint_qdesn_phase179_dgp_score_confirmation_audit_20260819_work"
    ),
    audit = file.path(
      cache_root, "joint_qdesn_phase179_dgp_score_confirmation_audit_20260819"
    ),
    closeout = file.path(
      cache_root, "joint_qdesn_phase179_dgp_score_confirmation_closeout_20260824"
    )
  )
}

app_joint_qdesn_phase179_policy_value <- function(table, name) {
  hit <- table[table$policy_name == name, , drop = FALSE]
  if (nrow(hit) != 1L) {
    stop(sprintf("Phase179 policy must contain exactly one '%s' row.", name), call. = FALSE)
  }
  as.character(hit$value[[1L]])
}

app_joint_qdesn_phase179_read_policy <- function(
  path = app_joint_qdesn_phase179_policy_path()
) {
  table <- app_read_csv(path)
  app_check_required_columns(
    table, c("policy_section", "policy_name", "value", "value_type", "rationale"),
    "Phase179 DGP-score confirmation policy"
  )
  if (anyDuplicated(table$policy_name)) {
    stop("Phase179 policy names must be unique.", call. = FALSE)
  }
  get <- function(name) app_joint_qdesn_phase179_policy_value(table, name)
  num <- function(name) as.numeric(get(name))
  int <- function(name) as.integer(get(name))
  logical_value <- function(name) identical(tolower(get(name)), "true")
  policy <- list(
    table = table,
    path = normalizePath(path, mustWork = TRUE),
    version = get("policy_version"),
    selection_scope = get("selection_scope"),
    expected_target_cells = int("expected_target_cells"),
    expected_selected_nonparity = int("expected_selected_nonparity"),
    expected_confirmation_templates = int("expected_confirmation_templates"),
    expected_confirmation_replicates = int("expected_confirmation_replicates"),
    expected_confirmation_cases = int("expected_confirmation_cases"),
    expected_confirmation_workers = int("expected_confirmation_workers"),
    primary_metric = get("primary_metric"),
    selection_rule = get("selection_rule"),
    relative_gain_floor = num("relative_gain_floor"),
    direction_floor = num("protected_replicate_direction_floor"),
    posterior_probability_reporting_only = logical_value(
      "posterior_probability_reporting_only"
    ),
    median_oracle_ceiling = num("median_oracle_recovery_ratio_ceiling"),
    maximum_oracle_ceiling = num("maximum_oracle_recovery_ratio_ceiling"),
    score_rank_rhat_hard_ceiling = num("score_rank_rhat_hard_ceiling"),
    score_bulk_ess_hard_floor = num("score_bulk_ess_hard_floor"),
    score_tail_ess_hard_floor = num("score_tail_ess_hard_floor"),
    score_rank_rhat_review_ceiling = num("score_rank_rhat_review_ceiling"),
    score_bulk_ess_review_floor = num("score_bulk_ess_review_floor"),
    score_tail_ess_review_floor = num("score_tail_ess_review_floor"),
    raw_crossing_rate_review = num("raw_crossing_rate_review"),
    contract_crossing_pairs_required = int("contract_crossing_pairs_required"),
    inference_method_id = get("inference_method_id"),
    n_chains = int("n_chains"),
    n_iter = int("n_iter"),
    burn = int("burn"),
    thin = int("thin"),
    score_draws_per_chain = int("score_draws_per_chain"),
    pairing_seed = int("independent_product_pairing_seed"),
    protected_partition = get("protected_partition"),
    exact_m0_required = logical_value("exact_m0_required"),
    article_fixture_selection_allowed = logical_value(
      "article_fixture_selection_allowed"
    ),
    dense_grid_authorized = logical_value("dense_grid_authorized"),
    promote_any_confirmed_gain = logical_value("promote_any_confirmed_gain"),
    global_specification_selected = logical_value("global_specification_selected")
  )
  if (!identical(policy$selection_scope, "case_specific_scenario_readout") ||
      policy$relative_gain_floor != 0 ||
      policy$direction_floor < 2 / 3 - 1e-8 ||
      !policy$exact_m0_required || policy$article_fixture_selection_allowed ||
      policy$dense_grid_authorized || policy$global_specification_selected ||
      !policy$promote_any_confirmed_gain) {
    stop("Phase179 policy violates the prospective case-specific contract.", call. = FALSE)
  }
  policy
}

app_joint_qdesn_phase179_required_cases <- function() {
  app_joint_exqdesn_phase176_required_case_ids()
}

app_joint_qdesn_phase179_selection <- function(aggregate, controls, policy) {
  app_check_required_columns(aggregate, c(
    "case_id", "base_scenario_id", "fit_structure", "phase178_template_id",
    "variant_id", "median_posterior_score_mean", "score_ratio_vs_parity",
    "median_forecast_truth_mae", "forecast_truth_mae_ratio_vs_parity",
    "median_fit_truth_mae", "fit_truth_mae_ratio_vs_parity",
    "all_contract_crossings_zero"
  ), "Phase179 postscore aggregate")
  app_check_required_columns(controls, c(
    "case_id", "phase178_template_id", "variant_id", "tau0", "zeta2",
    "alpha_prior_sd", "fit_structure", "source_control_row_sha256"
  ), "Phase179 frozen controls")
  required <- sort(app_joint_qdesn_phase179_required_cases())
  observed <- sort(unique(aggregate$case_id))
  if (!identical(observed, required) ||
      nrow(aggregate) != 3L * policy$expected_target_cells ||
      any(!is.finite(aggregate$median_posterior_score_mean)) ||
      any(!app_as_bool_vec(aggregate$all_contract_crossings_zero))) {
    stop("Phase179 source aggregate is incomplete, nonfinite, or crossed.", call. = FALSE)
  }
  decisions <- app_joint_qdesn_bind_rows(lapply(required, function(case_id) {
    block <- aggregate[aggregate$case_id == case_id, , drop = FALSE]
    parity <- block[block$variant_id == "parity", , drop = FALSE]
    if (nrow(parity) != 1L || anyDuplicated(block$phase178_template_id)) {
      stop(sprintf("Phase179 case '%s' has malformed candidate rows.", case_id), call. = FALSE)
    }
    winner <- block[order(
      block$median_posterior_score_mean, block$phase178_template_id
    ), , drop = FALSE][1L, , drop = FALSE]
    improvement <- parity$median_posterior_score_mean[[1L]] -
      winner$median_posterior_score_mean[[1L]]
    data.frame(
      case_id = case_id,
      base_scenario_id = winner$base_scenario_id[[1L]],
      fit_structure = winner$fit_structure[[1L]],
      selected_template_id = winner$phase178_template_id[[1L]],
      selected_variant_id = winner$variant_id[[1L]],
      parity_template_id = parity$phase178_template_id[[1L]],
      selected_is_parity = winner$variant_id[[1L]] == "parity",
      selected_score = winner$median_posterior_score_mean[[1L]],
      parity_score = parity$median_posterior_score_mean[[1L]],
      absolute_score_improvement = improvement,
      relative_score_improvement = improvement /
        pmax(abs(parity$median_posterior_score_mean[[1L]]), .Machine$double.eps),
      source_forecast_oracle_mae_ratio = winner$forecast_truth_mae_ratio_vs_parity[[1L]],
      source_fit_oracle_mae_ratio = winner$fit_truth_mae_ratio_vs_parity[[1L]],
      selection_metric = policy$primary_metric,
      selection_rule = policy$selection_rule,
      relative_gain_floor = policy$relative_gain_floor,
      selection_scope = policy$selection_scope,
      global_specification_selected = FALSE,
      decision_status = "pass",
      decision_reason = if (winner$variant_id[[1L]] == "parity") {
        "parity_is_within_case_numerical_minimum"
      } else {
        "strictly_positive_within_case_score_gain_advances_to_fresh_confirmation"
      },
      stringsAsFactors = FALSE
    )
  }))
  if (nrow(decisions) != policy$expected_target_cells ||
      sum(!decisions$selected_is_parity) != policy$expected_selected_nonparity ||
      any(decisions$absolute_score_improvement < -1e-14)) {
    stop("Phase179 numerical selection differs from its predeclared prospective inventory.", call. = FALSE)
  }
  index <- match(decisions$selected_template_id, controls$phase178_template_id)
  if (anyNA(index)) stop("Phase179 selected controls cannot be resolved.", call. = FALSE)
  selected <- controls[index, , drop = FALSE]
  selected$phase178_frozen_control_row_sha256 <- selected$source_control_row_sha256
  selected$phase179_confirmation_role <- ifelse(
    decisions$selected_is_parity, "selected_parity", "selected_challenger"
  )
  parity_index <- match(decisions$parity_template_id, controls$phase178_template_id)
  if (anyNA(parity_index)) stop("Phase179 parity controls cannot be resolved.", call. = FALSE)
  parity <- controls[parity_index, , drop = FALSE]
  parity$phase178_frozen_control_row_sha256 <- parity$source_control_row_sha256
  parity$phase179_confirmation_role <- "parity_reference"
  templates <- app_joint_qdesn_bind_rows(list(selected, parity))
  templates <- templates[!duplicated(templates$phase178_template_id), , drop = FALSE]
  templates <- templates[order(templates$case_id, templates$phase178_template_id), , drop = FALSE]
  if (nrow(templates) != policy$expected_confirmation_templates ||
      anyDuplicated(templates$phase178_template_id) ||
      length(unique(selected$phase178_frozen_control_row_sha256)) !=
        policy$expected_target_cells) {
    stop("Phase179 selected-versus-parity template inventory is malformed.", call. = FALSE)
  }
  list(decisions = decisions, selected = selected, templates = templates)
}

app_joint_qdesn_phase179_control_audit <- function(selected, decisions, policy) {
  fields <- intersect(c(
    "case_id", "base_scenario_id", "fit_structure", "phase178_template_id",
    "variant_id", "source_candidate_id", "design_role", "design_class",
    "reservoir_width", "reservoir_alpha", "reservoir_rho", "reservoir_pi_w",
    "reservoir_pi_in", "input_scale", "reservoir_seed", "tau0", "zeta2",
    "alpha_prior_sd", "alpha_min_spacing", "source_control_row_sha256"
  ), names(selected))
  out <- selected[, fields, drop = FALSE]
  out$selection_scope <- policy$selection_scope
  out$global_specification_selected <- FALSE
  out$selected_score <- decisions$selected_score[
    match(out$case_id, decisions$case_id)
  ]
  out$phase178_frozen_control_row_sha256 <- out$source_control_row_sha256
  out$control_resolution_status <- ifelse(
    nzchar(out$phase178_frozen_control_row_sha256), "pass", "fail"
  )
  out
}

app_joint_qdesn_phase179_prepare_selection_freeze <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  out_dir = app_joint_qdesn_phase179_dirs(cache_root)$selection_freeze,
  force = FALSE
) {
  dirs178 <- app_joint_exqdesn_phase176_dirs(cache_root)
  dirs_score <- app_joint_qdesn_postscore_dirs(cache_root)
  dirs179 <- app_joint_qdesn_phase179_dirs(cache_root)
  policy <- app_joint_qdesn_phase179_read_policy()
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(out_dir, "phase179_score_selection")
    if (all(check$status == "pass")) {
      return(list(
        out_dir = normalizePath(out_dir),
        decisions = app_read_csv(file.path(out_dir, "case_specific_selection_decision.csv")),
        templates = app_read_csv(file.path(out_dir, "confirmation_templates.csv")),
        reused = TRUE
      ))
    }
  }
  source_dirs <- list(
    post_phase178_score_audit = dirs_score$postscore_audit,
    phase178_exact_m0_freeze = dirs178$phase178_m0_freeze,
    phase178_protected_registry_freeze = dirs178$phase178_freeze,
    phase178_protected_fixtures = dirs178$phase178_fixtures
  )
  source_check <- app_joint_qdesn_bind_rows(lapply(names(source_dirs), function(id) {
    app_joint_exqdesn_verify_manifest(source_dirs[[id]], id)
  }))
  if (any(source_check$status != "pass")) {
    stop("Phase179 selection source manifest verification failed.", call. = FALSE)
  }
  aggregate <- app_read_csv(file.path(
    dirs_score$postscore_audit, "candidate_metric_aggregate.csv"
  ))
  historical <- app_read_csv(file.path(
    dirs_score$postscore_audit, "decision_audit.csv"
  ))
  original_phase178 <- app_read_csv(file.path(
    dirs_score$postscore_audit, "phase178_original_decision.csv"
  ))
  controls <- app_read_csv(file.path(
    dirs178$phase178_m0_freeze, "model_control_freeze.csv"
  ))
  dgp <- app_read_csv(file.path(dirs178$phase178_freeze, "protected_dgp_registry.csv"))
  confirmation_dgp <- dgp[dgp$validation_partition == policy$protected_partition, , drop = FALSE]
  if (nrow(confirmation_dgp) != 12L ||
      any(table(confirmation_dgp$base_scenario_id) != policy$expected_confirmation_replicates) ||
      anyDuplicated(confirmation_dgp$scenario_id) || anyDuplicated(confirmation_dgp$seed)) {
    stop("Phase179 protected confirmation registry is malformed.", call. = FALSE)
  }
  selection <- app_joint_qdesn_phase179_selection(aggregate, controls, policy)
  control_audit <- app_joint_qdesn_phase179_control_audit(
    selection$selected, selection$decisions, policy
  )
  if (any(control_audit$control_resolution_status != "pass")) {
    stop("Phase179 case-specific control audit failed.", call. = FALSE)
  }
  readiness <- data.frame(
    phase_id = policy$version,
    gate_status = "pass",
    target_cells = nrow(selection$decisions),
    selected_nonparity = sum(!selection$decisions$selected_is_parity),
    confirmation_templates = nrow(selection$templates),
    protected_dgp_rows = nrow(confirmation_dgp),
    planned_confirmation_cases = nrow(selection$templates) *
      policy$expected_confirmation_replicates,
    planned_workers = nrow(selection$templates) *
      policy$expected_confirmation_replicates * policy$n_chains,
    original_phase178_contract_preserved = TRUE,
    historical_half_percent_decision_preserved = TRUE,
    prospective_any_gain_policy = TRUE,
    case_specific_desn_and_tau0 = TRUE,
    global_specification_selected = FALSE,
    article_fixture_used_for_selection = FALSE,
    recommendation = "prepare_fresh_seed_exact_m0_confirmation",
    stringsAsFactors = FALSE
  )
  if (readiness$planned_confirmation_cases[[1L]] != policy$expected_confirmation_cases ||
      readiness$planned_workers[[1L]] != policy$expected_confirmation_workers) {
    stop("Phase179 selection freeze has an unexpected workload.", call. = FALSE)
  }

  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase 179 case-specific DGP-score selection freeze", "",
    "This is a prospective decision layer; it does not rewrite Phase178 or its original oracle-MAE ranking.",
    "Selection is performed independently within each of five scenario-readout cells.",
    "Each selected row preserves its frozen DESN/control provenance and its own `tau0`.",
    "Any strictly positive current-grid DGP-integrated score gain may enter fresh confirmation.",
    "Fresh confirmation still fails closed on source defects, nonfinite values, or contract crossings.",
    "The seven-level quantile grid remains fixed and article fixtures remain excluded."
  ), readme, useBytes = TRUE)
  paths <- c(
    prospective_policy = write(policy$table, "prospective_selection_policy.csv"),
    source_manifest_verification = write(
      source_check, "source_manifest_verification.csv"
    ),
    historical_postscore_decision = write(
      historical, "historical_postscore_selection_decision.csv"
    ),
    original_phase178_decision = write(
      original_phase178, "original_phase178_selection_decision.csv"
    ),
    candidate_metric_aggregate = write(
      aggregate, "candidate_metric_aggregate.csv"
    ),
    case_specific_selection_decision = write(
      selection$decisions, "case_specific_selection_decision.csv"
    ),
    case_specific_selected_controls = write(
      selection$selected, "case_specific_selected_controls.csv"
    ),
    case_specific_control_audit = write(
      control_audit, "case_specific_control_audit.csv"
    ),
    confirmation_templates = write(
      selection$templates, "confirmation_templates.csv"
    ),
    protected_confirmation_registry = write(
      confirmation_dgp, "protected_confirmation_registry.csv"
    ),
    readiness_assessment = write(readiness, "readiness_assessment.csv"),
    run_config = write(data.frame(
      policy_version = policy$version,
      source_postscore_dir = normalizePath(dirs_score$postscore_audit),
      source_phase178_freeze = normalizePath(dirs178$phase178_m0_freeze),
      source_fixture_dir = normalizePath(dirs178$phase178_fixtures),
      confirmation_result_dir = dirs179$confirmation,
      code_commit = app_joint_exqdesn_phase171_git_value(c("rev-parse", "HEAD")),
      stringsAsFactors = FALSE
    ), "run_config.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine prior Phase179 selection freeze.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, final_dir)) {
    stop("Could not publish Phase179 selection freeze.", call. = FALSE)
  }
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase179_score_selection")
  if (any(check$status != "pass")) stop("Phase179 selection manifest failed.", call. = FALSE)
  list(
    out_dir = final_dir, decisions = selection$decisions,
    templates = selection$templates, readiness = readiness, reused = FALSE
  )
}

app_joint_qdesn_phase179_prepare_confirmation <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  n_vb_cores = 12L, force = FALSE
) {
  dirs178 <- app_joint_exqdesn_phase176_dirs(cache_root)
  dirs179 <- app_joint_qdesn_phase179_dirs(cache_root)
  policy <- app_joint_qdesn_phase179_read_policy()
  app_joint_qdesn_phase179_prepare_selection_freeze(cache_root, force = FALSE)
  selection_check <- app_joint_exqdesn_verify_manifest(
    dirs179$selection_freeze, "phase179_score_selection"
  )
  if (any(selection_check$status != "pass")) {
    stop("Phase179 selection freeze verification failed.", call. = FALSE)
  }
  templates <- app_read_csv(file.path(
    dirs179$selection_freeze, "confirmation_templates.csv"
  ))
  dgp <- app_read_csv(file.path(
    dirs179$selection_freeze, "protected_confirmation_registry.csv"
  ))
  compute <- app_joint_exqdesn_phase178_load_compute_policy()
  inherited <- c(
    n_chains = as.integer(compute$m0_confirmation_chains[[1L]]),
    n_iter = as.integer(compute$m0_confirmation_n_iter[[1L]]),
    burn = as.integer(compute$m0_confirmation_burn[[1L]]),
    thin = as.integer(compute$m0_confirmation_thin[[1L]])
  )
  expected <- c(
    n_chains = policy$n_chains, n_iter = policy$n_iter,
    burn = policy$burn, thin = policy$thin
  )
  if (!identical(inherited, expected) ||
      nrow(templates) != policy$expected_confirmation_templates) {
    stop("Phase179 compute controls differ from the frozen confirmation policy.", call. = FALSE)
  }
  result <- app_joint_exqdesn_phase178_prepare_m0_freeze(
    candidate_templates = templates,
    dgp_registry = dgp,
    partition = policy$protected_partition,
    source_dir = dirs179$selection_freeze,
    fixture_dir = dirs178$phase178_fixtures,
    out_dir = dirs179$confirmation_freeze,
    result_dir = dirs179$confirmation,
    phase_id = "phase179_case_specific_dgp_score_confirmation_freeze",
    seed_base = 179500000L,
    n_vb_cores = as.integer(n_vb_cores),
    policy = compute,
    force = force
  )
  plan <- result$plan
  if (nrow(plan) != policy$expected_confirmation_workers ||
      length(unique(plan$mcmc_case_id)) != policy$expected_confirmation_cases ||
      length(unique(plan$case_id)) != policy$expected_target_cells ||
      any(plan$validation_partition != policy$protected_partition) ||
      any(plan$inference_method_id != policy$inference_method_id) ||
      any(app_as_bool_vec(plan$article_fixture_selection_allowed))) {
    stop("Phase179 confirmation freeze failed its workload or source contract.", call. = FALSE)
  }
  result
}

app_joint_qdesn_phase179_health <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root()
) {
  dirs <- app_joint_qdesn_phase179_dirs(cache_root)
  app_joint_exqdesn_phase178_m0_health(
    dirs$confirmation_freeze, dirs$orchestration,
    "phase179_case_specific_dgp_score_confirmation_freeze"
  )
}

app_joint_qdesn_phase179_matched_decision <- function(
  selection_row, score_summary, m0_summary, contrast_summary, controls, policy
) {
  case_id <- selection_row$case_id[[1L]]
  selected_id <- selection_row$selected_template_id[[1L]]
  parity_id <- selection_row$parity_template_id[[1L]]
  ids <- unique(c(selected_id, parity_id))
  block <- score_summary[
    score_summary$case_id == case_id & score_summary$phase178_template_id %in% ids,
    , drop = FALSE
  ]
  source <- m0_summary[
    m0_summary$case_id == case_id & m0_summary$phase178_template_id %in% ids,
    , drop = FALSE
  ]
  expected_rows <- length(ids) * policy$expected_confirmation_replicates
  hard_source <- nrow(block) == expected_rows && nrow(source) == expected_rows &&
    all(source$implementation_status == "pass") &&
    all(is.finite(block$posterior_score_mean)) &&
    all(block$contract_crossing_pairs == policy$contract_crossing_pairs_required)
  functional_hard <- hard_source &&
    max(block$score_rank_rhat) <= policy$score_rank_rhat_hard_ceiling &&
    min(block$score_bulk_ess) >= policy$score_bulk_ess_hard_floor &&
    min(block$score_tail_ess) >= policy$score_tail_ess_hard_floor
  strict_review <- hard_source && (
    max(block$score_rank_rhat) > policy$score_rank_rhat_review_ceiling ||
      min(block$score_bulk_ess) < policy$score_bulk_ess_review_floor ||
      min(block$score_tail_ess) < policy$score_tail_ess_review_floor ||
      max(block$raw_crossing_rate) > policy$raw_crossing_rate_review
  )
  selected_control <- controls[
    controls$phase178_template_id == selected_id, , drop = FALSE
  ]
  parity_control <- controls[
    controls$phase178_template_id == parity_id, , drop = FALSE
  ]
  if (nrow(selected_control) != 1L || nrow(parity_control) != 1L) {
    stop("Phase179 final decision cannot resolve frozen controls.", call. = FALSE)
  }
  selected_is_parity <- isTRUE(selection_row$selected_is_parity[[1L]])
  if (!selected_is_parity && hard_source) {
    candidate <- block[block$phase178_template_id == selected_id, c(
      "dgp_replicate_id", "posterior_score_mean", "forecast_truth_mae", "fit_truth_mae"
    ), drop = FALSE]
    parity <- block[block$phase178_template_id == parity_id, c(
      "dgp_replicate_id", "posterior_score_mean", "forecast_truth_mae", "fit_truth_mae"
    ), drop = FALSE]
    names(candidate)[-1L] <- paste0("candidate_", names(candidate)[-1L])
    names(parity)[-1L] <- paste0("parity_", names(parity)[-1L])
    matched <- merge(candidate, parity, by = "dgp_replicate_id", sort = TRUE)
    matched$score_ratio <- matched$candidate_posterior_score_mean /
      matched$parity_posterior_score_mean
    matched$forecast_oracle_ratio <- matched$candidate_forecast_truth_mae /
      matched$parity_forecast_truth_mae
    matched$fit_oracle_ratio <- matched$candidate_fit_truth_mae /
      matched$parity_fit_truth_mae
    score_ratio <- stats::median(matched$score_ratio)
    direction_fraction <- mean(matched$score_ratio < 1 - policy$relative_gain_floor)
    median_forecast_ratio <- stats::median(matched$forecast_oracle_ratio)
    maximum_forecast_ratio <- max(matched$forecast_oracle_ratio)
    median_fit_ratio <- stats::median(matched$fit_oracle_ratio)
    maximum_fit_ratio <- max(matched$fit_oracle_ratio)
    oracle_pass <- median_forecast_ratio <= policy$median_oracle_ceiling &&
      median_fit_ratio <= policy$median_oracle_ceiling &&
      maximum_forecast_ratio <= policy$maximum_oracle_ceiling &&
      maximum_fit_ratio <= policy$maximum_oracle_ceiling
    gain_confirmed <- score_ratio < 1 - policy$relative_gain_floor &&
      direction_fraction + 1e-12 >= policy$direction_floor
    contrast <- contrast_summary[
      contrast_summary$case_id == case_id &
        contrast_summary$candidate_template_id == selected_id,
      , drop = FALSE
    ]
    probability_lower <- if (nrow(contrast)) {
      stats::median(contrast$probability_lower_score)
    } else NA_real_
  } else {
    score_ratio <- 1
    direction_fraction <- if (selected_is_parity) 1 else NA_real_
    median_forecast_ratio <- maximum_forecast_ratio <- 1
    median_fit_ratio <- maximum_fit_ratio <- 1
    oracle_pass <- selected_is_parity && hard_source
    gain_confirmed <- selected_is_parity && hard_source
    probability_lower <- if (selected_is_parity) 0.5 else NA_real_
  }
  hard_eligible <- hard_source && functional_hard && oracle_pass
  promote <- !selected_is_parity && hard_eligible && gain_confirmed
  final_id <- if (promote) selected_id else parity_id
  final_control <- controls[controls$phase178_template_id == final_id, , drop = FALSE]
  phase178_control_hash <- if (
    "phase178_frozen_control_row_sha256" %in% names(final_control)
  ) {
    final_control$phase178_frozen_control_row_sha256[[1L]]
  } else {
    final_control$source_control_row_sha256[[1L]]
  }
  gate <- if (!hard_source || !functional_hard) {
    "fail"
  } else if (strict_review || (!selected_is_parity && (!gain_confirmed || !oracle_pass))) {
    "review"
  } else {
    "pass"
  }
  data.frame(
    case_id = case_id,
    base_scenario_id = selection_row$base_scenario_id[[1L]],
    fit_structure = selection_row$fit_structure[[1L]],
    screened_template_id = selected_id,
    screened_variant_id = selection_row$selected_variant_id[[1L]],
    parity_template_id = parity_id,
    final_selected_template_id = final_id,
    final_selected_variant_id = final_control$variant_id[[1L]],
    promoted_nonparity = promote,
    fresh_replicates = policy$expected_confirmation_replicates,
    median_score_ratio_vs_parity = score_ratio,
    relative_score_improvement = 1 - score_ratio,
    lower_score_replicate_fraction = direction_fraction,
    median_probability_lower_score = probability_lower,
    posterior_probability_is_reporting_only = TRUE,
    median_forecast_oracle_mae_ratio = median_forecast_ratio,
    maximum_forecast_oracle_mae_ratio = maximum_forecast_ratio,
    median_fit_oracle_mae_ratio = median_fit_ratio,
    maximum_fit_oracle_mae_ratio = maximum_fit_ratio,
    source_and_implementation_pass = hard_source,
    score_functional_hard_pass = functional_hard,
    oracle_safeguard_pass = oracle_pass,
    directional_gain_confirmed = gain_confirmed,
    strict_mixing_or_crossing_review = strict_review,
    final_tau0 = final_control$tau0[[1L]],
    final_zeta2 = final_control$zeta2[[1L]],
    final_alpha_prior_sd = final_control$alpha_prior_sd[[1L]],
    final_source_control_row_sha256 = final_control$source_control_row_sha256[[1L]],
    final_phase178_control_row_sha256 = phase178_control_hash,
    selection_scope = policy$selection_scope,
    global_specification_selected = FALSE,
    gate_status = gate,
    promotion_status = if (!hard_source || !functional_hard) {
      "fail_closed"
    } else if (promote) {
      "promote_any_confirmed_positive_gain"
    } else {
      "retain_case_specific_parity"
    },
    decision_reason = if (!hard_source) {
      "source_implementation_finiteness_or_contract_gate_failed"
    } else if (!functional_hard) {
      "material_score_functional_instability"
    } else if (selected_is_parity) {
      "parity_was_the_case_specific_screening_minimum"
    } else if (!oracle_pass) {
      "score_gain_did_not_pass_oracle_recovery_safeguards"
    } else if (!gain_confirmed) {
      "screening_gain_did_not_repeat_on_two_of_three_fresh_replicates"
    } else {
      "strictly_positive_score_gain_confirmed_with_hard_safeguards"
    },
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase179_finalize_confirmation <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  score_cores = 12L, force = FALSE
) {
  dirs <- app_joint_qdesn_phase179_dirs(cache_root)
  policy <- app_joint_qdesn_phase179_read_policy()
  health <- app_joint_qdesn_phase179_health(cache_root)
  if (health$summary$failed[[1L]] > 0L || health$summary$remaining[[1L]] > 0L) {
    stop("Phase179 confirmation cannot finalize before all workers pass.", call. = FALSE)
  }
  if (!force && file.exists(file.path(dirs$audit, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(dirs$audit, "phase179_score_confirmation")
    if (all(check$status == "pass")) {
      return(list(
        out_dir = normalizePath(dirs$audit),
        assessment = app_read_csv(file.path(dirs$audit, "assessment.csv")),
        reused = TRUE
      ))
    }
  }
  selection_check <- app_joint_exqdesn_verify_manifest(
    dirs$selection_freeze, "phase179_score_selection"
  )
  freeze_check <- app_joint_exqdesn_verify_manifest(
    dirs$confirmation_freeze, "phase179_score_confirmation_freeze"
  )
  if (any(selection_check$status != "pass") || any(freeze_check$status != "pass")) {
    stop("Phase179 finalization source manifests failed.", call. = FALSE)
  }
  freeze <- app_joint_exqdesn_phase178_load_m0_freeze(
    dirs$confirmation_freeze, "phase179_case_specific_dgp_score_confirmation_freeze"
  )
  contract <- app_joint_qdesn_postscore_read_contract()
  if (contract$score_draws_per_chain != policy$score_draws_per_chain ||
      contract$primary_pairing_seed != policy$pairing_seed) {
    stop("Phase179 score reconstruction differs from the frozen current-grid contract.", call. = FALSE)
  }
  groups <- split(freeze$plan, freeze$plan$mcmc_case_id)
  if (length(groups) != policy$expected_confirmation_cases) {
    stop("Phase179 confirmation case count is incomplete.", call. = FALSE)
  }
  cell_paths <- app_joint_qdesn_postscore_run_cells(
    groups, freeze, contract, dirs$score_work, as.integer(score_cores)
  )
  score <- app_joint_qdesn_postscore_collect_cells(cell_paths)
  m0 <- app_joint_exqdesn_phase178_m0_results(freeze)
  if (nrow(score$diagnostics) != policy$expected_confirmation_cases ||
      any(score$diagnostics$contract_crossing_pairs != 0L) ||
      any(score$previsibility$status != "pass") ||
      any(score$source$worker_manifest_status != "pass") ||
      any(m0$summary$implementation_status != "pass")) {
    stop("Phase179 confirmation evidence failed a hard source gate.", call. = FALSE)
  }
  pairing <- app_joint_qdesn_postscore_pairing_stability(
    score$pairing_sensitivity, contract
  )
  score_summary <- merge(
    score$diagnostics, score$canonical,
    by = c(
      "mcmc_case_id", "phase178_template_id", "case_id", "scenario_id",
      "base_scenario_id", "dgp_replicate_id", "validation_partition",
      "fit_structure", "variant_id", "candidate_role", "design_role",
      "distribution_family", "dynamics_class"
    ), all = FALSE, sort = FALSE
  )
  template <- app_joint_qdesn_postscore_template_aggregate(
    score_summary, m0$summary, pairing
  )
  contrast <- app_joint_qdesn_postscore_candidate_parity_contrasts(
    score$draws, contract
  )
  selection <- app_read_csv(file.path(
    dirs$selection_freeze, "case_specific_selection_decision.csv"
  ))
  decisions <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(selection)), function(ii) {
    app_joint_qdesn_phase179_matched_decision(
      selection[ii, , drop = FALSE], template$case_replicate,
      m0$summary, contrast$summary, freeze$controls, policy
    )
  }))
  if (nrow(decisions) != policy$expected_target_cells ||
      any(decisions$global_specification_selected)) {
    stop("Phase179 final decisions violate the case-specific contract.", call. = FALSE)
  }
  final_controls <- freeze$controls[
    match(decisions$final_selected_template_id, freeze$controls$phase178_template_id),
    , drop = FALSE
  ]
  if (anyNA(final_controls$phase178_template_id) || nrow(final_controls) != nrow(decisions)) {
    stop("Phase179 final controls cannot be resolved.", call. = FALSE)
  }
  final_controls$phase179_final_role <- ifelse(
    decisions$promoted_nonparity, "confirmed_score_challenger", "retained_parity"
  )
  runtime <- app_joint_qdesn_bind_rows(lapply(
    freeze$plan$worker_output_dir,
    function(path) app_read_csv(file.path(path, "runtime.csv"))
  ))
  inventory <- data.frame(
    mcmc_case_id = names(cell_paths),
    cell_dir = normalizePath(cell_paths),
    manifest_sha256 = vapply(cell_paths, function(path) {
      app_sha256_file(file.path(path, "artifact_manifest.csv"))
    }, character(1L)),
    status = "pass", stringsAsFactors = FALSE
  )
  hard_fail <- any(decisions$gate_status == "fail")
  review <- any(decisions$gate_status == "review") ||
    any(score$diagnostics$score_functional_status == "review") ||
    any(score$diagnostics$coherence_status == "review")
  assessment <- data.frame(
    phase_id = policy$version,
    gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
    workers_planned = policy$expected_confirmation_workers,
    workers_complete = health$summary$complete[[1L]],
    workers_failed = health$summary$failed[[1L]],
    confirmation_cases = nrow(score$diagnostics),
    target_cells = nrow(decisions),
    promoted_nonparity = sum(decisions$promoted_nonparity),
    retained_parity = sum(!decisions$promoted_nonparity),
    contract_crossing_pairs = sum(score$diagnostics$contract_crossing_pairs),
    case_specific_desn_and_tau0 = TRUE,
    global_specification_selected = FALSE,
    original_phase178_contract_preserved = TRUE,
    article_fixture_used_for_selection = FALSE,
    article_assets_mutated = FALSE,
    recommendation = if (hard_fail) {
      "repair_hard_confirmation_failure"
    } else {
      "freeze_case_specific_winners_for_article_fixture_confirmation"
    },
    stringsAsFactors = FALSE
  )

  final_dir <- normalizePath(dirs$audit, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase 179 fresh-seed DGP-score confirmation", "",
    "The confirmation uses exact M0 and the three protected confirmation DGP replicates.",
    "Candidates and parity controls remain case-specific, including their frozen DESN inputs and `tau0`.",
    "Any strictly positive score improvement can be promoted when at least two of three fresh replicates agree.",
    "Posterior score probabilities and 95% intervals are reported but are not a practical-significance gate.",
    "Nonfinite output, source defects, material score-functional instability, or contract crossings fail closed.",
    "No article fixture or article asset is used or changed by this audit."
  ), readme, useBytes = TRUE)
  paths <- c(
    prospective_policy = write(policy$table, "prospective_selection_policy.csv"),
    selection_manifest_verification = write(
      selection_check, "selection_manifest_verification.csv"
    ),
    confirmation_freeze_manifest_verification = write(
      freeze_check, "confirmation_freeze_manifest_verification.csv"
    ),
    worker_health_summary = write(health$summary, "worker_health_summary.csv"),
    worker_health_by_case = write(health$by_case, "worker_health_by_case.csv"),
    source_selection_decision = write(selection, "source_selection_decision.csv"),
    frozen_model_controls = write(freeze$controls, "frozen_model_controls.csv"),
    posterior_score_draws = app_joint_qdesn_postscore_write_gzip_csv(
      score$draws, file.path(tmp, "posterior_dgp_integrated_acrps_draws.csv.gz")
    ),
    posterior_score_summary = write(
      template$case_replicate, "posterior_dgp_integrated_acrps_summary.csv"
    ),
    canonical_action_score = write(
      score$canonical, "canonical_action_dgp_integrated_acrps.csv"
    ),
    candidate_parity_contrast_draws = app_joint_qdesn_postscore_write_gzip_csv(
      contrast$draws, file.path(tmp, "candidate_parity_contrast_draws.csv.gz")
    ),
    candidate_parity_contrast_summary = write(
      contrast$summary, "candidate_parity_contrast_summary.csv"
    ),
    score_pairing_stability = write(pairing, "score_pairing_stability.csv"),
    mcmc_case_summary = write(m0$summary, "mcmc_case_summary.csv"),
    mcmc_parameter_diagnostics = write(
      m0$diagnostics, "mcmc_parameter_diagnostics.csv"
    ),
    mcmc_partition_stability = write(
      m0$partition_summary, "mcmc_partition_stability.csv"
    ),
    mcmc_summary_sensitivity = write(
      m0$sensitivity, "mcmc_summary_sensitivity.csv"
    ),
    case_specific_confirmation_decision = write(
      decisions, "case_specific_confirmation_decision.csv"
    ),
    final_case_specific_controls = write(
      final_controls, "final_case_specific_controls.csv"
    ),
    score_cell_inventory = write(inventory, "score_cell_inventory.csv"),
    runtime_summary = write(runtime, "runtime_summary.csv"),
    assessment = write(assessment, "assessment.csv"),
    next_stage_plan = write(data.frame(
      stage = "article_fixture_confirmation",
      authorized = !hard_fail,
      source = "final_case_specific_controls.csv",
      selection_metric = policy$primary_metric,
      article_asset_mutation_allowed = FALSE,
      rationale = "Only freshly confirmed case-specific controls may enter the later article-fixture stage.",
      stringsAsFactors = FALSE
    ), "next_stage_plan.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine prior Phase179 confirmation audit.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, final_dir)) {
    stop("Could not publish Phase179 confirmation audit.", call. = FALSE)
  }
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase179_score_confirmation")
  if (any(check$status != "pass")) {
    stop("Phase179 confirmation audit manifest failed.", call. = FALSE)
  }
  list(out_dir = final_dir, assessment = assessment, decisions = decisions, reused = FALSE)
}

app_joint_qdesn_phase179_balanced_source_completeness <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root()
) {
  phase174 <- file.path(cache_root, "joint_qdesn_phase174_balanced_mcmc_final_20260809")
  phase172 <- file.path(
    cache_root, "joint_exqdesn_phase172_m0_balanced_article_confirmation_20260809"
  )
  al_sources <- c(
    joint_qdesn_rhs_vb = file.path(cache_root, "joint_qdesn_phase154_mcmc_joint_al_20260730"),
    qdesn_rhs_independent_vb = file.path(
      cache_root, "joint_qdesn_phase154_mcmc_independent_al_20260730"
    )
  )
  phase174_check <- app_joint_exqdesn_verify_manifest(phase174, "phase174")
  if (any(phase174_check$status != "pass")) {
    stop("Phase179 closeout cannot inventory an unverifiable Phase174 packet.", call. = FALSE)
  }
  authority <- app_read_csv(file.path(phase174, "final_mcmc_case_summary.csv"))
  if (nrow(authority) != 32L || any(table(authority$source_model_id) != 8L)) {
    stop("Phase174 balanced authority is not an 8-by-4 model grid.", call. = FALSE)
  }

  phase172_check <- app_joint_exqdesn_verify_manifest(phase172, "phase172")
  if (any(phase172_check$status != "pass")) {
    stop("Phase172 retained-draw packet is not hash verified.", call. = FALSE)
  }
  worker_inventory <- app_read_csv(file.path(phase172, "worker_manifest_inventory.csv"))
  app_check_required_columns(worker_inventory, c(
    "mcmc_case_id", "fit_structure", "chain_id", "manifest_path",
    "manifest_sha256", "verified"
  ), "Phase172 worker manifest inventory")
  manifest_exists <- file.exists(worker_inventory$manifest_path)
  manifest_sha_verified <- rep(FALSE, nrow(worker_inventory))
  manifest_sha_verified[manifest_exists] <- tolower(vapply(
    worker_inventory$manifest_path[manifest_exists], app_sha256_file, character(1L)
  )) == tolower(worker_inventory$manifest_sha256[manifest_exists])
  if (nrow(worker_inventory) != 128L ||
      !all(app_as_bool_vec(worker_inventory$verified)) ||
      !all(manifest_sha_verified)) {
    stop("Phase172 retained worker-manifest inventory failed closed.", call. = FALSE)
  }

  exal_candidates <- file.path(phase172, "candidates")
  exal_dirs <- list.dirs(exal_candidates, recursive = FALSE, full.names = TRUE)
  exal_models <- c(
    joint_exqdesn_rhs_vb = "joint",
    exqdesn_rhs_independent_vb = "independent"
  )
  exal_rows <- lapply(names(exal_models), function(model_id) {
      structure <- exal_models[[model_id]]
      suffix <- paste0("__", structure, "$")
      dirs <- exal_dirs[grepl(suffix, basename(exal_dirs))]
      complete <- vapply(dirs, function(path) {
        draws <- file.path(path, sprintf("chain_%02d", 1:8), "checkpoint", "posterior_draws.csv.gz")
        manifests <- file.path(path, sprintf("chain_%02d", 1:8), "artifact_manifest.csv")
        inventory_rows <- worker_inventory[
          worker_inventory$mcmc_case_id == basename(path) &
            worker_inventory$fit_structure == structure,
          , drop = FALSE
        ]
        all(file.exists(draws)) && all(file.exists(manifests)) &&
          nrow(inventory_rows) == 8L &&
          all(app_as_bool_vec(inventory_rows$verified))
      }, logical(1L))
      data.frame(
        source_model_id = model_id, likelihood_family = "exAL",
        fit_structure = structure, article_cells = 8L,
        canonical_action_rows_available = 8L,
        posterior_draw_cells_available = sum(complete),
        worker_manifests_expected = 64L,
        worker_manifests_verified = sum(
          worker_inventory$fit_structure == structure & manifest_sha_verified
        ),
        source_manifest_verified = TRUE,
        posterior_draw_status = if (length(dirs) == 8L && all(complete)) {
          "source_complete_retained_phase172"
        } else "source_incomplete",
        retained_source_dir = phase172,
        next_action = "reuse_verified_draws_except_matched_promoted_cells",
        stringsAsFactors = FALSE
      )
    }
  )
  al_rows <- lapply(names(al_sources), function(model_id) {
    source <- al_sources[[model_id]]
    source_check <- app_joint_exqdesn_verify_manifest(source, model_id)
    source_verified <- nrow(source_check) > 0L && all(source_check$status == "pass")
    draw_files <- if (dir.exists(source)) {
      list.files(source, pattern = "^posterior_draws[.]csv[.]gz$", recursive = TRUE)
    } else character()
    data.frame(
      source_model_id = model_id, likelihood_family = "AL",
      fit_structure = if (startsWith(model_id, "joint_")) "joint" else "independent",
      article_cells = 8L,
      canonical_action_rows_available = sum(authority$source_model_id == model_id),
      posterior_draw_cells_available = 0L,
      worker_manifests_expected = 0L, worker_manifests_verified = 0L,
      source_manifest_verified = source_verified,
      posterior_draw_status = if (!length(draw_files)) {
        "action_only_rerun_required"
      } else "unexpected_draw_inventory_review",
      retained_source_dir = source,
      next_action = "rerun_balanced_article_fixture_for_posterior_score_intervals",
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(c(al_rows, exal_rows))
  out <- out[match(c(
    "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
  ), out$source_model_id), , drop = FALSE]
  if (anyNA(out$source_model_id) || sum(out$article_cells) != 32L ||
      sum(out$posterior_draw_cells_available) != 16L ||
      !all(out$source_manifest_verified) ||
      sum(out$worker_manifests_verified) != 128L) {
    stop("Balanced posterior-draw source inventory failed closed.", call. = FALSE)
  }
  out
}

app_joint_qdesn_phase179_closeout_tables <- function(
  assessment, decisions, controls, score_summary, mcmc_summary,
  parameter_diagnostics, pairing, runtime, source_completeness
) {
  app_check_required_columns(assessment, c(
    "workers_planned", "workers_complete", "workers_failed",
    "confirmation_cases", "target_cells", "promoted_nonparity",
    "retained_parity", "contract_crossing_pairs"
  ), "Phase179 closeout assessment")
  app_check_required_columns(decisions, c(
    "case_id", "base_scenario_id", "fit_structure", "final_selected_template_id",
    "final_selected_variant_id", "promoted_nonparity", "fresh_replicates",
    "median_score_ratio_vs_parity", "relative_score_improvement",
    "lower_score_replicate_fraction", "median_probability_lower_score",
    "median_forecast_oracle_mae_ratio", "maximum_forecast_oracle_mae_ratio",
    "median_fit_oracle_mae_ratio", "maximum_fit_oracle_mae_ratio",
    "source_and_implementation_pass", "score_functional_hard_pass",
    "oracle_safeguard_pass", "directional_gain_confirmed", "gate_status"
  ), "Phase179 closeout decisions")
  app_check_required_columns(controls, c(
    "case_id", "phase178_template_id", "variant_id", "tau0", "zeta2",
    "alpha_prior_sd", "source_control_row_sha256", "phase179_final_role"
  ), "Phase179 closeout controls")
  app_check_required_columns(score_summary, c(
    "case_id", "phase178_template_id", "dgp_replicate_id",
    "posterior_score_mean", "posterior_score_median", "posterior_score_q025",
    "posterior_score_q975", "canonical_action_dgp_integrated_acrps",
    "score_rank_rhat", "score_bulk_ess", "score_tail_ess",
    "raw_crossing_rate", "contract_crossing_pairs", "score_functional_status"
  ), "Phase179 closeout posterior scores")
  app_check_required_columns(mcmc_summary, c(
    "mcmc_case_id", "implementation_status", "scalar_mixing_status",
    "forecast_contract_crossing_pairs"
  ), "Phase179 closeout MCMC summary")
  app_check_required_columns(parameter_diagnostics, c(
    "parameter", "rank_rhat", "bulk_ess", "tail_ess"
  ), "Phase179 closeout parameter diagnostics")
  app_check_required_columns(pairing, c(
    "fit_structure", "maximum_relative_mean_shift", "pairing_status"
  ), "Phase179 closeout pairing audit")
  app_check_required_columns(runtime, c("worker_id", "elapsed_seconds"), "Phase179 runtime")
  app_check_required_columns(source_completeness, c(
    "source_model_id", "article_cells", "posterior_draw_cells_available",
    "worker_manifests_verified", "source_manifest_verified"
  ), "Phase179 balanced source completeness")

  hard_pass <- nrow(assessment) == 1L && assessment$workers_planned[[1L]] == 384L &&
    assessment$workers_complete[[1L]] == 384L && assessment$workers_failed[[1L]] == 0L &&
    assessment$confirmation_cases[[1L]] == 24L && assessment$target_cells[[1L]] == 5L &&
    assessment$promoted_nonparity[[1L]] == 3L && assessment$retained_parity[[1L]] == 2L &&
    assessment$contract_crossing_pairs[[1L]] == 0L && nrow(decisions) == 5L &&
    sum(app_as_bool_vec(decisions$promoted_nonparity)) == 3L &&
    all(app_as_bool_vec(decisions$source_and_implementation_pass)) &&
    all(app_as_bool_vec(decisions$score_functional_hard_pass)) &&
    all(app_as_bool_vec(decisions$oracle_safeguard_pass)) &&
    !anyDuplicated(decisions$case_id) && !anyDuplicated(controls$case_id) &&
    nrow(controls) == 5L &&
    all(mcmc_summary$implementation_status == "pass") &&
    all(mcmc_summary$forecast_contract_crossing_pairs == 0L) &&
    nrow(mcmc_summary) == 24L && nrow(score_summary) == 24L &&
    !anyDuplicated(paste(
      score_summary$case_id, score_summary$phase178_template_id,
      score_summary$dgp_replicate_id, sep = "::"
    )) &&
    all(is.finite(unlist(score_summary[, c(
      "posterior_score_mean", "posterior_score_median", "posterior_score_q025",
      "posterior_score_q975", "canonical_action_dgp_integrated_acrps",
      "score_rank_rhat", "score_bulk_ess", "score_tail_ess", "raw_crossing_rate"
    ), drop = FALSE]))) &&
    all(score_summary$score_functional_status %in% c("pass", "review")) &&
    all(score_summary$contract_crossing_pairs == 0L) &&
    nrow(pairing) == 24L && all(pairing$pairing_status == "pass") &&
    all(is.finite(pairing$maximum_relative_mean_shift)) &&
    nrow(runtime) == 384L && !anyDuplicated(runtime$worker_id) &&
    all(is.finite(runtime$elapsed_seconds)) && all(runtime$elapsed_seconds > 0) &&
    nrow(source_completeness) == 4L &&
    sum(source_completeness$article_cells) == 32L &&
    sum(source_completeness$posterior_draw_cells_available) == 16L &&
    sum(source_completeness$worker_manifests_verified) == 128L &&
    all(app_as_bool_vec(source_completeness$source_manifest_verified))
  if (!hard_pass) stop("Phase179 closeout hard evidence gate failed.", call. = FALSE)

  selected <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(decisions)), function(ii) {
    decision <- decisions[ii, , drop = FALSE]
    block <- score_summary[
      score_summary$case_id == decision$case_id[[1L]] &
        score_summary$phase178_template_id == decision$final_selected_template_id[[1L]],
      , drop = FALSE
    ]
    if (nrow(block) != 3L) stop("Selected control lacks three score replicates.", call. = FALSE)
    data.frame(
      case_id = decision$case_id[[1L]], base_scenario_id = decision$base_scenario_id[[1L]],
      fit_structure = decision$fit_structure[[1L]],
      final_selected_template_id = decision$final_selected_template_id[[1L]],
      final_selected_variant_id = decision$final_selected_variant_id[[1L]],
      promoted_nonparity = decision$promoted_nonparity[[1L]],
      relative_score_improvement = decision$relative_score_improvement[[1L]],
      lower_score_replicate_fraction = decision$lower_score_replicate_fraction[[1L]],
      median_probability_lower_score = decision$median_probability_lower_score[[1L]],
      median_posterior_score_mean = stats::median(block$posterior_score_mean),
      median_canonical_action_score = stats::median(
        block$canonical_action_dgp_integrated_acrps
      ),
      maximum_score_rank_rhat = max(block$score_rank_rhat),
      minimum_score_bulk_ess = min(block$score_bulk_ess),
      minimum_score_tail_ess = min(block$score_tail_ess),
      median_raw_crossing_rate = stats::median(block$raw_crossing_rate),
      maximum_raw_crossing_rate = max(block$raw_crossing_rate),
      contract_crossing_pairs = sum(block$contract_crossing_pairs),
      score_functional_pass_replicates = sum(block$score_functional_status == "pass"),
      gate_status = decision$gate_status[[1L]], stringsAsFactors = FALSE
    )
  }))
  selected <- merge(
    selected,
    controls[, c(
      "case_id", "phase178_template_id", "tau0", "zeta2", "alpha_prior_sd",
      "source_control_row_sha256", "phase179_final_role"
    ), drop = FALSE],
    by.x = c("case_id", "final_selected_template_id"),
    by.y = c("case_id", "phase178_template_id"), all.x = TRUE, sort = FALSE
  )
  if (anyNA(selected$source_control_row_sha256)) {
    stop("Phase179 closeout could not resolve a selected frozen control.", call. = FALSE)
  }

  parameter_blocks <- app_joint_qdesn_bind_rows(lapply(
    split(parameter_diagnostics, parameter_diagnostics$parameter), function(x) {
      data.frame(
        parameter = x$parameter[[1L]], diagnostic_rows = nrow(x),
        maximum_rank_rhat = max(x$rank_rhat, na.rm = TRUE),
        median_rank_rhat = stats::median(x$rank_rhat, na.rm = TRUE),
        minimum_bulk_ess = min(x$bulk_ess, na.rm = TRUE),
        median_bulk_ess = stats::median(x$bulk_ess, na.rm = TRUE),
        minimum_tail_ess = min(x$tail_ess, na.rm = TRUE),
        median_tail_ess = stats::median(x$tail_ess, na.rm = TRUE),
        stringsAsFactors = FALSE
      )
    }
  ))
  parameter_blocks <- parameter_blocks[order(parameter_blocks$parameter), , drop = FALSE]

  evidence <- data.frame(
    phase_id = "joint_qdesn_phase179_dgp_score_confirmation_closeout_v1",
    gate_status = "review",
    implementation_hard_gates = "pass",
    workers_complete = assessment$workers_complete[[1L]],
    workers_failed = assessment$workers_failed[[1L]],
    score_cells = nrow(score_summary),
    score_functional_pass = sum(score_summary$score_functional_status == "pass"),
    score_functional_review = sum(score_summary$score_functional_status == "review"),
    scalar_mixing_review = sum(mcmc_summary$scalar_mixing_status == "review"),
    promoted_nonparity = sum(app_as_bool_vec(decisions$promoted_nonparity)),
    retained_parity = sum(!app_as_bool_vec(decisions$promoted_nonparity)),
    contract_crossing_pairs = sum(score_summary$contract_crossing_pairs),
    maximum_raw_crossing_rate = max(score_summary$raw_crossing_rate),
    independent_pairing_maximum_relative_shift = max(
      pairing$maximum_relative_mean_shift[pairing$fit_structure == "independent"]
    ),
    worker_core_hours = sum(runtime$elapsed_seconds) / 3600,
    article_fixture_used_for_selection = FALSE,
    article_assets_mutated = FALSE,
    ready_for_integration = TRUE,
    ready_for_article_launch_from_current_branch = FALSE,
    stringsAsFactors = FALSE
  )
  next_stage <- data.frame(
    stage_order = 1:4,
    stage = c(
      "integrate_phase179_scientific_branch",
      "matched_article_fixture_confirmation",
      "balanced_32_cell_posterior_score_completion",
      "dense_19_level_quantile_grid"
    ),
    status = c(
      "ready_for_integration", "blocked_pending_integration",
      "blocked_pending_article_confirmation", "deferred"
    ),
    planned_cases = c(NA_integer_, 6L, 32L, NA_integer_),
    planned_workers = c(NA_integer_, 96L, 128L, NA_integer_),
    primary_metric = c(
      "dgp_integrated_acrps", "dgp_integrated_acrps",
      "dgp_integrated_acrps", "not_frozen"
    ),
    source_rule = c(
      "integration_coordinator_merges_only_after_handoff",
      "three_confirmed_challengers_plus_matched_parity",
      "reuse_16_verified_exAL_cells_and_rerun_16_AL_cells_with_8_chains",
      "separate_refit_contract_after_current_grid_article_packet"
    ),
    article_mutation_allowed = FALSE,
    stringsAsFactors = FALSE
  )
  list(
    evidence = evidence, selected = selected, parameter_blocks = parameter_blocks,
    source_completeness = source_completeness, next_stage = next_stage
  )
}

app_joint_qdesn_phase179_freeze_closeout <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(), audit_dir = NULL,
  out_dir = NULL, source_completeness = NULL, force = FALSE
) {
  dirs <- app_joint_qdesn_phase179_dirs(cache_root)
  audit_dir <- audit_dir %||% dirs$audit
  out_dir <- out_dir %||% dirs$closeout
  audit_check <- app_joint_exqdesn_verify_manifest(audit_dir, "phase179_score_audit")
  if (any(audit_check$status != "pass")) {
    stop("Phase179 closeout source manifest failed.", call. = FALSE)
  }
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(out_dir, "phase179_score_closeout")
    if (all(check$status == "pass")) {
      return(list(
        out_dir = normalizePath(out_dir),
        assessment = app_read_csv(file.path(out_dir, "closeout_assessment.csv")),
        reused = TRUE
      ))
    }
  }
  read <- function(name) app_read_csv(file.path(audit_dir, name))
  if (is.null(source_completeness)) {
    source_completeness <- app_joint_qdesn_phase179_balanced_source_completeness(cache_root)
  }
  tables <- app_joint_qdesn_phase179_closeout_tables(
    assessment = read("assessment.csv"),
    decisions = read("case_specific_confirmation_decision.csv"),
    controls = read("final_case_specific_controls.csv"),
    score_summary = read("posterior_dgp_integrated_acrps_summary.csv"),
    mcmc_summary = read("mcmc_case_summary.csv"),
    parameter_diagnostics = read("mcmc_parameter_diagnostics.csv"),
    pairing = read("score_pairing_stability.csv"),
    runtime = read("runtime_summary.csv"),
    source_completeness = source_completeness
  )
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase179 DGP-score confirmation closeout", "",
    "This packet closes the 384-chain protected confirmation and verifies its final audit.",
    "Three case-specific challengers are promoted and two cells retain parity.",
    "The overall gate remains review because raw crossings and scalar alpha/trend mixing remain diagnostic concerns.",
    "Gamma and sigma diagnostics are healthy; every reported contract grid is noncrossing.",
    "The next production launch is blocked until this branch is integrated onto a fresh main-based JOINT branch.",
    "No article fixture, dense-grid model, article asset, main branch, or Overleaf branch is changed here."
  ), readme, useBytes = TRUE)
  paths <- c(
    source_audit_manifest_verification = write(
      audit_check, "source_audit_manifest_verification.csv"
    ),
    closeout_assessment = write(tables$evidence, "closeout_assessment.csv"),
    final_case_specific_decisions = write(
      read("case_specific_confirmation_decision.csv"),
      "final_case_specific_decisions.csv"
    ),
    final_case_specific_controls = write(
      read("final_case_specific_controls.csv"), "final_case_specific_controls.csv"
    ),
    selected_score_diagnostics = write(
      tables$selected, "selected_score_diagnostics.csv"
    ),
    parameter_block_diagnostics = write(
      tables$parameter_blocks, "parameter_block_diagnostics.csv"
    ),
    balanced_source_completeness = write(
      tables$source_completeness, "balanced_source_completeness.csv"
    ),
    next_stage_contract = write(tables$next_stage, "next_stage_contract.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine prior Phase179 closeout.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase179 closeout.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase179_score_closeout")
  if (any(check$status != "pass")) stop("Phase179 closeout manifest failed.", call. = FALSE)
  list(out_dir = final_dir, assessment = tables$evidence, reused = FALSE)
}
