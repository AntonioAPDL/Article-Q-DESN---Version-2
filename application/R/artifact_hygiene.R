# Report-only artifact hygiene helpers.

app_generated_artifact_extensions <- function() {
  c("rds", "rda", "rdata")
}

app_default_fit_artifact_policy <- function() {
  list(
    retain_fit_object = TRUE,
    retain_design_object = TRUE,
    retain_prediction_design_object = TRUE,
    retain_reference_fit_object = TRUE,
    compact_latent_path_design = TRUE
  )
}

app_fit_artifact_policy <- function(cfg = list()) {
  policy <- app_default_fit_artifact_policy()
  raw <- cfg$execution$artifacts %||% cfg$artifacts %||% list()
  for (nm in intersect(names(policy), names(raw))) {
    policy[[nm]] <- app_as_bool(raw[[nm]])
  }
  policy
}

app_fit_artifact_retained <- function(policy, name) {
  isTRUE((policy %||% app_default_fit_artifact_policy())[[name]])
}

app_validate_fit_artifact_policy <- function(cfg = list(), policy = app_fit_artifact_policy(cfg)) {
  post_analysis <- isTRUE((cfg$post_analysis %||% list())$run_after_outputs %||% FALSE)
  if (post_analysis &&
      (!app_fit_artifact_retained(policy, "retain_fit_object") ||
       !app_fit_artifact_retained(policy, "retain_design_object"))) {
    stop(
      paste(
        "post_analysis.run_after_outputs requires retained fit and design objects.",
        "Keep execution.artifacts.retain_fit_object and",
        "execution.artifacts.retain_design_object enabled, or disable post-analysis."
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

app_artifact_path_for_manifest <- function(path, retained) {
  if (!isTRUE(retained)) return(NA_character_)
  app_prefer_repo_relative_path(path)
}

app_maybe_save_rds <- function(object, path, retained = TRUE) {
  if (!isTRUE(retained)) return(NA_character_)
  app_ensure_dir(dirname(path))
  saveRDS(object, path)
  app_prefer_repo_relative_path(path)
}

app_path_within_root <- function(path, root) {
  path <- normalizePath(path, mustWork = file.exists(path))
  root <- normalizePath(root, mustWork = TRUE)
  identical(path, root) || startsWith(path, paste0(root, .Platform$file.sep))
}

app_runtime_paths_under_root <- function(root, exclude_pids = Sys.getpid()) {
  root <- normalizePath(root, mustWork = TRUE)
  proc_dirs <- list.dirs("/proc", recursive = FALSE, full.names = TRUE)
  proc_dirs <- proc_dirs[grepl("/[0-9]+$", proc_dirs)]
  proc_pids <- suppressWarnings(as.integer(basename(proc_dirs)))
  proc_dirs <- proc_dirs[is.na(proc_pids) | !proc_pids %in% as.integer(exclude_pids)]
  paths <- character()
  for (proc_dir in proc_dirs) {
    cwd <- tryCatch(
      suppressWarnings(normalizePath(file.path(proc_dir, "cwd"), mustWork = TRUE)),
      error = function(e) NA_character_
    )
    if (!is.na(cwd) && app_path_within_root(cwd, root)) paths <- c(paths, cwd)
    cmdline <- tryCatch(
      suppressWarnings(readBin(file.path(proc_dir, "cmdline"), "raw", n = 1.0e6)),
      error = function(e) raw()
    )
    if (length(cmdline)) {
      boundaries <- c(0L, which(cmdline == as.raw(0)), length(cmdline) + 1L)
      fields <- vapply(seq_len(length(boundaries) - 1L), function(i) {
        from <- boundaries[[i]] + 1L
        to <- boundaries[[i + 1L]] - 1L
        if (from > to) return("")
        rawToChar(cmdline[from:to])
      }, character(1L))
      candidates <- fields[startsWith(fields, root)]
      paths <- c(paths, candidates[file.exists(candidates)])
    }
  }
  tmux_paths <- tryCatch(
    system2(
      "tmux",
      c("list-panes", "-a", "-F", shQuote("#{pane_current_path}")),
      stdout = TRUE,
      stderr = FALSE
    ),
    error = function(e) character()
  )
  tmux_paths <- tmux_paths[nzchar(tmux_paths) & startsWith(tmux_paths, root)]
  sort(unique(normalizePath(c(paths, tmux_paths), mustWork = FALSE)))
}

app_glofas_heavy_artifact_manifest <- function(
  runs_root,
  delete_run_ids = character(),
  protected_run_ids = character(),
  active_paths = app_runtime_paths_under_root(runs_root),
  terminal_markers = c(
    ".fit_recovery_complete", ".reservoir_preflight_rejected",
    ".fit_recovery_failed", ".fit_recovery_aborted"
  )
) {
  runs_root <- normalizePath(runs_root, mustWork = TRUE)
  paths <- list.files(runs_root, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  paths <- paths[file.exists(paths) & !dir.exists(paths)]
  ext <- tolower(tools::file_ext(paths))
  heavy <- ext %in% app_generated_artifact_extensions() |
    grepl("(__design|checkpoint)[.]rds$", basename(paths), ignore.case = TRUE)
  paths <- normalizePath(paths[heavy], mustWork = TRUE)
  if (!length(paths)) {
    return(data.frame(
      path = character(), run_id = character(), size_bytes = numeric(), sha256 = character(),
      ownership = character(), lifecycle_class = character(), reason = character(),
      action = character(), stringsAsFactors = FALSE
    ))
  }
  prefix <- paste0(runs_root, .Platform$file.sep)
  relative <- sub(prefix, "", paths, fixed = TRUE)
  run_id <- vapply(strsplit(relative, .Platform$file.sep, fixed = TRUE), `[[`, character(1L), 1L)
  active_paths <- normalizePath(active_paths[file.exists(active_paths)], mustWork = FALSE)
  is_active <- vapply(paths, function(path) {
    any(vapply(active_paths, function(active) {
      identical(path, active) || startsWith(path, paste0(active, .Platform$file.sep)) ||
        startsWith(active, paste0(dirname(path), .Platform$file.sep))
    }, logical(1L)))
  }, logical(1L))
  run_dirs <- file.path(runs_root, run_id)
  terminal <- vapply(run_dirs, function(run_dir) {
    any(file.exists(file.path(run_dir, terminal_markers)))
  }, logical(1L))
  protected <- run_id %in% as.character(protected_run_ids)
  requested <- run_id %in% as.character(delete_run_ids)
  lifecycle_class <- ifelse(
    is_active, "active_current",
    ifelse(
      protected, "authoritative_or_contender",
      ifelse(requested & terminal, "old_regenerable_heavy_artifact", "unknown_or_not_approved")
    )
  )
  action <- ifelse(lifecycle_class == "old_regenerable_heavy_artifact", "delete", "keep")
  reason <- ifelse(
    is_active, "path is referenced by an active process or tmux pane",
    ifelse(
      protected, "run is explicitly protected",
      ifelse(
        requested & !terminal, "requested run lacks an audited terminal marker",
        ifelse(requested, "explicitly approved terminal run; heavy object is regenerable", "run was not explicitly approved for cleanup")
      )
    )
  )
  data.frame(
    path = paths,
    run_id = run_id,
    size_bytes = app_file_size_bytes(paths),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    ownership = "glofas_task_runs_root",
    lifecycle_class = lifecycle_class,
    reason = reason,
    action = action,
    stringsAsFactors = FALSE
  )
}

app_glofas_execute_artifact_manifest <- function(
  manifest,
  runs_root,
  execute = FALSE,
  active_paths = app_runtime_paths_under_root(runs_root)
) {
  runs_root <- normalizePath(runs_root, mustWork = TRUE)
  out <- manifest
  out$executed <- FALSE
  out$execution_status <- ifelse(out$action == "delete", "dry_run", "kept")
  if (!isTRUE(execute) || !nrow(out)) return(out)
  selected <- which(out$action == "delete")
  active_paths <- normalizePath(active_paths[file.exists(active_paths)], mustWork = FALSE)
  validated_paths <- character(length(selected))
  for (j in seq_along(selected)) {
    i <- selected[[j]]
    if (!identical(out$ownership[[i]], "glofas_task_runs_root") ||
        !identical(out$lifecycle_class[[i]], "old_regenerable_heavy_artifact")) {
      stop("Cleanup manifest contains an unapproved ownership or lifecycle class.", call. = FALSE)
    }
    path <- normalizePath(out$path[[i]], mustWork = TRUE)
    if (!app_path_within_root(path, runs_root)) {
      stop(sprintf("Cleanup path escaped the owned GloFAS root: %s.", path), call. = FALSE)
    }
    became_active <- any(vapply(active_paths, function(active) {
      identical(path, active) || startsWith(path, paste0(active, .Platform$file.sep)) ||
        startsWith(active, paste0(dirname(path), .Platform$file.sep))
    }, logical(1L)))
    if (isTRUE(became_active)) {
      stop(sprintf("Cleanup candidate became active after dry-run inventory: %s.", path), call. = FALSE)
    }
    if (!identical(app_sha256_file(path), out$sha256[[i]])) {
      stop(sprintf("Cleanup candidate changed after dry-run inventory: %s.", path), call. = FALSE)
    }
    validated_paths[[j]] <- path
  }
  for (j in seq_along(selected)) {
    i <- selected[[j]]
    path <- validated_paths[[j]]
    if (!file.remove(path)) stop(sprintf("Could not remove cleanup candidate: %s.", path), call. = FALSE)
    out$executed[[i]] <- TRUE
    out$execution_status[[i]] <- "deleted_verified"
  }
  out
}

app_git_ls_files <- function(args = character()) {
  out <- tryCatch(
    app_system2_repo("git", c("ls-files", args), stdout = TRUE, stderr = TRUE),
    error = function(e) character()
  )
  out[!grepl("^fatal:", out)]
}

app_file_size_bytes <- function(path) {
  info <- file.info(path)
  out <- as.numeric(info$size)
  out[!is.finite(out)] <- NA_real_
  out
}

app_file_size_sum <- function(path) {
  path <- path[file.exists(path)]
  if (!length(path)) return(0)
  sum(app_file_size_bytes(path), na.rm = TRUE)
}

app_root_relative_path <- function(path, root = app_repo_root()) {
  if (is.null(path) || !length(path) || is.na(path[[1L]]) || !nzchar(path[[1L]])) {
    return(NA_character_)
  }
  abs_path <- normalizePath(path, mustWork = file.exists(path))
  root <- normalizePath(root, mustWork = TRUE)
  prefix <- paste0(root, .Platform$file.sep)
  if (startsWith(abs_path, prefix)) {
    return(sub(prefix, "", abs_path, fixed = TRUE))
  }
  abs_path
}

app_artifact_inventory_row <- function(category, path, status = "", root = app_repo_root()) {
  abs_path <- if (grepl("^/", path)) path else file.path(root, path)
  data.frame(
    category = category,
    path = app_root_relative_path(abs_path, root = root),
    extension = tolower(tools::file_ext(path)),
    size_bytes = if (file.exists(abs_path)) app_file_size_bytes(abs_path) else NA_real_,
    git_status = status,
    stringsAsFactors = FALSE
  )
}

app_git_status_paths <- function() {
  lines <- tryCatch(
    app_system2_repo("git", c("status", "--short"), stdout = TRUE, stderr = TRUE),
    error = function(e) character()
  )
  lines <- lines[nzchar(lines)]
  if (!length(lines)) {
    return(data.frame(status = character(), path = character(), stringsAsFactors = FALSE))
  }
  data.frame(
    status = trimws(substr(lines, 1L, 2L)),
    path = trimws(substr(lines, 4L, nchar(lines))),
    stringsAsFactors = FALSE
  )
}

app_local_artifact_roots <- function() {
  c("application/runs", "application/cache", "application/logs", "application/outputs")
}

app_list_local_generated_artifacts <- function(root = app_repo_root()) {
  roots <- file.path(root, app_local_artifact_roots())
  roots <- roots[dir.exists(roots)]
  if (!length(roots)) return(character())
  paths <- unlist(lapply(roots, list.files, recursive = TRUE, full.names = TRUE, all.files = FALSE), use.names = FALSE)
  paths[file.exists(paths) & !dir.exists(paths)]
}

app_generated_artifact_inventory <- function(
  root = app_repo_root(),
  large_file_bytes = 50 * 1024^2
) {
  root <- normalizePath(root, mustWork = TRUE)
  generated_ext <- app_generated_artifact_extensions()
  rows <- list()

  tracked <- app_git_ls_files()
  tracked_ext <- tolower(tools::file_ext(tracked))
  tracked_generated <- tracked[tracked_ext %in% generated_ext]
  for (path in tracked_generated) {
    rows[[length(rows) + 1L]] <- app_artifact_inventory_row(
      "tracked_generated_extension",
      path,
      status = "tracked",
      root = root
    )
  }

  status <- app_git_status_paths()
  if (nrow(status)) {
    status_ext <- tolower(tools::file_ext(status$path))
    generated_status <- status[status_ext %in% generated_ext, , drop = FALSE]
    for (i in seq_len(nrow(generated_status))) {
      rows[[length(rows) + 1L]] <- app_artifact_inventory_row(
        "working_tree_generated_extension",
        generated_status$path[[i]],
        status = generated_status$status[[i]],
        root = root
      )
    }
  }

  local_paths <- app_list_local_generated_artifacts(root = root)
  if (length(local_paths)) {
    local_ext <- tolower(tools::file_ext(local_paths))
    local_size <- app_file_size_bytes(local_paths)
    keep <- local_ext %in% generated_ext | (is.finite(local_size) & local_size >= large_file_bytes)
    for (path in local_paths[keep]) {
      rows[[length(rows) + 1L]] <- app_artifact_inventory_row(
        "ignored_local_generated_or_large",
        path,
        status = "ignored_or_untracked",
        root = root
      )
    }
  }

  out <- app_bind_rows_fill(rows)
  if (!nrow(out)) {
    out <- data.frame(
      category = character(),
      path = character(),
      extension = character(),
      size_bytes = numeric(),
      git_status = character(),
      stringsAsFactors = FALSE
    )
  }
  out[order(out$category, out$path), , drop = FALSE]
}

app_infer_run_type <- function(run_id) {
  x <- tolower(run_id)
  if (grepl("reservoir_screen", x)) return("reservoir_screen")
  if (grepl("design_check|design_gate", x)) return("design_gate")
  if (grepl("smoke", x)) return("smoke")
  if (grepl("pilot", x)) return("pilot")
  if (grepl("tau[0-9].*main|main1000|_main_", x)) return("main_or_sensitivity")
  if (grepl("source_figures|source_audit|authoritative_source", x)) return("source_audit")
  "other"
}

app_run_required_readiness_failures <- function(readiness_path) {
  if (!file.exists(readiness_path)) return(NA_integer_)
  readiness <- tryCatch(app_read_csv(readiness_path), error = function(e) data.frame())
  if (!nrow(readiness) || !all(c("required", "status") %in% names(readiness))) return(NA_integer_)
  sum(app_as_bool_vec(readiness$required) & readiness$status != "ok")
}

app_promoted_run_ids <- function(root = app_repo_root(), tables_path = "tables") {
  tables_dir <- app_resolve_path(tables_path, base = root, must_work = FALSE)
  if (!dir.exists(tables_dir)) return(character())
  manifests <- list.files(
    tables_dir,
    pattern = "^glofas_application_promotion_manifest__.*[.]csv$",
    full.names = TRUE
  )
  run_ids <- character()
  for (path in manifests) {
    manifest <- tryCatch(app_read_csv(path), error = function(e) data.frame())
    if ("run_id" %in% names(manifest)) {
      run_ids <- c(run_ids, as.character(manifest$run_id))
    }
  }
  sort(unique(run_ids[nzchar(run_ids)]))
}

app_run_level_artifact_inventory <- function(
  root = app_repo_root(),
  runs_path = "application/runs",
  generated_outputs_path = "application/outputs/generated",
  promoted_tables_path = "tables"
) {
  root <- normalizePath(root, mustWork = TRUE)
  runs_dir <- app_resolve_path(runs_path, base = root, must_work = FALSE)
  generated_dir <- app_resolve_path(generated_outputs_path, base = root, must_work = FALSE)
  promoted_ids <- app_promoted_run_ids(root = root, tables_path = promoted_tables_path)

  empty_inventory <- function() {
    return(data.frame(
      run_id = character(),
      run_type = character(),
      run_path = character(),
      total_size_bytes = numeric(),
      heavy_object_count = integer(),
      heavy_object_size_bytes = numeric(),
      largest_heavy_object_path = character(),
      largest_heavy_object_size_bytes = numeric(),
      has_launch_readiness_report = logical(),
      required_readiness_failures = integer(),
      has_generated_outputs = logical(),
      generated_output_file_count = integer(),
      generated_output_size_bytes = numeric(),
      has_promoted_outputs = logical(),
      has_post_fit_analysis = logical(),
      has_run_config_yaml = logical(),
      has_model_grid_used = logical(),
      has_quantile_grid_used = logical(),
      has_fit_manifest = logical(),
      has_design_summary = logical(),
      stringsAsFactors = FALSE
    ))
  }

  if (!dir.exists(runs_dir)) {
    return(empty_inventory())
  }

  run_dirs <- list.files(runs_dir, full.names = TRUE, recursive = FALSE)
  run_dirs <- run_dirs[dir.exists(run_dirs)]
  if (!length(run_dirs)) {
    return(empty_inventory())
  }

  rows <- vector("list", length(run_dirs))
  generated_ext <- app_generated_artifact_extensions()

  for (i in seq_along(run_dirs)) {
    run_dir <- run_dirs[[i]]
    run_id <- basename(run_dir)
    all_files <- list.files(run_dir, recursive = TRUE, full.names = TRUE, all.files = FALSE)
    all_files <- all_files[file.exists(all_files) & !dir.exists(all_files)]

    heavy_files <- all_files[tolower(tools::file_ext(all_files)) %in% generated_ext]
    heavy_sizes <- app_file_size_bytes(heavy_files)
    largest_idx <- if (length(heavy_files) && any(is.finite(heavy_sizes))) {
      which.max(replace(heavy_sizes, !is.finite(heavy_sizes), -Inf))
    } else {
      NA_integer_
    }

    generated_run_dir <- file.path(generated_dir, run_id)
    generated_files <- if (dir.exists(generated_run_dir)) {
      paths <- list.files(generated_run_dir, recursive = TRUE, full.names = TRUE, all.files = FALSE)
      paths[file.exists(paths) & !dir.exists(paths)]
    } else {
      character()
    }

    readiness_path <- file.path(run_dir, "tables", "launch_readiness_report.csv")
    rows[[i]] <- data.frame(
      run_id = run_id,
      run_type = app_infer_run_type(run_id),
      run_path = app_root_relative_path(run_dir, root = root),
      total_size_bytes = app_file_size_sum(all_files),
      heavy_object_count = length(heavy_files),
      heavy_object_size_bytes = app_file_size_sum(heavy_files),
      largest_heavy_object_path = if (is.na(largest_idx)) NA_character_ else app_root_relative_path(heavy_files[[largest_idx]], root = root),
      largest_heavy_object_size_bytes = if (is.na(largest_idx)) NA_real_ else heavy_sizes[[largest_idx]],
      has_launch_readiness_report = file.exists(readiness_path),
      required_readiness_failures = app_run_required_readiness_failures(readiness_path),
      has_generated_outputs = dir.exists(generated_run_dir) && length(generated_files) > 0L,
      generated_output_file_count = length(generated_files),
      generated_output_size_bytes = app_file_size_sum(generated_files),
      has_promoted_outputs = run_id %in% promoted_ids,
      has_post_fit_analysis = dir.exists(file.path(run_dir, "figures", "post_fit_analysis")),
      has_run_config_yaml = file.exists(file.path(run_dir, "manifest", "run_config.yaml")),
      has_model_grid_used = file.exists(file.path(run_dir, "manifest", "model_grid_used.csv")),
      has_quantile_grid_used = file.exists(file.path(run_dir, "manifest", "quantile_grid_used.csv")),
      has_fit_manifest = file.exists(file.path(run_dir, "manifest", "qdesn_discrepancy_fit_manifest.csv")),
      has_design_summary = file.exists(file.path(run_dir, "tables", "qdesn_discrepancy_design_summary.csv")),
      stringsAsFactors = FALSE
    )
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out[order(out$run_type, out$run_id), , drop = FALSE]
}
