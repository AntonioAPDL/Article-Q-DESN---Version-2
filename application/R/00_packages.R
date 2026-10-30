# Shared utilities for the GloFAS Q-DESN application workflow.

app_env <- new.env(parent = emptyenv())

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L) y else x
}

app_find_repo_root <- function(start = getwd()) {
  path <- normalizePath(start, mustWork = TRUE)
  repeat {
    if (file.exists(file.path(path, "main.tex")) &&
        dir.exists(file.path(path, "application"))) {
      return(path)
    }
    parent <- dirname(path)
    if (identical(parent, path)) {
      stop("Could not locate Article-Q-DESN repository root.", call. = FALSE)
    }
    path <- parent
  }
}

app_set_repo_root <- function(root) {
  assign("repo_root", normalizePath(root, mustWork = TRUE), envir = app_env)
  invisible(app_env$repo_root)
}

app_repo_root <- function() {
  if (exists("repo_root", envir = app_env, inherits = FALSE)) {
    return(get("repo_root", envir = app_env, inherits = FALSE))
  }
  app_set_repo_root(app_find_repo_root())
}

app_path <- function(...) {
  file.path(app_repo_root(), ...)
}

app_resolve_path <- function(path, base = app_repo_root(), must_work = FALSE) {
  if (is.null(path) || !length(path) || !nzchar(as.character(path[[1L]]))) {
    stop("Cannot resolve an empty path.", call. = FALSE)
  }
  out <- if (grepl("^/", path)) path else file.path(base, path)
  normalizePath(out, mustWork = must_work)
}

app_prefer_repo_relative_path <- function(path) {
  abs_path <- normalizePath(path, mustWork = file.exists(path))
  root <- normalizePath(app_repo_root(), mustWork = TRUE)
  prefix <- paste0(root, .Platform$file.sep)
  if (startsWith(abs_path, prefix)) {
    return(sub(prefix, "", abs_path, fixed = TRUE))
  }
  abs_path
}

app_script_repo_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg)) {
    script_file <- normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE)
    return(normalizePath(file.path(dirname(script_file), "..", ".."), mustWork = TRUE))
  }
  app_find_repo_root()
}

app_parse_args <- function(defaults = list()) {
  args <- commandArgs(trailingOnly = TRUE)
  out <- defaults
  i <- 1L
  while (i <= length(args)) {
    token <- args[[i]]
    if (!startsWith(token, "--")) {
      i <- i + 1L
      next
    }
    token <- sub("^--", "", token)
    if (grepl("=", token, fixed = TRUE)) {
      parts <- strsplit(token, "=", fixed = TRUE)[[1L]]
      out[[parts[[1L]]]] <- paste(parts[-1L], collapse = "=")
      i <- i + 1L
    } else {
      key <- token
      nxt <- if (i < length(args)) args[[i + 1L]] else NULL
      if (!is.null(nxt) && !startsWith(nxt, "--")) {
        out[[key]] <- nxt
        i <- i + 2L
      } else {
        out[[key]] <- TRUE
        i <- i + 1L
      }
    }
  }
  out
}

app_require_namespace <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf("Required R package '%s' is not installed.", pkg), call. = FALSE)
  }
  invisible(TRUE)
}

app_read_yaml <- function(path) {
  app_require_namespace("yaml")
  yaml::read_yaml(path)
}

app_write_yaml <- function(x, path) {
  app_require_namespace("yaml")
  app_ensure_dir(dirname(path))
  yaml::write_yaml(x, path)
  invisible(path)
}

app_write_json <- function(x, path, pretty = TRUE) {
  app_require_namespace("jsonlite")
  app_ensure_dir(dirname(path))
  jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = pretty, null = "null")
  invisible(path)
}

app_read_csv <- function(path, required = TRUE) {
  if (!file.exists(path)) {
    if (isTRUE(required)) stop(sprintf("Missing CSV file: %s", path), call. = FALSE)
    return(data.frame())
  }
  read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

app_read_table <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext %in% c("csv", "txt")) return(app_read_csv(path))
  if (ext == "rds") return(readRDS(path))
  if (ext == "parquet") {
    if (!requireNamespace("arrow", quietly = TRUE)) {
      stop("Reading parquet inputs requires the R package 'arrow'.", call. = FALSE)
    }
    return(as.data.frame(arrow::read_parquet(path)))
  }
  stop(sprintf("Unsupported input file extension '%s' for %s.", ext, path), call. = FALSE)
}

app_table_profile <- function(path, date_columns = character()) {
  x <- app_read_table(path)
  date_cols <- intersect(date_columns %||% character(), names(x))
  dates <- as.Date(character())
  for (nm in date_cols) {
    dates <- c(dates, suppressWarnings(as.Date(x[[nm]])))
  }
  dates <- dates[!is.na(dates)]
  list(
    row_count = nrow(x),
    column_count = ncol(x),
    date_min = if (length(dates)) as.character(min(dates)) else NA_character_,
    date_max = if (length(dates)) as.character(max(dates)) else NA_character_,
    column_names = names(x)
  )
}

app_write_csv <- function(x, path) {
  app_ensure_dir(dirname(path))
  write.csv(x, path, row.names = FALSE, na = "")
  invisible(path)
}

app_bind_rows_fill <- function(rows) {
  rows <- rows[!vapply(rows, is.null, logical(1L))]
  if (!length(rows)) return(data.frame())
  all_names <- unique(unlist(lapply(rows, names), use.names = FALSE))
  out <- lapply(rows, function(x) {
    missing <- setdiff(all_names, names(x))
    for (nm in missing) x[[nm]] <- NA
    x[, all_names, drop = FALSE]
  })
  ans <- do.call(rbind, out)
  rownames(ans) <- NULL
  ans
}

app_ensure_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  invisible(path)
}

app_as_bool <- function(x) {
  if (is.logical(x)) return(isTRUE(x))
  tolower(as.character(x)[1L]) %in% c("true", "t", "yes", "y", "1")
}

app_enabled_rows <- function(x) {
  if (!nrow(x) || !"enabled" %in% names(x)) return(x)
  x[app_as_bool_vec(x$enabled), , drop = FALSE]
}

app_as_bool_vec <- function(x) {
  if (is.logical(x)) return(x)
  tolower(as.character(x)) %in% c("true", "t", "yes", "y", "1")
}

app_sha256_file <- function(path) {
  if (!file.exists(path)) stop(sprintf("Cannot hash missing file: %s", path), call. = FALSE)
  unname(tools::sha256sum(path))
}

app_file_info_row <- function(path) {
  info <- file.info(path)
  data.frame(
    local_path = path,
    file_size_bytes = as.numeric(info$size),
    modified_time = format(info$mtime, "%Y-%m-%d %H:%M:%S %Z"),
    stringsAsFactors = FALSE
  )
}

app_hash_files <- function(paths) {
  paths <- normalizePath(paths[file.exists(paths)], mustWork = TRUE)
  if (!length(paths)) return("nohash")
  tmp <- tempfile("app_hash_")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(vapply(paths, app_sha256_file, character(1L)), tmp)
  substr(app_sha256_file(tmp), 1L, 12L)
}

app_git_sha <- function(short = TRUE) {
  flag <- if (isTRUE(short)) "--short" else ""
  out <- tryCatch(
    app_system2_repo("git", c("rev-parse", flag, "HEAD"), stdout = TRUE, stderr = TRUE),
    error = function(e) NA_character_
  )
  if (!length(out)) NA_character_ else out[[1L]]
}

app_system2_repo <- function(command, args = character(), stdout = TRUE, stderr = TRUE) {
  old <- setwd(app_repo_root())
  on.exit(setwd(old), add = TRUE)
  system2(command, args, stdout = stdout, stderr = stderr)
}

app_write_git_state <- function(path) {
  app_ensure_dir(dirname(path))
  lines <- c(
    "git rev-parse HEAD",
    app_system2_repo("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = TRUE),
    "",
    "git status --short",
    app_system2_repo("git", c("status", "--short"), stdout = TRUE, stderr = TRUE),
    "",
    "git remote -v",
    app_system2_repo("git", c("remote", "-v"), stdout = TRUE, stderr = TRUE)
  )
  writeLines(lines, path)
  invisible(path)
}

app_write_session_info <- function(path) {
  app_ensure_dir(dirname(path))
  capture.output(sessionInfo(), file = path)
  invisible(path)
}

app_read_config <- function(config_path = app_path("application/config/glofas_discrepancy_application.yaml")) {
  cfg <- app_read_yaml(config_path)
  cfg$.__config_path__ <- normalizePath(config_path, mustWork = TRUE)
  cfg
}

app_config_path <- function(cfg, key) {
  val <- cfg$paths[[key]]
  if (is.null(val)) stop(sprintf("Config path '%s' is not defined.", key), call. = FALSE)
  if (grepl("^/", val)) val else app_path(val)
}

app_run_id <- function(cfg) {
  hash_keys <- c("input_bundle", "cutoffs", "quantile_grid", "model_grid", "figure_specs")
  hash_paths <- c(cfg$.__config_path__)
  for (key in hash_keys) {
    if (!is.null(cfg$paths[[key]])) hash_paths <- c(hash_paths, app_config_path(cfg, key))
  }
  cfg_hash <- app_hash_files(hash_paths)
  sprintf(
    "glofas_qdesn_%s__git-%s__cfg-%s",
    format(Sys.time(), "%Y%m%d_%H%M%S"),
    app_git_sha(short = TRUE) %||% "unknown",
    cfg_hash
  )
}

app_create_run_dirs <- function(cfg, run_id = app_run_id(cfg)) {
  run_dir <- file.path(app_config_path(cfg, "runs"), run_id)
  dirs <- list(
    run_dir = run_dir,
    manifest = file.path(run_dir, "manifest"),
    tables = file.path(run_dir, "tables"),
    objects = file.path(run_dir, "objects"),
    logs = file.path(run_dir, "logs"),
    figures = file.path(run_dir, "figures")
  )
  invisible(lapply(dirs, app_ensure_dir))
  dirs
}

app_stage_start <- function(stage, run_dirs) {
  app_ensure_dir(run_dirs$logs)
  status <- data.frame(
    stage = stage,
    status = "started",
    time = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    stringsAsFactors = FALSE
  )
  app_write_csv(status, file.path(run_dirs$logs, paste0(stage, "_started.csv")))
}

app_stage_done <- function(stage, run_dirs, status = "completed", message = "") {
  out <- data.frame(
    stage = stage,
    status = status,
    time = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    message = message,
    stringsAsFactors = FALSE
  )
  app_write_csv(out, file.path(run_dirs$logs, paste0(stage, "_status.csv")))
}
