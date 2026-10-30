# Phase 116 article-readiness audit for the joint QDESN validation study.

app_joint_qdesn_default_phase116_article_readiness_dir <- function() {
  app_path("application/cache/joint_qdesn_phase116_article_readiness_audit_20260709")
}

app_joint_qdesn_phase116_write_csv <- function(x, path) {
  app_ensure_dir(dirname(path))
  utils::write.csv(x, path, row.names = FALSE, na = "")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

app_joint_qdesn_phase116_verify_asset_manifest <- function(manifest_path, artifact_label = "article_asset_manifest") {
  if (!file.exists(manifest_path)) {
    return(data.frame(
      artifact_label = artifact_label,
      label = "article_asset_manifest",
      path = normalizePath(manifest_path, mustWork = FALSE),
      exists = FALSE,
      declared_size_bytes = NA_real_,
      actual_size_bytes = NA_real_,
      declared_sha256 = NA_character_,
      actual_sha256 = NA_character_,
      status = "fail",
      stringsAsFactors = FALSE
    ))
  }
  manifest <- app_read_csv(manifest_path)
  app_check_required_columns(manifest, c("label", "path", "size_bytes", "sha256"), artifact_label)
  app_bind_rows_fill(lapply(seq_len(nrow(manifest)), function(ii) {
    path <- manifest$path[[ii]]
    abs_path <- if (grepl("^/", path)) path else app_path(path)
    exists <- file.exists(abs_path)
    actual_sha <- if (exists) app_sha256_file(abs_path) else NA_character_
    actual_size <- if (exists) as.numeric(file.info(abs_path)$size) else NA_real_
    data.frame(
      artifact_label = artifact_label,
      label = manifest$label[[ii]],
      relative_path = path,
      path = normalizePath(abs_path, winslash = "/", mustWork = FALSE),
      exists = exists,
      declared_size_bytes = as.numeric(manifest$size_bytes[[ii]]),
      actual_size_bytes = actual_size,
      declared_sha256 = manifest$sha256[[ii]],
      actual_sha256 = actual_sha,
      status = if (exists &&
        identical(tolower(actual_sha), tolower(manifest$sha256[[ii]])) &&
        identical(as.numeric(actual_size), as.numeric(manifest$size_bytes[[ii]]))) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_phase116_manifest_gate <- function(x) {
  if (!nrow(x) || !"status" %in% names(x)) return("fail")
  if (any(x$status == "fail")) return("fail")
  "pass"
}

app_joint_qdesn_phase116_gate <- function(status) {
  status <- as.character(status)
  if (any(status == "fail")) return("fail")
  if (any(status == "review")) return("review")
  "pass"
}

app_joint_qdesn_phase116_selected_row <- function(x) {
  app_check_required_columns(x, c("candidate_id"), "selected recommendation")
  if ("selected" %in% names(x)) {
    keep <- app_as_bool_vec(x$selected)
    if (any(keep)) return(x[which(keep)[[1L]], , drop = FALSE])
  }
  x[1L, , drop = FALSE]
}

app_joint_qdesn_phase116_load_sources <- function(
  phase113_dir = app_joint_qdesn_default_phase113_vb_screening_dir(),
  phase114_freeze_dir = app_joint_qdesn_default_phase114_vb_freeze_dir(),
  phase114_mcmc_dir = app_joint_qdesn_default_phase114_mcmc_article_dir(),
  phase115_dir = app_joint_qdesn_default_phase115_article_assets_dir()
) {
  phase113_dir <- normalizePath(phase113_dir, winslash = "/", mustWork = TRUE)
  phase114_freeze_dir <- normalizePath(phase114_freeze_dir, winslash = "/", mustWork = TRUE)
  phase114_mcmc_dir <- normalizePath(phase114_mcmc_dir, winslash = "/", mustWork = TRUE)
  phase115_dir <- normalizePath(phase115_dir, winslash = "/", mustWork = TRUE)

  selected <- app_joint_qdesn_phase116_selected_row(app_read_csv(file.path(phase113_dir, "selected_spec_recommendation.csv")))
  selected_id <- selected$candidate_id[[1L]]
  health <- app_read_csv(file.path(phase113_dir, "screening_health_summary.csv"))
  health <- health[health$candidate_id == selected_id, , drop = FALSE]
  if (!nrow(health)) stop("Phase 113 health table has no row for the selected candidate.", call. = FALSE)

  list(
    dirs = data.frame(
      source = c("phase113_vb", "phase114_freeze", "phase114_mcmc", "phase115_assets"),
      path = c(phase113_dir, phase114_freeze_dir, phase114_mcmc_dir, phase115_dir),
      stringsAsFactors = FALSE
    ),
    phase113 = list(
      selected = selected,
      health = health,
      scorecard = app_read_csv(file.path(phase113_dir, "candidate_scorecard.csv")),
      forecast_model = app_read_csv(file.path(phase113_dir, "forecast_model_metric_summary.csv")),
      forecast_scenario = app_read_csv(file.path(phase113_dir, "forecast_scenario_metric_summary.csv")),
      forecast_tau = app_read_csv(file.path(phase113_dir, "forecast_tau_metric_summary.csv")),
      top_manifest = app_joint_qdesn_phase108_manifest_verify(phase113_dir, "phase113_vb_top"),
      candidate_manifest = app_read_csv(file.path(phase113_dir, "candidate_manifest_verification.csv"))
    ),
    phase114_freeze = list(
      decision = app_read_csv(file.path(phase114_freeze_dir, "freeze_decision_summary.csv")),
      gate = app_read_csv(file.path(phase114_freeze_dir, "freeze_gate_audit.csv")),
      launch_plan = app_read_csv(file.path(phase114_freeze_dir, "phase114_launch_plan.csv")),
      manifest = app_joint_qdesn_phase108_manifest_verify(phase114_freeze_dir, "phase114_freeze")
    ),
    phase114_mcmc = list(
      assessment = app_read_csv(file.path(phase114_mcmc_dir, "mcmc_readiness_assessment.csv")),
      summary = app_read_csv(file.path(phase114_mcmc_dir, "mcmc_readiness_summary.csv")),
      vb_mcmc_distance = app_read_csv(file.path(phase114_mcmc_dir, "vb_mcmc_distance_summary.csv")),
      chain_distance = app_read_csv(file.path(phase114_mcmc_dir, "chain_to_pooled_distance_summary.csv")),
      worker_failures = app_read_csv(file.path(phase114_mcmc_dir, "scenario_worker_failures.csv")),
      manifest = app_joint_qdesn_phase108_manifest_verify(phase114_mcmc_dir, "phase114_mcmc")
    ),
    phase115 = list(
      readiness = app_read_csv(file.path(phase115_dir, "article_readiness_assessment.csv")),
      gate = app_read_csv(file.path(phase115_dir, "gate_summary.csv")),
      source_manifest = app_read_csv(file.path(phase115_dir, "source_manifest_verification.csv")),
      artifact_manifest = app_joint_qdesn_phase108_manifest_verify(phase115_dir, "phase115_cache"),
      article_asset_manifest = app_joint_qdesn_phase116_verify_asset_manifest(file.path(phase115_dir, "article_asset_manifest.csv"), "phase115_article_assets")
    )
  )
}

app_joint_qdesn_phase116_source_manifest_summary <- function(src) {
  rows <- list(
    data.frame(
      source = "phase113_top_manifest",
      rows = nrow(src$phase113$top_manifest),
      gate = app_joint_qdesn_phase116_manifest_gate(src$phase113$top_manifest),
      detail = sprintf("%d top-level Phase 113 manifest rows checked", nrow(src$phase113$top_manifest)),
      stringsAsFactors = FALSE
    ),
    data.frame(
      source = "phase113_candidate_manifest",
      rows = nrow(src$phase113$candidate_manifest),
      gate = ifelse(nrow(src$phase113$candidate_manifest) && all(src$phase113$candidate_manifest$status == "pass"), "pass", "fail"),
      detail = sprintf("%d nested Phase 113 candidate manifest rows checked", nrow(src$phase113$candidate_manifest)),
      stringsAsFactors = FALSE
    ),
    data.frame(
      source = "phase114_freeze_manifest",
      rows = nrow(src$phase114_freeze$manifest),
      gate = app_joint_qdesn_phase116_manifest_gate(src$phase114_freeze$manifest),
      detail = sprintf("%d Phase 114 freeze manifest rows checked", nrow(src$phase114_freeze$manifest)),
      stringsAsFactors = FALSE
    ),
    data.frame(
      source = "phase114_mcmc_manifest",
      rows = nrow(src$phase114_mcmc$manifest),
      gate = app_joint_qdesn_phase116_manifest_gate(src$phase114_mcmc$manifest),
      detail = sprintf("%d Phase 114 MCMC manifest rows checked", nrow(src$phase114_mcmc$manifest)),
      stringsAsFactors = FALSE
    ),
    data.frame(
      source = "phase115_cache_manifest",
      rows = nrow(src$phase115$artifact_manifest),
      gate = app_joint_qdesn_phase116_manifest_gate(src$phase115$artifact_manifest),
      detail = sprintf("%d Phase 115 cache manifest rows checked", nrow(src$phase115$artifact_manifest)),
      stringsAsFactors = FALSE
    ),
    data.frame(
      source = "phase115_source_manifest",
      rows = nrow(src$phase115$source_manifest),
      gate = ifelse(nrow(src$phase115$source_manifest) && all(src$phase115$source_manifest$status == "pass"), "pass", "fail"),
      detail = sprintf("%d Phase 115 source rows checked", nrow(src$phase115$source_manifest)),
      stringsAsFactors = FALSE
    ),
    data.frame(
      source = "phase115_article_asset_manifest",
      rows = nrow(src$phase115$article_asset_manifest),
      gate = app_joint_qdesn_phase116_manifest_gate(src$phase115$article_asset_manifest),
      detail = sprintf("%d article table/figure asset rows checked", nrow(src$phase115$article_asset_manifest)),
      stringsAsFactors = FALSE
    )
  )
  app_bind_rows_fill(rows)
}

app_joint_qdesn_phase116_health_summary <- function(src, manifest_summary) {
  selected <- src$phase113$selected
  health <- src$phase113$health
  mcmc_assessment <- src$phase114_mcmc$assessment
  mcmc_summary <- src$phase114_mcmc$summary
  phase115 <- src$phase115$readiness
  data.frame(
    component = c(
      "Phase 113 selected VB screen",
      "Phase 114 VB freeze",
      "Phase 114 MCMC reference",
      "Phase 115 article assets",
      "Manifest/hash verification",
      "Joint-lane background dependency"
    ),
    status = c(
      as.character(selected$gate_status[[1L]]),
      as.character(src$phase114_freeze$decision$freeze_status[[1L]]),
      app_joint_qdesn_phase116_gate(mcmc_assessment$gate_status),
      as.character(phase115$overall_gate[[1L]]),
      app_joint_qdesn_phase116_gate(manifest_summary$gate),
      "none_required"
    ),
    evidence = c(
      sprintf(
        "Selected %s; mean forecast MAE %.3f; raw/contract forecast crossings %d/%d",
        selected$candidate_id[[1L]],
        as.numeric(selected$mean_forecast_truth_mae[[1L]]),
        as.integer(selected$forecast_raw_crossings[[1L]]),
        as.integer(health$contract_crossings[[1L]])
      ),
      sprintf(
        "Freeze decision %s; %d gate rows",
        src$phase114_freeze$decision$decision[[1L]],
        nrow(src$phase114_freeze$gate)
      ),
      sprintf(
        "%d scenario rows pass; worker failures %d; MCMC raw/contract crossings %d/%d",
        sum(mcmc_assessment$gate_status == "pass"),
        nrow(src$phase114_mcmc$worker_failures),
        sum(mcmc_summary$mcmc_raw_crossing_pairs, na.rm = TRUE),
        sum(mcmc_summary$mcmc_contract_crossing_pairs, na.rm = TRUE)
      ),
      sprintf(
        "Overall gate %s; MCMC reference gate %s",
        phase115$overall_gate[[1L]],
        phase115$mcmc_reference_gate[[1L]]
      ),
      sprintf("%d manifest groups checked; %d fail groups", nrow(manifest_summary), sum(manifest_summary$gate == "fail")),
      "No new joint QDESN compute is needed before manuscript QA; unrelated GloFAS/PriceFM sessions are not dependencies."
    ),
    immediate_action = c(
      "Use as frozen VB forecast source with review language for pre-rearrangement crossings.",
      "Retain as reproducibility anchor; do not rename or mutate Phase 113/114 artifacts.",
      "Use as fit-window posterior reference only, not as held-out forecast evidence.",
      "Use generated tables/figures as the current article evidence pack.",
      "Hard-fail only if any manifest/hash row fails.",
      "Do not wait for unrelated workstreams."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase116_phase_status <- function(src, manifest_summary) {
  selected <- src$phase113$selected
  mcmc_summary <- src$phase114_mcmc$summary
  data.frame(
    phase = c("113", "114-freeze", "114-mcmc", "115-assets", "116-audit"),
    role = c(
      "VB specification screening and selected candidate",
      "Freeze selected VB candidate and record MCMC launch contract",
      "VB-initialized MCMC fit-window reference",
      "Article table/figure asset build",
      "Decision audit and next-step plan"
    ),
    gate = c(
      as.character(selected$gate_status[[1L]]),
      as.character(src$phase114_freeze$decision$freeze_status[[1L]]),
      app_joint_qdesn_phase116_gate(src$phase114_mcmc$assessment$gate_status),
      as.character(src$phase115$readiness$overall_gate[[1L]]),
      ifelse(any(manifest_summary$gate == "fail"), "fail", "review")
    ),
    primary_evidence = c(
      sprintf("selected candidate %s, rank %s", selected$candidate_id[[1L]], selected$rank[[1L]]),
      sprintf("decision %s", src$phase114_freeze$decision$decision[[1L]]),
      sprintf("%d scenarios, %d kept posterior draws per scenario", nrow(mcmc_summary), unique(mcmc_summary$mcmc_n_keep_total)[[1L]]),
      sprintf("%d asset manifest rows", nrow(src$phase115$article_asset_manifest)),
      "binds completed evidence into an inspectable readiness record"
    ),
    completion_state = c("complete", "complete", "complete", "complete", "current_stage"),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase116_scenario_sensitivity <- function(src) {
  selected_id <- src$phase113$selected$candidate_id[[1L]]
  x <- src$phase113$forecast_scenario
  x <- x[x$candidate_id == selected_id, , drop = FALSE]
  model_ids <- c("joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb", "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb")
  rows <- lapply(sort(unique(x$scenario_id)), function(sid) {
    block <- x[x$scenario_id == sid & x$model_id %in% model_ids, , drop = FALSE]
    block <- block[order(block$truth_mae, block$check_loss_mean), , drop = FALSE]
    val <- function(model_id, col) {
      row <- block[block$model_id == model_id, , drop = FALSE]
      if (!nrow(row)) return(NA_real_)
      as.numeric(row[[col]][[1L]])
    }
    primary_rank <- match("joint_qdesn_rhs_vb", block$model_id)
    data.frame(
      scenario_id = sid,
      winner_model_id = block$model_id[[1L]],
      winner_label = block$display_label[[1L]],
      primary_joint_qdesn_rank = as.integer(primary_rank %||% NA_integer_),
      joint_qdesn_truth_mae = val("joint_qdesn_rhs_vb", "truth_mae"),
      independent_qdesn_truth_mae = val("qdesn_rhs_independent_vb", "truth_mae"),
      joint_exqdesn_truth_mae = val("joint_exqdesn_rhs_vb", "truth_mae"),
      independent_exqdesn_truth_mae = val("exqdesn_rhs_independent_vb", "truth_mae"),
      joint_qdesn_raw_crossings = val("joint_qdesn_rhs_vb", "raw_crossing_pairs"),
      joint_qdesn_reached_max_iter = val("joint_qdesn_rhs_vb", "reached_max_iter"),
      interpretation = if (!is.na(primary_rank) && primary_rank == 1L) {
        "primary joint QDESN is best by forecast MAE for this scenario"
      } else {
        "primary joint QDESN is competitive but not the lowest forecast-MAE row; describe as robust rather than uniformly dominant"
      },
      stringsAsFactors = FALSE
    )
  })
  out <- app_bind_rows_fill(rows)
  out[order(out$primary_joint_qdesn_rank, out$scenario_id), , drop = FALSE]
}

app_joint_qdesn_phase116_tau_sensitivity <- function(src) {
  selected_id <- src$phase113$selected$candidate_id[[1L]]
  x <- src$phase113$forecast_tau
  x <- x[x$candidate_id == selected_id, , drop = FALSE]
  rows <- lapply(sort(unique(as.numeric(x$tau))), function(tt) {
    block <- x[abs(as.numeric(x$tau) - tt) < 1.0e-12, , drop = FALSE]
    val <- function(model_id) {
      row <- block[block$model_id == model_id, , drop = FALSE]
      if (!nrow(row)) return(NA_real_)
      as.numeric(row$truth_mae[[1L]])
    }
    jq <- val("joint_qdesn_rhs_vb")
    jx <- val("joint_exqdesn_rhs_vb")
    iq <- val("qdesn_rhs_independent_vb")
    ix <- val("exqdesn_rhs_independent_vb")
    data.frame(
      tau = tt,
      region = ifelse(tt <= 0.10, "lower_tail", ifelse(tt >= 0.90, "upper_tail", "center")),
      joint_qdesn_truth_mae = jq,
      independent_qdesn_truth_mae = iq,
      joint_exqdesn_truth_mae = jx,
      independent_exqdesn_truth_mae = ix,
      joint_exqdesn_minus_joint_qdesn = jx - jq,
      independent_exqdesn_minus_independent_qdesn = ix - iq,
      interpretation = if (is.finite(jx - jq) && jx - jq > 0.04) {
        "exQDESN remains materially worse than QDESN at this quantile; do not claim exAL dominance"
      } else {
        "no material exAL disadvantage at this quantile"
      },
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_joint_qdesn_phase116_vb_mcmc_distance_focus <- function(src) {
  x <- src$phase114_mcmc$summary
  x$mcmc_minus_vb_truth_mae <- x$mcmc_truth_mae - x$vb_truth_mae
  x$distance_gate <- ifelse(
    x$vb_mcmc_max_normalized_distance > 0.25 | x$max_chain_to_pooled_normalized_distance > 0.25,
    "review",
    "pass"
  )
  x$interpretation <- ifelse(
    x$distance_gate == "pass",
    "MCMC reference is close enough for implementation-level posterior agreement.",
    "Distance is still finite but large enough to avoid stronger posterior promotion language."
  )
  keep <- c(
    "scenario_id", "distribution_family", "dynamics_class", "vb_truth_mae",
    "mcmc_truth_mae", "mcmc_minus_vb_truth_mae", "vb_mcmc_max_normalized_distance",
    "max_chain_to_pooled_normalized_distance", "mcmc_n_keep_total",
    "mcmc_raw_crossing_pairs", "mcmc_contract_crossing_pairs", "total_elapsed_seconds",
    "distance_gate", "interpretation"
  )
  x[order(-x$vb_mcmc_max_normalized_distance), intersect(keep, names(x)), drop = FALSE]
}

app_joint_qdesn_phase116_claim_audit <- function(src, scenario_sensitivity, tau_sensitivity) {
  selected <- src$phase113$selected
  health <- src$phase113$health
  phase115 <- src$phase115$readiness
  mcmc_assessment <- src$phase114_mcmc$assessment
  joint_wins <- sum(scenario_sensitivity$winner_model_id == "joint_qdesn_rhs_vb", na.rm = TRUE)
  n_scenarios <- nrow(scenario_sensitivity)
  worst_exal_gap <- max(tau_sensitivity$joint_exqdesn_minus_joint_qdesn, na.rm = TRUE)
  data.frame(
    claim_or_decision = c(
      "No need to wait for a joint-lane launch",
      "Use Phase 115 assets as the current article evidence pack",
      "Primary VB row is Joint QDESN RHS under AL with RHS prior",
      "Report VB forecast validation with review language",
      "Treat MCMC as fit-window reference, not forecast validation",
      "Do not claim uniform dominance across all scenarios",
      "Do not claim exQDESN improves over QDESN in this suite",
      "Do not run another broad VB screen before manuscript QA"
    ),
    status = c(
      "pass",
      ifelse(phase115$overall_gate[[1L]] == "fail", "fail", "review"),
      "pass",
      ifelse(as.integer(selected$forecast_raw_crossings[[1L]]) > 0L, "review", "pass"),
      ifelse(all(mcmc_assessment$gate_status == "pass"), "pass", "review"),
      ifelse(joint_wins < n_scenarios, "review", "pass"),
      ifelse(is.finite(worst_exal_gap) && worst_exal_gap > 0.02, "review", "pass"),
      "pass"
    ),
    evidence = c(
      "Phase 114 MCMC completed and Phase 115 article assets were built; no live joint compute dependency remains.",
      sprintf("Phase 115 overall gate is %s with %d verified asset rows.", phase115$overall_gate[[1L]], nrow(src$phase115$article_asset_manifest)),
      sprintf("Selected candidate is %s.", selected$candidate_id[[1L]]),
      sprintf("Selected VB source has %d raw forecast crossings and %d contract crossings.", as.integer(selected$forecast_raw_crossings[[1L]]), as.integer(health$contract_crossings[[1L]])),
      sprintf("%d/%d MCMC scenario rows pass; MCMC raw/contract crossings are %d/%d.", sum(mcmc_assessment$gate_status == "pass"), nrow(mcmc_assessment), sum(src$phase114_mcmc$summary$mcmc_raw_crossing_pairs, na.rm = TRUE), sum(src$phase114_mcmc$summary$mcmc_contract_crossing_pairs, na.rm = TRUE)),
      sprintf("Joint QDESN is the lowest-MAE row in %d/%d scenarios.", joint_wins, n_scenarios),
      sprintf("Largest joint exQDESN minus joint QDESN tau-level MAE gap is %.3f.", worst_exal_gap),
      "The current blocker is not implementation compute; it is manuscript-quality framing and conservative qualification."
    ),
    manuscript_guidance = c(
      "Move to article QA/polish now.",
      "Use tables from Phase 115, plus Phase 116 diagnostics for internal readiness notes.",
      "Keep this as the article anchor; comparator rows provide context.",
      "Say reported scores use monotone rearrangement and raw crossings are retained as diagnostics.",
      "Avoid saying MCMC validates held-out forecasts unless a separate MCMC forecast run is launched.",
      "Phrase the result as robust/competitive rather than uniformly best.",
      "Describe exQDESN as an extension requiring additional calibration rather than a superior row.",
      "Only launch targeted sensitivity if a new manuscript claim requires it."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase116_gate_rollup <- function(src, manifest_summary, claim_audit) {
  rows <- list(
    data.frame(gate = "manifest_hashes", status = app_joint_qdesn_phase116_gate(manifest_summary$gate), detail = sprintf("%d manifest groups checked", nrow(manifest_summary)), stringsAsFactors = FALSE),
    data.frame(gate = "selected_vb_source", status = as.character(src$phase113$selected$gate_status[[1L]]), detail = sprintf("%d raw forecast crossings; %d contract crossings", as.integer(src$phase113$selected$forecast_raw_crossings[[1L]]), as.integer(src$phase113$health$contract_crossings[[1L]])), stringsAsFactors = FALSE),
    data.frame(gate = "phase114_freeze", status = ifelse(grepl("^fail", src$phase114_freeze$decision$freeze_status[[1L]]), "fail", ifelse(grepl("review", src$phase114_freeze$decision$freeze_status[[1L]]), "review", "pass")), detail = src$phase114_freeze$decision$freeze_status[[1L]], stringsAsFactors = FALSE),
    data.frame(gate = "mcmc_reference", status = app_joint_qdesn_phase116_gate(src$phase114_mcmc$assessment$gate_status), detail = sprintf("%d scenario rows", nrow(src$phase114_mcmc$assessment)), stringsAsFactors = FALSE),
    data.frame(gate = "mcmc_worker_failures", status = ifelse(nrow(src$phase114_mcmc$worker_failures) == 0L, "pass", "fail"), detail = sprintf("%d worker failure rows", nrow(src$phase114_mcmc$worker_failures)), stringsAsFactors = FALSE),
    data.frame(gate = "article_assets", status = as.character(src$phase115$readiness$overall_gate[[1L]]), detail = src$phase115$readiness$recommended_next_action[[1L]], stringsAsFactors = FALSE),
    data.frame(gate = "manuscript_claims", status = app_joint_qdesn_phase116_gate(claim_audit$status), detail = sprintf("%d claim rows", nrow(claim_audit)), stringsAsFactors = FALSE)
  )
  app_bind_rows_fill(rows)
}

app_joint_qdesn_phase116_decision_summary <- function(src, gate_rollup) {
  fail <- any(gate_rollup$status == "fail")
  review <- any(gate_rollup$status == "review")
  data.frame(
    audit_id = "joint_qdesn_phase116_article_readiness_audit",
    overall_gate = if (fail) "fail" else if (review) "review" else "pass",
    recommendation = if (fail) {
      "blocked_fix_reproducibility_or_artifact_gate"
    } else {
      "proceed_to_manuscript_qa_and_article_framing"
    },
    wait_required = FALSE,
    new_broad_vb_screen_recommended = FALSE,
    selected_candidate = src$phase113$selected$candidate_id[[1L]],
    primary_article_model = "Joint QDESN RHS",
    mcmc_status = app_joint_qdesn_phase116_gate(src$phase114_mcmc$assessment$gate_status),
    article_asset_status = src$phase115$readiness$overall_gate[[1L]],
    review_reason = "The evidence pack is implementation-clean, but the selected VB forecast source retains pre-rearrangement crossings and some comparator behavior must be described conservatively.",
    next_stage = "manuscript QA/polish using Phase 115 assets; optional targeted sensitivity only if new claims require it",
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase116_next_action_plan <- function(src) {
  data.frame(
    step_order = seq_len(6L),
    action = c(
      "Keep Phase 113/114/115 artifacts frozen",
      "Use Phase 115 compact tables in the main article",
      "Use Phase 115 provenance tables and Phase 116 audit for appendix/internal reproducibility",
      "Polish the joint-validation prose around raw versus reported quantile grids",
      "Compile the manuscript and inspect table placement/readability",
      "Consider targeted sensitivity only after manuscript QA"
    ),
    command_or_artifact = c(
      "Do not mutate existing cache directories; rebuild only into a new dated output directory if needed.",
      "tables/joint_qdesn_article_validation_tables.tex",
      "tables/joint_qdesn_article_validation_provenance_tables.tex and application/cache/joint_qdesn_phase116_article_readiness_audit_20260709",
      "main.tex",
      "latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex",
      "No broad VB screen; optional long-MCMC or exAL-specific sensitivity only if needed."
    ),
    rationale = c(
      "Preserves traceability from screening to freeze to MCMC to article assets.",
      "Keeps the main result compact and avoids idiosyncratic cache-level details.",
      "Retains full reproducibility without overcrowding the main article.",
      "This is the only remaining review-level qualification in the evidence pack.",
      "The next risk is presentation, not compute.",
      "Additional compute should answer a manuscript question, not restart calibration by habit."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase116_readme <- function(decision, health, gate_rollup) {
  c(
    "# Joint QDESN Phase 116 Article-Readiness Audit",
    "",
    "This directory binds the completed Phase 113 VB screen, Phase 114 VB freeze, Phase 114 VB-initialized MCMC reference, and Phase 115 article asset build into one readiness record.",
    "",
    sprintf("- Overall gate: `%s`", decision$overall_gate[[1L]]),
    sprintf("- Recommendation: `%s`", decision$recommendation[[1L]]),
    sprintf("- Selected candidate: `%s`", decision$selected_candidate[[1L]]),
    sprintf("- Wait required: `%s`", decision$wait_required[[1L]]),
    "",
    "Health summary:",
    paste(capture.output(print(health[, c("component", "status", "immediate_action"), drop = FALSE], row.names = FALSE)), collapse = "\n"),
    "",
    "Gate counts:",
    paste(capture.output(print(table(gate_rollup$status))), collapse = "\n"),
    "",
    "Interpretation:",
    "- The MCMC article-candidate reference completed and passed all implementation/readiness gates.",
    "- The current overall gate remains `review` because the VB forecast source preserves pre-rearrangement crossings as diagnostics.",
    "- No additional broad screening or waiting is recommended before manuscript QA.",
    "- MCMC should be described as a fit-window posterior reference, not as held-out forecast validation."
  )
}

app_joint_qdesn_run_phase116_article_readiness_audit <- function(
  out_dir = app_joint_qdesn_default_phase116_article_readiness_dir(),
  phase113_dir = app_joint_qdesn_default_phase113_vb_screening_dir(),
  phase114_freeze_dir = app_joint_qdesn_default_phase114_vb_freeze_dir(),
  phase114_mcmc_dir = app_joint_qdesn_default_phase114_mcmc_article_dir(),
  phase115_dir = app_joint_qdesn_default_phase115_article_assets_dir()
) {
  out_dir <- normalizePath(out_dir, winslash = "/", mustWork = FALSE)
  app_ensure_dir(out_dir)
  src <- app_joint_qdesn_phase116_load_sources(
    phase113_dir = phase113_dir,
    phase114_freeze_dir = phase114_freeze_dir,
    phase114_mcmc_dir = phase114_mcmc_dir,
    phase115_dir = phase115_dir
  )
  manifest_summary <- app_joint_qdesn_phase116_source_manifest_summary(src)
  health <- app_joint_qdesn_phase116_health_summary(src, manifest_summary)
  phase_status <- app_joint_qdesn_phase116_phase_status(src, manifest_summary)
  scenario_sensitivity <- app_joint_qdesn_phase116_scenario_sensitivity(src)
  tau_sensitivity <- app_joint_qdesn_phase116_tau_sensitivity(src)
  distance_focus <- app_joint_qdesn_phase116_vb_mcmc_distance_focus(src)
  claim_audit <- app_joint_qdesn_phase116_claim_audit(src, scenario_sensitivity, tau_sensitivity)
  gate_rollup <- app_joint_qdesn_phase116_gate_rollup(src, manifest_summary, claim_audit)
  decision <- app_joint_qdesn_phase116_decision_summary(src, gate_rollup)
  next_plan <- app_joint_qdesn_phase116_next_action_plan(src)
  run_config <- data.frame(
    run_id = basename(out_dir),
    phase113_dir = normalizePath(phase113_dir, winslash = "/", mustWork = TRUE),
    phase114_freeze_dir = normalizePath(phase114_freeze_dir, winslash = "/", mustWork = TRUE),
    phase114_mcmc_dir = normalizePath(phase114_mcmc_dir, winslash = "/", mustWork = TRUE),
    phase115_dir = normalizePath(phase115_dir, winslash = "/", mustWork = TRUE),
    selected_candidate = src$phase113$selected$candidate_id[[1L]],
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_phase116_readme(decision, health, gate_rollup), readme_path, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qdesn_phase116_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    readiness_decision_summary = app_joint_qdesn_phase116_write_csv(decision, file.path(out_dir, "readiness_decision_summary.csv")),
    health_check_summary = app_joint_qdesn_phase116_write_csv(health, file.path(out_dir, "health_check_summary.csv")),
    phase_status_summary = app_joint_qdesn_phase116_write_csv(phase_status, file.path(out_dir, "phase_status_summary.csv")),
    source_manifest_summary = app_joint_qdesn_phase116_write_csv(manifest_summary, file.path(out_dir, "source_manifest_summary.csv")),
    gate_rollup = app_joint_qdesn_phase116_write_csv(gate_rollup, file.path(out_dir, "gate_rollup.csv")),
    scenario_sensitivity_summary = app_joint_qdesn_phase116_write_csv(scenario_sensitivity, file.path(out_dir, "scenario_sensitivity_summary.csv")),
    tau_sensitivity_summary = app_joint_qdesn_phase116_write_csv(tau_sensitivity, file.path(out_dir, "tau_sensitivity_summary.csv")),
    vb_mcmc_distance_focus = app_joint_qdesn_phase116_write_csv(distance_focus, file.path(out_dir, "vb_mcmc_distance_focus.csv")),
    manuscript_claim_audit = app_joint_qdesn_phase116_write_csv(claim_audit, file.path(out_dir, "manuscript_claim_audit.csv")),
    next_action_plan = app_joint_qdesn_phase116_write_csv(next_plan, file.path(out_dir, "next_action_plan.csv")),
    provenance = app_joint_qdesn_phase116_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, winslash = "/", mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, winslash = "/", mustWork = TRUE),
    decision = decision,
    health = health,
    gate_rollup = gate_rollup,
    scenario_sensitivity = scenario_sensitivity,
    tau_sensitivity = tau_sensitivity,
    distance_focus = distance_focus,
    claim_audit = claim_audit,
    next_action_plan = next_plan,
    artifact_manifest = manifest_info$manifest,
    artifact_manifest_path = manifest_info$manifest_path
  )
}
