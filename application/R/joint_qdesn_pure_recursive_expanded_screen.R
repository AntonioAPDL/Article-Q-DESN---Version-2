# Additive, case-specific expansion of the pure-DESN screening domain.

app_joint_pure_expanded_contract_path <- function() {
  app_path("application/config/joint_qdesn_pure_recursive_expanded_screen_contract_v2.csv")
}

app_joint_pure_expanded_axes_path <- function() {
  app_path("application/config/joint_qdesn_pure_recursive_expanded_candidate_axes_v2.csv")
}

app_joint_pure_expanded_default_root <- function() {
  app_path("application/cache/joint_qdesn_pure_recursive_expanded_screen_jerez_15core_20260925")
}

app_joint_pure_expanded_source_root <- function() {
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_pure_desn_recursive_selection_20260925/application/cache/joint_qdesn_pure_recursive_campaign_jerez_15core_20260925"
}

app_joint_pure_expanded_axis_value <- function(tab, axis, numeric = FALSE) {
  row <- tab[tab$axis == axis, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("Expanded axes require one '%s' row.", axis), call. = FALSE)
  out <- strsplit(as.character(row$values[[1L]]), ";", fixed = TRUE)[[1L]]
  if (numeric) as.numeric(out) else out
}

app_joint_pure_expanded_read_axes <- function(path = app_joint_pure_expanded_axes_path()) {
  tab <- app_read_csv(path)
  app_check_required_columns(tab, c("axis", "values", "role"), "expanded pure-DESN axes")
  if (anyDuplicated(tab$axis)) stop("Expanded candidate axes must be unique.", call. = FALSE)
  value <- function(axis, numeric = FALSE) app_joint_pure_expanded_axis_value(tab, axis, numeric)
  out <- list(
    table = tab,
    depth = as.integer(value("depth", TRUE)),
    state_budget = as.integer(value("state_budget", TRUE)),
    width_shape = value("width_shape"),
    response_lags = as.integer(value("response_lags", TRUE)),
    exogenous_lags = as.integer(value("exogenous_lags", TRUE)),
    alpha_range = value("alpha_range", TRUE),
    alpha_anchors = value("alpha_anchors", TRUE),
    rho_range = value("rho_range", TRUE),
    rho_anchors = value("rho_anchors", TRUE),
    input_scale = value("input_scale", TRUE),
    pi_w = value("pi_w", TRUE),
    pi_in = value("pi_in", TRUE),
    reservoir_seed = as.integer(value("reservoir_seed", TRUE)),
    legacy_candidate_count = as.integer(value("legacy_candidate_count", TRUE)),
    expanded_candidate_count = as.integer(value("expanded_candidate_count", TRUE)),
    halton_skip = as.integer(value("halton_skip", TRUE)),
    design_class = value("design_class"),
    state_reduction = tolower(value("state_reduction")) == "true"
  )
  if (!identical(out$depth, 1:4) || !identical(out$state_budget, c(20L, 40L, 75L, 100L, 150L, 200L, 250L, 300L)) ||
      !identical(out$response_lags, c(1L, 2L, 3L, 5L, 8L, 12L, 15L, 24L, 30L, 45L, 60L, 75L, 90L, 120L, 150L)) ||
      !identical(out$exogenous_lags, 0L) || !isTRUE(all.equal(out$alpha_range, c(0.01, 0.99))) ||
      !isTRUE(all.equal(out$rho_range, c(0.20, 0.99))) || out$legacy_candidate_count != 256L ||
      out$expanded_candidate_count != 512L || out$reservoir_seed != 202609250L || isTRUE(out$state_reduction)) {
    stop("Expanded candidate axes violate the frozen search contract.", call. = FALSE)
  }
  out
}

app_joint_pure_expanded_read_contract <- function(path = app_joint_pure_expanded_contract_path()) {
  out <- app_joint_pure_read_contract(path)
  legacy <- as.integer(app_joint_pure_contract_value(out$table, "legacy_candidate_count"))
  expanded <- as.integer(app_joint_pure_contract_value(out$table, "expanded_candidate_count"))
  screening_only <- identical(tolower(app_joint_pure_contract_value(out$table, "screening_only")), "true")
  if (legacy != 256L || expanded != 512L || legacy + expanded != out$candidate_count ||
      out$advance_count != 64L || !screening_only) {
    stop("Expanded screening contract cardinality or stop policy is malformed.", call. = FALSE)
  }
  out$legacy_candidate_count <- legacy
  out$expanded_candidate_count <- expanded
  out$screening_only <- screening_only
  out
}

app_joint_pure_expanded_radical_inverse <- function(index, base) {
  index <- as.integer(index); base <- as.integer(base)
  value <- 0; factor <- 1 / base
  while (index > 0L) {
    value <- value + factor * (index %% base)
    index <- index %/% base
    factor <- factor / base
  }
  value
}

app_joint_pure_expanded_halton <- function(n, d, skip = 1024L) {
  primes <- c(2L, 3L, 5L, 7L, 11L, 13L, 17L, 19L, 23L, 29L, 31L)
  n <- as.integer(n); d <- as.integer(d); skip <- as.integer(skip)
  if (n < 1L || d < 1L || d > length(primes) || skip < 0L) stop("Invalid Halton dimensions.", call. = FALSE)
  out <- matrix(NA_real_, nrow = n, ncol = d)
  for (jj in seq_len(d)) {
    out[, jj] <- vapply(skip + seq_len(n), app_joint_pure_expanded_radical_inverse,
      numeric(1L), base = primes[[jj]])
  }
  out
}

app_joint_pure_expanded_pick <- function(values, u) {
  values[pmin(length(values), floor(u * length(values)) + 1L)]
}

app_joint_pure_expanded_scalar_label <- function(x) {
  sub("[.]?0+$", "", sprintf("%.8f", as.numeric(x)))
}

app_joint_pure_expanded_candidate_pool <- function(n = 2048L, axes = app_joint_pure_expanded_read_axes()) {
  H <- app_joint_pure_expanded_halton(n, 9L, axes$halton_skip)
  D <- as.integer(app_joint_pure_expanded_pick(axes$depth, H[, 1L]))
  budget <- as.integer(app_joint_pure_expanded_pick(axes$state_budget, H[, 2L]))
  shape <- as.character(app_joint_pure_expanded_pick(axes$width_shape, H[, 3L]))
  response_lags <- as.integer(app_joint_pure_expanded_pick(axes$response_lags, H[, 4L]))
  logit_alpha <- stats::qlogis(axes$alpha_range)
  alpha <- stats::plogis(logit_alpha[[1L]] + H[, 5L] * diff(logit_alpha))
  rho <- axes$rho_range[[1L]] + H[, 6L] * diff(axes$rho_range)
  input_scale <- as.numeric(app_joint_pure_expanded_pick(axes$input_scale, H[, 7L]))
  pi_w <- as.numeric(app_joint_pure_expanded_pick(axes$pi_w, H[, 8L]))
  pi_in <- as.numeric(app_joint_pure_expanded_pick(axes$pi_in, H[, 9L]))

  boundary <- rbind(
    c(1, 20, 1, 1, 0.01, 0.20), c(4, 300, 2, 150, 0.01, 0.99),
    c(4, 20, 1, 150, 0.99, 0.20), c(1, 300, 2, 1, 0.99, 0.99),
    c(2, 75, 1, 30, 0.20, 0.75), c(3, 100, 2, 45, 0.50, 0.90),
    c(4, 150, 1, 60, 0.80, 0.98), c(2, 250, 2, 120, 0.50, 0.99)
  )
  take <- seq_len(nrow(boundary))
  D[take] <- boundary[, 1L]; budget[take] <- boundary[, 2L]
  shape[take] <- axes$width_shape[boundary[, 3L]]; response_lags[take] <- boundary[, 4L]
  alpha[take] <- boundary[, 5L]; rho[take] <- boundary[, 6L]

  rows <- lapply(seq_len(n), function(ii) {
    widths <- app_joint_pure_widths(D[[ii]], budget[[ii]], shape[[ii]])
    a <- as.numeric(app_joint_pure_expanded_scalar_label(alpha[[ii]]))
    r <- as.numeric(app_joint_pure_expanded_scalar_label(rho[[ii]]))
    row <- data.frame(
      feature_contract = "pure_recursive_v1", design_class = "reservoir", D = D[[ii]],
      n = paste(widths, collapse = ";"),
      n_tilde = if (D[[ii]] > 1L) paste(widths[seq_len(D[[ii]] - 1L)], collapse = ";") else "",
      retained_state_budget = sum(widths), width_shape = shape[[ii]], state_reduction = FALSE,
      response_lags = response_lags[[ii]], exogenous_lags = 0L,
      alpha = paste(rep(app_joint_pure_expanded_scalar_label(a), D[[ii]]), collapse = ";"),
      rho = paste(rep(app_joint_pure_expanded_scalar_label(r), D[[ii]]), collapse = ";"),
      pi_w = paste(rep(app_joint_pure_expanded_scalar_label(pi_w[[ii]]), D[[ii]]), collapse = ";"),
      pi_in = paste(rep(app_joint_pure_expanded_scalar_label(pi_in[[ii]]), D[[ii]]), collapse = ";"),
      input_scale = input_scale[[ii]], reservoir_seed = axes$reservoir_seed,
      raw_inputs_in_readout = FALSE, full_states_all_layers = TRUE,
      candidate_role = if (ii <= nrow(boundary)) "expanded_boundary_anchor" else "expanded_halton",
      stringsAsFactors = FALSE
    )
    row$architecture_signature <- app_joint_pure_architecture_signature(row)
    row
  })
  out <- app_bind_rows_fill(rows)
  out <- out[!duplicated(out$architecture_signature), , drop = FALSE]
  rownames(out) <- NULL
  out
}

app_joint_pure_expanded_candidates <- function(source_candidates, scenario_id, contract, axes, pool = NULL) {
  legacy <- source_candidates[source_candidates$scenario_id == scenario_id, , drop = FALSE]
  if (nrow(legacy) != contract$legacy_candidate_count || anyDuplicated(legacy$architecture_signature)) {
    stop(sprintf("Source candidates for '%s' violate the 256-candidate contract.", scenario_id), call. = FALSE)
  }
  if (is.null(pool)) {
    pool <- app_joint_pure_expanded_candidate_pool(max(2048L, 4L * contract$expanded_candidate_count), axes)
  }
  pool <- pool[!pool$architecture_signature %in% legacy$architecture_signature, , drop = FALSE]
  if (nrow(pool) < contract$expanded_candidate_count) stop("Expanded candidate pool is unexpectedly too small.", call. = FALSE)
  fresh <- pool[seq_len(contract$expanded_candidate_count), , drop = FALSE]
  fresh$scenario_id <- scenario_id
  fresh$candidate_id <- sprintf("%s__pure_expanded_%03d", scenario_id,
    contract$legacy_candidate_count + seq_len(nrow(fresh)))
  fresh <- fresh[, names(legacy), drop = FALSE]
  out <- rbind(legacy, fresh)
  if (nrow(out) != contract$candidate_count || anyDuplicated(out$candidate_id) ||
      anyDuplicated(out$architecture_signature)) stop("Combined expanded candidate registry is malformed.", call. = FALSE)
  rownames(out) <- NULL
  out
}

app_joint_pure_expanded_source_gate <- function(source_root, require_pipeline_complete = TRUE) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  required <- c(
    "artifact_manifest.csv", "ridge_candidate_registry.csv", "ridge_worker_plan.csv",
    "ridge_final_health.csv", "rhs_worker_plan.csv", "rhs_final_health.csv",
    "selected_family_backbones.csv", "selection_artifact_manifest.csv", "fixture_manifest.csv"
  )
  missing <- required[!file.exists(file.path(source_root, required))]
  if (length(missing)) stop(sprintf("Source campaign is missing: %s", paste(missing, collapse = ", ")), call. = FALSE)
  selection_verify <- app_joint_shared_verify_manifest(source_root,
    file.path(source_root, "selection_artifact_manifest.csv"))
  if (!all(selection_verify$verified)) stop("Source selection manifest does not verify.", call. = FALSE)
  ridge_health <- app_read_csv(file.path(source_root, "ridge_final_health.csv"))
  rhs_health <- app_read_csv(file.path(source_root, "rhs_final_health.csv"))
  if (ridge_health$completed[[1L]] != 6144L || ridge_health$failed[[1L]] != 0L ||
      rhs_health$completed[[1L]] != 6000L || rhs_health$failed[[1L]] != 0L) {
    stop("Source ridge/RHS stages are not complete and failure-free.", call. = FALSE)
  }
  pipeline <- file.path(source_root, "final_pipeline_status.csv")
  if (isTRUE(require_pipeline_complete)) {
    if (!file.exists(pipeline)) stop("Source pipeline has not reached its terminal status.", call. = FALSE)
    status <- app_read_csv(pipeline)
    if (nrow(status) != 1L || status$status[[1L]] != "COMPLETE_WITH_PATH_AND_MEAN_STATE_SCORE_PACKETS") {
      stop("Source pipeline terminal status is not successful.", call. = FALSE)
    }
  }
  data.frame(
    source_root = source_root, ridge_completed = ridge_health$completed[[1L]],
    rhs_completed = rhs_health$completed[[1L]], pipeline_complete = file.exists(pipeline),
    selection_manifest_verified = TRUE, stringsAsFactors = FALSE
  )
}

app_joint_pure_expanded_copy_file <- function(source, target) {
  app_ensure_dir(dirname(target))
  if (!file.copy(source, target, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE)) {
    stop(sprintf("Could not copy '%s'.", source), call. = FALSE)
  }
  target
}

app_joint_pure_expanded_rewrite_summary <- function(source_path, target_row, stage) {
  summary <- app_joint_pure_assert_unique_summary(app_read_csv(source_path), "source reusable summary")
  identity <- app_joint_pure_worker_identity_columns(stage)
  for (name in intersect(identity, intersect(names(summary), names(target_row)))) {
    summary[[name]] <- target_row[[name]][[1L]]
  }
  app_joint_pure_assert_unique_summary(summary, "rewritten reusable summary")
}

app_joint_pure_expanded_import_workers <- function(root, source_root, stage = c("ridge", "rhs")) {
  stage <- match.arg(stage)
  root <- normalizePath(root, mustWork = TRUE); source_root <- normalizePath(source_root, mustWork = TRUE)
  target_plan <- app_read_csv(file.path(root, paste0(stage, "_worker_plan.csv")))
  source_plan <- app_read_csv(file.path(source_root, paste0(stage, "_worker_plan.csv")))
  id_name <- if (stage == "ridge") "worker_id" else "rhs_worker_id"
  keys <- c("scenario_id", "candidate_id", if (stage == "rhs") "rhs_tau0", "replicate_id")
  key <- function(x) do.call(paste, c(lapply(x[keys], as.character), sep = "::"))
  source_index <- match(key(target_plan), key(source_plan))
  reusable <- which(!is.na(source_index))
  audits <- vector("list", length(reusable))
  for (jj in seq_along(reusable)) {
    ii <- reusable[[jj]]; src <- source_plan[source_index[[ii]], , drop = FALSE]
    target <- target_plan[ii, , drop = FALSE]
    if (as.character(src$architecture_signature[[1L]]) != as.character(target$architecture_signature[[1L]]) ||
        as.integer(src$dgp_seed[[1L]]) != as.integer(target$dgp_seed[[1L]])) {
      stop("Reusable worker identity differs from the expanded plan.", call. = FALSE)
    }
    src_dir <- app_joint_pure_worker_dir(source_root, stage, src[[id_name]][[1L]])
    manifest <- file.path(src_dir, "artifact_manifest.csv")
    verified <- app_joint_shared_verify_manifest(src_dir, manifest)
    if (!file.exists(file.path(src_dir, "DONE")) || !all(verified$verified)) {
      stop(sprintf("Reusable %s worker is not complete and verified.", stage), call. = FALSE)
    }
    dst_dir <- app_joint_pure_worker_dir(root, stage, target[[id_name]][[1L]])
    if (!file.exists(file.path(dst_dir, "DONE"))) {
      app_ensure_dir(dst_dir)
      summary <- app_joint_pure_expanded_rewrite_summary(file.path(src_dir, "summary.csv"), target, stage)
      paths <- c(summary = app_write_csv(summary, file.path(dst_dir, "summary.csv")))
      for (name in c("calibration_detail.csv", "vb_trace.csv")) {
        src_path <- file.path(src_dir, name)
        if (file.exists(src_path)) {
          paths <- c(paths, stats::setNames(app_joint_pure_expanded_copy_file(src_path, file.path(dst_dir, name)),
            sub("[.]csv$", "", name)))
        }
      }
      app_joint_shared_write_manifest(dst_dir, paths)
      writeLines("completed", file.path(dst_dir, "DONE"))
    }
    target_verify <- app_joint_shared_verify_manifest(dst_dir)
    if (!all(target_verify$verified)) stop("Imported worker manifest failed verification.", call. = FALSE)
    audits[[jj]] <- data.frame(
      stage = stage, source_worker_id = src[[id_name]][[1L]], target_worker_id = target[[id_name]][[1L]],
      scenario_id = target$scenario_id[[1L]], candidate_id = target$candidate_id[[1L]],
      replicate_id = target$replicate_id[[1L]], source_manifest_sha256 = app_sha256_file(manifest),
      target_manifest_sha256 = app_sha256_file(file.path(dst_dir, "artifact_manifest.csv")),
      imported_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), stringsAsFactors = FALSE
    )
  }
  audit_rows <- Filter(Negate(is.null), audits)
  audit <- if (length(audit_rows)) app_bind_rows_fill(audit_rows) else data.frame(
    stage = character(), source_worker_id = integer(), target_worker_id = integer(),
    scenario_id = character(), candidate_id = character(), replicate_id = integer(),
    source_manifest_sha256 = character(), target_manifest_sha256 = character(),
    imported_at_utc = character(), stringsAsFactors = FALSE)
  expected <- if (stage == "ridge") 6144L else length(reusable)
  if (nrow(audit) != expected) stop(sprintf("Imported %d %s workers; expected %d.", nrow(audit), stage, expected), call. = FALSE)
  audit_path <- app_write_csv(audit, file.path(root, paste0(stage, "_reuse_audit.csv")))
  app_joint_shared_write_manifest(root, c(reuse_audit = audit_path),
    filename = paste0(stage, "_reuse_manifest.csv"))
  audit
}

app_joint_pure_expanded_prepare <- function(
  root = app_joint_pure_expanded_default_root(),
  source_root = app_joint_pure_expanded_source_root(),
  require_pipeline_complete = TRUE
) {
  source_gate <- app_joint_pure_expanded_source_gate(source_root, require_pipeline_complete)
  contract <- app_joint_pure_expanded_read_contract()
  axes <- app_joint_pure_expanded_read_axes()
  registry <- app_joint_pure_read_registry()
  root <- normalizePath(root, mustWork = FALSE)
  if (dir.exists(root) && length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    stop("Refusing to overwrite a nonempty expanded-screen root.", call. = FALSE)
  }
  app_ensure_dir(root); app_ensure_dir(file.path(root, "fixtures")); app_ensure_dir(file.path(root, "ridge_workers"))
  source_candidates <- app_read_csv(file.path(source_root, "ridge_candidate_registry.csv"))
  source_fixtures <- app_read_csv(file.path(source_root, "fixture_manifest.csv"))
  expanded_pool <- app_joint_pure_expanded_candidate_pool(
    max(2048L, 4L * contract$expanded_candidate_count), axes
  )
  candidate_rows <- fixture_rows <- job_rows <- list(); worker_id <- 0L
  for (ii in seq_len(nrow(registry))) {
    scenario <- registry$scenario_id[[ii]]
    candidates <- app_joint_pure_expanded_candidates(
      source_candidates, scenario, contract, axes, pool = expanded_pool
    )
    candidate_rows[[ii]] <- candidates
    for (replicate_id in seq_len(contract$calibration_replicates)) {
      source_fixture <- source_fixtures[source_fixtures$scenario_id == scenario &
        as.integer(source_fixtures$replicate_id) == replicate_id, , drop = FALSE]
      if (nrow(source_fixture) != 1L || app_sha256_file(source_fixture$fixture_path[[1L]]) != source_fixture$sha256[[1L]]) {
        stop("Reusable selector fixture is missing or has changed.", call. = FALSE)
      }
      fixture_path <- file.path(root, "fixtures", basename(source_fixture$fixture_path[[1L]]))
      app_joint_pure_expanded_copy_file(source_fixture$fixture_path[[1L]], fixture_path)
      fixture_rows[[length(fixture_rows) + 1L]] <- data.frame(
        scenario_id = scenario, replicate_id = replicate_id,
        dgp_seed = source_fixture$dgp_seed[[1L]], fixture_path = normalizePath(fixture_path, mustWork = TRUE),
        size_bytes = file.info(fixture_path)$size, sha256 = app_sha256_file(fixture_path),
        protected_rows_persisted = 0L, source_fixture_sha256 = source_fixture$sha256[[1L]], stringsAsFactors = FALSE)
      jobs <- candidates; jobs$replicate_id <- replicate_id
      jobs$dgp_seed <- source_fixture$dgp_seed[[1L]]; jobs$fixture_path <- normalizePath(fixture_path, mustWork = TRUE)
      jobs$worker_id <- seq.int(worker_id + 1L, worker_id + nrow(jobs)); worker_id <- worker_id + nrow(jobs)
      job_rows[[length(job_rows) + 1L]] <- jobs
    }
  }
  candidates <- app_bind_rows_fill(candidate_rows); fixtures <- app_bind_rows_fill(fixture_rows)
  jobs <- app_bind_rows_fill(job_rows); jobs <- jobs[order(jobs$worker_id), , drop = FALSE]
  if (nrow(candidates) != 8L * 768L || nrow(jobs) != 18432L || anyDuplicated(jobs$worker_id) ||
      sum(grepl("^expanded_", candidates$candidate_role)) != 8L * 512L) {
    stop("Expanded campaign cardinality gate failed.", call. = FALSE)
  }
  expected <- data.frame(
    scenarios = 8L, ridge_candidates = nrow(candidates), ridge_workers = nrow(jobs),
    reusable_ridge_workers = 6144L, new_ridge_workers = 12288L,
    maximum_rhs_workers = 8L * 64L * 5L * 3L, concurrent_workers = 15L,
    automatic_stop_after = "expanded_rhs_selection", stringsAsFactors = FALSE)
  files <- c(
    frozen_contract = app_write_csv(contract$table, file.path(root, "frozen_contract.csv")),
    frozen_axes = app_write_csv(axes$table, file.path(root, "frozen_candidate_axes.csv")),
    frozen_registry = app_write_csv(registry, file.path(root, "frozen_family_registry.csv")),
    candidate_registry = app_write_csv(candidates, file.path(root, "ridge_candidate_registry.csv")),
    fixture_manifest = app_write_csv(fixtures, file.path(root, "fixture_manifest.csv")),
    ridge_worker_plan = app_write_csv(jobs, file.path(root, "ridge_worker_plan.csv")),
    expected_work = app_write_csv(expected, file.path(root, "expected_work.csv")),
    source_gate = app_write_csv(source_gate, file.path(root, "source_campaign_gate.csv")),
    source_git_state = app_write_csv(app_joint_shared_git_state(), file.path(root, "source_git_state.csv")))
  readiness <- data.frame(
    status = "READY_TO_RUN_EXPANDED_RIDGE_PENDING_IMPORT", expected_workers = nrow(jobs),
    reusable_workers = 6144L, new_workers = 12288L, max_workers = 15L,
    cpu_affinity_list = "2-16", protected_rows_used_for_selection = 0L,
    article_fixture_used_for_selection = FALSE, stringsAsFactors = FALSE)
  files <- c(files, launch_readiness = app_write_csv(readiness, file.path(root, "launch_readiness.csv")))
  app_joint_shared_write_manifest(root, files)
  reuse <- app_joint_pure_expanded_import_workers(root, source_root, "ridge")
  readiness$status <- "READY_TO_RUN_12288_NEW_EXPANDED_RIDGE_WORKERS"
  files[["launch_readiness"]] <- app_write_csv(readiness, file.path(root, "launch_readiness.csv"))
  app_joint_shared_write_manifest(root, files)
  list(root = root, expected = expected, readiness = readiness, reuse = reuse)
}

app_joint_pure_expanded_pending_ids <- function(root, stage = c("ridge", "rhs")) {
  stage <- match.arg(stage); root <- normalizePath(root, mustWork = TRUE)
  plan <- app_read_csv(file.path(root, paste0(stage, "_worker_plan.csv")))
  id_name <- if (stage == "ridge") "worker_id" else "rhs_worker_id"
  ids <- as.integer(plan[[id_name]])
  dirs <- vapply(ids, function(id) app_joint_pure_worker_dir(root, stage, id), character(1L))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))
  if (any(failed)) stop(sprintf("Expanded %s queue contains failed workers.", stage), call. = FALSE)
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  ids[!done]
}

app_joint_pure_expanded_finalize <- function(root, source_root) {
  root <- normalizePath(root, mustWork = TRUE); source_root <- normalizePath(source_root, mustWork = TRUE)
  expanded <- app_read_csv(file.path(root, "selected_family_backbones.csv"))
  source <- app_read_csv(file.path(source_root, "selected_family_backbones.csv"))
  compare <- merge(
    source[, c("scenario_id", "candidate_id", "response_lags", "D", "n", "alpha", "rho", "rhs_tau0", "calibration_acrps_mean")],
    expanded[, c("scenario_id", "candidate_id", "response_lags", "D", "n", "alpha", "rho", "rhs_tau0", "calibration_acrps_mean")],
    by = "scenario_id", suffixes = c("_source", "_expanded"), all = TRUE)
  compare$delta_expanded_minus_source <- compare$calibration_acrps_mean_expanded - compare$calibration_acrps_mean_source
  compare$expanded_improves <- compare$delta_expanded_minus_source < 0
  axes <- app_joint_pure_expanded_read_axes(file.path(root, "frozen_candidate_axes.csv"))
  alpha_first <- vapply(strsplit(expanded$alpha, ";", fixed = TRUE), function(x) as.numeric(x[[1L]]), numeric(1L))
  rho_first <- vapply(strsplit(expanded$rho, ";", fixed = TRUE), function(x) as.numeric(x[[1L]]), numeric(1L))
  boundary <- data.frame(
    scenario_id = expanded$scenario_id,
    lag_at_boundary = expanded$response_lags %in% range(axes$response_lags),
    alpha_near_boundary = alpha_first <= axes$alpha_range[[1L]] + 0.01 || alpha_first >= axes$alpha_range[[2L]] - 0.01,
    rho_near_boundary = rho_first <= axes$rho_range[[1L]] + 0.02 || rho_first >= axes$rho_range[[2L]] - 0.02,
    depth_at_upper_boundary = expanded$D == max(axes$depth),
    budget_at_boundary = expanded$retained_state_budget %in% range(axes$state_budget), stringsAsFactors = FALSE)
  files <- c(
    comparison = app_write_csv(compare, file.path(root, "expanded_vs_source_selection.csv")),
    boundary = app_write_csv(boundary, file.path(root, "expanded_winner_boundary_audit.csv")),
    ridge_health = app_write_csv(app_joint_pure_health(root, "ridge"), file.path(root, "expanded_ridge_health.csv")),
    rhs_health = app_write_csv(app_joint_pure_health(root, "rhs"), file.path(root, "expanded_rhs_health.csv")))
  status <- data.frame(
    status = "EXPANDED_RHS_SELECTION_COMPLETE_REVIEW_REQUIRED_BEFORE_QUANTILE_CONTINUATION",
    scenarios = nrow(expanded), improvements = sum(compare$expanded_improves, na.rm = TRUE),
    protected_rows_used_for_selection = 0L, quantile_or_mcmc_auto_launched = FALSE,
    completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), stringsAsFactors = FALSE)
  files <- c(files, status = app_write_csv(status, file.path(root, "final_expanded_screen_status.csv")))
  manifest <- app_joint_shared_write_manifest(root, files, filename = "expanded_screen_final_manifest.csv")
  verify <- app_joint_shared_verify_manifest(root, manifest)
  if (!all(verify$verified)) stop("Expanded final manifest failed verification.", call. = FALSE)
  app_write_csv(verify, file.path(root, "expanded_screen_final_manifest_verification.csv"))
  list(status = status, comparison = compare, boundary = boundary)
}
