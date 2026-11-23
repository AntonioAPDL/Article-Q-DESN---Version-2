# Corrected AL replacement and score reconstruction for the JOINT super-final lane.

app_joint_alkernel_default_root <- function() {
  app_path("application/cache/joint_qdesn_superfinal_al_kernel_rerun_20261123")
}

app_joint_alkernel_contract <- function() {
  data.frame(
    name = c(
      "contract_version", "correction_base_commit", "source_mcmc_plan_sha256",
      "source_model_cell_plan_sha256", "source_component_seed_plan_sha256",
      "source_score_contract_sha256", "source_score_plan_sha256",
      "source_score_summary_sha256", "source_mcmc_summary_sha256",
      "source_oracle_manifest_sha256", "source_score_final_manifest_sha256",
      "source_transfer_inventory_sha256", "source_handoff_manifest_sha256",
      "superfinal_plan_sha256", "superfinal_selected_packet_sha256",
      "superfinal_final_decision_sha256", "mandatory_al_workers",
      "reused_exal_workers", "rescored_al_cells", "reused_score_cells",
      "scale_update_id", "sigma_support", "exal_method",
      "conditional_al_supplement_policy", "article_assets_modified"
    ),
    value = c(
      "joint_qdesn_superfinal_al_kernel_rerun_v1",
      "c9e728842c5c256bfded27d27987c4f9dd7ebc94",
      "e2da12a9c87987cb0b9c0221a0ec8b69a8f66df77dab39420b636b8f151f9e01",
      "1f223b6e57f407997578dc3a25052576f0ea87c90e492567437cfd789f153258",
      "a585a0b3fccbe6c9b1c214a0e298dfc283c8f25f98ac8921dc43b4e3fcc882c1",
      "cc022ba7066118d293f8d7c161fe8609ab239c9bb787d9fb8c5348eb512dd268",
      "6d8e1fa67d8df9fe90e45878708068d8d228fee3cb30b76944178df81f978dce",
      "d6f8045171a2955bbbb136a040882d5d6a93d2e18af706e5a803a1313ad3483c",
      "6621609d62e6cdeb80086b4fdb0ea03ade405a0cbdd2548bb04f65d6da7ac9c9",
      "ebbdaed3355a6ee4e83bb9c731d92474f7855280739ab275092d9967dba02d79",
      "e0713427aca5d6358e468394ade636620a2088e5d39b8c0e5196080df4774643",
      "213dc7f45004b0383db87054abf479200193b45056b64d461f2edc75a34f28d0",
      "20ade34f91e08de24f213a532af994b6232aa7fffc5f62f08022291bc42fe277",
      "eed15287c7927d54c759df27ad114f0d1b9a2b9c32646ea59a1b4638326c502e",
      "69aced9bbd37ee506a382ed85a7fe2aba116ed296ae4285890540e572122f5f3",
      "a6ca1194d317c885b0433cdcafc6f4706e0929c7c5863669a9a03f03b290f433",
      "96", "96", "32", "96", "direct_inverse_gamma_unbounded_v1",
      "(0,Inf)", "M0_v_collapsed_support_logit",
      "run_only_if_complete_challenger_packet_remains_eligible_after_exal_stability_gate",
      "FALSE"
    ), stringsAsFactors = FALSE
  )
}

app_joint_alkernel_value <- function(contract, name, numeric = FALSE) {
  row <- contract[contract$name == name, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("AL-kernel contract lacks '%s'.", name), call. = FALSE)
  value <- as.character(row$value[[1L]])
  if (numeric) as.numeric(value) else value
}

app_joint_alkernel_paths <- function(source_root, superfinal_root) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  superfinal_root <- normalizePath(superfinal_root, mustWork = TRUE)
  confirmation <- file.path(source_root, "full_confirmation")
  score <- file.path(confirmation, "score_packet")
  list(source = source_root, confirmation = confirmation, score = score,
    superfinal = superfinal_root,
    transfer_inventory = file.path(source_root, "integration_handoff",
      "full_confirmation_transfer_inventory.csv"),
    handoff_manifest = file.path(source_root, "integration_handoff", "handoff_manifest.csv"))
}

app_joint_alkernel_source_inventory <- function(source_root, superfinal_root,
    contract = app_joint_alkernel_contract()) {
  paths <- app_joint_alkernel_paths(source_root, superfinal_root)
  expected <- c(
    source_mcmc_plan_sha256 = file.path(paths$confirmation, "mcmc_worker_plan.csv"),
    source_model_cell_plan_sha256 = file.path(paths$confirmation, "model_cell_plan.csv"),
    source_component_seed_plan_sha256 = file.path(paths$confirmation,
      "mcmc_component_seed_plan.csv"),
    source_score_contract_sha256 = file.path(paths$score, "score_contract.csv"),
    source_score_plan_sha256 = file.path(paths$score, "score_worker_plan.csv"),
    source_score_summary_sha256 = file.path(paths$score, "score_summary.csv"),
    source_mcmc_summary_sha256 = file.path(paths$score, "mcmc_worker_summary.csv"),
    source_oracle_manifest_sha256 = file.path(paths$score, "oracle_bank_manifest.csv"),
    source_score_final_manifest_sha256 = file.path(paths$score, "score_final_manifest.csv"),
    source_transfer_inventory_sha256 = paths$transfer_inventory,
    source_handoff_manifest_sha256 = paths$handoff_manifest,
    superfinal_plan_sha256 = file.path(paths$superfinal, "full_confirmation",
      "mcmc_worker_plan.csv"),
    superfinal_selected_packet_sha256 = file.path(paths$superfinal,
      "superfinal_selected_score_summary.csv"),
    superfinal_final_decision_sha256 = file.path(paths$superfinal, "final_decision.csv")
  )
  rows <- lapply(names(expected), function(name) {
    path <- expected[[name]]
    wanted <- app_joint_alkernel_value(contract, name)
    observed <- if (file.exists(path)) app_sha256_file(path) else NA_character_
    data.frame(contract_field = name, absolute_path = path,
      expected_sha256 = wanted, observed_sha256 = observed,
      verified = identical(tolower(observed), tolower(wanted)), stringsAsFactors = FALSE)
  })
  out <- app_bind_rows_fill(rows)
  if (!all(out$verified)) stop("Frozen AL-kernel source inventory does not verify.", call. = FALSE)
  out
}

app_joint_alkernel_copy <- function(source, target) {
  if (!file.exists(source) && !dir.exists(source)) {
    stop(sprintf("Copy source does not exist: %s", source), call. = FALSE)
  }
  app_ensure_dir(dirname(target))
  status <- system2("/bin/cp", c("-a", "--reflink=auto", source, target),
    stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(status, "status")) && attr(status, "status") != 0L) {
    stop(sprintf("Could not copy %s: %s", source, paste(status, collapse = "\n")), call. = FALSE)
  }
  target
}

app_joint_alkernel_worker_files <- function(worker) {
  paths <- list.files(worker, full.names = TRUE, recursive = FALSE)
  paths <- paths[file.info(paths)$isdir %in% FALSE]
  paths <- paths[!basename(paths) %in% c("DONE", "FAILED", "artifact_manifest.csv")]
  stats::setNames(paths, make.unique(basename(paths)))
}

app_joint_alkernel_attest_exal <- function(source_root, root, row) {
  source_worker <- app_joint_swcf_worker_dir(source_root, "mcmc", row$worker_id[[1L]])
  target_worker <- app_joint_swcf_worker_dir(root, "mcmc", row$worker_id[[1L]])
  source_verified <- app_joint_shared_verify_manifest(source_worker,
    file.path(source_worker, "artifact_manifest.csv"))
  if (!nrow(source_verified) || any(!source_verified$verified) ||
      !file.exists(file.path(source_worker, "DONE"))) {
    stop(sprintf("Source exact-M0 worker %d is not verified.", row$worker_id[[1L]]), call. = FALSE)
  }
  source_manifest_sha <- app_sha256_file(file.path(source_worker, "artifact_manifest.csv"))
  source_draw_sha <- app_sha256_file(file.path(source_worker, "posterior_draws.csv.gz"))
  if (dir.exists(target_worker)) unlink(target_worker, recursive = TRUE, force = TRUE)
  app_joint_alkernel_copy(source_worker, target_worker)
  summary_path <- file.path(target_worker, "summary.csv")
  summary <- app_read_csv(summary_path)
  design <- readRDS(row$design_path[[1L]])
  packet <- readRDS(row$vb_packet_path[[1L]])
  target <- app_joint_swcf_complete_target(row$model_id[[1L]], design,
    packet$normal, row$rhs_tau0[[1L]])
  sampler <- app_joint_swcf_sampler_control_contract(row$model_id[[1L]],
    row$n_iter[[1L]], row$burn[[1L]], row$thin[[1L]])
  if (summary$likelihood_family[[1L]] != "exAL" ||
      summary$inference_method_id[[1L]] != app_joint_alkernel_value(
        app_joint_alkernel_contract(), "exal_method")) {
    stop("Only frozen exact-M0 exAL workers may be attested without refitting.", call. = FALSE)
  }
  summary$complete_posterior_target_sha256 <- target$hash
  summary$effective_sampler_control_sha256 <- sampler$hash
  summary$sigma_support <- "(0,Inf)"
  summary$sigma_update_id <- "exact_M0_v_collapsed_scale_shape"
  app_write_csv(summary, summary_path)
  app_write_csv(target$fields, file.path(target_worker,
    "complete_posterior_target_contract.csv"))
  app_write_csv(sampler$fields, file.path(target_worker,
    "effective_sampler_control_contract.csv"))
  files <- app_joint_alkernel_worker_files(target_worker)
  app_joint_shared_write_manifest(target_worker, files)
  verified <- app_joint_shared_verify_manifest(target_worker,
    file.path(target_worker, "artifact_manifest.csv"))
  if (any(!verified$verified) ||
      app_sha256_file(file.path(target_worker, "posterior_draws.csv.gz")) != source_draw_sha) {
    stop("Attested exact-M0 worker differs from its frozen posterior draws.", call. = FALSE)
  }
  data.frame(worker_id = row$worker_id, model_cell_id = row$model_cell_id,
    chain_id = row$chain_id, source_manifest_sha256 = source_manifest_sha,
    posterior_draws_sha256 = source_draw_sha,
    complete_posterior_target_sha256 = target$hash,
    effective_sampler_control_sha256 = sampler$hash,
    attestation = "unchanged_exact_M0_draws_complete_identity_added",
    stringsAsFactors = FALSE)
}

app_joint_alkernel_prepare <- function(source_root, superfinal_root,
    root = app_joint_alkernel_default_root()) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  superfinal_root <- normalizePath(superfinal_root, mustWork = TRUE)
  if (dir.exists(root) && length(list.files(root, all.files = TRUE,
      no.. = TRUE))) stop("AL-kernel rerun root must be new and empty.", call. = FALSE)
  root <- normalizePath(app_ensure_dir(root), mustWork = TRUE)
  contract <- app_joint_alkernel_contract()
  binding <- app_joint_alkernel_source_inventory(source_root, superfinal_root, contract)
  source_paths <- app_joint_alkernel_paths(source_root, superfinal_root)
  source_plan <- app_read_csv(file.path(source_paths$confirmation, "mcmc_worker_plan.csv"))
  if (nrow(source_plan) != 192L || sum(source_plan$likelihood_family == "AL") != 96L ||
      sum(source_plan$likelihood_family == "exAL") != 96L) {
    stop("Frozen source does not contain the expected balanced 192-worker plan.", call. = FALSE)
  }
  sf_plan <- app_read_csv(file.path(superfinal_root, "full_confirmation", "mcmc_worker_plan.csv"))
  if (sum(sf_plan$likelihood_family == "exAL") != 10L ||
      sum(sf_plan$likelihood_family == "AL") != 5L) {
    stop("Frozen super-final supplemental plan is malformed.", call. = FALSE)
  }
  confirmation <- file.path(root, "full_confirmation")
  app_ensure_dir(file.path(confirmation, "mcmc_workers"))
  metadata <- c("mcmc_worker_plan.csv", "model_cell_plan.csv",
    "mcmc_component_seed_plan.csv", "article_fixture_manifest.csv",
    "confirmation_contract.csv")
  for (name in metadata) app_joint_alkernel_copy(
    file.path(source_paths$confirmation, name), file.path(confirmation, name))
  al_plan <- source_plan[source_plan$likelihood_family == "AL", , drop = FALSE]
  exal_plan <- source_plan[source_plan$likelihood_family == "exAL", , drop = FALSE]
  al_plan_path <- app_write_csv(al_plan, file.path(confirmation, "al_mcmc_rerun_plan.csv"))
  attestations <- app_bind_rows_fill(lapply(seq_len(nrow(exal_plan)), function(i) {
    app_joint_alkernel_attest_exal(source_root, root, exal_plan[i, , drop = FALSE])
  }))
  attestation_path <- app_write_csv(attestations,
    file.path(confirmation, "exal_reuse_attestation.csv"))

  source_score <- source_paths$score
  target_score <- file.path(confirmation, "score_packet")
  app_ensure_dir(file.path(target_score, "cells"))
  for (name in c("score_contract.csv", "score_worker_plan.csv",
      "oracle_bank_manifest.csv", "oracle_diagnostics.csv",
      "oracle_final_manifest.csv", "score_launch_readiness.csv",
      "oracle_worker_plan.csv")) {
    app_joint_alkernel_copy(file.path(source_score, name), file.path(target_score, name))
  }
  app_joint_alkernel_copy(file.path(source_score, "oracle_banks"),
    file.path(target_score, "oracle_banks"))
  score_plan <- app_read_csv(file.path(source_score, "score_worker_plan.csv"))
  rerun <- score_plan$inference_method == "mcmc" & score_plan$likelihood_family == "AL"
  if (sum(rerun) != 32L || sum(!rerun) != 96L) {
    stop("Frozen protected score plan is not the expected 32/96 partition.", call. = FALSE)
  }
  reused_rows <- list()
  for (id in score_plan$score_worker_id[!rerun]) {
    source_cell <- app_joint_swscore_cell_dir(source_root, id)
    verified <- app_joint_shared_verify_manifest(source_cell,
      file.path(source_cell, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified) ||
        !file.exists(file.path(source_cell, "DONE"))) {
      stop(sprintf("Reusable score worker %d is not verified.", id), call. = FALSE)
    }
    target_cell <- app_joint_swscore_cell_dir(root, id)
    app_joint_alkernel_copy(source_cell, target_cell)
    reused_rows[[length(reused_rows) + 1L]] <- data.frame(score_worker_id = id,
      source_manifest_sha256 = app_sha256_file(file.path(source_cell,
        "artifact_manifest.csv")), stringsAsFactors = FALSE)
  }
  score_plan_path <- app_write_csv(score_plan[rerun, , drop = FALSE],
    file.path(target_score, "al_score_rerun_plan.csv"))
  reused_score_path <- app_write_csv(app_bind_rows_fill(reused_rows),
    file.path(target_score, "reused_score_cell_attestation.csv"))
  contract_path <- app_write_csv(contract, file.path(root, "rerun_contract.csv"))
  binding_path <- app_write_csv(binding, file.path(root, "source_binding.csv"))
  readiness <- data.frame(status = "CORRECTED_AL_MCMC_READY",
    mandatory_al_workers = nrow(al_plan), reused_exact_m0_exal_workers = nrow(exal_plan),
    al_score_cells = sum(rerun), reused_score_cells = sum(!rerun),
    production_launched = FALSE, article_assets_modified = FALSE,
    stringsAsFactors = FALSE)
  readiness_path <- app_write_csv(readiness, file.path(root, "readiness.csv"))
  app_joint_shared_write_manifest(root, c(contract = contract_path,
    binding = binding_path, al_plan = al_plan_path,
    exal_attestation = attestation_path, score_plan = score_plan_path,
    reused_scores = reused_score_path, readiness = readiness_path),
    filename = "prepare_manifest.csv")
  readiness
}

app_joint_alkernel_health <- function(root = app_joint_alkernel_default_root(),
    stage = c("mcmc", "score")) {
  stage <- match.arg(stage)
  if (stage == "mcmc") {
    plan <- app_read_csv(file.path(root, "full_confirmation", "al_mcmc_rerun_plan.csv"))
    dirs <- vapply(plan$worker_id, function(id) app_joint_swcf_worker_dir(root,
      "mcmc", id), character(1L))
  } else {
    plan <- app_read_csv(file.path(root, "full_confirmation", "score_packet",
      "al_score_rerun_plan.csv"))
    dirs <- vapply(plan$score_worker_id, function(id) app_joint_swscore_cell_dir(root,
      id), character(1L))
  }
  done <- file.exists(file.path(dirs, "DONE")); failed <- file.exists(file.path(dirs, "FAILED"))
  data.frame(stage = stage, expected = nrow(plan), completed = sum(done),
    failed = sum(failed), remaining = sum(!done & !failed), stringsAsFactors = FALSE)
}

app_joint_alkernel_run_mcmc <- function(root, worker_id) {
  plan <- app_read_csv(file.path(root, "full_confirmation", "al_mcmc_rerun_plan.csv"))
  row <- plan[plan$worker_id == as.integer(worker_id), , drop = FALSE]
  if (nrow(row) != 1L || row$likelihood_family[[1L]] != "AL") {
    stop("Corrected replacement worker must be one frozen AL chain.", call. = FALSE)
  }
  app_joint_swcf_run_mcmc(root, worker_id)
}

app_joint_alkernel_finalize_mcmc <- function(root = app_joint_alkernel_default_root()) {
  root <- normalizePath(root, mustWork = TRUE)
  health <- app_joint_alkernel_health(root, "mcmc")
  if (health$completed != health$expected || health$failed != 0L) {
    stop("Corrected AL replacement is incomplete.", call. = FALSE)
  }
  confirmation <- file.path(root, "full_confirmation")
  plan <- app_read_csv(file.path(confirmation, "mcmc_worker_plan.csv"))
  summaries <- lapply(plan$worker_id, function(id) {
    worker <- app_joint_swcf_worker_dir(root, "mcmc", id)
    verified <- app_joint_shared_verify_manifest(worker,
      file.path(worker, "artifact_manifest.csv"))
    if (!nrow(verified) || any(!verified$verified) ||
        !file.exists(file.path(worker, "DONE"))) {
      stop(sprintf("Combined MCMC worker %d is not verified.", id), call. = FALSE)
    }
    app_read_csv(file.path(worker, "summary.csv"))
  })
  summary <- app_bind_rows_fill(summaries)
  if (nrow(summary) != 192L || any(!summary$finite_draws) ||
      sum(summary$likelihood_family == "AL") != 96L ||
      any(summary$likelihood_family == "AL" &
        (summary$sigma_update_id != "direct_inverse_gamma_unbounded_v1" |
         summary$sigma_support != "(0,Inf)")) ||
      any(summary$likelihood_family == "exAL" &
        summary$inference_method_id != "M0_v_collapsed_support_logit")) {
    stop("Corrected combined MCMC summary violates its frozen contract.", call. = FALSE)
  }
  identity <- app_joint_swcf_chain_identity_audit(summary, expected_chains = 3L)
  summary_path <- app_write_csv(summary, file.path(confirmation,
    "corrected_mcmc_worker_summary.csv"))
  identity_path <- app_write_csv(identity, file.path(confirmation,
    "corrected_chain_identity_audit.csv"))
  readiness <- data.frame(status = "CORRECTED_AL_MCMC_COMPLETE_SCORE_READY",
    workers = nrow(summary), al_workers_replaced = sum(summary$likelihood_family == "AL"),
    exal_workers_reused = sum(summary$likelihood_family == "exAL"),
    incompatible_cells = sum(!identity$verified), stringsAsFactors = FALSE)
  readiness_path <- app_write_csv(readiness, file.path(confirmation,
    "corrected_mcmc_readiness.csv"))
  app_joint_shared_write_manifest(confirmation, c(summary = summary_path,
    identities = identity_path, readiness = readiness_path),
    filename = "corrected_mcmc_final_manifest.csv")
  readiness
}

app_joint_alkernel_run_score <- function(root, score_worker_id) {
  plan <- app_read_csv(file.path(root, "full_confirmation", "score_packet",
    "al_score_rerun_plan.csv"))
  row <- plan[plan$score_worker_id == as.integer(score_worker_id), , drop = FALSE]
  if (nrow(row) != 1L || row$likelihood_family[[1L]] != "AL" ||
      row$inference_method[[1L]] != "mcmc") {
    stop("Corrected score worker must be one frozen MCMC-AL cell.", call. = FALSE)
  }
  app_joint_swscore_run_cell(root, score_worker_id)
}

app_joint_alkernel_selected_packet <- function(root, superfinal_root) {
  score_root <- app_joint_swscore_root(root)
  summary <- app_read_csv(file.path(score_root, "score_summary.csv"))
  decisions <- app_read_csv(file.path(score_root, "scenario_packet_decisions.csv"))
  mcmc <- summary[summary$inference_method == "mcmc", , drop = FALSE]
  selected <- merge(mcmc, decisions[, c("scenario_id",
    "promote_complete_challenger_packet")], by = "scenario_id")
  selected <- selected[(selected$promote_complete_challenger_packet &
    selected$specification_role == "challenger") |
    (!selected$promote_complete_challenger_packet &
    selected$specification_role == "new_geometry_parity"), , drop = FALSE]
  supplemental <- app_read_csv(file.path(superfinal_root, "supplemental_score_summary.csv"))
  laplace <- supplemental[supplemental$target_id == 1L, , drop = FALSE]
  persistent_exal <- supplemental[supplemental$target_id == 3L, , drop = FALSE]
  if (nrow(laplace) != 1L || !isTRUE(laplace$stable[[1L]]) ||
      nrow(persistent_exal) != 1L) {
    stop("Frozen exact-M0 supplemental evidence is incomplete.", call. = FALSE)
  }
  replace_common <- function(packet, replacement) {
    key <- packet$scenario_id == replacement$scenario_id[[1L]] &
      packet$model_id == replacement$model_id[[1L]]
    common <- intersect(names(packet), names(replacement))
    packet[key, common] <- replacement[1L, common]
    packet
  }
  selected <- replace_common(selected, laplace)
  persistent_requires_parity <- !isTRUE(persistent_exal$stable[[1L]])
  if (persistent_requires_parity) {
    selected <- selected[selected$scenario_id != "persistent_heavy_tail", , drop = FALSE]
    parity <- mcmc[mcmc$scenario_id == "persistent_heavy_tail" &
      mcmc$specification_role == "new_geometry_parity", , drop = FALSE]
    if (nrow(parity) != 4L || anyDuplicated(parity$model_id)) {
      stop("Persistent-tail parity fallback is not a complete four-model packet.", call. = FALSE)
    }
    parity$promote_complete_challenger_packet <- FALSE
    selected <- app_bind_rows_fill(list(selected, parity))
  }
  selected <- selected[order(selected$scenario_id, selected$model_id), , drop = FALSE]
  key <- paste(selected$scenario_id, selected$model_id, sep = "__")
  counts <- table(selected$scenario_id)
  if (nrow(selected) != 32L || anyDuplicated(key) || length(counts) != 8L ||
      any(counts != 4L) || any(!is.finite(selected$posterior_score_mean)) ||
      any(selected$canonical_contract_crossing_pairs != 0L)) {
    stop("Corrected selected packet is incomplete or invalid.", call. = FALSE)
  }
  list(packet = selected, persistent_exal_stable = isTRUE(persistent_exal$stable[[1L]]),
    al_supplement_required = !persistent_requires_parity &&
      any(selected$scenario_id == "persistent_heavy_tail" &
        selected$model_id == "joint_qdesn_rhs" &
        selected$specification_role == "challenger"))
}

app_joint_alkernel_finalize_score <- function(source_root, superfinal_root,
    root = app_joint_alkernel_default_root()) {
  root <- normalizePath(root, mustWork = TRUE)
  source_root <- normalizePath(source_root, mustWork = TRUE)
  superfinal_root <- normalizePath(superfinal_root, mustWork = TRUE)
  health <- app_joint_alkernel_health(root, "score")
  if (health$completed != health$expected || health$failed != 0L) {
    stop("Corrected AL score replacement is incomplete.", call. = FALSE)
  }
  base <- app_joint_swscore_finalize(root)
  score_root <- app_joint_swscore_root(root)
  current <- app_read_csv(file.path(score_root, "score_summary.csv"))
  historical <- app_read_csv(file.path(source_root, "full_confirmation",
    "score_packet", "score_summary.csv"))
  key <- c("scenario_id", "specification_role", "model_id", "inference_method")
  joined <- merge(current, historical, by = key, suffixes = c("_corrected", "_historical"))
  al <- joined$likelihood_family_corrected == "AL" & joined$inference_method == "mcmc"
  comparison <- joined[al, c(key, "posterior_score_mean_corrected",
    "posterior_score_mean_historical", "posterior_score_q025_corrected",
    "posterior_score_q975_corrected", "posterior_score_q025_historical",
    "posterior_score_q975_historical", "posterior_score_interval_width_corrected",
    "posterior_score_interval_width_historical", "canonical_origin_marginal_dgp_integrated_acrps_corrected",
    "canonical_origin_marginal_dgp_integrated_acrps_historical"), drop = FALSE]
  comparison$mean_score_change <- comparison$posterior_score_mean_corrected -
    comparison$posterior_score_mean_historical
  comparison$interval_width_ratio <- comparison$posterior_score_interval_width_corrected /
    comparison$posterior_score_interval_width_historical
  comparison_path <- app_write_csv(comparison, file.path(score_root,
    "corrected_vs_historical_al.csv"))
  unchanged_columns <- intersect(names(current), names(historical))
  corrected_al_keys <- do.call(paste, c(joined[al, key], sep = "__"))
  historical_keys <- do.call(paste, c(historical[key], sep = "__"))
  current_keys <- do.call(paste, c(current[key], sep = "__"))
  historical_keep <- !historical_keys %in% corrected_al_keys
  current_u <- current[match(historical_keys[historical_keep], current_keys),
    unchanged_columns, drop = FALSE]
  historical_u <- historical[historical_keep, unchanged_columns, drop = FALSE]
  if (!identical(current_u, historical_u)) {
    stop("A score row outside the 32 declared MCMC-AL replacements changed.", call. = FALSE)
  }
  packet <- app_joint_alkernel_selected_packet(root, superfinal_root)
  packet_path <- app_write_csv(packet$packet, file.path(root,
    "corrected_superfinal_selected_score_summary.csv"))
  supplemental <- data.frame(
    target = "persistent_heavy_tail__challenger__joint_qdesn_rhs",
    exact_m0_counterpart_stable = packet$persistent_exal_stable,
    al_supplement_required = packet$al_supplement_required,
    al_supplement_launched = FALSE,
    decision = if (packet$al_supplement_required) "REQUIRES_CONDITIONAL_AL_SUPPLEMENT" else
      "SKIP_AL_SUPPLEMENT_COMPLETE_PACKET_INELIGIBLE",
    reason = if (packet$al_supplement_required) "complete challenger packet remains eligible" else
      "unchanged exact-M0 joint-exAL challenger remains unstable; whole-scenario parity fallback applies",
    stringsAsFactors = FALSE)
  supplemental_path <- app_write_csv(supplemental, file.path(root,
    "conditional_al_supplement_decision.csv"))
  ready <- !packet$al_supplement_required
  final <- data.frame(status = if (ready)
      "CORRECTED_SUPERFINAL_PACKET_READY_FOR_FINAL_VERIFICATION" else
      "CONDITIONAL_AL_SUPPLEMENT_REQUIRED",
    score_rows = nrow(current), corrected_al_score_rows = nrow(comparison),
    selected_rows = nrow(packet$packet), exal_refits = 0L,
    conditional_al_supplement_launched = FALSE,
    article_assets_modified = FALSE, stringsAsFactors = FALSE)
  final_path <- app_write_csv(final, file.path(root, "final_decision.csv"))
  app_joint_shared_write_manifest(root, c(comparison = comparison_path,
    packet = packet_path, supplement = supplemental_path, final = final_path),
    filename = "final_manifest.csv")
  final
}
