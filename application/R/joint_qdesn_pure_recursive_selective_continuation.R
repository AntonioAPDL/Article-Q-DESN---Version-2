# Selective continuation from the expanded pure-DESN screen.

app_joint_pure_continuation_changed_scenarios <- function() {
  c("asymmetric_laplace_tail", "nonlinear_reservoir_friendly")
}

app_joint_pure_continuation_spec_columns <- function() {
  c(
    "scenario_id", "candidate_id", "feature_contract", "design_class", "D",
    "n", "n_tilde", "retained_state_budget", "width_shape",
    "state_reduction", "response_lags", "exogenous_lags", "alpha", "rho",
    "pi_w", "pi_in", "input_scale", "reservoir_seed",
    "raw_inputs_in_readout", "full_states_all_layers",
    "architecture_signature", "rhs_tau0"
  )
}

app_joint_pure_quantile_reuse_plan_columns <- function() {
  c(
    "job_id", "stage_order", "stage_id", "replicate_id", "model_id",
    "tau", "parent_tau", "dgp_seed", "design_fingerprint"
  )
}

app_joint_pure_vb_reuse_plan_columns <- function() {
  c(
    "job_id", "scenario_id", "stage_order", "stage_id", "model_id", "tau",
    "parent_tau", "component_seed", "selected_candidate_id",
    "selected_architecture_signature", "selected_design_class",
    "selected_rhs_tau0", "design_fingerprint"
  )
}

app_joint_pure_mcmc_reuse_plan_columns <- function() {
  c(
    "worker_id", "scenario_id", "model_id", "likelihood_family",
    "fit_structure", "chain_id", "chain_seed", "chain_start_seed",
    "tau_seed_stride", "n_iter", "burn", "thin", "n_keep",
    "inference_method_id", "candidate_id", "architecture_signature",
    "design_class", "rhs_tau0", "design_fingerprint"
  )
}

app_joint_pure_values_equal <- function(x, y, tolerance = 1e-12) {
  if (length(x) != length(y)) return(FALSE)
  both_na <- is.na(x) & is.na(y)
  one_na <- xor(is.na(x), is.na(y))
  if (any(one_na)) return(FALSE)
  keep <- !both_na
  if (!any(keep)) return(TRUE)
  if (is.numeric(x) || is.integer(x)) {
    return(all(abs(as.numeric(x[keep]) - as.numeric(y[keep])) <= tolerance))
  }
  identical(as.character(x[keep]), as.character(y[keep]))
}

app_joint_pure_rows_equal <- function(x, y, columns, context) {
  missing <- setdiff(columns, intersect(names(x), names(y)))
  if (length(missing)) {
    stop(sprintf("%s is missing columns: %s", context,
      paste(missing, collapse = ", ")), call. = FALSE)
  }
  all(vapply(columns, function(name) {
    app_joint_pure_values_equal(x[[name]], y[[name]])
  }, logical(1L)))
}

app_joint_pure_continuation_spec_audit <- function(target_root, source_root) {
  target_root <- normalizePath(target_root, mustWork = TRUE)
  source_root <- normalizePath(source_root, mustWork = TRUE)
  target <- app_read_csv(file.path(target_root, "selected_family_backbones.csv"))
  source <- app_read_csv(file.path(source_root, "selected_family_backbones.csv"))
  scenarios <- sort(unique(c(target$scenario_id, source$scenario_id)))
  if (length(scenarios) != 8L || nrow(target) != 8L || nrow(source) != 8L ||
      anyDuplicated(target$scenario_id) || anyDuplicated(source$scenario_id)) {
    stop("Selective continuation requires two complete eight-family selections.",
      call. = FALSE)
  }
  columns <- app_joint_pure_continuation_spec_columns()
  rows <- lapply(scenarios, function(scenario) {
    one_target <- target[target$scenario_id == scenario, , drop = FALSE]
    one_source <- source[source$scenario_id == scenario, , drop = FALSE]
    same <- app_joint_pure_rows_equal(
      one_target, one_source, columns,
      sprintf("Selected specification for %s", scenario)
    )
    data.frame(
      scenario_id = scenario,
      source_candidate_id = one_source$candidate_id[[1L]],
      target_candidate_id = one_target$candidate_id[[1L]],
      source_architecture_signature = one_source$architecture_signature[[1L]],
      target_architecture_signature = one_target$architecture_signature[[1L]],
      source_rhs_tau0 = one_source$rhs_tau0[[1L]],
      target_rhs_tau0 = one_target$rhs_tau0[[1L]],
      specification_identical = same,
      action = if (same) "reuse_verified" else "refit",
      stringsAsFactors = FALSE
    )
  })
  audit <- app_joint_qdesn_bind_rows(rows)
  observed_changed <- sort(audit$scenario_id[!audit$specification_identical])
  expected_changed <- sort(app_joint_pure_continuation_changed_scenarios())
  if (!identical(observed_changed, expected_changed) ||
      sum(audit$specification_identical) != 6L) {
    stop(sprintf(
      "Expanded continuation expected only %s to change; observed %s.",
      paste(expected_changed, collapse = ";"),
      paste(observed_changed, collapse = ";")
    ), call. = FALSE)
  }
  audit
}

app_joint_pure_copy_tree <- function(source, target) {
  source <- normalizePath(source, mustWork = TRUE)
  target <- normalizePath(target, mustWork = FALSE)
  if (dir.exists(target) && length(list.files(
      target, all.files = TRUE, no.. = TRUE))) {
    stop(sprintf("Refusing to overwrite nonempty reuse target: %s", target),
      call. = FALSE)
  }
  app_ensure_dir(target)
  entries <- list.files(source, recursive = TRUE, full.names = TRUE,
    all.files = TRUE, no.. = TRUE, include.dirs = TRUE)
  if (!length(entries)) stop("Reuse source directory is empty.", call. = FALSE)
  relative <- substring(entries, nchar(source) + 2L)
  info <- file.info(entries)
  directories <- relative[!is.na(info$isdir) & info$isdir]
  if (length(directories)) {
    invisible(lapply(file.path(target, directories), app_ensure_dir))
  }
  files <- entries[!is.na(info$isdir) & !info$isdir]
  file_relative <- relative[!is.na(info$isdir) & !info$isdir]
  for (ii in seq_along(files)) {
    destination <- file.path(target, file_relative[[ii]])
    app_ensure_dir(dirname(destination))
    if (!file.copy(files[[ii]], destination, overwrite = FALSE,
        copy.mode = TRUE, copy.date = TRUE)) {
      stop(sprintf("Could not copy reuse artifact: %s", files[[ii]]),
        call. = FALSE)
    }
  }
  target
}

app_joint_pure_refresh_worker_summary <- function(worker_dir, target_row,
  summary_name) {
  summary_path <- file.path(worker_dir, summary_name)
  manifest_path <- file.path(worker_dir, "artifact_manifest.csv")
  summary <- app_read_csv(summary_path)
  if (nrow(summary) != 1L) {
    stop("Reusable worker summary must contain exactly one row.", call. = FALSE)
  }
  overlap <- intersect(names(target_row), names(summary))
  for (name in overlap) summary[[name]] <- target_row[[name]][[1L]]
  app_write_csv(summary, summary_path)
  manifest <- app_read_csv(manifest_path)
  row <- which(manifest$relative_path == summary_name)
  if (length(row) != 1L) {
    stop("Reusable worker manifest does not identify its summary uniquely.",
      call. = FALSE)
  }
  manifest$size_bytes[[row]] <- as.numeric(file.info(summary_path)$size)
  manifest$sha256[[row]] <- app_sha256_file(summary_path)
  app_write_csv(manifest, manifest_path)
  verification <- app_joint_shared_verify_manifest(worker_dir, manifest_path)
  if (!nrow(verification) || any(!verification$verified)) {
    stop("Rewritten reusable worker failed manifest verification.",
      call. = FALSE)
  }
  invisible(manifest_path)
}

app_joint_pure_import_worker <- function(source_dir, target_dir, target_row,
  summary_name) {
  source_dir <- normalizePath(source_dir, mustWork = TRUE)
  target_dir <- normalizePath(target_dir, mustWork = FALSE)
  source_verification <- app_joint_shared_verify_manifest(
    source_dir, file.path(source_dir, "artifact_manifest.csv")
  )
  if (!file.exists(file.path(source_dir, "DONE")) ||
      any(!source_verification$verified)) {
    stop("Reusable source worker is incomplete or has a bad manifest.",
      call. = FALSE)
  }
  if (dir.exists(target_dir)) {
    target_verification <- tryCatch(app_joint_shared_verify_manifest(
      target_dir, file.path(target_dir, "artifact_manifest.csv")),
      error = function(error) NULL)
    if (file.exists(file.path(target_dir, "DONE")) &&
        is.data.frame(target_verification) &&
        nrow(target_verification) && all(target_verification$verified)) {
      target_summary <- app_read_csv(file.path(target_dir, summary_name))
      overlap <- intersect(names(target_row), names(target_summary))
      if (nrow(target_summary) != 1L || !app_joint_pure_rows_equal(
          target_summary, target_row, overlap,
          "Already-imported worker summary")) {
        stop("Verified reuse target does not match the target plan.",
          call. = FALSE)
      }
      return(data.frame(
        source_worker_manifest_sha256 = app_sha256_file(file.path(
          source_dir, "artifact_manifest.csv")),
        target_worker_manifest_sha256 = app_sha256_file(file.path(
          target_dir, "artifact_manifest.csv")),
        import_status = "already_present_verified", stringsAsFactors = FALSE
      ))
    }
    stop("Reuse target exists but is not a verified completed worker.",
      call. = FALSE)
  }
  temporary <- paste0(target_dir, ".importing.", Sys.getpid())
  unlink(temporary, recursive = TRUE, force = TRUE)
  app_joint_pure_copy_tree(source_dir, temporary)
  app_joint_pure_refresh_worker_summary(temporary, target_row, summary_name)
  if (!file.rename(temporary, target_dir)) {
    stop("Could not atomically publish imported worker.", call. = FALSE)
  }
  data.frame(
    source_worker_manifest_sha256 = app_sha256_file(file.path(
      source_dir, "artifact_manifest.csv")),
    target_worker_manifest_sha256 = app_sha256_file(file.path(
      target_dir, "artifact_manifest.csv")),
    import_status = "imported_verified", stringsAsFactors = FALSE
  )
}

app_joint_pure_assert_plan_rows <- function(source_row, target_row, columns,
  context) {
  if (!app_joint_pure_rows_equal(source_row, target_row, columns, context)) {
    stop(sprintf("%s differs between source and target plans.", context),
      call. = FALSE)
  }
  invisible(TRUE)
}

app_joint_pure_write_reuse_manifest <- function(root, stage, audit,
  worker_manifest_paths) {
  audit_path <- app_write_csv(audit, file.path(root, paste0(stage,
    "_reuse_audit.csv")))
  paths <- c(reuse_audit = audit_path)
  if (length(worker_manifest_paths)) {
    names(worker_manifest_paths) <- sprintf("worker_manifest_%04d",
      seq_along(worker_manifest_paths))
    paths <- c(paths, worker_manifest_paths)
  }
  manifest <- app_joint_shared_write_manifest(
    root, paths, filename = paste0(stage, "_reuse_artifact_manifest.csv")
  )
  verification <- app_joint_shared_verify_manifest(root, manifest)
  if (any(!verification$verified)) {
    stop(sprintf("%s reuse artifact manifest failed verification.", stage),
      call. = FALSE)
  }
  app_write_csv(verification, file.path(root, paste0(stage,
    "_reuse_manifest_verification.csv")))
  audit
}

app_joint_pure_import_quantile_reuse <- function(target_root, source_root) {
  target_root <- normalizePath(target_root, mustWork = TRUE)
  source_root <- normalizePath(source_root, mustWork = TRUE)
  spec <- app_joint_pure_continuation_spec_audit(target_root, source_root)
  reusable <- spec$scenario_id[spec$specification_identical]
  target_families <- app_read_csv(file.path(target_root,
    "quantile_family_plan.csv"))
  source_families <- app_read_csv(file.path(source_root,
    "quantile_family_plan.csv"))
  plan_columns <- app_joint_pure_quantile_reuse_plan_columns()
  rows <- list(); manifests <- character()
  for (scenario in reusable) {
    target_qroot <- target_families$quantile_root[
      target_families$scenario_id == scenario][[1L]]
    source_qroot <- source_families$quantile_root[
      source_families$scenario_id == scenario][[1L]]
    target_plan <- app_read_csv(file.path(target_qroot, "worker_plan.csv"))
    source_plan <- app_read_csv(file.path(source_qroot, "worker_plan.csv"))
    if (nrow(target_plan) != 51L || nrow(source_plan) != 51L) {
      stop("Reusable quantile family must contain 51 workers.", call. = FALSE)
    }
    for (job_id in target_plan$job_id) {
      target_row <- target_plan[target_plan$job_id == job_id, , drop = FALSE]
      source_row <- source_plan[source_plan$job_id == job_id, , drop = FALSE]
      app_joint_pure_assert_plan_rows(source_row, target_row, plan_columns,
        sprintf("Quantile worker %s/%d", scenario, job_id))
      source_dir <- app_joint_shared_quantile_worker_dir(source_qroot, job_id)
      target_dir <- app_joint_shared_quantile_worker_dir(target_qroot, job_id)
      imported <- app_joint_pure_import_worker(
        source_dir, target_dir, target_row, "summary.csv"
      )
      rows[[length(rows) + 1L]] <- cbind(data.frame(
        stage = "quantile_vb", scenario_id = scenario, worker_id = job_id,
        source_worker_dir = source_dir, target_worker_dir = target_dir,
        design_fingerprint = target_row$design_fingerprint[[1L]],
        stringsAsFactors = FALSE
      ), imported)
      manifests <- c(manifests, file.path(target_dir,
        "artifact_manifest.csv"))
    }
  }
  audit <- app_joint_qdesn_bind_rows(rows)
  if (nrow(audit) != 306L || any(!audit$import_status %in%
      c("imported_verified", "already_present_verified"))) {
    stop("Quantile reuse did not verify exactly 306 workers.", call. = FALSE)
  }
  app_write_csv(spec, file.path(target_root,
    "selective_continuation_spec_audit.csv"))
  app_joint_pure_write_reuse_manifest(target_root, "quantile", audit,
    manifests)
}

app_joint_pure_import_vb_reuse <- function(target_root, source_root,
  target_campaign_root, source_campaign_root) {
  target_root <- normalizePath(target_root, mustWork = TRUE)
  source_root <- normalizePath(source_root, mustWork = TRUE)
  spec <- app_joint_pure_continuation_spec_audit(
    target_campaign_root, source_campaign_root
  )
  reusable <- spec$scenario_id[spec$specification_identical]
  target_plan <- app_read_csv(file.path(target_root, "vb_worker_plan.csv"))
  source_plan <- app_read_csv(file.path(source_root, "vb_worker_plan.csv"))
  plan_columns <- app_joint_pure_vb_reuse_plan_columns()
  target_plan <- target_plan[target_plan$scenario_id %in% reusable, , drop = FALSE]
  rows <- list(); manifests <- character()
  for (ii in seq_len(nrow(target_plan))) {
    target_row <- target_plan[ii, , drop = FALSE]
    source_row <- source_plan[source_plan$job_id == target_row$job_id[[1L]],
      , drop = FALSE]
    app_joint_pure_assert_plan_rows(source_row, target_row, plan_columns,
      sprintf("Article VB worker %d", target_row$job_id[[1L]]))
    source_dir <- app_joint_article_vb_worker_dir(
      source_root, target_row$job_id[[1L]])
    target_dir <- app_joint_article_vb_worker_dir(
      target_root, target_row$job_id[[1L]])
    imported <- app_joint_pure_import_worker(
      source_dir, target_dir, target_row, "summary.csv"
    )
    rows[[ii]] <- cbind(data.frame(
      stage = "article_vb", scenario_id = target_row$scenario_id[[1L]],
      worker_id = target_row$job_id[[1L]], source_worker_dir = source_dir,
      target_worker_dir = target_dir,
      design_fingerprint = target_row$design_fingerprint[[1L]],
      stringsAsFactors = FALSE
    ), imported)
    manifests <- c(manifests, file.path(target_dir, "artifact_manifest.csv"))
  }
  audit <- app_joint_qdesn_bind_rows(rows)
  if (nrow(audit) != 102L) {
    stop("Article VB reuse did not verify exactly 102 workers.",
      call. = FALSE)
  }
  app_joint_pure_write_reuse_manifest(target_root, "vb", audit, manifests)
}

app_joint_pure_import_mcmc_reuse <- function(target_root, source_root,
  target_campaign_root, source_campaign_root) {
  target_root <- normalizePath(target_root, mustWork = TRUE)
  source_root <- normalizePath(source_root, mustWork = TRUE)
  spec <- app_joint_pure_continuation_spec_audit(
    target_campaign_root, source_campaign_root
  )
  reusable <- spec$scenario_id[spec$specification_identical]
  target_plan <- app_read_csv(file.path(target_root, "mcmc_worker_plan.csv"))
  source_plan <- app_read_csv(file.path(source_root, "mcmc_worker_plan.csv"))
  target_cells <- app_read_csv(file.path(target_root, "model_cell_plan.csv"))
  source_cells <- app_read_csv(file.path(source_root, "model_cell_plan.csv"))
  target_contract <- app_joint_article_read_contract(file.path(
    target_root, "frozen_contract.csv"))
  if (!identical(target_contract$exal_mcmc_method,
      "M0_v_collapsed_support_logit")) {
    stop("Selective continuation requires exact M0 for every exAL MCMC cell.",
      call. = FALSE)
  }
  plan_columns <- app_joint_pure_mcmc_reuse_plan_columns()
  target_plan <- target_plan[target_plan$scenario_id %in% reusable, , drop = FALSE]
  rows <- list(); manifests <- character()
  for (ii in seq_len(nrow(target_plan))) {
    target_row <- target_plan[ii, , drop = FALSE]
    source_row <- source_plan[source_plan$worker_id ==
      target_row$worker_id[[1L]], , drop = FALSE]
    app_joint_pure_assert_plan_rows(source_row, target_row, plan_columns,
      sprintf("Article MCMC worker %d", target_row$worker_id[[1L]]))
    target_cell <- target_cells[target_cells$model_cell_id ==
      target_row$model_cell_id[[1L]], , drop = FALSE]
    source_cell <- source_cells[source_cells$model_cell_id ==
      target_row$model_cell_id[[1L]], , drop = FALSE]
    target_initializer <- file.path(target_root,
      target_cell$initializer_relative_path[[1L]])
    source_initializer <- file.path(source_root,
      source_cell$initializer_relative_path[[1L]])
    initializer_hash_equal <- identical(
      app_sha256_file(target_initializer), app_sha256_file(source_initializer)
    )
    if (!initializer_hash_equal) {
      stop(sprintf("Initializer hash changed for reusable cell %s.",
        target_row$model_cell_id[[1L]]), call. = FALSE)
    }
    design <- readRDS(target_row$design_path[[1L]])
    target_posterior <- app_joint_article_resolve_posterior_target(
      target_root, target_row, design, target_contract
    )
    source_dir <- app_joint_article_mcmc_worker_dir(
      source_root, target_row$worker_id[[1L]])
    source_summary <- app_read_csv(file.path(source_dir,
      "posterior_summary.csv"))
    posterior_target_equal <- nrow(source_summary) == 1L && identical(
      as.character(source_summary$posterior_target_sha256[[1L]]),
      target_posterior$hash
    )
    if (!posterior_target_equal) {
      stop(sprintf("Posterior target changed for reusable MCMC worker %d.",
        target_row$worker_id[[1L]]), call. = FALSE)
    }
    target_dir <- app_joint_article_mcmc_worker_dir(
      target_root, target_row$worker_id[[1L]])
    imported <- app_joint_pure_import_worker(
      source_dir, target_dir, target_row, "posterior_summary.csv"
    )
    rows[[ii]] <- cbind(data.frame(
      stage = "article_mcmc", scenario_id = target_row$scenario_id[[1L]],
      model_cell_id = target_row$model_cell_id[[1L]],
      worker_id = target_row$worker_id[[1L]],
      source_worker_dir = source_dir, target_worker_dir = target_dir,
      initializer_hash_equal = initializer_hash_equal,
      posterior_target_equal = posterior_target_equal,
      likelihood_family = target_row$likelihood_family[[1L]],
      mcmc_method_id = target_row$inference_method_id[[1L]],
      stringsAsFactors = FALSE
    ), imported)
    manifests <- c(manifests, file.path(target_dir, "artifact_manifest.csv"))
  }
  audit <- app_joint_qdesn_bind_rows(rows)
  if (nrow(audit) != 120L ||
      any(audit$mcmc_method_id[audit$likelihood_family == "exAL"] !=
        "M0_v_collapsed_support_logit") ||
      any(audit$mcmc_method_id[audit$likelihood_family == "AL"] !=
        target_contract$al_mcmc_method)) {
    stop("Article MCMC reuse did not verify exactly 120 target-matched workers.",
      call. = FALSE)
  }
  app_joint_pure_write_reuse_manifest(target_root, "mcmc", audit,
    manifests)
}
