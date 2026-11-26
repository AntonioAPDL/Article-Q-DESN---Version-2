# Sealed V5 confirmation for the persistent-heavy-tail V4 finalists.

app_joint_pht5_contract_path <- function() {
  app_path("application/config/joint_qdesn_persistent_tail_sealed_v5_contract.csv")
}

app_joint_pht5_default_root <- function() {
  app_path("application/cache/joint_qdesn_persistent_tail_sealed_v5_20261126")
}

app_joint_pht5_value <- function(tab, name) {
  row <- tab[tab$name == name, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("V5 contract requires one '%s'.", name), call. = FALSE)
  as.character(row$value[[1L]])
}

app_joint_pht5_read_contract <- function(path = app_joint_pht5_contract_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "persistent-tail V5 contract")
  if (anyDuplicated(tab$name)) stop("V5 contract fields must be unique.", call. = FALSE)
  value <- function(name) app_joint_pht5_value(tab, name)
  numvec <- function(name) as.numeric(strsplit(value(name), ";", fixed = TRUE)[[1L]])
  intvec <- function(name) as.integer(numvec(name))
  bool <- function(name) identical(tolower(value(name)), "true")
  out <- list(table = tab, version = value("contract_version"), run_tag = value("run_tag"),
    source_branch = value("source_branch"), source_head = value("source_head"),
    source_manifest_sha256 = value("source_manifest_sha256"),
    source_decision_sha256 = value("source_decision_sha256"),
    source_challengers_sha256 = value("source_challengers_sha256"),
    source_exact_sha256 = value("source_exact_sha256"), scenario_id = value("scenario_id"),
    challenger_ids = strsplit(value("challenger_ids"), ";", fixed = TRUE)[[1L]],
    exact_candidate_id = value("exact_candidate_id"), quantile_grid = numvec("quantile_grid"),
    sealed_replicates = as.integer(value("sealed_replicates")),
    full_origins = intvec("full_origin_indices"),
    expected_workers = as.integer(value("expected_workers")),
    primary_metric = value("primary_metric"), required_hostname = value("required_hostname"),
    physical_workers = as.integer(value("physical_workers")),
    blas_threads = as.integer(value("blas_threads")), nice_level = as.integer(value("nice_level")))
  for (name in c("median_fit_relative_margin", "median_fit_absolute_margin",
      "tail_fit_relative_margin", "tail_fit_absolute_margin", "horizon1_relative_margin",
      "horizon1_absolute_margin", "min_data_free_gib", "min_available_memory_gib")) {
    out[[name]] <- as.numeric(value(name))
  }
  for (name in c("protected_selection_forbidden", "automatic_downstream_launch",
      "promote_any_strict_mean_improvement", "interval_overlap_is_equivalence",
      "require_zero_contract_crossings")) out[[name]] <- bool(name)
  hashes <- c(out$source_manifest_sha256, out$source_decision_sha256,
    out$source_challengers_sha256, out$source_exact_sha256)
  valid <- identical(out$version, "joint_qdesn_persistent_tail_sealed_v5") &&
    identical(out$scenario_id, "persistent_heavy_tail") && length(out$challenger_ids) == 2L &&
    length(unique(c(out$challenger_ids, out$exact_candidate_id))) == 3L &&
    identical(out$quantile_grid, c(0.05, 0.50, 0.95)) &&
    identical(out$full_origins, seq_len(10L)) && out$sealed_replicates == 5L &&
    out$expected_workers == 15L && out$physical_workers == 15L &&
    all(grepl("^[a-f0-9]{64}$", hashes)) && out$protected_selection_forbidden &&
    !out$automatic_downstream_launch && out$promote_any_strict_mean_improvement &&
    !out$interval_overlap_is_equivalence && out$require_zero_contract_crossings
  if (!valid) stop("Persistent-tail V5 contract is malformed.", call. = FALSE)
  out
}

app_joint_pht5_source_files <- function() {
  c(manifest = "t1_gate_failure_manifest.csv",
    verification = "t1_gate_failure_manifest_verification.csv",
    decision = "t1_gate_failure_decision.csv",
    challengers = "t1_gate_failure_qualified_challengers.csv",
    exact = "t1_gate_failure_exact_control.csv",
    limits = "t1_gate_failure_limits.csv", audit = "t1_gate_failure_audit.csv",
    git_state = "t1_gate_failure_git_state.csv", capacity = "t1_capacity_receipt.csv")
}

app_joint_pht5_verify_v4_source <- function(source_root,
    contract = app_joint_pht5_read_contract()) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  files <- app_joint_pht5_source_files()
  paths <- file.path(source_root, unname(files))
  if (!all(file.exists(paths)) || any(file.info(paths)$isdir)) {
    stop("V5 source packet is incomplete.", call. = FALSE)
  }
  pins <- c(manifest = contract$source_manifest_sha256,
    decision = contract$source_decision_sha256,
    challengers = contract$source_challengers_sha256, exact = contract$source_exact_sha256)
  observed <- unname(tools::sha256sum(file.path(source_root, files[names(pins)])))
  if (!identical(observed, unname(pins))) stop("V5 source packet hash pin failed.", call. = FALSE)
  verified <- app_joint_shared_verify_manifest(source_root, file.path(source_root, files[["manifest"]]))
  if (!nrow(verified) || any(!verified$verified)) stop("V4 source manifest does not verify.", call. = FALSE)
  decision <- app_read_csv(file.path(source_root, files[["decision"]]))
  if (nrow(decision) != 1L || decision$status[[1L]] !=
      "T1_COMPLETE_STOP_INSUFFICIENT_FIT_CAPABLE_CHALLENGERS" ||
      decision$fit_capable_challengers[[1L]] != 2L ||
      app_as_bool_vec(decision$s1_prepared)[[1L]] ||
      app_as_bool_vec(decision$sealed_panel_materialized)[[1L]]) {
    stop("V4 terminal decision is incompatible with V5.", call. = FALSE)
  }
  git_state <- app_read_csv(file.path(source_root, files[["git_state"]]))
  if (nrow(git_state) != 1L || git_state$head[[1L]] != contract$source_head ||
      git_state$branch[[1L]] != contract$source_branch) {
    stop("V4 source Git identity does not match the frozen contract.", call. = FALSE)
  }
  challengers <- app_read_csv(file.path(source_root, files[["challengers"]]))
  exact <- app_read_csv(file.path(source_root, files[["exact"]]))
  if (nrow(challengers) != 2L || !setequal(challengers$candidate_id, contract$challenger_ids) ||
      nrow(exact) != 1L || exact$candidate_id[[1L]] != contract$exact_candidate_id ||
      !all(app_as_bool_vec(challengers$fit_capable)) ||
      !app_as_bool_vec(exact$fit_capable)[[1L]]) {
    stop("V4 finalist identities or qualification gates do not match V5.", call. = FALSE)
  }
  fixture_manifest <- app_read_csv(file.path(source_root, "fixture_manifest.csv"))
  sealed <- fixture_manifest$panel == "sealed"
  preexisting <- c(file.path(source_root, "sealed_fixture_manifest.csv"),
    file.path(source_root, "s1_worker_plan.csv"),
    list.files(file.path(source_root, "fixtures"), pattern = "^sealed_rep.*[.]rds$", full.names = TRUE))
  if (sum(sealed) != contract$sealed_replicates ||
      any(app_as_bool_vec(fixture_manifest$materialized[sealed])) ||
      any(!is.na(fixture_manifest$fixture_path[sealed]) & nzchar(fixture_manifest$fixture_path[sealed])) ||
      any(file.exists(preexisting))) {
    stop("V4 sealed fixtures were already exposed or prepared.", call. = FALSE)
  }
  list(root = source_root, files = files, challengers = challengers, exact = exact,
    verification = verified)
}

app_joint_pht5_finalists <- function(source, contract = app_joint_pht5_read_contract()) {
  finalists <- app_bind_rows_fill(list(source$challengers, source$exact))
  finalists <- finalists[match(c(contract$challenger_ids, contract$exact_candidate_id),
    finalists$candidate_id), , drop = FALSE]
  if (nrow(finalists) != 3L || anyNA(finalists$candidate_id) ||
      anyDuplicated(finalists$candidate_id)) stop("V5 finalists are not exact.", call. = FALSE)
  finalists$qualification_role <- ifelse(finalists$candidate_id == contract$exact_candidate_id,
    "exact_v2_control", "v4_qualified_challenger")
  finalists$source_stage <- "v4_t1_gate_failure_closeout"
  finalists
}

app_joint_pht5_build_plan <- function(finalists, registry, sealed,
    contract = app_joint_pht5_read_contract(), finalists_sha256 = strrep("0", 64L)) {
  required <- c("candidate_id", "rhs_tau0", "normal_rhs_tau0", "rhs_zeta2_profile",
    "rhs_zeta2_fixed", "prior_spec_id", "quantile_spec_id", "al_tau0_multiplier",
    "qualification_role")
  app_check_required_columns(finalists, required, "V5 finalists")
  app_check_required_columns(registry, c("candidate_id", "structural_signature"),
    "V5 candidate registry")
  app_check_required_columns(sealed, c("scenario_id", "replicate_id", "dgp_seed",
    "fixture_path", "protected_rows_persisted"), "V5 sealed fixtures")
  profiles <- registry[match(finalists$candidate_id, registry$candidate_id), , drop = FALSE]
  if (nrow(profiles) != 3L || anyNA(profiles$candidate_id)) {
    stop("V5 finalists are absent from the frozen candidate registry.", call. = FALSE)
  }
  if (!identical(profiles$structural_signature, finalists$structural_signature)) {
    stop("V5 finalist architecture signatures changed.", call. = FALSE)
  }
  specs <- finalists[, required, drop = FALSE]
  profiles <- merge(profiles, specs, by = "candidate_id", all.y = TRUE, sort = FALSE)
  profiles <- profiles[match(finalists$candidate_id, profiles$candidate_id), , drop = FALSE]
  profiles$prior_mode <- "fixed_tau0"
  plan <- merge(profiles, sealed[, c("scenario_id", "replicate_id", "dgp_seed",
    "fixture_path")], by = "scenario_id", all.x = TRUE, sort = FALSE)
  plan <- plan[order(match(plan$candidate_id, finalists$candidate_id), plan$replicate_id), , drop = FALSE]
  plan$origin_indices <- paste(contract$full_origins, collapse = ";")
  plan$finalists_sha256 <- finalists_sha256
  plan$s1_worker_id <- seq_len(nrow(plan))
  if (nrow(plan) != contract$expected_workers || anyNA(plan$fixture_path) ||
      any(sealed$protected_rows_persisted != 0L) ||
      any(table(plan$candidate_id) != contract$sealed_replicates) ||
      any(table(plan$replicate_id) != 3L)) stop("V5 worker plan cardinality failed.", call. = FALSE)
  plan
}

app_joint_pht5_copy_source <- function(source_root, root, files) {
  out <- file.path(root, paste0("v4_source_", unname(files)))
  ok <- file.copy(file.path(source_root, unname(files)), out, overwrite = FALSE, copy.mode = TRUE)
  if (!all(ok)) stop("Could not freeze the V4 source evidence in V5.", call. = FALSE)
  stats::setNames(out, paste0("v4_source_", names(files)))
}

app_joint_pht5_prepare <- function(source_root, root = app_joint_pht5_default_root()) {
  contract <- app_joint_pht5_read_contract()
  source <- app_joint_pht5_verify_v4_source(source_root, contract)
  root <- normalizePath(root, mustWork = FALSE)
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty V5 campaign root.", call. = FALSE)
  }
  app_ensure_dir(root); app_ensure_dir(file.path(root, "fixtures"))
  foundational <- c("frozen_contract.csv", "frozen_v4_contract.csv", "frozen_registry.csv",
    "derived_dgp_registry.csv", "candidate_registry.csv", "fixture_manifest.csv")
  copied_foundational <- file.path(root, foundational)
  if (!all(file.copy(file.path(source$root, foundational), copied_foundational,
      overwrite = FALSE, copy.mode = TRUE))) stop("Could not copy V4 frozen inputs.", call. = FALSE)
  source_files <- app_joint_pht5_copy_source(source$root, root, source$files)
  finalists <- app_joint_pht5_finalists(source, contract)
  finalists_path <- app_write_csv(finalists, file.path(root, "v5_frozen_finalists.csv"))
  finalists_sha256 <- app_sha256_file(finalists_path)
  frozen_contract <- app_write_csv(contract$table, file.path(root, "frozen_v5_contract.csv"))
  selection <- data.frame(
    frozen_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    source_head = contract$source_head, source_manifest_sha256 = contract$source_manifest_sha256,
    source_decision_sha256 = contract$source_decision_sha256,
    source_challengers_sha256 = contract$source_challengers_sha256,
    source_exact_sha256 = contract$source_exact_sha256,
    finalists_sha256 = finalists_sha256, finalist_count = 3L,
    sealed_fixtures_materialized_at_freeze = FALSE, protected_rows_used = 0L,
    stringsAsFactors = FALSE)
  selection_path <- app_write_csv(selection, file.path(root, "selection_freeze.csv"))
  selection_hash_path <- file.path(root, "selection_freeze.sha256")
  writeLines(app_sha256_file(selection_path), selection_hash_path)

  v4_contract <- app_joint_pht4_read_contract(file.path(root, "frozen_v4_contract.csv"))
  sealed <- app_joint_pht4_materialize_panel(root, "sealed", v4_contract)
  sealed_path <- app_write_csv(sealed, file.path(root, "sealed_fixture_manifest.csv"))
  registry <- app_read_csv(file.path(root, "candidate_registry.csv"))
  plan <- app_joint_pht5_build_plan(finalists, registry, sealed, contract, finalists_sha256)
  plan_files <- app_joint_pht4_freeze_plan(root, "s1", plan)
  readiness <- data.frame(status = "V5_PREPARED_SEALED_WORKERS_NOT_LAUNCHED",
    source_head = contract$source_head, finalist_count = 3L,
    sealed_replicates = contract$sealed_replicates, expected_workers = nrow(plan),
    finalists_sha256 = finalists_sha256, automatic_downstream_launch = FALSE,
    protected_rows_used = 0L, stringsAsFactors = FALSE)
  readiness_path <- app_write_csv(readiness, file.path(root, "launch_readiness.csv"))
  files <- c(frozen_v5_contract = frozen_contract, v5_finalists = finalists_path,
    selection_freeze = selection_path, selection_freeze_sha256 = selection_hash_path,
    sealed_fixtures = sealed_path, plan_files, launch_readiness = readiness_path,
    stats::setNames(copied_foundational, paste0("v4_", sub("[.]csv$", "", foundational))),
    source_files)
  manifest <- app_joint_shared_write_manifest(root, files, filename = "preparation_manifest.csv")
  verified <- app_joint_shared_verify_manifest(root, manifest)
  if (!nrow(verified) || any(!verified$verified) || any(sealed$protected_rows_persisted != 0L)) {
    stop("V5 preparation manifest or protected-data gate failed.", call. = FALSE)
  }
  app_write_csv(verified, file.path(root, "preparation_manifest_verification.csv"))
  list(root = root, readiness = readiness, plan = plan, sealed = sealed)
}

app_joint_pht5_health <- function(root) app_joint_pht4_health(root, "s1")

app_joint_pht5_run_worker <- function(root, worker_id) {
  app_joint_pht4_run_worker(root, "s1", worker_id)
}

app_joint_pht5_interval <- function(x) {
  stats::quantile(x, probs = c(0.025, 0.5, 0.975), names = FALSE, type = 8)
}

app_joint_pht5_evaluate <- function(scores, contract = app_joint_pht5_read_contract()) {
  required <- c("candidate_id", "replicate_id", "dgp_integrated_three_level_score",
    "realized_three_level_score", "lower_fit_mae", "median_fit_mae", "upper_fit_mae",
    "lower_horizon1_mae", "median_horizon1_mae", "upper_horizon1_mae",
    "hard_functional_pass", "convergence_review_only", "contract_crossing_pairs")
  app_check_required_columns(scores, required, "V5 worker scores")
  ids <- c(contract$challenger_ids, contract$exact_candidate_id)
  if (nrow(scores) != contract$expected_workers || !setequal(scores$candidate_id, ids) ||
      any(table(scores$candidate_id) != contract$sealed_replicates) ||
      any(table(scores$replicate_id) != 3L) ||
      !setequal(unique(scores$replicate_id), seq_len(contract$sealed_replicates))) {
    stop("V5 completed score panel is not exactly matched.", call. = FALSE)
  }
  metric_names <- c("lower_fit_mae", "median_fit_mae", "upper_fit_mae",
    "lower_horizon1_mae", "median_horizon1_mae", "upper_horizon1_mae")
  aggregates <- app_bind_rows_fill(lapply(ids, function(id) {
    x <- scores[scores$candidate_id == id, , drop = FALSE]
    q <- app_joint_pht5_interval(x$dgp_integrated_three_level_score)
    rq <- app_joint_pht5_interval(x$realized_three_level_score)
    meta <- x[1L, intersect(c("scenario_id", "candidate_id", "candidate_role",
      "source_candidate_id", "qualification_role", "D", "n", "response_lags", "alpha",
      "rho", "input_scale", "rhs_tau0", "normal_rhs_tau0", "rhs_zeta2_profile",
      "rhs_zeta2_fixed", "prior_spec_id", "quantile_spec_id"), names(x)), drop = FALSE]
    means <- as.list(vapply(x[metric_names], mean, numeric(1L)))
    names(means) <- paste0(metric_names, "_mean")
    cbind(meta, as.data.frame(means), data.frame(replicates = nrow(x),
      dgp_score_mean = mean(x$dgp_integrated_three_level_score),
      dgp_score_sd = stats::sd(x$dgp_integrated_three_level_score),
      dgp_score_q025 = q[[1L]], dgp_score_median = q[[2L]], dgp_score_q975 = q[[3L]],
      realized_score_mean = mean(x$realized_three_level_score),
      realized_score_q025 = rq[[1L]], realized_score_median = rq[[2L]],
      realized_score_q975 = rq[[3L]],
      hard_functional_pass_all = all(app_as_bool_vec(x$hard_functional_pass)),
      convergence_review_any = any(app_as_bool_vec(x$convergence_review_only)),
      contract_crossing_pairs_sum = sum(x$contract_crossing_pairs), stringsAsFactors = FALSE))
  }))
  anchor <- aggregates[aggregates$candidate_id == contract$exact_candidate_id, , drop = FALSE]
  if (nrow(anchor) != 1L || !app_as_bool_vec(anchor$hard_functional_pass_all)[[1L]]) {
    stop("V5 exact V2 anchor is unavailable.", call. = FALSE)
  }
  limit <- function(value, rel, absolute) value + max(rel * abs(value), absolute)
  limits <- data.frame(
    median_fit = limit(anchor$median_fit_mae_mean, contract$median_fit_relative_margin,
      contract$median_fit_absolute_margin),
    lower_fit = limit(anchor$lower_fit_mae_mean, contract$tail_fit_relative_margin,
      contract$tail_fit_absolute_margin),
    upper_fit = limit(anchor$upper_fit_mae_mean, contract$tail_fit_relative_margin,
      contract$tail_fit_absolute_margin),
    median_h1 = limit(anchor$median_horizon1_mae_mean, contract$horizon1_relative_margin,
      contract$horizon1_absolute_margin),
    lower_h1 = limit(anchor$lower_horizon1_mae_mean, contract$horizon1_relative_margin,
      contract$horizon1_absolute_margin),
    upper_h1 = limit(anchor$upper_horizon1_mae_mean, contract$horizon1_relative_margin,
      contract$horizon1_absolute_margin), stringsAsFactors = FALSE)
  aggregates$median_fit_gate <- aggregates$median_fit_mae_mean <= limits$median_fit
  aggregates$lower_fit_gate <- aggregates$lower_fit_mae_mean <= limits$lower_fit
  aggregates$upper_fit_gate <- aggregates$upper_fit_mae_mean <= limits$upper_fit
  aggregates$median_h1_gate <- aggregates$median_horizon1_mae_mean <= limits$median_h1
  aggregates$lower_h1_gate <- aggregates$lower_horizon1_mae_mean <= limits$lower_h1
  aggregates$upper_h1_gate <- aggregates$upper_horizon1_mae_mean <= limits$upper_h1
  aggregates$fit_capable <- app_as_bool_vec(aggregates$hard_functional_pass_all) &
    aggregates$contract_crossing_pairs_sum == 0L & aggregates$median_fit_gate &
    aggregates$lower_fit_gate & aggregates$upper_fit_gate & aggregates$median_h1_gate &
    aggregates$lower_h1_gate & aggregates$upper_h1_gate
  aggregates$score_interval_overlaps_exact <- !(aggregates$dgp_score_q975 < anchor$dgp_score_q025 |
    aggregates$dgp_score_q025 > anchor$dgp_score_q975)
  aggregates$formal_equivalence_established <- FALSE

  exact_scores <- scores[scores$candidate_id == contract$exact_candidate_id,
    c("replicate_id", "dgp_integrated_three_level_score"), drop = FALSE]
  contrasts <- app_bind_rows_fill(lapply(contract$challenger_ids, function(id) {
    x <- scores[scores$candidate_id == id,
      c("replicate_id", "dgp_integrated_three_level_score"), drop = FALSE]
    paired <- merge(x, exact_scores, by = "replicate_id", suffixes = c("_challenger", "_exact"))
    delta <- paired$dgp_integrated_three_level_score_challenger -
      paired$dgp_integrated_three_level_score_exact
    q <- app_joint_pht5_interval(delta)
    data.frame(candidate_id = id, exact_candidate_id = contract$exact_candidate_id,
      matched_replicates = nrow(paired), challenger_minus_exact_mean = mean(delta),
      challenger_minus_exact_sd = stats::sd(delta), challenger_minus_exact_q025 = q[[1L]],
      challenger_minus_exact_median = q[[2L]], challenger_minus_exact_q975 = q[[3L]],
      fixtures_favoring_challenger = sum(delta < 0), interval_excludes_zero = q[[3L]] < 0,
      formal_equivalence_established = FALSE, stringsAsFactors = FALSE)
  }))
  eligible <- aggregates[aggregates$candidate_id %in% contract$challenger_ids &
    aggregates$fit_capable, , drop = FALSE]
  eligible <- eligible[order(eligible$dgp_score_mean,
    pmax(eligible$lower_fit_mae_mean, eligible$upper_fit_mae_mean),
    eligible$median_fit_mae_mean, eligible$candidate_id), , drop = FALSE]
  improves <- nrow(eligible) && eligible$dgp_score_mean[[1L]] < anchor$dgp_score_mean[[1L]]
  selected <- if (improves) eligible[1L, , drop = FALSE] else anchor
  contrast <- contrasts[contrasts$candidate_id == selected$candidate_id, , drop = FALSE]
  interpretation <- if (!improves) "exact_v2_retained_no_eligible_mean_improvement" else if (
      selected$score_interval_overlaps_exact[[1L]]) {
    "descriptive_mean_improvement_with_overlapping_marginal_intervals"
  } else "descriptive_mean_improvement_with_nonoverlapping_marginal_intervals"
  decision <- data.frame(
    status = if (improves) "V5_COMPLETE_SEVEN_LEVEL_CONTINUATION_AUTHORIZED" else
      "V5_COMPLETE_RETAIN_EXACT_V2_STOP",
    selected_candidate_id = selected$candidate_id[[1L]],
    exact_v2_candidate_id = contract$exact_candidate_id,
    eligible_challengers = nrow(eligible), selected_dgp_score = selected$dgp_score_mean[[1L]],
    exact_v2_dgp_score = anchor$dgp_score_mean[[1L]],
    selected_minus_exact_mean = if (nrow(contrast)) contrast$challenger_minus_exact_mean[[1L]] else 0,
    selected_interval_overlaps_exact = if (improves)
      selected$score_interval_overlaps_exact[[1L]] else TRUE,
    evidence_interpretation = interpretation, formal_equivalence_established = FALSE,
    seven_level_independent_al_continuation_authorized = improves,
    joint_launched = FALSE, exal_launched = FALSE, mcmc_launched = FALSE,
    article_updated = FALSE, protected_rows_used = 0L, stringsAsFactors = FALSE)
  list(aggregates = aggregates, contrasts = contrasts, limits = limits,
    selected = selected, decision = decision)
}

app_joint_pht5_finalize <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  contract <- app_joint_pht5_read_contract(file.path(root, "frozen_v5_contract.csv"))
  scores <- app_joint_pht4_collect(root, "s1")
  result <- app_joint_pht5_evaluate(scores, contract)
  files <- c(scores = app_write_csv(scores, file.path(root, "v5_worker_scores.csv")),
    aggregates = app_write_csv(result$aggregates, file.path(root, "v5_profile_summary.csv")),
    contrasts = app_write_csv(result$contrasts, file.path(root, "v5_matched_contrasts.csv")),
    limits = app_write_csv(result$limits, file.path(root, "v5_fit_gate_limits.csv")),
    selected = app_write_csv(result$selected, file.path(root, "v5_selected_profile.csv")),
    decision = app_write_csv(result$decision, file.path(root, "v5_decision.csv")),
    git_state = app_write_csv(app_joint_shared_git_state(), file.path(root, "v5_git_state.csv")),
    app_joint_sw_stage_receipts(root, "s1"))
  manifest <- app_joint_pht4_freeze_manifest(root, files, "v5_closeout_manifest.csv")
  result$manifest <- manifest
  result
}

app_joint_pht5_check <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  prep <- app_joint_shared_verify_manifest(root, file.path(root, "preparation_manifest.csv"))
  if (!nrow(prep) || any(!prep$verified)) stop("V5 preparation manifest failed.", call. = FALSE)
  health <- app_joint_pht5_health(root)
  if (health$failed[[1L]] > 0L) stop("V5 has failed workers.", call. = FALSE)
  health
}
