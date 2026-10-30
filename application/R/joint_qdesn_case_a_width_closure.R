# Reproducible closure audit for Case A score-interval width differences.

app_joint_case_a_width_contract_path <- function() {
  app_path("application/config/joint_qdesn_case_a_width_closure_contract_v1.csv")
}

app_joint_case_a_width_contract <- function(path = app_joint_case_a_width_contract_path()) {
  tab <- app_read_csv(path)
  if (anyDuplicated(tab$name)) stop("Duplicate Case A contract keys.", call. = FALSE)
  out <- as.list(setNames(as.character(tab$value), tab$name))
  numeric_keys <- c(
    "score_rhat_pathology_threshold", "score_bulk_ess_pathology_floor",
    "state_half_score_gate", "expected_fresh_replicates"
  )
  for (key in numeric_keys) out[[key]] <- as.numeric(out[[key]])
  stopifnot(
    out$version == "joint_qdesn_case_a_width_closure_v1",
    out$scenario_id == "asymmetric_laplace_tail",
    out$decision == "retain_case_a_v2_no_retuning",
    out$model_refit_allowed == "false",
    out$article_edit_allowed == "false",
    out$width_equality_is_selection_target == "false",
    out$dense_grid_in_scope == "false"
  )
  out
}

app_joint_case_a_width_assert_columns <- function(x, columns, label) {
  missing <- setdiff(columns, names(x))
  if (length(missing)) {
    stop(sprintf("%s is missing columns: %s", label, paste(missing, collapse = ", ")),
      call. = FALSE)
  }
  invisible(TRUE)
}

app_joint_case_a_width_sha256 <- function(path) {
  if (!file.exists(path)) stop(sprintf("Missing audit source: %s", path), call. = FALSE)
  unname(tools::sha256sum(path)[[1L]])
}

app_joint_case_a_width_assert_source <- function(path, expected_sha256, label) {
  observed <- app_joint_case_a_width_sha256(path)
  if (!identical(tolower(observed), tolower(expected_sha256))) {
    stop(sprintf("%s hash mismatch: %s", label, observed), call. = FALSE)
  }
  data.frame(
    source = label,
    path = normalizePath(path, mustWork = TRUE),
    size_bytes = as.numeric(file.info(path)$size),
    sha256 = observed,
    stringsAsFactors = FALSE
  )
}

app_joint_case_a_width_assert_git_commit <- function(repo_root, commit, label,
  require_ancestor = FALSE) {
  exists_status <- suppressWarnings(system2(
    "git", c("-C", repo_root, "cat-file", "-e", paste0(commit, "^{commit}")),
    stdout = FALSE, stderr = FALSE
  ))
  if (!identical(as.integer(exists_status), 0L)) {
    stop(sprintf("Missing frozen %s commit: %s", label, commit), call. = FALSE)
  }
  ancestor <- NA
  if (require_ancestor) {
    ancestor_status <- suppressWarnings(system2(
      "git", c("-C", repo_root, "merge-base", "--is-ancestor", commit, "HEAD"),
      stdout = FALSE, stderr = FALSE
    ))
    ancestor <- identical(as.integer(ancestor_status), 0L)
    if (!ancestor) {
      stop(sprintf("Frozen %s commit is not an ancestor of HEAD: %s", label, commit),
        call. = FALSE)
    }
  }
  data.frame(
    source = label,
    commit = commit,
    required_ancestor = require_ancestor,
    ancestor_of_head = ancestor,
    stringsAsFactors = FALSE
  )
}

app_joint_case_a_width_model_key <- function(model_id) {
  structure <- ifelse(grepl("^joint", model_id), "joint", "independent")
  likelihood <- ifelse(grepl("exqdesn", model_id), "exAL", "AL")
  paste(likelihood, structure, sep = "__")
}

app_joint_case_a_width_current_audit <- function(scores, recursive_policy,
  fit_diagnostics, mean_design, ct = app_joint_case_a_width_contract()) {
  required_score <- c(
    "worker_id", "scenario_id", "model_cell_id", "model_id",
    "fit_structure", "likelihood_family", "inference_method",
    "posterior_score_mean", "posterior_score_q025", "posterior_score_q975",
    "posterior_score_interval_width", "score_rank_rhat", "score_bulk_ess",
    "score_stability_status", "canonical_contract_crossing_pairs"
  )
  app_joint_case_a_width_assert_columns(scores, required_score, "Score summary")
  current <- scores[
    scores$scenario_id == ct$scenario_id & scores$inference_method == "mcmc",
    required_score, drop = FALSE
  ]
  if (nrow(current) != 4L || anyDuplicated(app_joint_case_a_width_model_key(current$model_id))) {
    stop("Case A authority must contain exactly four unique MCMC model rows.", call. = FALSE)
  }
  if (any(!is.finite(current$posterior_score_mean)) ||
      any(!is.finite(current$posterior_score_interval_width)) ||
      any(current$posterior_score_interval_width <= 0)) {
    stop("Case A authority contains nonfinite or nonpositive score summaries.", call. = FALSE)
  }

  app_joint_case_a_width_assert_columns(recursive_policy, c(
    "scenario_id", "model_cell_id", "inference_method",
    "path_posterior_score_mean", "path_posterior_score_interval_width",
    "mean_state_to_path_width_ratio"
  ), "Recursive-policy comparison")
  path_rows <- recursive_policy[
    recursive_policy$scenario_id == ct$scenario_id &
      recursive_policy$inference_method == "mcmc", , drop = FALSE
  ]
  path_index <- match(current$model_cell_id, path_rows$model_cell_id)
  if (anyNA(path_index)) stop("Case A recursive-policy rows are incomplete.", call. = FALSE)

  app_joint_case_a_width_assert_columns(fit_diagnostics, c(
    "scenario_id", "model_cell_id", "inference_method", "fit_oracle_mae",
    "fit_oracle_rmse", "fit_contract_crossing_pairs"
  ), "Fit diagnostics")
  fit_rows <- fit_diagnostics[
    fit_diagnostics$scenario_id == ct$scenario_id &
      fit_diagnostics$inference_method == "mcmc", , drop = FALSE
  ]
  fit_index <- match(current$model_cell_id, fit_rows$model_cell_id)
  if (anyNA(fit_index)) stop("Case A fit-diagnostic rows are incomplete.", call. = FALSE)

  app_joint_case_a_width_assert_columns(mean_design, c(
    "scenario_id", "worker_id", "half_score_relative_difference",
    "chain_score_max_relative_deviation", "score_stability_status"
  ), "Mean-design diagnostics")
  design_rows <- mean_design[mean_design$scenario_id == ct$scenario_id, , drop = FALSE]
  design_index <- match(current$worker_id, design_rows$worker_id)
  if (anyNA(design_index)) stop("Case A mean-design diagnostics are incomplete.", call. = FALSE)

  out <- current
  out$relative_interval_width <- out$posterior_score_interval_width / out$posterior_score_mean
  out$path_posterior_score_mean <- path_rows$path_posterior_score_mean[path_index]
  out$path_posterior_score_interval_width <-
    path_rows$path_posterior_score_interval_width[path_index]
  out$mean_state_to_path_width_ratio <- path_rows$mean_state_to_path_width_ratio[path_index]
  out$fit_oracle_mae <- fit_rows$fit_oracle_mae[fit_index]
  out$fit_oracle_rmse <- fit_rows$fit_oracle_rmse[fit_index]
  out$fit_contract_crossing_pairs <- fit_rows$fit_contract_crossing_pairs[fit_index]
  out$state_half_score_relative_difference <-
    design_rows$half_score_relative_difference[design_index]
  out$chain_score_relative_range <-
    design_rows$chain_score_max_relative_deviation[design_index]
  out$mean_design_stability_status <- design_rows$score_stability_status[design_index]
  out$predictive_pathology <-
    out$score_stability_status != "pass" |
    out$mean_design_stability_status != "pass" |
    out$canonical_contract_crossing_pairs != 0 |
    out$fit_contract_crossing_pairs != 0 |
    !is.finite(out$score_rank_rhat) |
    out$score_rank_rhat > ct$score_rhat_pathology_threshold |
    !is.finite(out$score_bulk_ess) |
    out$score_bulk_ess < ct$score_bulk_ess_pathology_floor |
    !is.finite(out$state_half_score_relative_difference) |
    out$state_half_score_relative_difference > ct$state_half_score_gate
  out[order(match(out$likelihood_family, c("AL", "exAL")),
    match(out$fit_structure, c("joint", "independent"))), , drop = FALSE]
}

app_joint_case_a_width_pair_summary <- function(current) {
  rows <- lapply(c("AL", "exAL"), function(likelihood) {
    one <- current[current$likelihood_family == likelihood, , drop = FALSE]
    joint <- one[one$fit_structure == "joint", , drop = FALSE]
    independent <- one[one$fit_structure == "independent", , drop = FALSE]
    if (nrow(joint) != 1L || nrow(independent) != 1L) {
      stop(sprintf("Malformed Case A %s pair.", likelihood), call. = FALSE)
    }
    data.frame(
      likelihood = likelihood,
      joint_score_mean = joint$posterior_score_mean,
      independent_score_mean = independent$posterior_score_mean,
      joint_minus_independent_score =
        joint$posterior_score_mean - independent$posterior_score_mean,
      joint_interval_width = joint$posterior_score_interval_width,
      independent_interval_width = independent$posterior_score_interval_width,
      independent_to_joint_width_ratio =
        independent$posterior_score_interval_width / joint$posterior_score_interval_width,
      marginal_intervals_overlap =
        max(joint$posterior_score_q025, independent$posterior_score_q025) <=
          min(joint$posterior_score_q975, independent$posterior_score_q975),
      independent_predictive_pathology = independent$predictive_pathology,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_case_a_width_fresh_seed_audit <- function(confirmation_scores,
  article_pairs, ct = app_joint_case_a_width_contract()) {
  app_joint_case_a_width_assert_columns(confirmation_scores, c(
    "scenario_id", "replicate_id", "likelihood", "structure", "arm_id",
    "posterior_score_mean", "posterior_score_interval_width",
    "functional_status", "contract_crossing_pairs"
  ), "Fresh-seed confirmation scores")
  x <- confirmation_scores[confirmation_scores$scenario_id == ct$scenario_id, , drop = FALSE]
  rows <- lapply(c("AL", "exAL"), function(likelihood) {
    joint <- x[x$likelihood == likelihood & x$structure == "joint" &
      x$arm_id == ct$baseline_joint_arm_id, , drop = FALSE]
    independent <- x[x$likelihood == likelihood & x$structure == "independent", , drop = FALSE]
    expected <- as.integer(ct$expected_fresh_replicates)
    if (nrow(joint) != expected || nrow(independent) != expected ||
        length(unique(joint$replicate_id)) != expected ||
        length(unique(independent$replicate_id)) != expected) {
      stop(sprintf("Fresh-seed Case A %s evidence is incomplete.", likelihood), call. = FALSE)
    }
    if (any(joint$functional_status != "pass") ||
        any(independent$functional_status != "pass") ||
        any(joint$contract_crossing_pairs != 0) ||
        any(independent$contract_crossing_pairs != 0)) {
      stop("Fresh-seed Case A evidence failed a functional or contract gate.", call. = FALSE)
    }
    article <- article_pairs[article_pairs$likelihood == likelihood, , drop = FALSE]
    ratio <- mean(independent$posterior_score_interval_width) /
      mean(joint$posterior_score_interval_width)
    data.frame(
      likelihood = likelihood,
      replicates = expected,
      joint_score_mean = mean(joint$posterior_score_mean),
      independent_score_mean = mean(independent$posterior_score_mean),
      joint_interval_width = mean(joint$posterior_score_interval_width),
      independent_interval_width = mean(independent$posterior_score_interval_width),
      independent_to_joint_width_ratio = ratio,
      article_independent_to_joint_width_ratio =
        article$independent_to_joint_width_ratio,
      width_order_reverses_article_fixture =
        ratio < 1 && article$independent_to_joint_width_ratio > 1,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_case_a_width_architecture_sensitivity <- function(comparison,
  ct = app_joint_case_a_width_contract()) {
  required <- c(
    "scenario_id", "model_id", "fit_structure", "likelihood_family",
    "inference_method", "posterior_score_mean", "posterior_score_interval_width",
    "posterior_score_mean_baseline", "posterior_score_interval_width_baseline",
    "mean_change_percent", "interval_width_ratio", "intervals_overlap_baseline"
  )
  app_joint_case_a_width_assert_columns(comparison, required, "Architecture comparison")
  x <- comparison[
    comparison$scenario_id == ct$scenario_id & comparison$inference_method == "mcmc",
    required, drop = FALSE
  ]
  if (nrow(x) != 4L) stop("Case A architecture comparison must contain four MCMC rows.", call. = FALSE)
  names(x)[names(x) == "posterior_score_mean"] <- "current_score_mean"
  names(x)[names(x) == "posterior_score_interval_width"] <- "current_interval_width"
  names(x)[names(x) == "posterior_score_mean_baseline"] <- "previous_score_mean"
  names(x)[names(x) == "posterior_score_interval_width_baseline"] <-
    "previous_interval_width"
  x[order(match(x$likelihood_family, c("AL", "exAL")),
    match(x$fit_structure, c("joint", "independent"))), , drop = FALSE]
}

app_joint_case_a_width_backbone_audit <- function(backbones,
  ct = app_joint_case_a_width_contract()) {
  required <- c(
    "scenario_id", "candidate_id", "architecture_signature", "rhs_tau0",
    "selection_window", "selection_metric", "protected_rows_used_for_selection",
    "shared_across_four_quantile_rows", "raw_inputs_in_readout",
    "full_states_all_layers"
  )
  app_joint_case_a_width_assert_columns(backbones, required, "Selected backbones")
  one <- backbones[backbones$scenario_id == ct$scenario_id, required, drop = FALSE]
  if (nrow(one) != 1L || one$protected_rows_used_for_selection[[1L]] != 0L ||
      !isTRUE(one$shared_across_four_quantile_rows[[1L]]) ||
      isTRUE(one$raw_inputs_in_readout[[1L]]) ||
      !isTRUE(one$full_states_all_layers[[1L]])) {
    stop("Case A selected-backbone comparison contract is not preserved.", call. = FALSE)
  }
  one
}

app_joint_case_a_width_article_wording_audit <- function(repo_root) {
  normalize <- function(path) {
    gsub("[[:space:]]+", " ", paste(readLines(path, warn = FALSE), collapse = " "))
  }
  main <- normalize(file.path(repo_root, "main.tex"))
  supplement <- normalize(file.path(repo_root, "qdesn-supplement.tex"))
  checks <- data.frame(
    check = c(
      "conditional_interval_scope", "no_general_superiority_claim",
      "descriptive_joint_independent_contrasts"
    ),
    pass = c(
      grepl("score intervals condition on that summary", main, fixed = TRUE),
      grepl("do not establish a general forecast advantage", main, fixed = TRUE),
      grepl("descriptive joint-minus-independent score intervals", supplement, fixed = TRUE)
    ),
    stringsAsFactors = FALSE
  )
  checks
}

app_joint_case_a_width_write_markdown <- function(path, decision, pairs, fresh,
  architecture, wording) {
  format_rows <- function(x) paste(apply(x, 1L, function(row) paste(row, collapse = " | ")),
    collapse = "\n")
  pair_rows <- data.frame(
    Likelihood = pairs$likelihood,
    `Joint mean` = sprintf("%.6f", pairs$joint_score_mean),
    `Independent mean` = sprintf("%.6f", pairs$independent_score_mean),
    `Joint width` = sprintf("%.6f", pairs$joint_interval_width),
    `Independent width` = sprintf("%.6f", pairs$independent_interval_width),
    `Independent/Joint` = sprintf("%.3f", pairs$independent_to_joint_width_ratio),
    check.names = FALSE
  )
  fresh_rows <- data.frame(
    Likelihood = fresh$likelihood,
    `Joint width` = sprintf("%.6f", fresh$joint_interval_width),
    `Independent width` = sprintf("%.6f", fresh$independent_interval_width),
    `Independent/Joint` = sprintf("%.3f", fresh$independent_to_joint_width_ratio),
    `Ordering reversed` = fresh$width_order_reverses_article_fixture,
    check.names = FALSE
  )
  lines <- c(
    "# JOINT Case A width-compatibility closure",
    "",
    sprintf("- Decision: `%s`", decision$decision),
    sprintf("- Current independent pathology detected: `%s`", decision$independent_pathology_detected),
    sprintf("- Fresh-seed width ordering reverses the article fixture: `%s`", decision$fresh_seed_width_reversal),
    "- Width equality is not a selection target.",
    "- No model refit, article edit, dense-grid fit, or Overleaf action is authorized.",
    "",
    "## Current protected realization",
    "",
    paste(names(pair_rows), collapse = " | "),
    paste(rep("---", ncol(pair_rows)), collapse = " | "),
    format_rows(pair_rows),
    "",
    "## Fresh-seed check",
    "",
    paste(names(fresh_rows), collapse = " | "),
    paste(rep("---", ncol(fresh_rows)), collapse = " | "),
    format_rows(fresh_rows),
    "",
    "## Interpretation",
    "",
    "The current independent intervals are wider but have healthy score diagnostics.",
    "The ordering reverses on the two frozen fresh DGP realizations, so the article-fixture",
    "difference is realization-dependent rather than a reproducible independent-model defect.",
    "The architecture comparison also shows a joint/independent tradeoff; tuning only to",
    "equalize widths would use the wrong objective and weaken the shared-backbone design.",
    "Current manuscript language already states the conditional interval scope and avoids",
    "a general superiority claim.",
    "",
    sprintf("Architecture rows audited: %d.", nrow(architecture)),
    sprintf("Manuscript wording checks passed: %d/%d.", sum(wording$pass), nrow(wording))
  )
  writeLines(lines, path, useBytes = TRUE)
  path
}

app_joint_case_a_width_run_audit <- function(repo_root, confirmation_path,
  comparison_path, mean_design_path, output_dir,
  ct = app_joint_case_a_width_contract()) {
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  source_specs <- list(
    score_summary = c(file.path(repo_root, ct$score_summary_relative_path),
      ct$score_summary_sha256),
    recursive_policy = c(file.path(repo_root, ct$recursive_policy_relative_path),
      ct$recursive_policy_sha256),
    fit_diagnostics = c(file.path(repo_root, ct$fit_diagnostics_relative_path),
      ct$fit_diagnostics_sha256),
    selected_backbones = c(file.path(repo_root, ct$selected_backbones_relative_path),
      ct$selected_backbones_sha256),
    fresh_confirmation = c(confirmation_path, ct$fixed_backbone_confirmation_sha256),
    architecture_comparison = c(comparison_path, ct$expanded_comparison_sha256),
    mean_design_diagnostics = c(mean_design_path, ct$mean_design_diagnostics_sha256)
  )
  source_manifest <- do.call(rbind, lapply(names(source_specs), function(name) {
    spec <- source_specs[[name]]
    app_joint_case_a_width_assert_source(spec[[1L]], spec[[2L]], name)
  }))
  source_heads <- do.call(rbind, list(
    app_joint_case_a_width_assert_git_commit(repo_root, ct$authority_source_head,
      "integrated_v2_authority", require_ancestor = TRUE),
    app_joint_case_a_width_assert_git_commit(repo_root, ct$expanded_closeout_source_head,
      "expanded_closeout", require_ancestor = TRUE),
    app_joint_case_a_width_assert_git_commit(repo_root, ct$fixed_backbone_source_head,
      "fixed_backbone_prior", require_ancestor = FALSE)
  ))

  scores <- app_read_csv(source_specs$score_summary[[1L]])
  recursive <- app_read_csv(source_specs$recursive_policy[[1L]])
  fit <- app_read_csv(source_specs$fit_diagnostics[[1L]])
  backbone <- app_joint_case_a_width_backbone_audit(
    app_read_csv(source_specs$selected_backbones[[1L]]), ct
  )
  mean_design <- app_read_csv(mean_design_path)
  current <- app_joint_case_a_width_current_audit(scores, recursive, fit, mean_design, ct)
  pairs <- app_joint_case_a_width_pair_summary(current)
  fresh <- app_joint_case_a_width_fresh_seed_audit(
    app_read_csv(confirmation_path), pairs, ct
  )
  architecture <- app_joint_case_a_width_architecture_sensitivity(
    app_read_csv(comparison_path), ct
  )
  wording <- app_joint_case_a_width_article_wording_audit(repo_root)
  independent_pathology <- any(current$predictive_pathology[current$fit_structure == "independent"])
  fresh_reversal <- all(fresh$width_order_reverses_article_fixture)
  decision_value <- if (!independent_pathology && fresh_reversal && all(wording$pass)) {
    ct$decision
  } else {
    "review_required_no_automatic_rerun"
  }
  decision <- data.frame(
    scenario_id = ct$scenario_id,
    decision = decision_value,
    independent_pathology_detected = independent_pathology,
    fresh_seed_width_reversal = fresh_reversal,
    width_equality_is_selection_target = FALSE,
    model_refit_authorized = FALSE,
    article_edit_required = !all(wording$pass),
    dense_grid_in_scope = FALSE,
    stringsAsFactors = FALSE
  )

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c(
    source_manifest = app_write_csv(source_manifest, file.path(output_dir, "source_manifest.csv")),
    source_heads = app_write_csv(source_heads, file.path(output_dir, "source_heads.csv")),
    selected_backbone = app_write_csv(backbone, file.path(output_dir, "selected_backbone.csv")),
    current_audit = app_write_csv(current, file.path(output_dir, "current_case_a_audit.csv")),
    pair_summary = app_write_csv(pairs, file.path(output_dir, "current_pair_summary.csv")),
    fresh_seed = app_write_csv(fresh, file.path(output_dir, "fresh_seed_width_audit.csv")),
    architecture = app_write_csv(architecture,
      file.path(output_dir, "architecture_sensitivity.csv")),
    wording = app_write_csv(wording, file.path(output_dir, "article_wording_audit.csv")),
    decision = app_write_csv(decision, file.path(output_dir, "decision.csv"))
  )
  paths <- c(paths, decision_markdown = app_joint_case_a_width_write_markdown(
    file.path(output_dir, "DECISION.md"), decision, pairs, fresh, architecture, wording
  ))
  artifact_manifest <- data.frame(
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = unname(tools::sha256sum(paths)),
    stringsAsFactors = FALSE
  )
  app_write_csv(artifact_manifest, file.path(output_dir, "artifact_manifest.csv"))
  writeLines("COMPLETE", file.path(output_dir, "COMPLETE"), useBytes = TRUE)
  list(
    decision = decision, current = current, pairs = pairs, fresh = fresh,
    architecture = architecture, wording = wording, source_manifest = source_manifest,
    source_heads = source_heads, backbone = backbone,
    output_dir = normalizePath(output_dir, mustWork = TRUE)
  )
}
