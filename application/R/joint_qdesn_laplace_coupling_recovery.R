# Targeted recovery for a completed Laplace coupling screen. This module never
# mutates the source runtime; it copies sealed inputs into a new frozen runtime.

app_joint_recovery_contract <- function() {
  tab <- app_read_csv(app_path(
    "application/config/joint_qdesn_laplace_coupling_recovery_contract_v1.csv"))
  if (anyDuplicated(tab$name)) stop("Duplicate recovery contract keys.")
  out <- as.list(setNames(as.character(tab$value), tab$name))
  for (key in names(out)) {
    if (key %in% c("source_cell_ids", "source_arm_ids")) {
      out[[key]] <- strsplit(out[[key]], ";", fixed = TRUE)[[1L]]
      if (key == "source_cell_ids") out[[key]] <- as.integer(out[[key]])
    } else if (grepl("^[0-9.]+$", out[[key]])) out[[key]] <- as.numeric(out[[key]])
  }
  stopifnot(out$version == "joint_laplace_coupling_recovery_v1",
    grepl("^[0-9a-f]{40}$", out$source_expected_head),
    grepl("^[0-9a-f]{40}$", out$predecessor_expected_head),
    identical(out$predecessor_run_tag, "joint_laplace_coupling_recovery_20261007"),
    identical(out$continuation_run_tag,
      "joint_laplace_coupling_recovery_continuation_20261007"),
    identical(out$scenario_id, "laplace_bridge"),
    identical(out$source_cell_ids, 9:11),
    identical(out$source_arm_ids,
      c("baseline", "relaxed_innovation_slab", "conditional_variance_budget")),
    out$adjudication_dataset_id == 2, out$supplemental_chains_per_cell == 2,
    out$max_workers == 15, out$partial_confirmation_allowed == "true",
    out$publication_allowed == "false")
  out
}

app_joint_recovery_bind_rows <- function(frames) {
  if (!length(frames) || !all(vapply(frames, is.data.frame, logical(1L))))
    stop("Schema-safe binding requires data frames.")
  columns <- unique(unlist(lapply(frames, names), use.names = FALSE))
  aligned <- lapply(frames, function(frame) {
    missing <- setdiff(columns, names(frame))
    for (column in missing) frame[[column]] <- NA
    frame[, columns, drop = FALSE]
  })
  base::do.call(rbind, aligned)
}

app_joint_recovery_bind_chain_metadata <- function(frames) {
  required <- c("target_hash", "method", "retained_draws", "iterations",
    "burn", "thin", "chain_seed")
  if (!length(frames) || !all(vapply(frames, function(frame)
      is.data.frame(frame) && nrow(frame) == 1L &&
        all(required %in% names(frame)), logical(1L))))
    stop("Chain metadata is incomplete or malformed.")
  app_joint_recovery_bind_rows(frames)
}

# The frozen source scorer is reused byte-for-byte. Only its metadata rbind is
# intercepted so historical 26-column and recovery 28-column receipts align by
# name. All model, forecast, diagnostic, and score calculations remain unchanged.
app_joint_recovery_score <- function(root, stage, cell_id) {
  scorer <- app_joint_prior_score
  scorer_environment <- new.env(parent = environment(scorer))
  scorer_environment$do.call <- function(what, args, ...) {
    required <- c("target_hash", "method", "retained_draws", "iterations",
      "burn", "thin", "chain_seed")
    is_metadata_bind <- (identical(what, rbind) || identical(what, "rbind")) &&
      length(args) && all(vapply(args, function(frame)
        is.data.frame(frame) && nrow(frame) == 1L &&
          all(required %in% names(frame)), logical(1L)))
    if (is_metadata_bind) return(app_joint_recovery_bind_chain_metadata(args))
    base::do.call(what, args, ...)
  }
  environment(scorer) <- scorer_environment
  scorer(root, stage, cell_id)
}

app_joint_recovery_copy_tree <- function(from, to) {
  if (!dir.exists(from) || file.exists(to)) stop("Invalid recovery copy request.")
  app_ensure_dir(to)
  entries <- list.files(from, recursive = TRUE, all.files = TRUE,
    full.names = TRUE, include.dirs = TRUE, no.. = TRUE)
  relative <- substring(entries, nchar(from) + 2L)
  directories <- dir.exists(entries)
  for (path in file.path(to, relative[directories])) app_ensure_dir(path)
  if (any(!directories)) {
    destinations <- file.path(to, relative[!directories])
    for (path in unique(dirname(destinations))) app_ensure_dir(path)
    copied <- file.copy(entries[!directories], destinations, overwrite = FALSE,
      copy.mode = TRUE, copy.date = TRUE)
    if (!all(copied)) stop("Failed to copy sealed recovery input.")
  }
  invisible(to)
}

app_joint_recovery_predecessor_worker_ids <- function() c(3L, 4L, 7L, 8L, 11L, 12L)

app_joint_recovery_tree_inventory <- function(root, relative_directories) {
  paths <- unlist(lapply(relative_directories, function(directory) {
    absolute <- file.path(root, directory)
    if (!dir.exists(absolute)) stop("Predecessor import directory is missing.")
    files <- list.files(absolute, recursive = TRUE, all.files = TRUE,
      full.names = TRUE, include.dirs = FALSE, no.. = TRUE)
    substring(files, nchar(root) + 2L)
  }), use.names = FALSE)
  paths <- unique(paths)
  absolute <- file.path(root, paths)
  data.frame(relative_path = paths, size_bytes = file.info(absolute)$size,
    sha256 = unname(vapply(absolute, app_sha256_file, character(1L))))
}

app_joint_recovery_verify_predecessor <- function(predecessor_root, source_root,
    rc = app_joint_recovery_contract()) {
  predecessor_root <- normalizePath(predecessor_root, mustWork = TRUE)
  source_root <- normalizePath(source_root, mustWork = TRUE)
  observed_head <- trimws(readLines(file.path(predecessor_root, "source_head.txt"),
    warn = FALSE)[1L])
  if (!identical(observed_head, rc$predecessor_expected_head))
    stop("Unexpected predecessor execution HEAD.")
  predecessor_source <- normalizePath(trimws(readLines(file.path(predecessor_root,
    "source_runtime.txt"), warn = FALSE)[1L]), mustWork = TRUE)
  if (!identical(predecessor_source, source_root))
    stop("Predecessor does not reference the frozen source runtime.")
  freeze <- app_joint_shared_verify_manifest(predecessor_root,
    file.path(predecessor_root, "freeze_manifest.csv"))
  plan <- app_joint_shared_verify_manifest(file.path(predecessor_root, "screen"),
    file.path(predecessor_root, "screen/plan_manifest.csv"))
  if (!nrow(freeze) || any(!freeze$verified) || !nrow(plan) || any(!plan$verified))
    stop("Predecessor freeze or screen plan changed.")
  if (!file.exists(file.path(predecessor_root, "CONTROLLER_FAILED")) ||
      file.exists(file.path(predecessor_root, "COMPLETE")) ||
      file.exists(file.path(predecessor_root, "screen", "SELECTION_FROZEN")))
    stop("Predecessor is not the expected failed-closed preselection runtime.")
  failed <- file.path(predecessor_root, "screen", "scores",
    sprintf("cell_%04d", 1:3), "FAILED")
  if (!all(file.exists(failed)) || !all(vapply(failed, function(path)
      identical(trimws(readLines(path, warn = FALSE)[1L]),
        "numbers of columns of arguments do not match"), logical(1L))))
    stop("Predecessor score failure does not match the audited schema defect.")
  directories <- file.path(predecessor_root, "screen", "chains",
    sprintf("worker_%04d", 1:12))
  if (!all(vapply(directories, app_joint_prior_done, logical(1L))))
    stop("Predecessor chain evidence is incomplete or changed.")
  ids <- app_joint_recovery_predecessor_worker_ids()
  metadata <- lapply(file.path(predecessor_root, "screen", "chains",
    sprintf("worker_%04d", ids), "metadata.csv"), app_read_csv)
  if (!identical(vapply(metadata, function(x) as.integer(x$chain_id), integer(1L)),
      rep(3:4, 3L)))
    stop("Predecessor supplemental-chain map changed.")
  relative <- file.path("screen", "chains", sprintf("worker_%04d", ids))
  list(root = predecessor_root, worker_ids = ids,
    inventory = app_joint_recovery_tree_inventory(predecessor_root, relative))
}

app_joint_recovery_verify_import <- function(root) {
  manifest <- file.path(root, "predecessor_import_manifest.csv")
  if (!file.exists(manifest)) return(invisible(TRUE))
  tab <- app_read_csv(manifest)
  absolute <- file.path(root, tab$relative_path)
  if (!all(file.exists(absolute))) stop("Imported predecessor evidence is missing.")
  size <- file.info(absolute)$size
  hash <- unname(vapply(absolute, app_sha256_file, character(1L)))
  if (!identical(as.numeric(size), as.numeric(tab$size_bytes)) ||
      !identical(hash, as.character(tab$sha256)))
    stop("Imported predecessor evidence changed.")
  invisible(TRUE)
}

app_joint_recovery_source_manifest_paths <- function(source_root) {
  fixed <- c("freeze_manifest.csv", "source_manifest.csv", "source_head.txt",
    "contract.rds", "arms.csv", "backbones.csv", "screen/plan_manifest.csv",
    "screen/datasets.csv", "screen/cells.csv", "screen/chains.csv",
    "screen/warmups.csv", "CONTROLLER_FAILED")
  score <- unlist(lapply(1:16, function(id) file.path("screen/scores",
    sprintf("cell_%04d", id), c("summary.csv", "artifact_manifest.csv", "DONE"))))
  affected <- c(
    file.path("screen/datasets/dataset_02", c("artifact_manifest.csv", "component_manifest.csv", "DONE")),
    file.path("screen/calibrations/dataset_02", c("artifact_manifest.csv", "DONE")),
    unlist(lapply(4:6, function(id) file.path("screen/warmups", sprintf("worker_%03d", id),
      c("artifact_manifest.csv", "DONE")))),
    unlist(lapply(17:22, function(id) file.path("screen/chains", sprintf("worker_%04d", id),
      c("artifact_manifest.csv", "metadata.csv", "DONE")))))
  unique(c(fixed, score, affected))
}

app_joint_recovery_verify_source <- function(source_root,
    rc = app_joint_recovery_contract()) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  observed_head <- trimws(readLines(file.path(source_root, "source_head.txt"), warn = FALSE)[1L])
  if (!identical(observed_head, rc$source_expected_head)) stop("Unexpected source execution HEAD.")
  frozen <- app_joint_shared_verify_manifest(source_root,
    file.path(source_root, "freeze_manifest.csv"))
  if (!nrow(frozen) || any(!frozen$verified)) stop("Source experiment freeze changed.")
  source <- app_read_csv(file.path(source_root, "source_manifest.csv"))
  current <- vapply(file.path(app_path(), source$relative_path), app_sha256_file, character(1L))
  if (!identical(unname(current), as.character(source$sha256)))
    stop("Recovery branch changed a source-frozen implementation file.")
  plan <- app_joint_shared_verify_manifest(file.path(source_root, "screen"),
    file.path(source_root, "screen/plan_manifest.csv"))
  if (!nrow(plan) || any(!plan$verified)) stop("Source screen plan changed.")
  expected <- list(datasets = 2L, calibrations = 2L, warmups = 6L,
    chains = 32L, scores = 16L)
  prefixes <- c(datasets = "dataset_", calibrations = "dataset_",
    warmups = "worker_", chains = "worker_", scores = "cell_")
  widths <- c(datasets = 2L, calibrations = 2L, warmups = 3L, chains = 4L, scores = 4L)
  for (kind in names(expected)) {
    folders <- file.path(source_root, "screen", kind,
      sprintf(paste0(prefixes[[kind]], "%0", widths[[kind]], "d"), seq_len(expected[[kind]])))
    if (!all(vapply(folders, app_joint_prior_done, logical(1L))))
      stop("Source screen contains an incomplete or changed sealed artifact.")
  }
  if (file.exists(file.path(source_root, "screen", "SELECTION_FROZEN")))
    stop("Source selection unexpectedly exists; recovery contract is stale.")
  paths <- app_joint_recovery_source_manifest_paths(source_root)
  absolute <- file.path(source_root, paths)
  if (!all(file.exists(absolute))) stop("Required source evidence is missing.")
  data.frame(relative_path = paths, size_bytes = file.info(absolute)$size,
    sha256 = unname(vapply(absolute, app_sha256_file, character(1L))))
}

app_joint_recovery_screen_plan <- function(source_root,
    rc = app_joint_recovery_contract()) {
  cells_source <- app_read_csv(file.path(source_root, "screen/cells.csv"))
  chains_source <- app_read_csv(file.path(source_root, "screen/chains.csv"))
  cells <- cells_source[match(rc$source_cell_ids, cells_source$cell_id), , drop = FALSE]
  stopifnot(nrow(cells) == 3L, !anyNA(cells$cell_id),
    all(cells$dataset_id == rc$adjudication_dataset_id),
    all(cells$likelihood == "AL"), all(cells$structure == "joint"),
    identical(as.character(cells$arm_id), rc$source_arm_ids))
  cells$source_cell_id <- cells$cell_id
  cells$cell_id <- seq_len(nrow(cells))
  jobs <- cells[rep(seq_len(nrow(cells)), each = 4L), , drop = FALSE]
  jobs$chain_id <- rep(1:4, nrow(cells)); jobs$worker_id <- seq_len(nrow(jobs))
  jobs$source_worker_id <- NA_integer_
  jobs$chain_seed <- jobs$start_seed <- NA_integer_
  for (i in seq_len(nrow(cells))) {
    source_jobs <- chains_source[chains_source$cell_id == cells$source_cell_id[[i]], ]
    source_jobs <- source_jobs[order(source_jobs$chain_id), ]
    stopifnot(nrow(source_jobs) == 2L, identical(source_jobs$chain_id, 1:2))
    rows <- which(jobs$cell_id == i)
    jobs$source_worker_id[rows[1:2]] <- source_jobs$worker_id
    jobs$chain_seed[rows[1:2]] <- source_jobs$chain_seed
    jobs$start_seed[rows[1:2]] <- source_jobs$start_seed
    for (j in 3:4) {
      key <- (i - 1L) * 2L + (j - 2L)
      jobs$chain_seed[rows[j]] <- rc$supplemental_chain_seed_base + key * 1009L
      jobs$start_seed[rows[j]] <- rc$supplemental_initialization_seed_base + key * 1009L
    }
  }
  stopifnot(!anyDuplicated(jobs$chain_seed), !anyDuplicated(jobs$start_seed),
    !any(jobs$chain_seed[jobs$chain_id > 2] %in% chains_source$chain_seed))
  for (k in seq_len(7L)) jobs[[paste0("component_seed_", k)]] <-
    jobs$chain_seed + 100000L + k * 7919L
  warmups <- data.frame(dataset_id = rc$adjudication_dataset_id,
    arm_id = rc$source_arm_ids, worker_id = seq_along(rc$source_arm_ids),
    source_worker_id = 4:6)
  datasets <- app_read_csv(file.path(source_root, "screen/datasets.csv"))
  list(datasets = datasets, cells = cells, chains = jobs, warmups = warmups)
}

app_joint_recovery_prepare <- function(root, source_root, predecessor_root = NULL) {
  if (dir.exists(root)) stop("Recovery preparation will not overwrite an existing root.")
  rc <- app_joint_recovery_contract()
  source_root <- normalizePath(source_root, mustWork = TRUE)
  evidence <- app_joint_recovery_verify_source(source_root, rc)
  predecessor <- if (is.null(predecessor_root)) NULL else
    app_joint_recovery_verify_predecessor(predecessor_root, source_root, rc)
  source_ct <- readRDS(file.path(source_root, "contract.rds"))
  stopifnot(source_ct$screen_chains == 2, source_ct$confirmation_chains == 3,
    source_ct$exal_mcmc_method == "M0_v_collapsed_support_logit",
    source_ct$exal_vb_method == "VB1_structured_v")
  source_scores <- do.call(rbind, lapply(1:16, function(id) app_read_csv(file.path(
    source_root, "screen/scores", sprintf("cell_%04d", id), "summary.csv"))))
  stopifnot(nrow(source_scores) == 16L, all(is.finite(source_scores$posterior_score_mean)),
    all(source_scores$contract_crossing_pairs == 0))
  plan <- app_joint_recovery_screen_plan(source_root, rc)

  app_ensure_dir(root)
  saveRDS(source_ct, file.path(root, "contract.rds"))
  saveRDS(rc, file.path(root, "recovery_contract.rds"))
  for (name in c("arms.csv", "backbones.csv"))
    if (!file.copy(file.path(source_root, name), file.path(root, name), overwrite = FALSE))
      stop("Failed to copy source contract input.")
  writeLines(source_root, file.path(root, "source_runtime.txt"))
  app_write_csv(evidence, file.path(root, "source_evidence_manifest.csv"))
  app_write_csv(source_scores, file.path(root, "source_screen_scores.csv"))
  app_write_csv(data.frame(source_head = rc$source_expected_head,
    source_controller_status = "failed_closed_at_selection",
    source_worker_failures = 0L, source_chains_complete = 32L,
    source_score_cells_complete = 16L), file.path(root, "source_status.csv"))

  screen <- file.path(root, "screen")
  app_ensure_dir(screen)
  for (name in names(plan)) app_write_csv(plan[[name]], file.path(screen, paste0(name, ".csv")))
  app_joint_recovery_copy_tree(file.path(source_root, "screen/datasets/dataset_02"),
    file.path(screen, "datasets/dataset_02"))
  app_joint_recovery_copy_tree(file.path(source_root, "screen/calibrations/dataset_02"),
    file.path(screen, "calibrations/dataset_02"))
  for (i in seq_len(nrow(plan$warmups))) app_joint_recovery_copy_tree(
    file.path(source_root, "screen/warmups", sprintf("worker_%03d", plan$warmups$source_worker_id[i])),
    file.path(screen, "warmups", sprintf("worker_%03d", plan$warmups$worker_id[i])))
  copied <- plan$chains[plan$chains$chain_id <= 2L, ]
  for (i in seq_len(nrow(copied))) app_joint_recovery_copy_tree(
    file.path(source_root, "screen/chains", sprintf("worker_%04d", copied$source_worker_id[i])),
    file.path(screen, "chains", sprintf("worker_%04d", copied$worker_id[i])))
  if (!is.null(predecessor)) {
    for (id in predecessor$worker_ids) app_joint_recovery_copy_tree(
      file.path(predecessor$root, "screen/chains", sprintf("worker_%04d", id)),
      file.path(screen, "chains", sprintf("worker_%04d", id)))
    app_write_csv(predecessor$inventory,
      file.path(root, "predecessor_import_manifest.csv"))
    writeLines(predecessor$root, file.path(root, "predecessor_runtime.txt"))
    writeLines(rc$predecessor_expected_head, file.path(root, "predecessor_head.txt"))
    app_write_csv(data.frame(
      predecessor_status = "failed_closed_before_selection",
      completed_source_chains = 6L,
      completed_supplemental_chains = 6L,
      failed_score_cells = 3L,
      failure_message = "numbers of columns of arguments do not match",
      action = "reuse_sealed_chains_and_rescore_under_schema_safe_continuation"),
      file.path(root, "predecessor_failure_receipt.csv"))
    app_joint_recovery_verify_import(root)
  }
  stopifnot(app_joint_prior_done(file.path(screen, "datasets/dataset_02")),
    app_joint_prior_done(file.path(screen, "calibrations/dataset_02")),
    all(vapply(file.path(screen, "warmups", sprintf("worker_%03d", 1:3)),
      app_joint_prior_done, logical(1L))),
    all(vapply(file.path(screen, "chains", sprintf("worker_%04d", copied$worker_id)),
      app_joint_prior_done, logical(1L))))
  if (!is.null(predecessor)) stopifnot(all(vapply(file.path(screen, "chains",
    sprintf("worker_%04d", predecessor$worker_ids)), app_joint_prior_done, logical(1L))))
  plans <- file.path(screen, paste0(names(plan), ".csv"))
  app_joint_shared_write_manifest(screen, setNames(plans, basename(plans)),
    filename = "plan_manifest.csv")

  source_files <- unique(c(list.files(app_path("application/R"), "\\.R$", full.names = TRUE),
    list.files(app_path("application/scripts"), "joint.*\\.(R|sh)$", full.names = TRUE),
    list.files(app_path("application/config"), "joint.*\\.csv$", full.names = TRUE),
    app_path("tables/joint_qdesn_pure_desn_v1_selected_backbones.csv")))
  app_write_csv(data.frame(relative_path = substring(source_files, nchar(app_path()) + 2L),
    sha256 = vapply(source_files, app_sha256_file, character(1L))),
    file.path(root, "source_manifest.csv"))
  writeLines(system2("git", c("rev-parse", "HEAD"), stdout = TRUE),
    file.path(root, "source_head.txt"))
  writeLines(capture.output(sessionInfo()), file.path(root, "session_info.txt"))
  top <- list.files(root, full.names = TRUE); top <- top[!dir.exists(top)]
  app_joint_shared_write_manifest(root, setNames(top, basename(top)),
    filename = "freeze_manifest.csv")
  app_joint_prior_verify_freeze(root)
  app_joint_recovery_verify_import(root)
  invisible(root)
}

app_joint_recovery_select_group <- function(rows, ct, baseline = "baseline") {
  rows$eligible <- app_joint_coupling_eligible(rows, ct)
  expected <- app_joint_coupling_arms(ct)$arm_id
  groups <- split(rows, rows$arm_id)
  if (!setequal(names(groups), expected)) stop("Missing or unexpected selector arm.")
  audit <- do.call(rbind, lapply(groups, function(x) {
    if (nrow(x) != ct$screen_replicates || anyDuplicated(x$replicate_id) ||
      !setequal(x$replicate_id, seq_len(ct$screen_replicates)))
      stop("Incomplete matched selector replicates.")
    data.frame(scenario_id = x$scenario_id[1L], likelihood = x$likelihood[1L],
      arm_id = x$arm_id[1L], mean = mean(x$posterior_score_mean),
      interval_width = mean(x$posterior_score_interval_width),
      canonical_mean = mean(x$canonical_origin_marginal_dgp_integrated_acrps),
      eligible = all(x$eligible), eligible_replicates = sum(x$eligible),
      replicate_count = nrow(x), max_score_rhat = max(x$score_rank_rhat),
      max_quantile_functional_rhat = max(x$quantile_functional_max_rhat),
      max_state_half_relative_difference = max(x$state_half_score_relative_difference),
      max_chain_relative_range = max(x$chain_score_relative_range))
  }))
  base <- audit[audit$arm_id == baseline, , drop = FALSE]
  if (nrow(base) != 1L || any(!is.finite(audit$mean))) stop("Nonfinite or missing selector baseline.")
  audit$improvement_over_baseline <- base$mean - audit$mean
  if (!base$eligible) {
    status <- data.frame(scenario_id = rows$scenario_id[1L], likelihood = rows$likelihood[1L],
      status = "blocked_baseline_functional_pathology", arm_id = NA_character_,
      baseline_arm_id = baseline, selector_mean = NA_real_, baseline_mean = base$mean,
      improvement = NA_real_, interpretation = "no_candidate_forced")
    return(list(audit = audit, status = status, selection = status[FALSE, ]))
  }
  eligible <- audit[audit$eligible & audit$mean < base$mean - ct$selection_epsilon, ]
  selected <- if (nrow(eligible)) eligible[order(eligible$mean, eligible$arm_id), ][1L, ] else base
  status <- data.frame(scenario_id = rows$scenario_id[1L], likelihood = rows$likelihood[1L],
    status = "ready_for_fresh_confirmation", arm_id = selected$arm_id,
    baseline_arm_id = baseline, selector_mean = selected$mean, baseline_mean = base$mean,
    improvement = base$mean - selected$mean,
    interpretation = "recovered_internal_selection_not_article_promotion")
  list(audit = audit, status = status, selection = status)
}

app_joint_recovery_confirmation_plan <- function(selection, ct) {
  stopifnot(nrow(selection) >= 1L, nrow(selection) <= 2L,
    !anyDuplicated(selection$likelihood), all(selection$likelihood %in% c("AL", "exAL")))
  datasets <- data.frame(scenario_id = ct$scenarios,
    replicate_id = seq_len(ct$confirmation_replicates))
  datasets$dataset_id <- seq_len(nrow(datasets))
  datasets$dgp_seed <- ct$confirmation_seed_base + datasets$dataset_id * 100L
  cells <- list()
  for (d in seq_len(nrow(datasets))) for (likelihood in selection$likelihood) {
    chosen <- unique(c("baseline", selection$arm_id[selection$likelihood == likelihood]))
    for (arm in chosen) cells[[length(cells) + 1L]] <- data.frame(dataset_id = d,
      scenario_id = ct$scenarios, replicate_id = d, likelihood = likelihood,
      structure = "joint", arm_id = arm, long_budget = FALSE)
    cells[[length(cells) + 1L]] <- data.frame(dataset_id = d,
      scenario_id = ct$scenarios, replicate_id = d, likelihood = likelihood,
      structure = "independent", arm_id = "baseline", long_budget = FALSE)
  }
  cells <- do.call(rbind, cells); cells$cell_id <- seq_len(nrow(cells))
  chains <- cells[rep(seq_len(nrow(cells)), each = ct$confirmation_chains), , drop = FALSE]
  chains$chain_id <- rep(seq_len(ct$confirmation_chains), nrow(cells))
  chains$worker_id <- seq_len(nrow(chains)); offset <- 1000000L
  chains$chain_seed <- ct$chain_seed_base + offset + chains$worker_id * 1009L
  chains$start_seed <- ct$initialization_seed_base + offset + chains$worker_id * 1009L
  for (k in seq_along(ct$tau)) chains[[paste0("component_seed_", k)]] <-
    chains$chain_seed + 100000L + k * 7919L
  warmups <- unique(cells[cells$structure == "joint", c("dataset_id", "arm_id")])
  warmups$worker_id <- seq_len(nrow(warmups))
  list(datasets = datasets, cells = cells, chains = chains, warmups = warmups)
}

app_joint_recovery_prepare_confirmation <- function(root, selection) {
  destination <- file.path(root, "confirmation")
  if (dir.exists(destination)) stop("Confirmation stage already exists.")
  ct <- readRDS(file.path(root, "contract.rds"))
  plan <- app_joint_recovery_confirmation_plan(selection, ct)
  app_ensure_dir(destination)
  for (name in names(plan)) app_write_csv(plan[[name]],
    file.path(destination, paste0(name, ".csv")))
  paths <- file.path(destination, paste0(names(plan), ".csv"))
  app_joint_shared_write_manifest(destination, setNames(paths, basename(paths)),
    filename = "plan_manifest.csv")
  invisible(plan)
}

app_joint_recovery_adjudicate <- function(root) {
  app_joint_prior_verify_freeze(root)
  app_joint_recovery_verify_import(root)
  if (file.exists(file.path(root, "screen/SELECTION_FROZEN")))
    stop("Recovery selection is already frozen.")
  checked <- app_joint_shared_verify_manifest(file.path(root, "screen"),
    file.path(root, "screen/plan_manifest.csv"))
  if (!all(checked$verified)) stop("Recovery screen plan changed.")
  folders <- file.path(root, "screen/scores", sprintf("cell_%04d", 1:3))
  if (!all(vapply(folders, app_joint_prior_done, logical(1L))))
    stop("Recovery scoring is incomplete.")
  original <- app_read_csv(file.path(root, "source_screen_scores.csv"))
  cells <- app_read_csv(file.path(root, "screen/cells.csv"))
  recovered <- do.call(rbind, lapply(seq_len(nrow(cells)), function(i) {
    x <- app_read_csv(file.path(folders[i], "summary.csv"))
    x$recovery_cell_id <- x$cell_id; x$cell_id <- cells$source_cell_id[i]; x
  }))
  original$recovery_cell_id <- NA_integer_
  combined <- original[!original$cell_id %in% recovered$cell_id, ]
  combined <- app_joint_recovery_bind_rows(list(combined, recovered))
  combined <- combined[order(combined$cell_id), ]
  stopifnot(nrow(combined) == 16L, identical(combined$cell_id, 1:16))
  ct <- readRDS(file.path(root, "contract.rds"))
  joint <- combined[combined$structure == "joint", ]
  decisions <- lapply(c("AL", "exAL"), function(likelihood)
    app_joint_recovery_select_group(joint[joint$likelihood == likelihood, ], ct))
  audit <- do.call(rbind, lapply(decisions, `[[`, "audit"))
  status <- do.call(rbind, lapply(decisions, `[[`, "status"))
  ready <- status[status$status == "ready_for_fresh_confirmation", ]
  if (!nrow(ready)) stop("No likelihood passed recovery selection; confirmation forbidden.")
  app_write_csv(combined, file.path(root, "screen/complete_screen_scores.csv"))
  app_write_csv(audit, file.path(root, "screen/selector_audit.csv"))
  app_write_csv(status, file.path(root, "screen/selection_status.csv"))
  app_write_csv(ready, file.path(root, "screen/selection.csv"))
  paths <- c("selection.csv", "selection_status.csv", "selector_audit.csv",
    "complete_screen_scores.csv")
  app_write_csv(data.frame(relative_path = paths,
    sha256 = vapply(file.path(root, "screen", paths), app_sha256_file, character(1L))),
    file.path(root, "screen/selection_manifest.csv"))
  writeLines("FROZEN_AFTER_TARGETED_ADJUDICATION_BEFORE_FRESH_CONFIRMATION",
    file.path(root, "screen/SELECTION_FROZEN"))
  app_joint_recovery_prepare_confirmation(root, ready)
  invisible(status)
}

app_joint_recovery_finalize <- function(root) {
  app_joint_prior_verify_freeze(root); app_joint_recovery_verify_import(root)
  app_joint_prior_verify_selection(root)
  tab <- app_joint_prior_collect(root, "confirmation")
  selection <- app_read_csv(file.path(root, "screen/selection.csv"))
  status <- app_read_csv(file.path(root, "screen/selection_status.csv"))
  verdict <- list(); contrasts <- list()
  for (i in seq_len(nrow(selection))) {
    s <- selection[i, ]; rows <- tab[tab$likelihood == s$likelihood, ]
    baseline <- rows[rows$structure == "joint" & rows$arm_id == "baseline", ]
    candidate <- rows[rows$structure == "joint" & rows$arm_id == s$arm_id, ]
    independent <- rows[rows$structure == "independent", ]
    baseline <- baseline[order(baseline$replicate_id), ]
    candidate <- candidate[order(candidate$replicate_id), ]
    independent <- independent[order(independent$replicate_id), ]
    stopifnot(nrow(candidate) == 2L, identical(candidate$replicate_id, baseline$replicate_id),
      identical(candidate$replicate_id, independent$replicate_id))
    delta <- candidate$posterior_score_mean - baseline$posterior_score_mean
    verdict[[i]] <- data.frame(scenario_id = "laplace_bridge", likelihood = s$likelihood,
      arm_id = s$arm_id, baseline_mean = mean(baseline$posterior_score_mean),
      candidate_mean = mean(candidate$posterior_score_mean),
      independent_mean = mean(independent$posterior_score_mean),
      candidate_minus_baseline = mean(delta), replicate_improvement_count = sum(delta < 0),
      confirmation_replicates = length(delta),
      candidate_mean_interval_width = mean(candidate$posterior_score_interval_width),
      baseline_mean_interval_width = mean(baseline$posterior_score_interval_width),
      independent_mean_interval_width = mean(independent$posterior_score_interval_width),
      canonical_mean_change = mean(candidate$canonical_origin_marginal_dgp_integrated_acrps -
        baseline$canonical_origin_marginal_dgp_integrated_acrps),
      functional_review_count = sum(candidate$functional_status == "review"),
      decision = if (s$arm_id == "baseline") "retain_baseline" else if (mean(delta) < 0 &&
        all(app_joint_coupling_eligible(candidate, readRDS(file.path(root, "contract.rds")))))
        "descriptive_mean_gain_integration_review" else "retain_baseline_review",
      claim = "fresh_seed_confirmation_not_article_fixture_supersession")
    for (replicate in candidate$replicate_id) for (reference in c("baseline", "independent")) {
      candidate_row <- candidate[candidate$replicate_id == replicate, ]
      reference_row <- if (reference == "baseline") baseline[baseline$replicate_id == replicate, ] else
        independent[independent$replicate_id == replicate, ]
      load_score <- function(id) app_read_csv(file.path(root, "confirmation/scores",
        sprintf("cell_%04d", id), "score_draws.csv.gz"))$origin_marginal_dgp_integrated_acrps
      left <- load_score(candidate_row$cell_id); right <- load_score(reference_row$cell_id)
      n <- min(length(left), length(right))
      set.seed(as.integer(readRDS(file.path(root, "contract.rds"))$score_seed_base +
        i * 100L + replicate * 10L + match(reference, c("baseline", "independent"))))
      difference <- if (candidate_row$cell_id == reference_row$cell_id) rep(0, n) else
        left[sample.int(length(left), n)] - right[sample.int(length(right), n)]
      contrasts[[length(contrasts) + 1L]] <- data.frame(likelihood = s$likelihood,
        replicate_id = replicate, reference = reference,
        mean_difference = mean(left) - mean(right),
        q025 = quantile(difference, .025, names = FALSE),
        q975 = quantile(difference, .975, names = FALSE),
        coupling = "independent_product_between_fitted_models")
    }
  }
  packet <- file.path(root, "closeout")
  if (app_joint_prior_done(packet)) return(invisible(packet))
  app_ensure_dir(packet)
  app_write_csv(tab, file.path(packet, "confirmation_scores.csv"))
  app_write_csv(do.call(rbind, verdict), file.path(packet, "decisions.csv"))
  app_write_csv(do.call(rbind, contrasts), file.path(packet, "posterior_score_contrasts.csv"))
  app_write_csv(status, file.path(packet, "selection_status.csv"))
  counts <- data.frame(stage = c("source_screen", "supplemental_adjudication", "confirmation"),
    workers = c(32L, 6L, nrow(app_read_csv(file.path(root, "confirmation/chains.csv")))),
    cells = c(16L, 3L, nrow(app_read_csv(file.path(root, "confirmation/cells.csv")))) )
  app_write_csv(counts, file.path(packet, "completion_counts.csv"))
  grDevices::pdf(file.path(packet, "laplace_coupling_recovery_confirmation.pdf"), width = 11, height = 7)
  for (family in selection$likelihood) {
    x <- tab[tab$likelihood == family, ]; at <- seq_len(nrow(x))
    graphics::par(mar = c(5, 16, 4, 2))
    graphics::plot(x$posterior_score_mean, at,
      xlim = range(x$posterior_score_q025, x$posterior_score_q975), pch = 19,
      yaxt = "n", ylab = "", xlab = "DGP-integrated forecast score; mean and 95% credible interval",
      main = paste("Laplace Bridge", family, "fresh recovery confirmation"))
    graphics::segments(x$posterior_score_q025, at, x$posterior_score_q975, at)
    graphics::axis(2, at, labels = paste(x$structure, x$arm_id, "rep", x$replicate_id),
      las = 1, cex.axis = .7)
  }
  grDevices::dev.off()
  writeLines(c("# JOINT Laplace coupling recovery closeout", "",
    "Source screen preserved at its original failed-closed selection state.",
    "Six supplemental AL chains adjudicated the localized replicate-2 functional warning.",
    "Likelihoods were selected independently; blocked likelihoods were not forced into confirmation.",
    "READY_FOR_INTEGRATION applies only to reviewed reproducibility code/evidence after handoff.",
    "NOT_READY_FOR_ARTICLE_PROMOTION: confirmation uses fresh protected data, not the article fixture.",
    paste("HEAD:", system2("git", c("rev-parse", "HEAD"), stdout = TRUE)),
    "No DESN, tau0, likelihood, forecast, score-grid, M0, or VB1 contract was changed.",
    "Runtime, draws, model objects, local trackers, and generated PDF remain excluded from Git."),
    file.path(packet, "HANDOFF.md"))
  app_joint_prior_seal(packet)
  writeLines("COMPLETE_READY_FOR_SCIENTIFIC_REVIEW", file.path(root, "COMPLETE"))
  invisible(packet)
}
