#!/usr/bin/env Rscript
# Purpose: collect reservoir-screening shard outputs and rank candidate
# reservoirs after a parallel screening campaign.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  run_id_prefix = "",
  output_dir = "",
  require_completed = "true"
))

prefix <- as.character(args$run_id_prefix %||% "")[[1L]]
if (!nzchar(prefix)) stop("--run_id_prefix is required.", call. = FALSE)

runs_root <- app_path("application/runs")
run_dirs <- list.dirs(runs_root, full.names = TRUE, recursive = FALSE)
run_dirs <- run_dirs[startsWith(basename(run_dirs), prefix)]
if (!length(run_dirs)) {
  stop(sprintf("No run directories matched prefix '%s'.", prefix), call. = FALSE)
}

require_completed <- app_as_bool(args$require_completed)
if (require_completed) {
  completed <- vapply(run_dirs, function(d) {
    status_path <- file.path(d, "logs", "03_screen_reservoir_candidate_grid_status.csv")
    file.exists(status_path) && any(app_read_csv(status_path)$status == "completed")
  }, logical(1L))
  if (!all(completed)) {
    missing <- basename(run_dirs[!completed])
    stop(
      sprintf(
        "Some matching shard runs are not completed: %s.",
        paste(missing, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

read_table <- function(d, name) {
  path <- file.path(d, "tables", name)
  if (!file.exists(path)) return(data.frame())
  x <- app_read_csv(path)
  x$screening_run_id <- basename(d)
  x
}

coerce_numeric_columns <- function(x, cols) {
  for (nm in intersect(cols, names(x))) {
    x[[nm]] <- suppressWarnings(as.numeric(x[[nm]]))
  }
  x
}

prefer_merged_column <- function(x, name) {
  y_name <- paste0(name, ".y")
  x_name <- paste0(name, ".x")
  if (y_name %in% names(x)) {
    x[[name]] <- x[[y_name]]
  } else if (x_name %in% names(x)) {
    x[[name]] <- x[[x_name]]
  }
  x
}

arch <- app_bind_rows_fill(lapply(run_dirs, read_table, "reservoir_screening_architecture_summary.csv"))
state <- app_bind_rows_fill(lapply(run_dirs, read_table, "reservoir_screening_state_diagnostics.csv"))
layer <- app_bind_rows_fill(lapply(run_dirs, read_table, "reservoir_screening_layer_stability.csv"))
suggestions <- app_bind_rows_fill(lapply(run_dirs, read_table, "reservoir_screening_repair_suggestions.csv"))

if (!nrow(arch)) stop("No architecture summary rows were found.", call. = FALSE)
if (!nrow(state)) stop("No state diagnostic rows were found.", call. = FALSE)

state <- coerce_numeric_columns(state, c(
  "saturation_fraction",
  "relative_effective_rank_entropy",
  "relative_effective_rank_participation",
  "condition_z",
  "condition_cov",
  "max_abs_corr",
  "near_duplicate_fraction"
))

decision_rank <- function(x) {
  x <- as.character(x)
  out <- rep(4L, length(x))
  out[x == "pass"] <- 1L
  out[x == "repair"] <- 2L
  out[x == "reject"] <- 3L
  out
}

state_by_spec <- do.call(rbind, lapply(split(state, state$spec_id), function(x) {
  data.frame(
    spec_id = x$spec_id[[1L]],
    worst_state_decision_rank = max(decision_rank(x$decision), na.rm = TRUE),
    max_saturation_fraction = max(x$saturation_fraction, na.rm = TRUE),
    min_relative_effective_rank_entropy = min(x$relative_effective_rank_entropy, na.rm = TRUE),
    min_relative_effective_rank_participation = min(x$relative_effective_rank_participation, na.rm = TRUE),
    max_condition_z = max(x$condition_z, na.rm = TRUE),
    max_condition_cov = max(x$condition_cov, na.rm = TRUE),
    max_abs_corr = max(x$max_abs_corr, na.rm = TRUE),
    max_near_duplicate_fraction = max(x$near_duplicate_fraction, na.rm = TRUE),
    n_state_reports = nrow(x),
    stringsAsFactors = FALSE
  )
}))

layer_by_spec <- if (nrow(layer)) {
  do.call(rbind, lapply(split(layer, layer$spec_id), function(x) {
    data.frame(
      spec_id = x$spec_id[[1L]],
      worst_layer_decision_rank = max(decision_rank(x$decision), na.rm = TRUE),
      n_layer_reports = nrow(x),
      stringsAsFactors = FALSE
    )
  }))
} else {
  data.frame(spec_id = character(), worst_layer_decision_rank = integer(), n_layer_reports = integer())
}

ranked <- merge(arch, state_by_spec, by = "spec_id", all.x = TRUE, sort = FALSE)
ranked <- merge(ranked, layer_by_spec, by = "spec_id", all.x = TRUE, sort = FALSE)
for (nm in c(
  "max_saturation_fraction",
  "min_relative_effective_rank_entropy",
  "min_relative_effective_rank_participation",
  "max_condition_z",
  "max_condition_cov",
  "max_abs_corr",
  "max_near_duplicate_fraction"
)) {
  ranked <- prefer_merged_column(ranked, nm)
}
ranked <- coerce_numeric_columns(ranked, c(
  "max_saturation_fraction",
  "min_relative_effective_rank_entropy",
  "min_relative_effective_rank_participation",
  "max_condition_z",
  "max_condition_cov",
  "max_abs_corr",
  "max_near_duplicate_fraction",
  "worst_state_decision_rank",
  "worst_layer_decision_rank"
))
ranked$architecture_decision_rank <- decision_rank(ranked$decision)
ranked$case_id <- if ("base_case" %in% names(ranked)) ranked$base_case else ranked$spec_id
ranked$launch_admissible <- ranked$decision %in% c("pass", "repair") &
  ranked$worst_state_decision_rank <= 2L &
  (is.na(ranked$worst_layer_decision_rank) | ranked$worst_layer_decision_rank <= 2L)

ranked <- ranked[order(
  ranked$case_id,
  ranked$architecture_decision_rank,
  ranked$worst_state_decision_rank,
  ranked$max_saturation_fraction,
  -ranked$min_relative_effective_rank_entropy,
  ranked$max_condition_cov
), , drop = FALSE]

best_by_case <- do.call(rbind, lapply(split(ranked, ranked$case_id), function(x) {
  x[order(
    !x$launch_admissible,
    x$architecture_decision_rank,
    x$worst_state_decision_rank,
    x$max_saturation_fraction,
    -x$min_relative_effective_rank_entropy,
    x$max_condition_cov
  ), , drop = FALSE][1L, , drop = FALSE]
}))

out_dir <- as.character(args$output_dir %||% "")[[1L]]
if (!nzchar(out_dir)) {
  out_dir <- file.path(app_path("application/outputs/generated/reservoir_screening"), prefix)
} else {
  out_dir <- app_resolve_path(out_dir, must_work = FALSE)
}
app_ensure_dir(out_dir)

app_write_csv(arch, file.path(out_dir, "combined_architecture_summary.csv"))
app_write_csv(state, file.path(out_dir, "combined_state_diagnostics.csv"))
app_write_csv(layer, file.path(out_dir, "combined_layer_stability.csv"))
app_write_csv(suggestions, file.path(out_dir, "combined_repair_suggestions.csv"))
app_write_csv(ranked, file.path(out_dir, "ranked_candidates.csv"))
app_write_csv(best_by_case, file.path(out_dir, "best_candidate_by_case.csv"))

cat(out_dir, "\n")
