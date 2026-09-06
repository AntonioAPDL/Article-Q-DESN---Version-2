# Seven-family extension of the validated shared-backbone screening pipeline.

app_joint_shared_family_default_root <- function() {
  app_path("application/cache/joint_qdesn_shared_backbone_family_campaign_20260906")
}

app_joint_shared_family_contract_path <- function() {
  app_path("application/config/joint_qdesn_shared_backbone_family_campaign_contract_v1.csv")
}

app_joint_shared_family_registry_path <- function() {
  app_path("application/config/joint_qdesn_shared_backbone_family_registry_v1.csv")
}

app_joint_shared_family_authority_path <- function() {
  app_path("application/config/joint_qdesn_shared_backbone_authority_design_registry_v1.csv")
}

app_joint_shared_family_authority_manifest_path <- function() {
  app_path("application/config/joint_qdesn_shared_backbone_authority_design_manifest_v1.csv")
}

app_joint_shared_family_retained_path <- function() {
  app_path("application/config/joint_qdesn_shared_backbone_retained_regime_shift_v1.csv")
}

app_joint_shared_family_read_contract <- function(path = app_joint_shared_family_contract_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("section", "name", "value", "type", "description"),
    "shared-backbone family campaign contract")
  if (anyDuplicated(tab$name)) stop("Family campaign contract names must be unique.", call. = FALSE)
  get <- function(name) {
    row <- tab[tab$name == name, , drop = FALSE]
    if (nrow(row) != 1L) stop(sprintf("Missing family campaign field '%s'.", name), call. = FALSE)
    as.character(row$value[[1L]])
  }
  out <- list(
    table = tab,
    path = normalizePath(path, mustWork = TRUE),
    version = get("contract_version"),
    article_scenarios = as.integer(get("article_scenarios")),
    campaign_scenarios = as.integer(get("campaign_scenarios")),
    retained_pilot_scenario = get("retained_pilot_scenario"),
    models_per_scenario = as.integer(get("models_per_scenario")),
    tau = app_joint_shared_split_values(get("quantile_grid"), TRUE),
    calibration_replicates = as.integer(get("calibration_replicates")),
    evaluation_replicates = as.integer(get("evaluation_replicates")),
    novel_candidates = as.integer(get("novel_candidates")),
    authority_anchors = as.integer(get("authority_anchors")),
    ridge_jobs_per_scenario = as.integer(get("ridge_jobs_per_scenario")),
    rhs_jobs_per_scenario = as.integer(get("rhs_jobs_per_scenario")),
    vb_jobs_per_scenario = as.integer(get("vb_jobs_per_scenario")),
    max_workers = as.integer(get("max_workers")),
    blas_threads = as.integer(get("blas_threads")),
    nice_level = as.integer(get("nice_level")),
    selection_window = get("selection_window"),
    protected_scores_for_selection = identical(tolower(get("protected_scores_for_selection")), "true"),
    article_fixture_used = identical(tolower(get("article_fixture_used")), "true"),
    vb_is_article_authority = identical(tolower(get("vb_is_article_authority")), "true"),
    mcmc_launched = identical(tolower(get("mcmc_launched")), "true"),
    article_assets_modified = identical(tolower(get("article_assets_modified")), "true")
  )
  if (out$campaign_scenarios != 7L || out$article_scenarios != 8L ||
      out$models_per_scenario != 4L || out$max_workers != 10L ||
      !identical(out$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)) ||
      out$protected_scores_for_selection || out$article_fixture_used ||
      out$vb_is_article_authority || out$mcmc_launched || out$article_assets_modified) {
    stop("Family campaign scope, score, or runtime policy is malformed.", call. = FALSE)
  }
  out
}

app_joint_shared_family_read_registry <- function(path = app_joint_shared_family_registry_path()) {
  out <- app_joint_shared_read_scenarios(path)
  app_check_required_columns(out, c("calibration_seed_base", "evaluation_seed_base", "article_seed"),
    "shared-backbone family registry")
  for (nm in c("calibration_seed_base", "evaluation_seed_base", "article_seed")) {
    out[[nm]] <- as.integer(out[[nm]])
  }
  out
}

app_joint_shared_family_set_contract <- function(tab, name, value) {
  idx <- which(tab$name == name)
  if (length(idx) != 1L) stop(sprintf("Cannot set non-unique contract field '%s'.", name), call. = FALSE)
  tab$value[[idx]] <- as.character(value)
  tab
}

app_joint_shared_family_screen_contract <- function(
  scenario_id,
  calibration_seed_base,
  authority_registry = app_joint_shared_family_authority_path(),
  authority_manifest = app_joint_shared_family_authority_manifest_path(),
  template_path = app_joint_shared_contract_path()
) {
  tab <- app_read_csv(template_path)
  tab <- app_joint_shared_family_set_contract(tab, "contract_version",
    paste0("joint_shared_backbone_family_screen_v1__", scenario_id))
  tab <- app_joint_shared_family_set_contract(tab, "authority_registry_sha256",
    app_sha256_file(authority_registry))
  tab <- app_joint_shared_family_set_contract(tab, "authority_manifest_sha256",
    app_sha256_file(authority_manifest))
  tab <- app_joint_shared_family_set_contract(tab, "pilot_scenario", scenario_id)
  tab <- app_joint_shared_family_set_contract(tab, "calibration_seed_base", calibration_seed_base)
  tab
}

app_joint_shared_family_quantile_contract <- function(
  scenario_id,
  evaluation_seed_base,
  parent_dir,
  template_path = app_joint_shared_quantile_contract_path()
) {
  parent_dir <- normalizePath(parent_dir, mustWork = TRUE)
  files <- app_joint_shared_quantile_parent_files(parent_dir)
  if (any(!file.exists(files))) stop("Completed family screen is missing quantile-parent files.", call. = FALSE)
  verified <- app_joint_shared_verify_manifest(parent_dir, files[["final_manifest"]])
  if (!all(verified$verified)) stop("Completed family screen manifest does not verify.", call. = FALSE)
  git_state <- app_read_csv(files[["source_git_state"]])
  if (nrow(git_state) != 1L || !nzchar(git_state$head[[1L]])) {
    stop("Completed family screen has no unique source Git HEAD.", call. = FALSE)
  }
  tab <- app_read_csv(template_path)
  tab <- app_joint_shared_family_set_contract(tab, "contract_version",
    paste0("joint_shared_backbone_quantile_family_v1__", scenario_id))
  tab <- app_joint_shared_family_set_contract(tab, "parent_head", git_state$head[[1L]])
  tab <- app_joint_shared_family_set_contract(tab, "parent_final_manifest_sha256",
    app_sha256_file(files[["final_manifest"]]))
  tab <- app_joint_shared_family_set_contract(tab, "parent_selected_sha256",
    app_sha256_file(files[["selected_backbone"]]))
  tab <- app_joint_shared_family_set_contract(tab, "parent_decision_sha256",
    app_sha256_file(files[["selection_decision"]]))
  if (!"parent_git_state_sha256" %in% tab$name) {
    tab <- rbind(tab, data.frame(
      section = "identity", name = "parent_git_state_sha256",
      value = app_sha256_file(files[["source_git_state"]]), type = "character",
      description = "Expected source-Git-state snapshot hash for the completed family screen.",
      stringsAsFactors = FALSE))
  } else {
    tab <- app_joint_shared_family_set_contract(tab, "parent_git_state_sha256",
      app_sha256_file(files[["source_git_state"]]))
  }
  tab <- app_joint_shared_family_set_contract(tab, "pilot_scenario", scenario_id)
  tab <- app_joint_shared_family_set_contract(tab, "evaluation_seed_base", evaluation_seed_base)
  tab
}

app_joint_shared_family_roots <- function(root, registry = app_joint_shared_family_read_registry()) {
  run <- registry[registry$enabled, , drop = FALSE]
  data.frame(
    scenario_id = run$scenario_id,
    scenario_order = run$scenario_order,
    calibration_seed_base = run$calibration_seed_base,
    evaluation_seed_base = run$evaluation_seed_base,
    article_seed = run$article_seed,
    screen_contract_path = file.path(root, "contracts", paste0(run$scenario_id, "__screen.csv")),
    quantile_contract_path = file.path(root, "contracts", paste0(run$scenario_id, "__quantile.csv")),
    screening_root = file.path(root, "families", run$scenario_id, "gaussian_screen"),
    quantile_root = file.path(root, "families", run$scenario_id, "quantile_vb"),
    ridge_jobs = 579L,
    rhs_jobs = 450L,
    quantile_jobs = 51L,
    stringsAsFactors = FALSE
  )
}

app_joint_shared_family_validate_sources <- function(contract, registry) {
  authority <- app_read_csv(app_joint_shared_family_authority_path())
  authority_manifest <- app_read_csv(app_joint_shared_family_authority_manifest_path())
  manifest_row <- authority_manifest[
    authority_manifest$relative_path == basename(app_joint_shared_family_authority_path()), , drop = FALSE]
  if (nrow(authority) != 32L || nrow(manifest_row) != 1L ||
      !identical(as.character(manifest_row$sha256[[1L]]),
        app_sha256_file(app_joint_shared_family_authority_path())) ||
      as.numeric(manifest_row$size_bytes[[1L]]) != as.numeric(file.info(
        app_joint_shared_family_authority_path())$size)) {
    stop("Tracked authority-design snapshot or manifest is invalid.", call. = FALSE)
  }
  article <- app_read_csv(app_path("tables/joint_qdesn_phase181_article_scenario_model_summary.csv"))
  if (nrow(article) != 32L || length(unique(article$scenario_id)) != contract$article_scenarios ||
      length(unique(article$source_model_id)) != contract$models_per_scenario ||
      any(article$dgp_replicate_id != "article_fixture") ||
      any(article$validation_partition != "article_evaluation")) {
    stop("The authoritative article packet is not the expected 8-by-4 fixture table.", call. = FALSE)
  }
  if (!setequal(unique(article$scenario_id), registry$scenario_id) ||
      !setequal(unique(authority$scenario_id), registry$scenario_id)) {
    stop("Campaign, authority-design, and article scenario registries differ.", call. = FALSE)
  }
  dgp <- app_joint_qdesn_load_simulation_registry()
  idx <- match(registry$scenario_id, dgp$scenario_id)
  if (anyNA(idx) || any(as.integer(dgp$seed[idx]) != registry$article_seed)) {
    stop("Campaign article seeds do not match the simulation registry.", call. = FALSE)
  }
  run <- registry[registry$enabled, , drop = FALSE]
  calibration_seeds <- unlist(lapply(run$calibration_seed_base,
    function(x) x + seq_len(contract$calibration_replicates) - 1L))
  evaluation_seeds <- unlist(lapply(run$evaluation_seed_base,
    function(x) x + seq_len(contract$evaluation_replicates) - 1L))
  all_seeds <- c(calibration_seeds, evaluation_seeds, registry$article_seed)
  if (anyDuplicated(all_seeds)) stop("Campaign calibration, evaluation, and article seeds overlap.", call. = FALSE)
  data.frame(
    source = c("authority_design_snapshot", "authority_design_manifest", "phase181_article_table",
      "simulation_dgp_registry"),
    path = normalizePath(c(app_joint_shared_family_authority_path(),
      app_joint_shared_family_authority_manifest_path(),
      app_path("tables/joint_qdesn_phase181_article_scenario_model_summary.csv"),
      app_path("application/config/joint_qdesn_simulation_dgp_registry_20260706.csv")), mustWork = TRUE),
    sha256 = vapply(c(app_joint_shared_family_authority_path(),
      app_joint_shared_family_authority_manifest_path(),
      app_path("tables/joint_qdesn_phase181_article_scenario_model_summary.csv"),
      app_path("application/config/joint_qdesn_simulation_dgp_registry_20260706.csv")),
      app_sha256_file, character(1L)),
    verified = TRUE,
    stringsAsFactors = FALSE
  )
}

app_joint_shared_family_prepare <- function(root = app_joint_shared_family_default_root()) {
  contract <- app_joint_shared_family_read_contract()
  registry <- app_joint_shared_family_read_registry()
  if (nrow(registry) != contract$article_scenarios || sum(registry$enabled) != contract$campaign_scenarios ||
      sum(!registry$enabled) != 1L ||
      registry$scenario_id[!registry$enabled] != contract$retained_pilot_scenario) {
    stop("Family registry does not encode seven runs plus the retained Regime Shift pilot.", call. = FALSE)
  }
  root <- normalizePath(root, mustWork = FALSE)
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty family campaign root.", call. = FALSE)
  }
  app_ensure_dir(root); app_ensure_dir(file.path(root, "contracts")); app_ensure_dir(file.path(root, "families"))
  source_verification <- app_joint_shared_family_validate_sources(contract, registry)
  plan <- app_joint_shared_family_roots(root, registry)
  child_manifests <- character(nrow(plan))
  for (ii in seq_len(nrow(plan))) {
    app_ensure_dir(dirname(plan$screening_root[[ii]]))
    screen_contract <- app_joint_shared_family_screen_contract(
      plan$scenario_id[[ii]], plan$calibration_seed_base[[ii]])
    app_write_csv(screen_contract, plan$screen_contract_path[[ii]])
    app_joint_shared_prepare_ridge(
      out_dir = plan$screening_root[[ii]],
      authority_registry = app_joint_shared_family_authority_path(),
      scenario_id = plan$scenario_id[[ii]],
      contract_path = plan$screen_contract_path[[ii]],
      scenario_registry_path = app_joint_shared_family_registry_path(),
      authority_manifest = app_joint_shared_family_authority_manifest_path()
    )
    child_manifests[[ii]] <- file.path(plan$screening_root[[ii]], "artifact_manifest.csv")
  }
  expected <- data.frame(
    campaign_scenarios = nrow(plan), retained_pilot_scenarios = 1L,
    ridge_jobs = sum(plan$ridge_jobs), rhs_jobs = sum(plan$rhs_jobs),
    quantile_vb_jobs = sum(plan$quantile_jobs), total_jobs = sum(plan$ridge_jobs + plan$rhs_jobs + plan$quantile_jobs),
    concurrent_workers = contract$max_workers, blas_threads_per_worker = contract$blas_threads,
    article_fixture_jobs = 0L, mcmc_jobs = 0L, stringsAsFactors = FALSE
  )
  policy <- data.frame(
    selection_unit = "scenario_specific", selection_window = contract$selection_window,
    shared_backbone_within_scenario = TRUE, shared_backbone_across_scenarios = FALSE,
    protected_forecast_selects_specification = FALSE, vb_role = "readiness_and_mcmc_initialization",
    final_comparison_layer = "future_mcmc_on_designated_article_fixture",
    article_assets_modified = FALSE, separate_phase182_untouched = TRUE, stringsAsFactors = FALSE
  )
  retained <- app_read_csv(app_joint_shared_family_retained_path())
  if (nrow(retained) != 1L || retained$scenario_id[[1L]] != contract$retained_pilot_scenario ||
      retained$retained_quantile_jobs[[1L]] != 51L || retained$retained_quantile_failures[[1L]] != 0L) {
    stop("Retained Regime Shift pilot snapshot is invalid.", call. = FALSE)
  }
  files <- c(
    frozen_contract = app_write_csv(contract$table, file.path(root, "frozen_campaign_contract.csv")),
    frozen_registry = app_write_csv(registry, file.path(root, "frozen_family_registry.csv")),
    family_plan = app_write_csv(plan, file.path(root, "family_plan.csv")),
    expected_work = app_write_csv(expected, file.path(root, "expected_work.csv")),
    selection_policy = app_write_csv(policy, file.path(root, "selection_policy.csv")),
    source_verification = app_write_csv(source_verification, file.path(root, "source_verification.csv")),
    retained_regime_shift = app_write_csv(retained, file.path(root, "retained_regime_shift_backbone.csv")),
    source_git_state = app_write_csv(app_joint_shared_git_state(), file.path(root, "source_git_state.csv"))
  )
  for (ii in seq_along(child_manifests)) {
    files[[paste0("screen_prepare_manifest__", plan$scenario_id[[ii]])]] <- child_manifests[[ii]]
  }
  readiness <- data.frame(
    status = "READY_TO_LAUNCH_SEVEN_FAMILY_VB_CAMPAIGN", campaign_scenarios = nrow(plan),
    expected_jobs = expected$total_jobs, max_concurrent_workers = contract$max_workers,
    protected_rows_used_for_selection = 0L, article_fixture_used = FALSE,
    mcmc_launched = FALSE, article_assets_modified = FALSE, stringsAsFactors = FALSE
  )
  files <- c(files, launch_readiness = app_write_csv(readiness, file.path(root, "launch_readiness.csv")))
  writeLines(c(
    "# JOINT seven-family shared-backbone VB campaign", "",
    "Each family receives an observational-only Gaussian ridge/RHS screen and four quantile VB continuations.",
    "Regime Shift is retained from the completed pilot. Article fixtures and MCMC are outside this campaign."
  ), file.path(root, "README.md"))
  files <- c(files, readme = file.path(root, "README.md"))
  app_joint_shared_write_manifest(root, files)
  list(root = root, plan = plan, readiness = readiness, expected = expected)
}

app_joint_shared_family_prepare_quantile <- function(root, scenario_id) {
  root <- normalizePath(root, mustWork = TRUE)
  plan <- app_read_csv(file.path(root, "family_plan.csv"))
  row <- plan[plan$scenario_id == scenario_id, , drop = FALSE]
  if (nrow(row) != 1L) stop("Requested family is not unique in the campaign plan.", call. = FALSE)
  if (!file.exists(file.path(row$screening_root[[1L]], "final_artifact_manifest.csv"))) {
    stop("Family Gaussian screening is not finalized.", call. = FALSE)
  }
  contract <- app_joint_shared_family_quantile_contract(
    scenario_id, row$evaluation_seed_base[[1L]], row$screening_root[[1L]])
  app_write_csv(contract, row$quantile_contract_path[[1L]])
  app_joint_shared_quantile_prepare(
    out_dir = row$quantile_root[[1L]],
    parent_dir = row$screening_root[[1L]],
    contract_path = row$quantile_contract_path[[1L]]
  )
}

app_joint_shared_family_stage_health <- function(plan_path, ids, worker_dirs, summary_name = "summary.csv") {
  if (!file.exists(plan_path)) {
    return(data.frame(expected = length(ids), completed = 0L, failed = 0L,
      remaining = length(ids), completion_fraction = 0, status = "pending", stringsAsFactors = FALSE))
  }
  completed <- file.exists(file.path(worker_dirs, "DONE")) & file.exists(file.path(worker_dirs, summary_name))
  failed <- file.exists(file.path(worker_dirs, "FAILED")) | file.exists(file.path(worker_dirs, "failure.csv"))
  data.frame(expected = length(ids), completed = sum(completed), failed = sum(failed),
    remaining = sum(!completed & !failed), completion_fraction = if (length(ids)) mean(completed) else 0,
    status = if (any(failed)) "failed" else if (all(completed)) "complete" else if (any(completed)) "running" else "pending",
    stringsAsFactors = FALSE)
}

app_joint_shared_family_health <- function(root = app_joint_shared_family_default_root()) {
  root <- normalizePath(root, mustWork = TRUE)
  plan <- app_read_csv(file.path(root, "family_plan.csv"))
  rows <- list()
  for (ii in seq_len(nrow(plan))) {
    screen <- plan$screening_root[[ii]]
    quantile <- plan$quantile_root[[ii]]
    ridge_plan <- app_read_csv(file.path(screen, "ridge_worker_plan.csv"))
    ridge_dirs <- file.path(screen, "workers", sprintf("worker_%04d", ridge_plan$worker_id))
    ridge <- app_joint_shared_family_stage_health(file.path(screen, "ridge_worker_plan.csv"),
      ridge_plan$worker_id, ridge_dirs)
    rhs_path <- file.path(screen, "rhs_worker_plan.csv")
    if (file.exists(rhs_path)) {
      rhs_plan <- app_read_csv(rhs_path)
      rhs_ids <- rhs_plan$rhs_worker_id
      rhs_dirs <- file.path(screen, "rhs_workers", sprintf("worker_%04d", rhs_ids))
    } else {
      rhs_ids <- seq_len(plan$rhs_jobs[[ii]])
      rhs_dirs <- file.path(screen, "rhs_workers", sprintf("worker_%04d", rhs_ids))
    }
    rhs <- app_joint_shared_family_stage_health(rhs_path, rhs_ids, rhs_dirs)
    quantile_path <- file.path(quantile, "worker_plan.csv")
    if (file.exists(quantile_path)) {
      quantile_plan <- app_read_csv(quantile_path)
      quantile_ids <- quantile_plan$job_id
      quantile_dirs <- file.path(quantile, "workers", sprintf("worker_%04d", quantile_ids))
    } else {
      quantile_ids <- seq_len(plan$quantile_jobs[[ii]])
      quantile_dirs <- file.path(quantile, "workers", sprintf("worker_%04d", quantile_ids))
    }
    quantile_health <- app_joint_shared_family_stage_health(quantile_path, quantile_ids, quantile_dirs)
    blocks <- list(ridge = ridge, gaussian_rhs = rhs, quantile_vb = quantile_health)
    for (stage in names(blocks)) {
      rows[[length(rows) + 1L]] <- cbind(data.frame(
        scenario_id = plan$scenario_id[[ii]], scenario_order = plan$scenario_order[[ii]], stage = stage,
        stringsAsFactors = FALSE), blocks[[stage]])
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  out[order(out$scenario_order, match(out$stage, c("ridge", "gaussian_rhs", "quantile_vb"))), , drop = FALSE]
}

app_joint_shared_family_finalize <- function(root = app_joint_shared_family_default_root()) {
  root <- normalizePath(root, mustWork = TRUE)
  plan <- app_read_csv(file.path(root, "family_plan.csv"))
  health <- app_joint_shared_family_health(root)
  if (any(health$status != "complete") || any(health$failed != 0L) ||
      sum(health$completed) != sum(health$expected)) {
    stop("Seven-family VB campaign is not complete and failure-free.", call. = FALSE)
  }
  nested <- selected <- scores <- contrasts <- list()
  for (ii in seq_len(nrow(plan))) {
    for (kind in c("screen", "quantile")) {
      child <- if (kind == "screen") plan$screening_root[[ii]] else plan$quantile_root[[ii]]
      manifest <- file.path(child, "final_artifact_manifest.csv")
      verification <- app_joint_shared_verify_manifest(child, manifest)
      nested[[length(nested) + 1L]] <- data.frame(
        scenario_id = plan$scenario_id[[ii]], artifact_kind = kind,
        manifest_path = normalizePath(manifest, mustWork = TRUE),
        manifest_sha256 = app_sha256_file(manifest), entries = nrow(verification),
        verified_entries = sum(verification$verified), all_verified = all(verification$verified),
        stringsAsFactors = FALSE)
    }
    selected[[ii]] <- app_read_csv(file.path(plan$screening_root[[ii]], "selected_shared_backbone.csv"))
    scores[[ii]] <- app_read_csv(file.path(plan$quantile_root[[ii]], "quantile_score_aggregate.csv"))
    contrasts[[ii]] <- app_read_csv(file.path(plan$quantile_root[[ii]], "joint_independent_contrast.csv"))
  }
  nested <- app_joint_qdesn_bind_rows(nested)
  if (any(!nested$all_verified)) stop("A nested family manifest failed verification.", call. = FALSE)
  selected <- app_joint_qdesn_bind_rows(selected)
  retained <- app_read_csv(file.path(root, "retained_regime_shift_backbone.csv"))
  common <- intersect(names(selected), names(retained))
  selected_all <- app_joint_qdesn_bind_rows(list(selected, retained[, common, drop = FALSE]))
  selected_all <- selected_all[order(match(selected_all$scenario_id,
    app_joint_shared_family_read_registry()$scenario_id)), , drop = FALSE]
  scores <- app_joint_qdesn_bind_rows(scores)
  contrasts <- app_joint_qdesn_bind_rows(contrasts)
  if (nrow(selected_all) != 8L || anyDuplicated(selected_all$scenario_id) ||
      nrow(scores) != 56L || any(!is.finite(scores$dgp_integrated_acrps_mean)) ||
      nrow(contrasts) != 14L || any(scores$contract_crossing_pairs != 0L)) {
    stop("Final family selections or VB score packet violates the frozen completion contract.", call. = FALSE)
  }
  models <- data.frame(
    model_id = c("joint_qdesn_rhs_mcmc", "qdesn_rhs_independent_mcmc",
      "joint_exqdesn_rhs_mcmc", "exqdesn_rhs_independent_mcmc"),
    fit_structure = c("joint", "independent", "joint", "independent"),
    likelihood_family = c("AL", "AL", "exAL", "exAL"), stringsAsFactors = FALSE)
  mcmc <- merge(selected_all[, c("scenario_id", "candidate_id", "architecture_signature",
    "design_class", "rhs_tau0"), drop = FALSE], models, by = NULL)
  registry <- app_joint_shared_family_read_registry()
  mcmc$article_seed <- registry$article_seed[match(mcmc$scenario_id, registry$scenario_id)]
  mcmc$specification_scope <- "scenario_specific_shared_within_family"
  mcmc$vb_role <- "refit_on_article_observational_window_for_mcmc_initialization"
  mcmc$article_fixture_used_for_selection <- FALSE
  mcmc$mcmc_status <- "NOT_LAUNCHED_REQUIRES_SEPARATE_FROZEN_CONFIRMATION"
  mcmc <- mcmc[order(match(mcmc$scenario_id, registry$scenario_id),
    match(mcmc$model_id, models$model_id)), , drop = FALSE]
  if (nrow(mcmc) != 32L || anyDuplicated(paste(mcmc$scenario_id, mcmc$model_id)) ||
      any(mcmc$article_fixture_used_for_selection)) {
    stop("Future MCMC handoff plan is not a complete 8-by-4 packet.", call. = FALSE)
  }
  decision <- data.frame(
    status = "VB_FAMILY_CAMPAIGN_COMPLETE_READY_TO_FREEZE_MCMC_PROTOCOL",
    completed_campaign_scenarios = 7L, retained_pilot_scenarios = 1L,
    selected_family_backbones = 8L, comparable_vb_models_per_new_scenario = 4L,
    vb_is_final_article_evidence = FALSE, mcmc_launched = FALSE,
    article_fixture_used = FALSE, article_assets_modified = FALSE,
    next_stage = "freeze_then_run_32_cell_article_fixture_mcmc_confirmation",
    stringsAsFactors = FALSE)
  files <- c(
    final_health = app_write_csv(health, file.path(root, "final_health.csv")),
    nested_manifest_verification = app_write_csv(nested, file.path(root, "nested_manifest_verification.csv")),
    selected_backbones = app_write_csv(selected_all, file.path(root, "selected_family_backbones.csv")),
    vb_score_aggregate = app_write_csv(scores, file.path(root, "seven_family_vb_score_aggregate.csv")),
    vb_contrasts = app_write_csv(contrasts, file.path(root, "seven_family_joint_independent_contrasts.csv")),
    future_mcmc_plan = app_write_csv(mcmc, file.path(root, "future_article_fixture_mcmc_plan.csv")),
    final_decision = app_write_csv(decision, file.path(root, "final_decision.csv"))
  )
  app_joint_shared_write_manifest(root, files, filename = "final_artifact_manifest.csv")
  verification <- app_joint_shared_verify_manifest(root, file.path(root, "final_artifact_manifest.csv"))
  if (!all(verification$verified)) stop("Final campaign artifact manifest failed verification.", call. = FALSE)
  app_write_csv(verification, file.path(root, "final_manifest_verification.csv"))
  list(health = health, selected = selected_all, scores = scores, contrasts = contrasts,
    mcmc_plan = mcmc, decision = decision)
}
