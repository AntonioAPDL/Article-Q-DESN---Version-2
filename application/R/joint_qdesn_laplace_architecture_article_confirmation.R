# Matched article-fixture confirmation for the selected Laplace Bridge architecture.

app_joint_laplace_article_contract_path <- function() {
  app_path("application/config/joint_qdesn_laplace_architecture_article_confirmation_contract_v1.csv")
}

app_joint_laplace_article_contract <- function(path = app_joint_laplace_article_contract_path()) {
  tab <- app_read_csv(path)
  if (anyDuplicated(tab$name)) stop("Duplicate article-confirmation contract keys.", call. = FALSE)
  out <- as.list(setNames(as.character(tab$value), tab$name))
  numeric_keys <- c(
    "article_fixture_size_bytes", "article_design_size_bytes", "article_seed",
    "article_oracle_size_bytes", "article_replicates", "article_chains",
    "article_al_iterations", "article_al_burn", "article_exal_iterations",
    "article_exal_burn", "article_thin", "vb_max_iterations", "state_draws_per_chain",
    "score_chunk_size", "functional_review_rhat",
    "functional_review_relative_difference", "predictive_pathology_rhat",
    "predictive_pathology_relative_difference", "selection_epsilon",
    "max_workers", "min_free_gib", "chain_seed_base",
    "initialization_seed_base", "score_seed_base"
  )
  for (key in numeric_keys) out[[key]] <- as.numeric(out[[key]])
  out$tau <- c(.05, .10, .25, .50, .75, .90, .95)
  out$weights <- c(.025, .10, .20, .25, .20, .10, .025)
  stopifnot(
    out$version == "joint_laplace_architecture_article_confirmation_v1",
    out$scenario == "laplace_bridge",
    out$baseline_architecture_id == "arch_00",
    out$candidate_architecture_id == "arch_02",
    out$article_replicates == 1, out$article_chains == 5,
    out$article_al_iterations == 4000, out$article_al_burn == 1000,
    out$article_exal_iterations == 8000, out$article_exal_burn == 2000,
    out$article_thin == 4, out$max_workers <= 15,
    out$exal_mcmc_method == "M0_v_collapsed_support_logit",
    out$exal_vb_method == "VB1_structured_v",
    out$primary_score == "dgp_integrated_acrps",
    out$article_fixture_used_for_selection == "false",
    out$mixing_gate_policy == "review_unless_predictive_pathology",
    out$publication_allowed == "false"
  )
  out
}

app_joint_laplace_article_assert_file <- function(path, sha256, size_bytes = NULL, label = basename(path)) {
  if (!file.exists(path)) stop(sprintf("Missing frozen %s: %s", label, path), call. = FALSE)
  observed_size <- file.info(path)$size
  observed_sha <- app_sha256_file(path)
  if ((!is.null(size_bytes) && observed_size != as.numeric(size_bytes)) ||
      !identical(tolower(observed_sha), tolower(as.character(sha256)))) {
    stop(sprintf("Frozen %s failed its byte/hash contract.", label), call. = FALSE)
  }
  data.frame(label = label, path = normalizePath(path), size_bytes = observed_size,
    sha256 = observed_sha, stringsAsFactors = FALSE)
}

app_joint_laplace_article_verify_manifest <- function(root, manifest, label) {
  checked <- app_joint_shared_verify_manifest(root, manifest)
  if (!nrow(checked) || any(!checked$verified)) {
    stop(sprintf("Frozen %s manifest does not verify.", label), call. = FALSE)
  }
  checked
}

app_joint_laplace_article_source_gate <- function(ct = app_joint_laplace_article_contract()) {
  architecture_root <- normalizePath(ct$source_architecture_runtime, mustWork = TRUE)
  authority_root <- normalizePath(ct$article_authority_runtime, mustWork = TRUE)
  score_root <- normalizePath(ct$score_authority_runtime, mustWork = TRUE)
  evidence <- list()
  add <- function(x) evidence[[length(evidence) + 1L]] <<- x

  add(app_joint_laplace_article_assert_file(file.path(architecture_root, "freeze_manifest.csv"),
    ct$source_freeze_manifest_sha256, label = "architecture freeze manifest"))
  add(app_joint_laplace_article_assert_file(file.path(architecture_root, "closeout", "artifact_manifest.csv"),
    ct$source_closeout_manifest_sha256, label = "architecture closeout manifest"))
  add(app_joint_laplace_article_assert_file(file.path(architecture_root, "closeout", "decision.csv"),
    ct$source_decision_sha256, label = "architecture decision"))
  add(app_joint_laplace_article_assert_file(file.path(architecture_root, "closeout", "frozen_architectures.csv"),
    ct$source_architectures_sha256, label = "frozen architectures"))
  app_joint_laplace_article_verify_manifest(architecture_root,
    file.path(architecture_root, "freeze_manifest.csv"), "architecture freeze")
  app_joint_laplace_article_verify_manifest(file.path(architecture_root, "closeout"),
    file.path(architecture_root, "closeout", "artifact_manifest.csv"), "architecture closeout")
  terminal <- trimws(readLines(file.path(architecture_root, "COMPLETE"), warn = FALSE)[[1L]])
  source_head <- trimws(readLines(file.path(architecture_root, "source_head.txt"), warn = FALSE)[[1L]])
  if (terminal != ct$source_architecture_terminal || source_head != ct$source_architecture_head) {
    stop("Architecture runtime terminal or source HEAD changed.", call. = FALSE)
  }
  decision <- app_read_csv(file.path(architecture_root, "closeout", "decision.csv"))
  if (nrow(decision) != 1L || decision$architecture_id[[1L]] != ct$candidate_architecture_id ||
      !app_as_bool_vec(decision$eligible)[[1L]] ||
      decision$promotion_decision[[1L]] != "numerical_mean_improvement_ready_for_integration_review") {
    stop("Architecture runtime did not freeze the declared eligible candidate.", call. = FALSE)
  }
  architectures <- app_read_csv(file.path(architecture_root, "closeout", "frozen_architectures.csv"))
  keep <- architectures$architecture_id %in% c(ct$baseline_architecture_id, ct$candidate_architecture_id)
  if (sum(keep) != 2L || sum(app_as_bool_vec(architectures$baseline[keep])) != 1L) {
    stop("Baseline/candidate architecture pair is malformed.", call. = FALSE)
  }

  add(app_joint_laplace_article_assert_file(file.path(authority_root, "artifact_manifest.csv"),
    ct$article_authority_manifest_sha256, label = "article authority manifest"))
  add(app_joint_laplace_article_assert_file(file.path(authority_root, "fixture_manifest.csv"),
    ct$article_fixture_manifest_sha256, label = "article fixture manifest"))
  fixture_path <- file.path(authority_root, ct$article_fixture_relative_path)
  design_path <- file.path(authority_root, ct$article_design_relative_path)
  add(app_joint_laplace_article_assert_file(fixture_path, ct$article_fixture_sha256,
    ct$article_fixture_size_bytes, "Laplace article fixture"))
  add(app_joint_laplace_article_assert_file(design_path, ct$article_design_sha256,
    ct$article_design_size_bytes, "Laplace baseline design"))
  app_joint_laplace_article_verify_manifest(authority_root,
    file.path(authority_root, "artifact_manifest.csv"), "article authority")
  fixture_manifest <- app_read_csv(file.path(authority_root, "fixture_manifest.csv"))
  fixture_row <- fixture_manifest[fixture_manifest$scenario_id == ct$scenario, , drop = FALSE]
  if (nrow(fixture_row) != 1L || fixture_row$article_seed[[1L]] != ct$article_seed ||
      fixture_row$sha256[[1L]] != ct$article_fixture_sha256 ||
      app_as_bool_vec(fixture_row$article_fixture_used_for_selection)[[1L]]) {
    stop("Protected Laplace fixture identity changed or was used for selection.", call. = FALSE)
  }
  authority_status <- app_read_csv(file.path(authority_root, "final_confirmation_assessment.csv"))
  authority_git <- app_read_csv(file.path(authority_root, "execution_git_state.csv"))
  if (authority_status$status[[1L]] != "MCMC_COMPLETE_READY_FOR_SCORE_PACKET" ||
      authority_git$head[[1L]] != ct$article_authority_head) {
    stop("Current article authority is not the frozen completed source.", call. = FALSE)
  }

  add(app_joint_laplace_article_assert_file(file.path(score_root, "final_packet", "artifact_manifest.csv"),
    ct$score_packet_manifest_sha256, label = "score packet manifest"))
  add(app_joint_laplace_article_assert_file(file.path(score_root, "dgp_oracle_manifest.csv"),
    ct$dgp_oracle_manifest_sha256, label = "DGP oracle manifest"))
  oracle_path <- file.path(score_root, ct$article_oracle_relative_path)
  add(app_joint_laplace_article_assert_file(oracle_path, ct$article_oracle_sha256,
    ct$article_oracle_size_bytes, "Laplace DGP oracle bank"))
  app_joint_laplace_article_verify_manifest(file.path(score_root, "final_packet"),
    file.path(score_root, "final_packet", "artifact_manifest.csv"), "score packet")
  packet_status <- app_read_csv(file.path(score_root, "final_packet", "packet_status.csv"))
  oracle_manifest <- app_read_csv(file.path(score_root, "dgp_oracle_manifest.csv"))
  oracle_row <- oracle_manifest[oracle_manifest$scenario_id == ct$scenario, , drop = FALSE]
  if (packet_status$status[[1L]] != "COMPLETE_WITH_ONE_SCORE_STABILITY_REVIEW" ||
      nrow(oracle_row) != 1L || oracle_row$sha256[[1L]] != ct$article_oracle_sha256) {
    stop("Current score packet or Laplace oracle bank is not authoritative.", call. = FALSE)
  }
  list(evidence = do.call(rbind, evidence), architectures = architectures[keep, , drop = FALSE],
    fixture_path = fixture_path, design_path = design_path, oracle_path = oracle_path,
    architecture_root = architecture_root, authority_root = authority_root, score_root = score_root)
}

app_joint_laplace_article_plan <- function(ct, architectures) {
  datasets <- data.frame(
    architecture_id = c(ct$baseline_architecture_id, ct$candidate_architecture_id),
    scenario_id = ct$scenario, replicate_id = "article_fixture",
    dgp_seed = as.integer(ct$article_seed), dataset_id = 1:2,
    article_fixture_used_for_selection = FALSE, stringsAsFactors = FALSE
  )
  models <- data.frame(
    model_id = c("independent_qdesn_rhs", "joint_qdesn_rhs",
      "independent_exqdesn_rhs", "joint_exqdesn_rhs"),
    likelihood = c("AL", "AL", "exAL", "exAL"),
    structure = c("independent", "joint", "independent", "joint"),
    stringsAsFactors = FALSE
  )
  cells <- merge(datasets, models, by = NULL, sort = FALSE)
  cells <- cells[order(cells$dataset_id, match(cells$model_id, models$model_id)), , drop = FALSE]
  cells$arm_id <- cells$architecture_id
  cells$long_budget <- FALSE
  cells$cell_id <- seq_len(nrow(cells))
  jobs <- cells[rep(seq_len(nrow(cells)), each = as.integer(ct$article_chains)), , drop = FALSE]
  jobs$chain_id <- rep(seq_len(as.integer(ct$article_chains)), nrow(cells))
  jobs$worker_id <- seq_len(nrow(jobs))
  jobs$chain_seed <- as.integer(ct$chain_seed_base + jobs$worker_id * 1009L)
  jobs$start_seed <- as.integer(ct$initialization_seed_base + jobs$worker_id * 1009L)
  for (k in seq_along(ct$tau)) jobs[[paste0("component_seed_", k)]] <-
    as.integer(jobs$chain_seed + 100000L + k * 7919L)
  warmups <- datasets[c("dataset_id", "architecture_id")]
  warmups$arm_id <- warmups$architecture_id
  warmups$worker_id <- seq_len(nrow(warmups))
  stopifnot(nrow(datasets) == 2L, nrow(cells) == 8L, nrow(jobs) == 40L,
    nrow(warmups) == 2L, !anyDuplicated(jobs$chain_seed), !anyDuplicated(jobs$start_seed),
    setequal(datasets$architecture_id, architectures$architecture_id))
  list(datasets = datasets, cells = cells, chains = jobs, warmups = warmups)
}

app_joint_laplace_article_prepare <- function(root, ct = app_joint_laplace_article_contract()) {
  if (dir.exists(root)) stop("Article confirmation root already exists.", call. = FALSE)
  gate <- app_joint_laplace_article_source_gate(ct)
  app_ensure_dir(root)
  input_dir <- file.path(root, "frozen_inputs"); evidence_dir <- file.path(root, "source_evidence")
  article_dir <- file.path(root, "article")
  app_ensure_dir(input_dir); app_ensure_dir(evidence_dir); app_ensure_dir(article_dir)
  copies <- c(
    architectures = file.path(gate$architecture_root, "closeout", "frozen_architectures.csv"),
    architecture_decision = file.path(gate$architecture_root, "closeout", "decision.csv"),
    architecture_freeze_manifest = file.path(gate$architecture_root, "freeze_manifest.csv"),
    architecture_closeout_manifest = file.path(gate$architecture_root, "closeout", "artifact_manifest.csv"),
    fixture_manifest = file.path(gate$authority_root, "fixture_manifest.csv"),
    authority_manifest = file.path(gate$authority_root, "artifact_manifest.csv"),
    authority_status = file.path(gate$authority_root, "final_confirmation_assessment.csv"),
    dgp_oracle_manifest = file.path(gate$score_root, "dgp_oracle_manifest.csv"),
    score_packet_manifest = file.path(gate$score_root, "final_packet", "artifact_manifest.csv"),
    score_packet_status = file.path(gate$score_root, "final_packet", "packet_status.csv")
  )
  # Preserve readable names while avoiding dependencies on external runtime paths.
  destinations <- file.path(evidence_dir, basename(copies))
  duplicated_names <- duplicated(basename(copies)) | duplicated(basename(copies), fromLast = TRUE)
  destinations[duplicated_names] <- file.path(evidence_dir,
    paste0(names(copies)[duplicated_names], "_", basename(copies[duplicated_names])))
  if (!all(file.copy(copies, destinations, overwrite = FALSE, copy.mode = TRUE))) {
    stop("Could not copy frozen source evidence.", call. = FALSE)
  }
  fixture_copy <- file.path(input_dir, "laplace_article_fixture.rds")
  design_copy <- file.path(input_dir, "laplace_baseline_design.rds")
  oracle_copy <- file.path(input_dir, "laplace_dgp_oracle.rds")
  if (!file.copy(gate$fixture_path, fixture_copy) || !file.copy(gate$design_path, design_copy) ||
      !file.copy(gate$oracle_path, oracle_copy)) stop("Could not copy frozen article inputs.", call. = FALSE)
  app_joint_laplace_article_assert_file(fixture_copy, ct$article_fixture_sha256,
    ct$article_fixture_size_bytes, "copied Laplace article fixture")
  app_joint_laplace_article_assert_file(design_copy, ct$article_design_sha256,
    ct$article_design_size_bytes, "copied Laplace baseline design")
  app_joint_laplace_article_assert_file(oracle_copy, ct$article_oracle_sha256,
    ct$article_oracle_size_bytes, "copied Laplace DGP oracle")

  architectures <- gate$architectures[match(c(ct$baseline_architecture_id,
    ct$candidate_architecture_id), gate$architectures$architecture_id), , drop = FALSE]
  app_write_csv(architectures, file.path(root, "architectures.csv"))
  saveRDS(ct, file.path(root, "contract.rds"))
  source_snapshot <- gate$evidence
  source_snapshot$copied_for_freeze <- TRUE
  app_write_csv(source_snapshot, file.path(root, "source_snapshot.csv"))
  app_write_csv(data.frame(status = "PASS", scenario_id = ct$scenario,
    baseline_architecture_id = ct$baseline_architecture_id,
    candidate_architecture_id = ct$candidate_architecture_id,
    article_seed = ct$article_seed, protected_rows_used_for_selection = 0L,
    article_fixture_used_for_selection = FALSE, stringsAsFactors = FALSE),
    file.path(root, "source_gate.csv"))
  git_value <- function(args) {
    out <- suppressWarnings(system2("git", args, stdout = TRUE, stderr = FALSE))
    if (length(out)) out[[1L]] else NA_character_
  }
  git_state <- data.frame(branch = git_value(c("branch", "--show-current")),
    head = git_value(c("rev-parse", "HEAD")), upstream = git_value(c("rev-parse", "@{upstream}")),
    stringsAsFactors = FALSE)
  app_write_csv(git_state, file.path(root, "execution_git_state.csv"))
  plan <- app_joint_laplace_article_plan(ct, architectures)
  for (name in names(plan)) app_write_csv(plan[[name]], file.path(article_dir, paste0(name, ".csv")))
  app_joint_shared_write_manifest(article_dir,
    setNames(file.path(article_dir, paste0(names(plan), ".csv")), paste0(names(plan), ".csv")),
    filename = "plan_manifest.csv")
  freeze_files <- c(
    contract = file.path(root, "contract.rds"), architectures = file.path(root, "architectures.csv"),
    source_snapshot = file.path(root, "source_snapshot.csv"), source_gate = file.path(root, "source_gate.csv"),
    execution_git_state = file.path(root, "execution_git_state.csv"),
    fixture = fixture_copy, baseline_design = design_copy, oracle = oracle_copy,
    article_plan = file.path(article_dir, "plan_manifest.csv"),
    setNames(destinations, paste0("evidence_", names(copies)))
  )
  app_joint_shared_write_manifest(root, freeze_files, filename = "freeze_manifest.csv")
  writeLines("PREPARED_NO_MODEL_WORK_STARTED", file.path(root, "PREPARED"))
  invisible(plan)
}

app_joint_laplace_article_verify_freeze <- function(root, verify_large_inputs = TRUE) {
  checked <- app_joint_shared_verify_manifest(root, file.path(root, "freeze_manifest.csv"))
  if (!nrow(checked) || any(!checked$verified)) stop("Article confirmation freeze changed.", call. = FALSE)
  plan <- app_joint_shared_verify_manifest(file.path(root, "article"),
    file.path(root, "article", "plan_manifest.csv"))
  if (!nrow(plan) || any(!plan$verified)) stop("Article execution plan changed.", call. = FALSE)
  ct <- readRDS(file.path(root, "contract.rds"))
  if (verify_large_inputs) {
    app_joint_laplace_article_assert_file(file.path(root, "frozen_inputs", "laplace_article_fixture.rds"),
      ct$article_fixture_sha256, ct$article_fixture_size_bytes, "local Laplace article fixture")
    app_joint_laplace_article_assert_file(file.path(root, "frozen_inputs", "laplace_baseline_design.rds"),
      ct$article_design_sha256, ct$article_design_size_bytes, "local Laplace baseline design")
    app_joint_laplace_article_assert_file(file.path(root, "frozen_inputs", "laplace_dgp_oracle.rds"),
      ct$article_oracle_sha256, ct$article_oracle_size_bytes, "local Laplace DGP oracle")
  }
  invisible(TRUE)
}

app_joint_laplace_article_design_parity <- function(observed, expected) {
  fields <- c("y", "Z", "fit_local", "validation_local", "forecast_map", "tau", "true_q",
    "raw_inputs_in_readout", "full_states_all_layers")
  available <- fields[fields %in% names(observed) & fields %in% names(expected)]
  checks <- vapply(available, function(name) isTRUE(all.equal(observed[[name]], expected[[name]],
    tolerance = 0, check.attributes = TRUE)), logical(1L))
  data.frame(field = available, identical = checks, stringsAsFactors = FALSE)
}

app_joint_laplace_article_context <- function(root, dataset_id) {
  row <- app_read_csv(file.path(root, "article", "datasets.csv"))[dataset_id, , drop = FALSE]
  ct <- readRDS(file.path(root, "contract.rds"))
  selected <- app_joint_arch_selected(root, row$architecture_id)
  fixture <- readRDS(file.path(root, "frozen_inputs", "laplace_article_fixture.rds"))
  design <- app_joint_arch_full_design(fixture, selected)
  oracle <- readRDS(file.path(root, "frozen_inputs", "laplace_dgp_oracle.rds"))
  if (!identical(as.character(oracle$scenario_id), ct$scenario) ||
      !isTRUE(all.equal(oracle$forecast_map, design$forecast_map, tolerance = 0)) ||
      !isTRUE(all.equal(oracle$tau, ct$tau, tolerance = 0)) ||
      !isTRUE(all.equal(oracle$weights, ct$weights, tolerance = 0)) ||
      oracle$diagnostics$status[[1L]] != "pass") {
    stop("Frozen Laplace oracle is incompatible with the rebuilt design.", call. = FALSE)
  }
  vc <- app_joint_arch_vb_contract(ct)
  vc$max_dense_dim <- max(300L, ncol(design$Z) * length(design$tau))
  context <- list(ct = ct, vc = vc, selected = selected, design = design, fixture = fixture,
    data_hash = digest::digest(list(y = design$y[design$fit_local],
      Z = design$Z[design$fit_local, , drop = FALSE]), algo = "sha256"))
  scratch <- tempfile("joint_laplace_article_vb_")
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
  fits <- app_joint_arch_nested_vb(context, scratch)
  context$gaussian <- fits$gaussian
  context$independent_al <- fits$independent_al
  context$independent_exal <- fits$independent_exal
  context$joint <- list(AL = fits$joint_al, exAL = fits$joint_exal)
  list(context = context, oracle = oracle)
}

app_joint_laplace_article_dataset <- function(root, dataset_id) {
  app_joint_laplace_article_verify_freeze(root, verify_large_inputs = TRUE)
  ct <- readRDS(file.path(root, "contract.rds"))
  row <- app_read_csv(file.path(root, "article", "datasets.csv"))[dataset_id, , drop = FALSE]
  folder <- file.path(root, "article", "datasets", sprintf("dataset_%02d", dataset_id))
  app_ensure_dir(folder)
  built <- app_joint_laplace_article_context(root, dataset_id)
  parity <- if (row$architecture_id[[1L]] == ct$baseline_architecture_id) {
    app_joint_laplace_article_design_parity(built$context$design,
      readRDS(file.path(root, "frozen_inputs", "laplace_baseline_design.rds")))
  } else data.frame(field = "candidate_not_applicable", identical = TRUE, stringsAsFactors = FALSE)
  if (any(!parity$identical)) stop("Baseline design failed exact article-authority parity.", call. = FALSE)
  saveRDS(built$context, file.path(folder, "context.rds"))
  saveRDS(built$oracle, file.path(folder, "oracle.rds"))
  app_write_csv(built$oracle$diagnostics, file.path(folder, "oracle_diagnostics.csv"))
  app_write_csv(parity, file.path(folder, "design_parity.csv"))
  app_joint_shared_write_manifest(folder, c(context = file.path(folder, "context.rds"),
    oracle = file.path(folder, "oracle.rds"), diagnostics = file.path(folder, "oracle_diagnostics.csv"),
    design_parity = file.path(folder, "design_parity.csv")), filename = "component_manifest.csv")
  app_joint_arch_seal(folder)
}

app_joint_laplace_article_model_id <- function(rows) {
  ifelse(rows$structure == "joint", ifelse(rows$likelihood == "AL", "joint_qdesn_rhs",
    "joint_exqdesn_rhs"), ifelse(rows$likelihood == "AL", "independent_qdesn_rhs",
      "independent_exqdesn_rhs"))
}

app_joint_laplace_article_comparison <- function(rows, baseline, candidate) {
  aggregate <- do.call(rbind, lapply(split(rows, list(rows$architecture_id, rows$model_id), drop = TRUE),
    function(x) data.frame(architecture_id = x$architecture_id[[1L]], model_id = x$model_id[[1L]],
      score_mean = mean(x$posterior_score_mean), score_median = mean(x$posterior_score_median),
      score_q025 = mean(x$posterior_score_q025), score_q975 = mean(x$posterior_score_q975),
      interval_width = mean(x$posterior_score_interval_width), fit_oracle_mae = mean(x$fit_oracle_mae),
      raw_crossing_pairs = sum(x$raw_crossing_pairs), contract_crossing_pairs = sum(x$contract_crossing_pairs),
      functional_reviews = sum(x$functional_status != "pass"), stringsAsFactors = FALSE)))
  base <- aggregate[aggregate$architecture_id == baseline, ]
  cand <- aggregate[aggregate$architecture_id == candidate, ]
  paired <- merge(cand, base, by = "model_id", suffixes = c("_candidate", "_baseline"), sort = FALSE)
  paired$score_difference <- paired$score_mean_candidate - paired$score_mean_baseline
  paired$score_relative <- paired$score_mean_candidate / paired$score_mean_baseline
  paired$score_gain_percent <- 100 * (1 - paired$score_relative)
  paired$interval_width_relative <- paired$interval_width_candidate / paired$interval_width_baseline
  paired$interval_width_reduction_percent <- 100 * (1 - paired$interval_width_relative)
  paired$fit_mae_relative <- paired$fit_oracle_mae_candidate / paired$fit_oracle_mae_baseline
  paired$marginal_intervals_overlap <- pmax(paired$score_q025_candidate, paired$score_q025_baseline) <=
    pmin(paired$score_q975_candidate, paired$score_q975_baseline)
  list(aggregate = aggregate, paired = paired)
}

app_joint_laplace_article_finalize <- function(root) {
  app_joint_laplace_article_verify_freeze(root, verify_large_inputs = TRUE)
  ct <- readRDS(file.path(root, "contract.rds"))
  rows <- app_joint_prior_collect(root, "article")
  rows$model_id <- app_joint_laplace_article_model_id(rows)
  rows$architecture_id <- rows$arm_id
  if (nrow(rows) != 8L || any(!is.finite(rows$posterior_score_mean)) ||
      any(rows$contract_crossing_pairs != 0L)) stop("Article score packet is incomplete or invalid.", call. = FALSE)
  comparison <- app_joint_laplace_article_comparison(rows, ct$baseline_architecture_id,
    ct$candidate_architecture_id)
  ranked <- app_joint_arch_rank(rows, ct$baseline_architecture_id, 1L, "posterior_score_mean")
  decision <- ranked$decision[ranked$decision$architecture_id == ct$candidate_architecture_id, , drop = FALSE]
  candidate_rows <- rows[rows$architecture_id == ct$candidate_architecture_id, , drop = FALSE]
  predictive_pathology <- any(candidate_rows$score_rank_rhat > ct$predictive_pathology_rhat |
    candidate_rows$state_half_score_relative_difference > ct$predictive_pathology_relative_difference |
    candidate_rows$chain_score_relative_range > ct$predictive_pathology_relative_difference)
  hard_validity <- all(is.finite(candidate_rows$posterior_score_mean)) &&
    all(candidate_rows$contract_crossing_pairs == 0L) && !predictive_pathology
  confirmed <- hard_validity && isTRUE(decision$both_joint_improve[[1L]]) &&
    isTRUE(decision$four_model_improves[[1L]])
  decision$hard_validity_pass <- hard_validity
  decision$predictive_pathology <- predictive_pathology
  decision$mixing_is_hard_gate <- FALSE
  decision$article_fixture_used_for_selection <- FALSE
  decision$promotion_decision <- if (confirmed) {
    "candidate_article_fixture_confirmation_pass_ready_for_integration_review"
  } else "retain_current_article_authority"
  decision$claim <- "single_protected_fixture_descriptive_confirmation_not_universal_superiority"
  packet <- file.path(root, "closeout")
  app_ensure_dir(packet)
  app_write_csv(rows, file.path(packet, "article_scores.csv"))
  app_write_csv(comparison$aggregate, file.path(packet, "model_aggregate.csv"))
  app_write_csv(comparison$paired, file.path(packet, "candidate_vs_baseline.csv"))
  app_write_csv(ranked$decision, file.path(packet, "architecture_decisions.csv"))
  app_write_csv(decision, file.path(packet, "decision.csv"))
  app_write_csv(app_read_csv(file.path(root, "architectures.csv")),
    file.path(packet, "frozen_architectures.csv"))
  joint_contrast <- do.call(rbind, lapply(c("AL", "exAL"), function(family) {
    x <- candidate_rows[candidate_rows$likelihood == family, , drop = FALSE]
    joint <- x[x$structure == "joint", , drop = FALSE]
    independent <- x[x$structure == "independent", , drop = FALSE]
    data.frame(likelihood = family, joint_score_mean = joint$posterior_score_mean,
      independent_score_mean = independent$posterior_score_mean,
      joint_minus_independent = joint$posterior_score_mean - independent$posterior_score_mean,
      marginal_intervals_overlap = max(joint$posterior_score_q025, independent$posterior_score_q025) <=
        min(joint$posterior_score_q975, independent$posterior_score_q975),
      joint_raw_crossings = joint$canonical_raw_crossing_pairs,
      independent_raw_crossings = independent$canonical_raw_crossing_pairs,
      stringsAsFactors = FALSE)
  }))
  app_write_csv(joint_contrast, file.path(packet, "candidate_joint_vs_independent.csv"))

  grDevices::pdf(file.path(packet, "laplace_article_fixture_comparison.pdf"), width = 11, height = 7)
  plot_rows <- rows[order(rows$model_id, rows$architecture_id), ]
  labels <- paste(plot_rows$model_id, plot_rows$architecture_id)
  graphics::par(mar = c(5, 15, 4, 2))
  graphics::plot(plot_rows$posterior_score_mean, seq_len(nrow(plot_rows)), yaxt = "n",
    xlab = "DGP-integrated finite-grid score (lower is better)", ylab = "",
    main = "Laplace Bridge: matched article-fixture architecture confirmation", pch = 19,
    xlim = range(plot_rows$posterior_score_q025, plot_rows$posterior_score_q975))
  graphics::segments(plot_rows$posterior_score_q025, seq_len(nrow(plot_rows)),
    plot_rows$posterior_score_q975, seq_len(nrow(plot_rows)))
  graphics::axis(2, at = seq_len(nrow(plot_rows)), labels = labels, las = 1, cex.axis = .7)
  grDevices::dev.off()
  handoff <- c(
    "# JOINT Laplace article-fixture confirmation handoff", "",
    sprintf("- Status: `%s`", decision$promotion_decision[[1L]]),
    sprintf("- Source branch: `%s`", app_read_csv(file.path(root, "execution_git_state.csv"))$branch[[1L]]),
    sprintf("- Source HEAD: `%s`", app_read_csv(file.path(root, "execution_git_state.csv"))$head[[1L]]),
    sprintf("- Runtime root: `%s`", normalizePath(root)),
    "- Scope: Laplace Bridge only; matched current baseline versus preselected arch_02.",
    "- Protected article fixture was evaluation-only and never selected a specification.",
    "- Article files, main, and Overleaf were not modified.",
    "- Runtime draws and model objects remain excluded from Git.", "",
    "## Required integration order", "",
    "1. Integrate the completed architecture-screen dependency.",
    "2. Integrate this confirmation implementation and frozen scientific closeout.",
    "3. Rebuild article assets only after coordinator review of the matched comparison."
  )
  writeLines(handoff, file.path(packet, "integration_handoff.md"))
  files <- list.files(packet, full.names = TRUE)
  app_joint_shared_write_manifest(packet, setNames(files, basename(files)), filename = "artifact_manifest.csv")
  app_joint_arch_seal(packet)
  terminal <- if (confirmed) "COMPLETE_READY_FOR_INTEGRATION_REVIEW" else "COMPLETE_RETAIN_CURRENT_AUTHORITY"
  writeLines(terminal, file.path(root, "COMPLETE"))
  invisible(decision)
}

app_joint_laplace_article_health <- function(root) {
  rows <- list()
  for (kind in c("datasets", "warmups", "chains", "cells")) {
    path <- file.path(root, "article", paste0(kind, ".csv"))
    if (!file.exists(path)) next
    plan <- app_read_csv(path)
    folder_kind <- if (kind == "cells") "scores" else kind
    prefix <- if (kind == "datasets") "dataset_" else if (kind == "cells") "cell_" else "worker_"
    width <- if (kind == "datasets") 2L else if (kind == "warmups") 3L else 4L
    folders <- file.path(root, "article", folder_kind,
      sprintf(paste0(prefix, "%0", width, "d"), seq_len(nrow(plan))))
    complete <- vapply(folders, app_joint_arch_done, logical(1L))
    failed <- file.exists(file.path(folders, "FAILED"))
    rows[[length(rows) + 1L]] <- data.frame(stage = "article", kind = kind,
      expected = nrow(plan), completed = sum(complete), failed = sum(failed & !complete),
      remaining = sum(!complete & !failed), stringsAsFactors = FALSE)
  }
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}
