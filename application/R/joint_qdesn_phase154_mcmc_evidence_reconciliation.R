app_joint_qdesn_phase154_default_readiness_dir <- function() {
  app_path("application/cache/joint_qdesn_phase154_mcmc_evidence_reconciliation_readiness_20260730")
}

app_joint_qdesn_phase154_default_freeze_dir <- function() {
  app_path("application/cache/joint_qdesn_phase154_article_grade_mcmc_rerun_freeze_20260730")
}

app_joint_qdesn_phase154_default_joint_al_dir <- function() {
  app_path("application/cache/joint_qdesn_phase154_mcmc_joint_al_20260730")
}

app_joint_qdesn_phase154_default_independent_al_dir <- function() {
  app_path("application/cache/joint_qdesn_phase154_mcmc_independent_al_20260730")
}

app_joint_qdesn_phase154_default_independent_exal_dir <- function() {
  app_path("application/cache/joint_qdesn_phase154_mcmc_independent_exal_20260730")
}

app_joint_qdesn_phase154_default_final_dir <- function() {
  app_path("application/cache/joint_qdesn_phase154_balanced_mcmc_final_20260730")
}

app_joint_qdesn_phase154_default_orchestration_dir <- function() {
  app_path("application/cache/joint_qdesn_phase154_article_grade_mcmc_20260730_orchestration")
}

app_joint_qdesn_phase154_default_phase122_dir <- function() {
  app_path("application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711")
}

app_joint_qdesn_phase154_default_phase124c_dir <- function() {
  app_path("application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711")
}

app_joint_qdesn_phase154_default_phase125_dir <- function() {
  app_path("application/cache/joint_qdesn_phase125_balanced_mcmc_audit_20260712")
}

app_joint_qdesn_phase154_default_phase150_dir <- function() {
  app_path("application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727")
}

app_joint_qdesn_phase154_default_phase153_readiness_dir <- function() {
  app_joint_qdesn_phase153_default_readiness_dir()
}

app_joint_qdesn_phase154_default_phase153_results_dir <- function() {
  app_joint_qdesn_phase153_default_vb_dir()
}

app_joint_qdesn_phase154_control_fields <- function() {
  c(
    "candidate_id", "vb_max_iter", "adaptive_vb_max_iter_grid", "vb_tol",
    "rhs_vb_inner", "tau0", "zeta2", "a_sigma", "b_sigma",
    "alpha_prior_sd", "alpha_min_spacing", "gamma_init_policy",
    "review_adjustment_threshold", "max_dense_dim"
  )
}

app_joint_qdesn_phase154_model_policy <- function() {
  data.frame(
    model_id = app_joint_qdesn_phase153_model_order(),
    evidence_role = c(
      "rerun_article_grade",
      "rerun_article_grade",
      "reuse_phase150_article_grade",
      "rerun_article_grade"
    ),
    required_n_chains = c(4L, 4L, 8L, 8L),
    required_n_iter = c(4000L, 4000L, 8000L, 8000L),
    required_burn = c(1000L, 1000L, 2000L, 2000L),
    maximum_thin = c(4L, 4L, 4L, 4L),
    required_total_kept_draws = c(3000L, 3000L, 12000L, 12000L),
    rationale = c(
      "AL has no gamma block; four long chains provide final confirmation.",
      "Independent AL has no gamma block; four long chains provide final confirmation.",
      "The existing Phase150 eight-chain gamma-bearing confirmation is retained.",
      "Independent exAL retains a gamma block at each tau and requires the stronger tier."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase154_verify_source <- function(dir, source_id) {
  verification <- app_joint_qdesn_phase153_verify_manifest(dir, source_id)
  if (any(!verification$verified)) {
    stop(sprintf("Phase154 source manifest failed for '%s'.", source_id), call. = FALSE)
  }
  verification
}

app_joint_qdesn_phase154_load_mcmc_source <- function(source_id, dir) {
  dir <- normalizePath(dir, mustWork = TRUE)
  controls_path <- file.path(dir, "case_winner_controls.csv")
  summary_path <- file.path(dir, "mcmc_case_summary.csv")
  assessment_path <- file.path(dir, "mcmc_case_assessment.csv")
  required <- c(controls_path, summary_path, assessment_path)
  if (any(!file.exists(required))) {
    stop(sprintf("MCMC source '%s' is incomplete.", source_id), call. = FALSE)
  }
  controls <- app_read_csv(controls_path)
  summary <- app_read_csv(summary_path)
  assessment <- app_read_csv(assessment_path)
  fields <- app_joint_qdesn_phase154_control_fields()
  app_check_required_columns(
    controls,
    c("case_id", "scenario_ids", "model_ids", fields),
    sprintf("%s controls", source_id)
  )
  app_check_required_columns(
    summary,
    c(
      "case_id", "source_candidate_id", "source_model_id",
      "mcmc_n_chains", "mcmc_n_iter", "mcmc_burn", "mcmc_thin",
      "mcmc_n_keep_total", "all_chain_init_source_provided",
      "mcmc_draws_all_finite", "mcmc_fit_truth_mae",
      "mcmc_forecast_truth_mae", "mcmc_forecast_check_loss_mean",
      "mcmc_fit_contract_crossing_pairs",
      "mcmc_forecast_contract_crossing_pairs"
    ),
    sprintf("%s MCMC summary", source_id)
  )
  app_check_required_columns(
    assessment,
    c("case_id", "implementation_status", "gate_status"),
    sprintf("%s MCMC assessment", source_id)
  )
  rows <- lapply(seq_len(nrow(controls)), function(ii) {
    control <- controls[ii, , drop = FALSE]
    hit <- summary[
      summary$case_id == control$case_id[[1L]] &
        summary$source_candidate_id == control$candidate_id[[1L]],
      ,
      drop = FALSE
    ]
    gate <- assessment[
      assessment$case_id == control$case_id[[1L]],
      ,
      drop = FALSE
    ]
    if (nrow(hit) != 1L || nrow(gate) != 1L) return(NULL)
    data.frame(
      source_id = source_id,
      source_dir = app_prefer_repo_relative_path(dir),
      case_id = control$case_id[[1L]],
      scenario_id = control$scenario_ids[[1L]],
      model_id = control$model_ids[[1L]],
      source_candidate_id = hit$source_candidate_id[[1L]],
      source_gate_status = gate$gate_status[[1L]],
      source_implementation_status = gate$implementation_status[[1L]],
      mcmc_n_chains = as.integer(hit$mcmc_n_chains[[1L]]),
      mcmc_n_iter = as.integer(hit$mcmc_n_iter[[1L]]),
      mcmc_burn = as.integer(hit$mcmc_burn[[1L]]),
      mcmc_thin = as.integer(hit$mcmc_thin[[1L]]),
      mcmc_n_keep_total = as.integer(hit$mcmc_n_keep_total[[1L]]),
      all_chain_init_source_provided = as.logical(
        hit$all_chain_init_source_provided[[1L]]
      ),
      mcmc_draws_all_finite = as.logical(hit$mcmc_draws_all_finite[[1L]]),
      mcmc_fit_truth_mae = as.numeric(hit$mcmc_fit_truth_mae[[1L]]),
      mcmc_forecast_truth_mae = as.numeric(
        hit$mcmc_forecast_truth_mae[[1L]]
      ),
      mcmc_forecast_check_loss_mean = as.numeric(
        hit$mcmc_forecast_check_loss_mean[[1L]]
      ),
      mcmc_fit_contract_crossing_pairs = as.integer(
        hit$mcmc_fit_contract_crossing_pairs[[1L]]
      ),
      mcmc_forecast_contract_crossing_pairs = as.integer(
        hit$mcmc_forecast_contract_crossing_pairs[[1L]]
      ),
      stringsAsFactors = FALSE
    )
  })
  catalog <- app_joint_qdesn_bind_rows(rows)
  list(
    source_id = source_id,
    source_dir = dir,
    controls = controls,
    summary = summary,
    assessment = assessment,
    catalog = catalog
  )
}

app_joint_qdesn_phase154_field_equal <- function(a, b, field) {
  if (field %in% c(
    "vb_max_iter", "rhs_vb_inner", "max_dense_dim"
  )) {
    return(identical(as.integer(a), as.integer(b)))
  }
  if (field %in% c(
    "vb_tol", "tau0", "zeta2", "a_sigma", "b_sigma",
    "alpha_min_spacing", "review_adjustment_threshold"
  )) {
    return(isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = 1e-12)))
  }
  identical(trimws(as.character(a)), trimws(as.character(b)))
}

app_joint_qdesn_phase154_control_comparison <- function(target, source) {
  fields <- app_joint_qdesn_phase154_control_fields()
  matched <- vapply(fields, function(field) {
    app_joint_qdesn_phase154_field_equal(
      target[[field]][[1L]],
      source[[field]][[1L]],
      field
    )
  }, logical(1L))
  data.frame(
    control_field = fields,
    target_value = vapply(fields, function(x) {
      as.character(target[[x]][[1L]])
    }, character(1L)),
    source_value = vapply(fields, function(x) {
      as.character(source[[x]][[1L]])
    }, character(1L)),
    matched = matched,
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase154_quality_status <- function(evidence, policy) {
  implementation_reusable <- evidence$source_implementation_status[[1L]] ==
    "pass" &&
    evidence$source_gate_status[[1L]] != "fail" &&
    isTRUE(evidence$all_chain_init_source_provided[[1L]]) &&
    isTRUE(evidence$mcmc_draws_all_finite[[1L]]) &&
    is.finite(evidence$mcmc_fit_truth_mae[[1L]]) &&
    is.finite(evidence$mcmc_forecast_truth_mae[[1L]]) &&
    is.finite(evidence$mcmc_forecast_check_loss_mean[[1L]]) &&
    evidence$mcmc_fit_contract_crossing_pairs[[1L]] == 0L &&
    evidence$mcmc_forecast_contract_crossing_pairs[[1L]] == 0L
  article_grade <- implementation_reusable &&
    evidence$mcmc_n_chains[[1L]] >= policy$required_n_chains[[1L]] &&
    evidence$mcmc_n_iter[[1L]] >= policy$required_n_iter[[1L]] &&
    evidence$mcmc_burn[[1L]] >= policy$required_burn[[1L]] &&
    evidence$mcmc_thin[[1L]] <= policy$maximum_thin[[1L]] &&
    evidence$mcmc_n_keep_total[[1L]] >=
      policy$required_total_kept_draws[[1L]]
  c(
    implementation_reusable = implementation_reusable,
    article_grade = article_grade
  )
}

app_joint_qdesn_phase154_build_coverage <- function(
  targets,
  sources,
  policy = app_joint_qdesn_phase154_model_policy()
) {
  fields <- app_joint_qdesn_phase154_control_fields()
  all_catalog <- app_joint_qdesn_bind_rows(lapply(sources, `[[`, "catalog"))
  detail_rows <- list()
  coverage_rows <- vector("list", nrow(targets))
  for (ii in seq_len(nrow(targets))) {
    target <- targets[ii, , drop = FALSE]
    candidates <- all_catalog[all_catalog$case_id == target$case_id[[1L]], ,
      drop = FALSE
    ]
    exact <- list()
    for (jj in seq_len(nrow(candidates))) {
      source_obj <- sources[[candidates$source_id[[jj]]]]
      source_control <- source_obj$controls[
        source_obj$controls$case_id == target$case_id[[1L]] &
          source_obj$controls$candidate_id ==
            candidates$source_candidate_id[[jj]],
        ,
        drop = FALSE
      ]
      if (nrow(source_control) != 1L) next
      comparison <- app_joint_qdesn_phase154_control_comparison(
        target,
        source_control
      )
      comparison$case_id <- target$case_id[[1L]]
      comparison$source_id <- candidates$source_id[[jj]]
      detail_rows[[length(detail_rows) + 1L]] <- comparison[, c(
        "case_id", "source_id", "control_field", "target_value",
        "source_value", "matched"
      )]
      if (all(comparison$matched)) {
        exact[[candidates$source_id[[jj]]]] <- candidates[jj, , drop = FALSE]
      }
    }
    preferred <- if (target$model_id[[1L]] == "joint_exqdesn_rhs_vb") {
      "phase150_joint_exal"
    } else {
      c("phase122_existing", "phase124c_completion")
    }
    selected_id <- preferred[preferred %in% names(exact)][1L]
    if (!length(selected_id) || is.na(selected_id)) {
      selected_id <- names(exact)[1L]
    }
    selected <- if (length(selected_id) && !is.na(selected_id)) {
      exact[[selected_id]]
    } else {
      data.frame()
    }
    model_policy <- policy[
      policy$model_id == target$model_id[[1L]],
      ,
      drop = FALSE
    ]
    if (nrow(selected) == 1L) {
      quality <- app_joint_qdesn_phase154_quality_status(
        selected,
        model_policy
      )
      action <- if (isTRUE(quality[["article_grade"]])) {
        "reuse_article_grade"
      } else {
        "rerun_article_grade"
      }
      coverage_rows[[ii]] <- data.frame(
        case_id = target$case_id[[1L]],
        scenario_id = target$base_scenario_id[[1L]],
        model_id = target$model_id[[1L]],
        target_candidate_id = target$source_candidate_id[[1L]],
        exact_control_sources = length(exact),
        selected_source_id = selected$source_id[[1L]],
        selected_source_dir = selected$source_dir[[1L]],
        selected_source_candidate_id = selected$source_candidate_id[[1L]],
        exact_control_match = TRUE,
        source_gate_status = selected$source_gate_status[[1L]],
        implementation_reusable = quality[["implementation_reusable"]],
        article_grade = quality[["article_grade"]],
        existing_n_chains = selected$mcmc_n_chains[[1L]],
        existing_n_iter = selected$mcmc_n_iter[[1L]],
        existing_burn = selected$mcmc_burn[[1L]],
        existing_thin = selected$mcmc_thin[[1L]],
        existing_total_kept_draws = selected$mcmc_n_keep_total[[1L]],
        required_n_chains = model_policy$required_n_chains[[1L]],
        required_n_iter = model_policy$required_n_iter[[1L]],
        required_burn = model_policy$required_burn[[1L]],
        maximum_thin = model_policy$maximum_thin[[1L]],
        required_total_kept_draws =
          model_policy$required_total_kept_draws[[1L]],
        action = action,
        action_reason = if (action == "reuse_article_grade") {
          "exact controls and final-confirmation effort already verified"
        } else {
          "exact implementation evidence exists but MCMC effort is below the final-confirmation policy"
        },
        stringsAsFactors = FALSE
      )
    } else {
      coverage_rows[[ii]] <- data.frame(
        case_id = target$case_id[[1L]],
        scenario_id = target$base_scenario_id[[1L]],
        model_id = target$model_id[[1L]],
        target_candidate_id = target$source_candidate_id[[1L]],
        exact_control_sources = 0L,
        selected_source_id = NA_character_,
        selected_source_dir = NA_character_,
        selected_source_candidate_id = NA_character_,
        exact_control_match = FALSE,
        source_gate_status = NA_character_,
        implementation_reusable = FALSE,
        article_grade = FALSE,
        existing_n_chains = NA_integer_,
        existing_n_iter = NA_integer_,
        existing_burn = NA_integer_,
        existing_thin = NA_integer_,
        existing_total_kept_draws = NA_integer_,
        required_n_chains = model_policy$required_n_chains[[1L]],
        required_n_iter = model_policy$required_n_iter[[1L]],
        required_burn = model_policy$required_burn[[1L]],
        maximum_thin = model_policy$maximum_thin[[1L]],
        required_total_kept_draws =
          model_policy$required_total_kept_draws[[1L]],
        action = "rerun_missing_exact_evidence",
        action_reason = "no exact control-matched MCMC evidence exists",
        stringsAsFactors = FALSE
      )
    }
  }
  coverage <- app_joint_qdesn_bind_rows(coverage_rows)
  coverage <- coverage[order(
    match(coverage$scenario_id, app_joint_qdesn_phase153_target_scenarios()),
    match(coverage$model_id, app_joint_qdesn_phase153_model_order())
  ), , drop = FALSE]
  list(
    coverage = coverage,
    control_detail = app_joint_qdesn_bind_rows(detail_rows),
    evidence_catalog = all_catalog
  )
}

app_joint_qdesn_phase154_metric_freeze <- function(
  targets,
  phase153_results_dir
) {
  distribution <- app_read_csv(file.path(
    phase153_results_dir,
    "scenario_model_distribution_summary.csv"
  ))
  rows <- lapply(seq_len(nrow(targets)), function(ii) {
    target <- targets[ii, , drop = FALSE]
    block <- distribution[
      distribution$base_scenario_id == target$base_scenario_id[[1L]] &
        distribution$model_id == target$model_id[[1L]] &
        distribution$metric %in% c(
          "fit_truth_mae", "forecast_truth_mae",
          "forecast_check_loss_mean", "forecast_crps_grid_mean"
        ),
      ,
      drop = FALSE
    ]
    data.frame(
      case_id = target$case_id[[1L]],
      scenario_id = target$base_scenario_id[[1L]],
      model_id = target$model_id[[1L]],
      candidate_id = target$source_candidate_id[[1L]],
      phase153_replicates = if (nrow(block)) unique(block$n)[[1L]] else NA,
      phase153_median_fit_truth_mae = block$median[
        block$metric == "fit_truth_mae"
      ][[1L]],
      phase153_median_forecast_truth_mae = block$median[
        block$metric == "forecast_truth_mae"
      ][[1L]],
      phase153_median_forecast_check_loss = block$median[
        block$metric == "forecast_check_loss_mean"
      ][[1L]],
      phase153_median_forecast_crps_grid = block$median[
        block$metric == "forecast_crps_grid_mean"
      ][[1L]],
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase154_freeze_controls <- function(targets, coverage) {
  rerun <- coverage$action != "reuse_article_grade"
  selected_ids <- coverage$case_id[rerun]
  controls <- targets[targets$case_id %in% selected_ids, , drop = FALSE]
  controls$candidate_label <- paste(
    controls$base_scenario_id,
    controls$model_id,
    "Phase154 exact Phase153 control",
    sep = " | "
  )
  controls$source_shard <- "phase153_balanced_independent_replication"
  controls$phase121_selection_status <- "pass"
  controls$phase121_selection_rule <-
    "frozen_before_phase153_and_retained_after_independent_replication"
  controls$phase121_freeze_role <-
    "phase154_article_grade_mcmc_initialization"
  controls$fit_dir <- NA_character_
  controls$forecast_dir <- NA_character_
  controls$notes <- paste(
    "Phase154 reruns the exact Phase153 case-specific controls.",
    "No post-Phase153 retuning is permitted."
  )
  controls
}

app_joint_qdesn_phase154_launch_plan <- function(
  freeze_dir = app_joint_qdesn_phase154_default_freeze_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir()
) {
  rows <- data.frame(
    block_id = c("joint_al", "independent_al", "independent_exal"),
    model_id = c(
      "joint_qdesn_rhs_vb",
      "qdesn_rhs_independent_vb",
      "exqdesn_rhs_independent_vb"
    ),
    output_dir = c(
      app_joint_qdesn_phase154_default_joint_al_dir(),
      app_joint_qdesn_phase154_default_independent_al_dir(),
      app_joint_qdesn_phase154_default_independent_exal_dir()
    ),
    n_cases = 8L,
    n_chains = c(4L, 4L, 8L),
    mcmc_n_iter = c(4000L, 4000L, 8000L),
    mcmc_burn = c(1000L, 1000L, 2000L),
    mcmc_thin = 4L,
    total_kept_draws_per_case = c(3000L, 3000L, 12000L),
    n_case_workers = 8L,
    mcmc_seed_offset = c(154100L, 154200L, 154300L),
    chain_seed_stride = 1009L,
    status = "ready_to_launch",
    stringsAsFactors = FALSE
  )
  rows$command <- sprintf(
    paste(
      "Rscript application/scripts/125_run_joint_qdesn_phase122_mcmc_case_confirmation.R",
      "--output-dir %s --phase121-dir %s --fixture-dir %s",
      "--model-ids %s --n-chains %d --mcmc-n-iter %d",
      "--mcmc-burn %d --mcmc-thin %d --mcmc-seed-offset %d",
      "--chain-seed-stride %d --n-cores %d"
    ),
    rows$output_dir,
    freeze_dir,
    fixture_dir,
    rows$model_id,
    rows$n_chains,
    rows$mcmc_n_iter,
    rows$mcmc_burn,
    rows$mcmc_thin,
    rows$mcmc_seed_offset,
    rows$chain_seed_stride,
    rows$n_case_workers
  )
  rows
}

app_joint_qdesn_phase154_prepare <- function(
  out_dir = app_joint_qdesn_phase154_default_readiness_dir(),
  freeze_dir = app_joint_qdesn_phase154_default_freeze_dir(),
  phase122_dir = app_joint_qdesn_phase154_default_phase122_dir(),
  phase124c_dir = app_joint_qdesn_phase154_default_phase124c_dir(),
  phase125_dir = app_joint_qdesn_phase154_default_phase125_dir(),
  phase150_dir = app_joint_qdesn_phase154_default_phase150_dir(),
  phase153_readiness_dir =
    app_joint_qdesn_phase154_default_phase153_readiness_dir(),
  phase153_results_dir =
    app_joint_qdesn_phase154_default_phase153_results_dir(),
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  verify_source_manifests = TRUE
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  freeze_dir <- normalizePath(freeze_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  app_ensure_dir(freeze_dir)
  source_dirs <- list(
    phase122_existing = phase122_dir,
    phase124c_completion = phase124c_dir,
    phase125_balanced_audit = phase125_dir,
    phase150_joint_exal = phase150_dir,
    phase153_readiness = phase153_readiness_dir,
    phase153_results = phase153_results_dir
  )
  source_manifest <- if (isTRUE(verify_source_manifests)) {
    app_joint_qdesn_bind_rows(lapply(names(source_dirs), function(id) {
      app_joint_qdesn_phase154_verify_source(source_dirs[[id]], id)
    }))
  } else {
    data.frame(
      source_id = names(source_dirs),
      source_dir = vapply(
        source_dirs,
        app_prefer_repo_relative_path,
        character(1L)
      ),
      verified = TRUE,
      stringsAsFactors = FALSE
    )
  }
  targets <- app_read_csv(file.path(
    phase153_readiness_dir,
    "frozen_case_model_controls.csv"
  ))
  phase153_assessment <- app_read_csv(file.path(
    phase153_results_dir,
    "replication_assessment.csv"
  ))
  if (nrow(targets) != 32L || anyDuplicated(targets$case_id)) {
    stop("Phase153 target control grid is not 32 unique cells.", call. = FALSE)
  }
  sources <- list(
    phase122_existing = app_joint_qdesn_phase154_load_mcmc_source(
      "phase122_existing",
      phase122_dir
    ),
    phase124c_completion = app_joint_qdesn_phase154_load_mcmc_source(
      "phase124c_completion",
      phase124c_dir
    ),
    phase150_joint_exal = app_joint_qdesn_phase154_load_mcmc_source(
      "phase150_joint_exal",
      phase150_dir
    )
  )
  evidence <- app_joint_qdesn_phase154_build_coverage(targets, sources)
  coverage <- evidence$coverage
  controls <- app_joint_qdesn_phase154_freeze_controls(targets, coverage)
  metric_freeze <- app_joint_qdesn_phase154_metric_freeze(
    targets,
    phase153_results_dir
  )
  rerun_metric <- metric_freeze[
    metric_freeze$case_id %in% controls$case_id,
    ,
    drop = FALSE
  ]
  gate_audit <- data.frame(
    case_id = controls$case_id,
    scenario_id = controls$base_scenario_id,
    model_id = controls$model_id,
    gate_status = "pass",
    phase153_controls_frozen = TRUE,
    phase153_independent_replication_complete = TRUE,
    contract_crossings = 0L,
    retuning_after_phase153 = FALSE,
    stringsAsFactors = FALSE
  )
  launch_plan <- app_joint_qdesn_phase154_launch_plan(
    freeze_dir,
    fixture_dir
  )
  hard_fail <- any(!source_manifest$verified) ||
    phase153_assessment$gate_status[[1L]] == "fail" ||
    nrow(coverage) != 32L ||
    any(!coverage$exact_control_match) ||
    any(!coverage$implementation_reusable) ||
    sum(coverage$action == "reuse_article_grade") != 8L ||
    sum(coverage$action == "rerun_article_grade") != 24L ||
    nrow(controls) != 24L
  readiness <- data.frame(
    audit_id = "phase154_mcmc_evidence_reconciliation",
    gate_status = if (hard_fail) "fail" else "pass",
    target_cells = 32L,
    exact_control_matched_cells = sum(coverage$exact_control_match),
    implementation_reusable_cells = sum(coverage$implementation_reusable),
    article_grade_reuse_cells = sum(
      coverage$action == "reuse_article_grade"
    ),
    article_grade_rerun_cells = sum(
      coverage$action == "rerun_article_grade"
    ),
    missing_exact_evidence_cells = sum(
      coverage$action == "rerun_missing_exact_evidence"
    ),
    source_manifest_failures = sum(!source_manifest$verified),
    phase153_retuning = FALSE,
    article_assets_modified = FALSE,
    recommendation = if (hard_fail) {
      "repair_phase154_reconciliation_before_mcmc"
    } else {
      "launch_exact_24_cell_article_grade_mcmc_completion"
    },
    stringsAsFactors = FALSE
  )

  freeze_readme <- file.path(freeze_dir, "README.md")
  writeLines(c(
    "# Phase154 Article-Grade MCMC Rerun Freeze",
    "",
    "This packet contains the exact 24 Phase153 controls whose historical MCMC",
    "evidence is implementation-valid but below the final-confirmation effort.",
    "No control was retuned after observing Phase153 replication outcomes.",
    "",
    sprintf("- Frozen rerun cases: %d", nrow(controls)),
    "- Joint QDESN AL: 8",
    "- Independent QDESN AL: 8",
    "- Independent exQDESN exAL: 8",
    "- Joint exQDESN exAL: reused from Phase150, not rerun here"
  ), freeze_readme, useBytes = TRUE)
  freeze_paths <- c(
    case_winner_controls = app_joint_qvp_write_csv(
      controls,
      file.path(freeze_dir, "case_winner_controls.csv")
    ),
    case_winner_metric_summary = app_joint_qvp_write_csv(
      rerun_metric,
      file.path(freeze_dir, "case_winner_metric_summary.csv")
    ),
    case_winner_gate_audit = app_joint_qvp_write_csv(
      gate_audit,
      file.path(freeze_dir, "case_winner_gate_audit.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      app_joint_qvp_provenance_rows(),
      file.path(freeze_dir, "provenance.csv")
    ),
    readme = normalizePath(freeze_readme, mustWork = TRUE)
  )
  old_freeze_manifest <- file.path(freeze_dir, "artifact_manifest.csv")
  if (file.exists(old_freeze_manifest)) unlink(old_freeze_manifest)
  freeze_manifest <- app_joint_qdesn_write_manifest(freeze_paths, freeze_dir)

  readme_path <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint QDESN Phase154 MCMC Evidence Reconciliation",
    "",
    sprintf("- Gate: `%s`", readiness$gate_status[[1L]]),
    sprintf(
      "- Exact control-matched historical evidence: %d/32",
      readiness$exact_control_matched_cells[[1L]]
    ),
    sprintf(
      "- Reuse at final-confirmation tier: %d",
      readiness$article_grade_reuse_cells[[1L]]
    ),
    sprintf(
      "- Selective reruns required: %d",
      readiness$article_grade_rerun_cells[[1L]]
    ),
    "",
    "Coverage is not conflated with adequacy. Phase122/124c short chains remain",
    "valid implementation references but are replaced for final article evidence."
  ), readme_path, useBytes = TRUE)
  paths <- c(
    source_manifest_verification = app_joint_qvp_write_csv(
      source_manifest,
      file.path(out_dir, "source_manifest_verification.csv")
    ),
    target_case_model_controls = app_joint_qvp_write_csv(
      targets,
      file.path(out_dir, "target_case_model_controls.csv")
    ),
    historical_mcmc_evidence_catalog = app_joint_qvp_write_csv(
      evidence$evidence_catalog,
      file.path(out_dir, "historical_mcmc_evidence_catalog.csv")
    ),
    control_equivalence_detail = app_joint_qvp_write_csv(
      evidence$control_detail,
      file.path(out_dir, "control_equivalence_detail.csv")
    ),
    mcmc_coverage_matrix = app_joint_qvp_write_csv(
      coverage,
      file.path(out_dir, "mcmc_coverage_matrix.csv")
    ),
    mcmc_quality_policy = app_joint_qvp_write_csv(
      app_joint_qdesn_phase154_model_policy(),
      file.path(out_dir, "mcmc_quality_policy.csv")
    ),
    phase153_metric_freeze = app_joint_qvp_write_csv(
      metric_freeze,
      file.path(out_dir, "phase153_metric_freeze.csv")
    ),
    mcmc_reuse_plan = app_joint_qvp_write_csv(
      coverage[coverage$action == "reuse_article_grade", , drop = FALSE],
      file.path(out_dir, "mcmc_reuse_plan.csv")
    ),
    mcmc_rerun_plan = app_joint_qvp_write_csv(
      coverage[coverage$action != "reuse_article_grade", , drop = FALSE],
      file.path(out_dir, "mcmc_rerun_plan.csv")
    ),
    mcmc_launch_plan = app_joint_qvp_write_csv(
      launch_plan,
      file.path(out_dir, "mcmc_launch_plan.csv")
    ),
    readiness_assessment = app_joint_qvp_write_csv(
      readiness,
      file.path(out_dir, "readiness_assessment.csv")
    ),
    freeze_manifest_verification = app_joint_qvp_write_csv(
      app_joint_qdesn_phase154_verify_source(freeze_dir, "phase154_freeze"),
      file.path(out_dir, "freeze_manifest_verification.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      app_joint_qvp_provenance_rows(),
      file.path(out_dir, "provenance.csv")
    ),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  old_manifest <- file.path(out_dir, "artifact_manifest.csv")
  if (file.exists(old_manifest)) unlink(old_manifest)
  manifest <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir,
    freeze_dir = freeze_dir,
    readiness = readiness,
    coverage = coverage,
    launch_plan = launch_plan,
    paths = c(paths, artifact_manifest = manifest$manifest_path),
    freeze_paths = c(
      freeze_paths,
      artifact_manifest = freeze_manifest$manifest_path
    )
  )
}

app_joint_qdesn_phase154_final_sources <- function(
  joint_al_dir = app_joint_qdesn_phase154_default_joint_al_dir(),
  independent_al_dir = app_joint_qdesn_phase154_default_independent_al_dir(),
  independent_exal_dir =
    app_joint_qdesn_phase154_default_independent_exal_dir(),
  phase150_dir = app_joint_qdesn_phase154_default_phase150_dir()
) {
  list(
    phase154_joint_al = joint_al_dir,
    phase154_independent_al = independent_al_dir,
    phase154_independent_exal = independent_exal_dir,
    phase150_joint_exal = phase150_dir
  )
}

app_joint_qdesn_phase154_finalize <- function(
  out_dir = app_joint_qdesn_phase154_default_final_dir(),
  readiness_dir = app_joint_qdesn_phase154_default_readiness_dir(),
  joint_al_dir = app_joint_qdesn_phase154_default_joint_al_dir(),
  independent_al_dir = app_joint_qdesn_phase154_default_independent_al_dir(),
  independent_exal_dir =
    app_joint_qdesn_phase154_default_independent_exal_dir(),
  phase150_dir = app_joint_qdesn_phase154_default_phase150_dir()
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  coverage <- app_read_csv(file.path(readiness_dir, "mcmc_coverage_matrix.csv"))
  targets <- app_read_csv(file.path(readiness_dir, "target_case_model_controls.csv"))
  source_dirs <- app_joint_qdesn_phase154_final_sources(
    joint_al_dir,
    independent_al_dir,
    independent_exal_dir,
    phase150_dir
  )
  missing_dirs <- names(source_dirs)[!vapply(
    source_dirs,
    function(x) file.exists(file.path(x, "artifact_manifest.csv")),
    logical(1L)
  )]
  if (length(missing_dirs)) {
    stop(sprintf(
      "Phase154 finalization is waiting for: %s",
      paste(missing_dirs, collapse = ", ")
    ), call. = FALSE)
  }
  manifest_verification <- app_joint_qdesn_bind_rows(lapply(
    names(source_dirs),
    function(id) app_joint_qdesn_phase154_verify_source(source_dirs[[id]], id)
  ))
  source_objects <- lapply(names(source_dirs), function(id) {
    app_joint_qdesn_phase154_load_mcmc_source(id, source_dirs[[id]])
  })
  names(source_objects) <- names(source_dirs)
  summaries <- app_joint_qdesn_bind_rows(lapply(names(source_objects), function(id) {
    x <- source_objects[[id]]$summary
    x$source_block_id <- id
    x$source_dir <- app_prefer_repo_relative_path(source_dirs[[id]])
    x
  }))
  assessments <- app_joint_qdesn_bind_rows(lapply(names(source_objects), function(id) {
    x <- source_objects[[id]]$assessment
    x$source_block_id <- id
    x$source_dir <- app_prefer_repo_relative_path(source_dirs[[id]])
    x
  }))
  controls <- app_joint_qdesn_bind_rows(lapply(names(source_objects), function(id) {
    x <- source_objects[[id]]$controls
    x$source_block_id <- id
    x
  }))
  summaries <- summaries[summaries$case_id %in% targets$case_id, , drop = FALSE]
  assessments <- assessments[
    assessments$case_id %in% targets$case_id,
    ,
    drop = FALSE
  ]
  controls <- controls[controls$case_id %in% targets$case_id, , drop = FALSE]
  duplicate_cases <- duplicated(summaries$case_id) |
    duplicated(summaries$case_id, fromLast = TRUE)
  if (any(duplicate_cases)) {
    stop("Phase154 final MCMC sources contain duplicated target cases.", call. = FALSE)
  }
  policy <- app_joint_qdesn_phase154_model_policy()
  case_rows <- lapply(seq_len(nrow(targets)), function(ii) {
    target <- targets[ii, , drop = FALSE]
    summary <- summaries[summaries$case_id == target$case_id[[1L]], ,
      drop = FALSE
    ]
    assessment <- assessments[
      assessments$case_id == target$case_id[[1L]],
      ,
      drop = FALSE
    ]
    control <- controls[controls$case_id == target$case_id[[1L]], ,
      drop = FALSE
    ]
    if (nrow(summary) != 1L || nrow(assessment) != 1L || nrow(control) != 1L) {
      return(data.frame(
        case_id = target$case_id[[1L]],
        scenario_id = target$base_scenario_id[[1L]],
        source_model_id = target$model_id[[1L]],
        final_status = "fail",
        status_reason = "missing or duplicated final MCMC evidence",
        stringsAsFactors = FALSE
      ))
    }
    comparison <- app_joint_qdesn_phase154_control_comparison(target, control)
    exact <- all(comparison$matched)
    model_policy <- policy[policy$model_id == target$model_id[[1L]], ,
      drop = FALSE
    ]
    evidence <- data.frame(
      source_implementation_status = assessment$implementation_status[[1L]],
      source_gate_status = assessment$gate_status[[1L]],
      all_chain_init_source_provided =
        summary$all_chain_init_source_provided[[1L]],
      mcmc_draws_all_finite = summary$mcmc_draws_all_finite[[1L]],
      mcmc_fit_truth_mae = summary$mcmc_fit_truth_mae[[1L]],
      mcmc_forecast_truth_mae = summary$mcmc_forecast_truth_mae[[1L]],
      mcmc_forecast_check_loss_mean =
        summary$mcmc_forecast_check_loss_mean[[1L]],
      mcmc_fit_contract_crossing_pairs =
        summary$mcmc_fit_contract_crossing_pairs[[1L]],
      mcmc_forecast_contract_crossing_pairs =
        summary$mcmc_forecast_contract_crossing_pairs[[1L]],
      mcmc_n_chains = summary$mcmc_n_chains[[1L]],
      mcmc_n_iter = summary$mcmc_n_iter[[1L]],
      mcmc_burn = summary$mcmc_burn[[1L]],
      mcmc_thin = summary$mcmc_thin[[1L]],
      mcmc_n_keep_total = summary$mcmc_n_keep_total[[1L]]
    )
    quality <- app_joint_qdesn_phase154_quality_status(evidence, model_policy)
    data.frame(
      case_id = target$case_id[[1L]],
      scenario_id = target$base_scenario_id[[1L]],
      source_model_id = target$model_id[[1L]],
      mcmc_model_id = summary$model_id[[1L]],
      source_block_id = summary$source_block_id[[1L]],
      target_candidate_id = target$source_candidate_id[[1L]],
      source_candidate_id = summary$source_candidate_id[[1L]],
      exact_control_match = exact,
      mcmc_n_chains = as.integer(summary$mcmc_n_chains[[1L]]),
      mcmc_n_iter = as.integer(summary$mcmc_n_iter[[1L]]),
      mcmc_burn = as.integer(summary$mcmc_burn[[1L]]),
      mcmc_thin = as.integer(summary$mcmc_thin[[1L]]),
      mcmc_n_keep_total = as.integer(summary$mcmc_n_keep_total[[1L]]),
      implementation_reusable = quality[["implementation_reusable"]],
      article_grade = quality[["article_grade"]],
      gate_status = assessment$gate_status[[1L]],
      mcmc_fit_truth_mae = as.numeric(summary$mcmc_fit_truth_mae[[1L]]),
      mcmc_forecast_truth_mae =
        as.numeric(summary$mcmc_forecast_truth_mae[[1L]]),
      mcmc_forecast_check_loss_mean =
        as.numeric(summary$mcmc_forecast_check_loss_mean[[1L]]),
      mcmc_fit_raw_crossing_pairs =
        as.integer(summary$mcmc_fit_raw_crossing_pairs[[1L]]),
      mcmc_forecast_raw_crossing_pairs =
        as.integer(summary$mcmc_forecast_raw_crossing_pairs[[1L]]),
      mcmc_fit_contract_crossing_pairs =
        as.integer(summary$mcmc_fit_contract_crossing_pairs[[1L]]),
      mcmc_forecast_contract_crossing_pairs =
        as.integer(summary$mcmc_forecast_contract_crossing_pairs[[1L]]),
      final_status = if (
        exact &&
          isTRUE(quality[["implementation_reusable"]]) &&
          isTRUE(quality[["article_grade"]])
      ) {
        if (assessment$gate_status[[1L]] == "pass") "pass" else "review"
      } else {
        "fail"
      },
      status_reason = if (!exact) {
        "final controls differ from Phase153 freeze"
      } else if (!isTRUE(quality[["implementation_reusable"]])) {
        "final implementation gates failed"
      } else if (!isTRUE(quality[["article_grade"]])) {
        "final MCMC effort is below the Phase154 policy"
      } else {
        assessment$status_reason[[1L]]
      },
      stringsAsFactors = FALSE
    )
  })
  case_audit <- app_joint_qdesn_bind_rows(case_rows)
  groups <- split(
    case_audit,
    interaction(case_audit$source_model_id, drop = TRUE)
  )
  model_summary <- app_joint_qdesn_bind_rows(lapply(groups, function(block) {
    data.frame(
      source_model_id = block$source_model_id[[1L]],
      n_cases = nrow(block),
      n_pass = sum(block$final_status == "pass"),
      n_review = sum(block$final_status == "review"),
      n_fail = sum(block$final_status == "fail"),
      median_mcmc_fit_truth_mae = stats::median(
        block$mcmc_fit_truth_mae,
        na.rm = TRUE
      ),
      median_mcmc_forecast_truth_mae = stats::median(
        block$mcmc_forecast_truth_mae,
        na.rm = TRUE
      ),
      median_mcmc_forecast_check_loss = stats::median(
        block$mcmc_forecast_check_loss_mean,
        na.rm = TRUE
      ),
      total_raw_crossing_pairs = sum(
        block$mcmc_fit_raw_crossing_pairs +
          block$mcmc_forecast_raw_crossing_pairs,
        na.rm = TRUE
      ),
      total_contract_crossing_pairs = sum(
        block$mcmc_fit_contract_crossing_pairs +
          block$mcmc_forecast_contract_crossing_pairs,
        na.rm = TRUE
      ),
      stringsAsFactors = FALSE
    )
  }))
  hard_fail <- any(!manifest_verification$verified) ||
    nrow(case_audit) != 32L ||
    any(case_audit$final_status == "fail") ||
    any(!case_audit$exact_control_match) ||
    any(!case_audit$article_grade) ||
    any(case_audit$mcmc_fit_contract_crossing_pairs > 0L) ||
    any(case_audit$mcmc_forecast_contract_crossing_pairs > 0L)
  review <- !hard_fail && (
    any(case_audit$final_status == "review") ||
      any(
        case_audit$mcmc_fit_raw_crossing_pairs +
          case_audit$mcmc_forecast_raw_crossing_pairs > 0L
      )
  )
  assessment <- data.frame(
    audit_id = "phase154_balanced_article_grade_mcmc",
    gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
    expected_cells = 32L,
    completed_cells = nrow(case_audit),
    exact_control_cells = sum(case_audit$exact_control_match),
    article_grade_cells = sum(case_audit$article_grade),
    pass_cells = sum(case_audit$final_status == "pass"),
    review_cells = sum(case_audit$final_status == "review"),
    fail_cells = sum(case_audit$final_status == "fail"),
    contract_crossing_pairs = sum(
      case_audit$mcmc_fit_contract_crossing_pairs +
        case_audit$mcmc_forecast_contract_crossing_pairs,
      na.rm = TRUE
    ),
    article_assets_modified = FALSE,
    recommendation = if (hard_fail) {
      "repair_phase154_before_article_assets"
    } else {
      "build_article_assets_from_phase154_final_evidence"
    },
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Phase154 Balanced Article-Grade MCMC Evidence",
    "",
    sprintf("- Gate: `%s`", assessment$gate_status[[1L]]),
    sprintf(
      "- Final-confirmation cells: %d/32",
      assessment$article_grade_cells[[1L]]
    ),
    sprintf(
      "- Contract crossings: %d",
      assessment$contract_crossing_pairs[[1L]]
    ),
    "",
    "This packet combines exact Phase154 reruns with the exact-control Phase150",
    "Joint exQDESN confirmation. It does not modify article assets."
  ), readme_path, useBytes = TRUE)
  paths <- c(
    source_manifest_verification = app_joint_qvp_write_csv(
      manifest_verification,
      file.path(out_dir, "source_manifest_verification.csv")
    ),
    final_mcmc_case_summary = app_joint_qvp_write_csv(
      summaries,
      file.path(out_dir, "final_mcmc_case_summary.csv")
    ),
    final_mcmc_case_assessment = app_joint_qvp_write_csv(
      assessments,
      file.path(out_dir, "final_mcmc_case_assessment.csv")
    ),
    final_case_audit = app_joint_qvp_write_csv(
      case_audit,
      file.path(out_dir, "final_case_audit.csv")
    ),
    final_model_summary = app_joint_qvp_write_csv(
      model_summary,
      file.path(out_dir, "final_model_summary.csv")
    ),
    final_assessment = app_joint_qvp_write_csv(
      assessment,
      file.path(out_dir, "final_assessment.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      app_joint_qvp_provenance_rows(),
      file.path(out_dir, "provenance.csv")
    ),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  old_manifest <- file.path(out_dir, "artifact_manifest.csv")
  if (file.exists(old_manifest)) unlink(old_manifest)
  manifest <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir,
    assessment = assessment,
    case_audit = case_audit,
    model_summary = model_summary,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_qdesn_phase154_health <- function(
  orchestration_dir = app_joint_qdesn_phase154_default_orchestration_dir(),
  final_dir = app_joint_qdesn_phase154_default_final_dir(),
  session_names = NULL
) {
  blocks <- c("joint_al", "independent_al", "independent_exal")
  exit_paths <- file.path(orchestration_dir, paste0(blocks, ".exit"))
  exit_values <- vapply(exit_paths, function(path) {
    if (!file.exists(path)) return(NA_integer_)
    suppressWarnings(as.integer(readLines(path, warn = FALSE)[[1L]]))
  }, integer(1L))
  if (is.null(session_names)) {
    session_names <- paste0("joint_qdesn_phase154_", blocks, "_20260730")
  }
  session_names <- as.character(session_names)
  if (length(session_names) != length(blocks) ||
      anyNA(session_names) ||
      any(!nzchar(session_names)) ||
      anyDuplicated(session_names)) {
    stop("session_names must contain one unique, nonempty name per Phase154 block.", call. = FALSE)
  }
  active <- vapply(session_names, function(name) {
    identical(
      suppressWarnings(system2(
        "tmux",
        c("has-session", "-t", name),
        stdout = FALSE,
        stderr = FALSE
      )),
      0L
    )
  }, logical(1L))
  final_complete <- file.exists(file.path(final_dir, "artifact_manifest.csv")) &&
    file.exists(file.path(final_dir, "final_assessment.csv"))
  rows <- data.frame(
    block_id = blocks,
    session_name = session_names,
    session_active = active,
    exit_code = exit_values,
    block_status = ifelse(
      active,
      "running",
      ifelse(
        is.na(exit_values),
        "not_started",
        ifelse(exit_values == 0L, "complete", "failed")
      )
    ),
    stringsAsFactors = FALSE
  )
  lifecycle <- if (final_complete) {
    "complete"
  } else if (any(active)) {
    "running"
  } else if (any(exit_values != 0L, na.rm = TRUE)) {
    "failed"
  } else if (all(exit_values == 0L, na.rm = TRUE) &&
      all(!is.na(exit_values))) {
    "completed_pending_final_audit"
  } else {
    "prepared_not_running"
  }
  summary <- data.frame(
    phase_id = "phase154_article_grade_mcmc",
    lifecycle_state = lifecycle,
    blocks_expected = 3L,
    blocks_complete = sum(rows$block_status == "complete"),
    blocks_running = sum(rows$block_status == "running"),
    blocks_failed = sum(rows$block_status == "failed"),
    cases_expected = 24L,
    cases_covered_by_complete_blocks =
      8L * sum(rows$block_status == "complete"),
    cases_remaining = 24L - 8L * sum(rows$block_status == "complete"),
    final_audit_complete = final_complete,
    recommendation = switch(
      lifecycle,
      complete = "audit_phase154_before_article_integration",
      running = "preserve_healthy_phase154_computation",
      failed = "diagnose_failed_phase154_block",
      completed_pending_final_audit = "run_phase154_finalizer",
      "launch_phase154_blocks"
    ),
    stringsAsFactors = FALSE
  )
  app_ensure_dir(orchestration_dir)
  app_joint_qvp_write_csv(
    rows,
    file.path(orchestration_dir, "block_health.csv")
  )
  app_joint_qvp_write_csv(
    summary,
    file.path(orchestration_dir, "phase154_health_summary.csv")
  )
  list(summary = summary, blocks = rows)
}
