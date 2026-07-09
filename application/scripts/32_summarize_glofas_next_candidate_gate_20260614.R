#!/usr/bin/env Rscript
# Purpose: summarize health and candidate-level ranking for the controlled
# GloFAS p05/p50/p95 next-candidate gate.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))

args <- app_parse_args(list(
  runtime_dir = "local_trackers/runtime_configs/glofas_next_candidate_gate_20260614"
))

runtime_dir <- app_path(args$runtime_dir)
manifest_path <- file.path(runtime_dir, "launch_manifest.csv")
if (!file.exists(manifest_path)) stop(sprintf("Missing launch manifest: %s", manifest_path), call. = FALSE)

read_csv_or_null <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(app_read_csv(path), error = function(e) NULL)
}

stage_state <- function(run_dir) {
  stages <- c(
    "00_check_inputs", "00_audit_input_bundle", "01_build_panel",
    "02_make_input_figures", "03_fit_models", "04_score_models",
    "05_make_outputs", "06_preflight_launch"
  )
  states <- vapply(stages, function(stage) {
    started <- file.exists(file.path(run_dir, "logs", sprintf("%s_started.csv", stage)))
    status_path <- file.path(run_dir, "logs", sprintf("%s_status.csv", stage))
    if (file.exists(status_path)) {
      x <- read_csv_or_null(status_path)
      if (!is.null(x) && nrow(x) && "status" %in% names(x)) return(as.character(utils::tail(x$status, 1L)))
      return("status_empty")
    }
    if (started) return("running")
    "pending"
  }, character(1L))
  idx <- suppressWarnings(max(which(states != "pending"), na.rm = TRUE))
  if (!is.finite(idx)) return(list(stage = "not_started", status = "pending"))
  list(stage = stages[[idx]], status = states[[idx]])
}

session_live <- function(session) {
  sessions <- tryCatch(system("tmux list-sessions 2>/dev/null", intern = TRUE), error = function(e) character())
  any(grepl(as.character(session), sessions, fixed = TRUE))
}

extract_fit <- function(run_dir, qdesn_fit_id) {
  fit <- read_csv_or_null(file.path(run_dir, "tables", "fit_status.csv"))
  out <- list(status = "pending", runtime_min = NA_real_, message = NA_character_)
  if (is.null(fit) || !nrow(fit)) return(out)
  idx <- which(as.character(fit$fit_id) == as.character(qdesn_fit_id))
  row <- if (length(idx)) fit[idx[[1L]], , drop = FALSE] else fit[nrow(fit), , drop = FALSE]
  out$status <- as.character(row$status[[1L]])
  out$message <- as.character(row$message[[1L]])
  if ("runtime_seconds" %in% names(row)) out$runtime_min <- as.numeric(row$runtime_seconds[[1L]]) / 60
  out
}

extract_score <- function(run_dir) {
  score <- read_csv_or_null(file.path(run_dir, "tables", "score_summary.csv"))
  out <- list(q_check = NA_real_, raw_check = NA_real_, improvement = NA_real_)
  if (is.null(score) || !nrow(score) || !"check_loss_mean" %in% names(score)) return(out)
  ids <- as.character(score$model_id %||% score$fit_id %||% "")
  qidx <- which(grepl("qdesn", ids, ignore.case = TRUE))
  ridx <- which(grepl("raw_glofas|raw", ids, ignore.case = TRUE))
  if (length(qidx)) out$q_check <- as.numeric(score$check_loss_mean[qidx[[1L]]])
  if (length(ridx)) out$raw_check <- as.numeric(score$check_loss_mean[ridx[[1L]]])
  if (is.finite(out$q_check) && is.finite(out$raw_check) && out$raw_check != 0) {
    out$improvement <- (out$raw_check - out$q_check) / abs(out$raw_check)
  }
  out
}

manifest <- app_read_csv(manifest_path)
rows <- lapply(seq_len(nrow(manifest)), function(i) {
  m <- manifest[i, , drop = FALSE]
  run_dir <- app_path(file.path("application/runs", m$run_id[[1L]]))
  st <- stage_state(run_dir)
  fit <- extract_fit(run_dir, m$qdesn_fit_id[[1L]])
  score <- extract_score(run_dir)
  live <- session_live(m$session[[1L]])
  status <- if (identical(fit$status, "completed") && is.finite(score$q_check)) {
    "complete_scored"
  } else if (grepl("fail|error", fit$status, ignore.case = TRUE)) {
    "failed"
  } else if (isTRUE(live)) {
    "running"
  } else if (dir.exists(run_dir)) {
    "partial_or_waiting"
  } else {
    "not_started"
  }
  data.frame(
    run_index = as.integer(m$run_index[[1L]]),
    candidate_id = as.character(m$candidate_id[[1L]]),
    candidate_name = as.character(m$candidate_name[[1L]]),
    quantile_id = as.character(m$quantile_id[[1L]]),
    quantile_level = as.numeric(m$quantile_level[[1L]]),
    run_id = as.character(m$run_id[[1L]]),
    session = as.character(m$session[[1L]]),
    core = as.integer(m$core[[1L]]),
    live = isTRUE(live),
    status = status,
    latest_stage = st$stage,
    stage_status = st$status,
    fit_status = fit$status,
    runtime_min = fit$runtime_min,
    qdesn_check_loss = score$q_check,
    raw_check_loss = score$raw_check,
    relative_improvement = score$improvement,
    message = fit$message,
    stringsAsFactors = FALSE
  )
})

health <- app_bind_rows_fill(rows)
health <- health[order(health$run_index), , drop = FALSE]
app_write_csv(health, file.path(runtime_dir, "health_check_latest.csv"))

complete <- health[health$status == "complete_scored", , drop = FALSE]
if (nrow(complete)) {
  ranking <- aggregate(
    cbind(qdesn_check_loss, raw_check_loss, relative_improvement) ~ candidate_id + candidate_name,
    complete,
    function(z) c(mean = mean(z, na.rm = TRUE), min = min(z, na.rm = TRUE), max = max(z, na.rm = TRUE))
  )
  flatten_mat_col <- function(x, prefix) {
    if (is.matrix(x)) {
      out <- as.data.frame(x)
      names(out) <- paste(prefix, colnames(x), sep = "_")
      out
    } else {
      stats <- do.call(rbind, x)
      out <- as.data.frame(stats)
      names(out) <- paste(prefix, colnames(stats), sep = "_")
      out
    }
  }
  ranking_flat <- cbind(
    ranking[, c("candidate_id", "candidate_name"), drop = FALSE],
    flatten_mat_col(ranking$qdesn_check_loss, "qdesn_check_loss"),
    flatten_mat_col(ranking$raw_check_loss, "raw_check_loss"),
    flatten_mat_col(ranking$relative_improvement, "relative_improvement")
  )
  counts <- aggregate(status ~ candidate_id + candidate_name, health, function(z) {
    paste(names(table(z)), as.integer(table(z)), sep = "=", collapse = ";")
  })
  names(counts)[names(counts) == "status"] <- "status_counts"
  ranking_flat <- merge(ranking_flat, counts, by = c("candidate_id", "candidate_name"), all.x = TRUE)
  ranking_flat <- ranking_flat[order(ranking_flat$qdesn_check_loss_mean, na.last = TRUE), , drop = FALSE]
  app_write_csv(ranking_flat, file.path(runtime_dir, "candidate_ranking_latest.csv"))
} else {
  ranking_flat <- data.frame()
  app_write_csv(ranking_flat, file.path(runtime_dir, "candidate_ranking_latest.csv"))
}

cat("\nGloFAS next-candidate gate health\n")
print(health[, c(
  "candidate_id", "candidate_name", "quantile_id", "status", "latest_stage",
  "stage_status", "fit_status", "runtime_min", "qdesn_check_loss", "raw_check_loss"
)], row.names = FALSE)

if (nrow(ranking_flat)) {
  cat("\nCandidate ranking from completed scored rows\n")
  print(ranking_flat, row.names = FALSE)
} else {
  cat("\nCandidate ranking unavailable: no completed scored rows yet.\n")
}

cat("\nWrote:\n")
cat(file.path(args$runtime_dir, "health_check_latest.csv"), "\n")
cat(file.path(args$runtime_dir, "candidate_ranking_latest.csv"), "\n")
