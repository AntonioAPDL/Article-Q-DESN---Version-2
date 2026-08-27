#!/usr/bin/env Rscript
# Purpose: turn the completed overnight reservoir ladder screen into a compact,
# reproducible multiseed shortlist. This script writes screening-only candidate
# grids; it does not launch VB/MCMC application fits.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  triage_candidates = "application/outputs/generated/reservoir_screening/reservoir_overnight_ladder_full_20260525/pilot_triage_candidates.csv",
  output_grid = "application/config/reservoir_candidate_grid_latent_path_shortlist_multiseed_20260525.csv",
  output_summary = "application/config/glofas_shortlist_multiseed_screen_20260525.csv",
  max_positive_control = "10",
  max_shallow = "12",
  max_two_layer = "8",
  max_total = "30"
))

triage_path <- app_resolve_path(args$triage_candidates, must_work = TRUE)
triage <- app_read_csv(triage_path)

required <- c(
  "spec_id", "family", "base_case", "D", "n_vector", "n_tilde", "m",
  "alpha", "rho", "pi_w", "pi_in", "win_scale_global", "win_scale_bias",
  "input_bound", "launch_seed", "triage_class", "decision",
  "max_saturation_fraction", "min_relative_effective_rank_entropy",
  "max_condition_cov", "max_abs_corr"
)
missing <- setdiff(required, names(triage))
if (length(missing)) {
  stop(sprintf("Triage table is missing required fields: %s.", paste(missing, collapse = ", ")), call. = FALSE)
}

as_num <- function(x) suppressWarnings(as.numeric(x))
triage$max_saturation_fraction <- as_num(triage$max_saturation_fraction)
triage$min_relative_effective_rank_entropy <- as_num(triage$min_relative_effective_rank_entropy)
triage$max_condition_cov <- as_num(triage$max_condition_cov)
triage$max_abs_corr <- as_num(triage$max_abs_corr)

eligible <- triage[
  triage$triage_class == "main_admissible" &
    triage$decision %in% c("pass", "repair") &
    is.finite(triage$max_saturation_fraction) &
    is.finite(triage$min_relative_effective_rank_entropy) &
    is.finite(triage$max_condition_cov) &
    is.finite(triage$max_abs_corr),
  ,
  drop = FALSE
]
if (!nrow(eligible)) stop("No main-admissible candidates were available for shortlisting.", call. = FALSE)

rank01 <- function(x, decreasing = FALSE) {
  if (decreasing) x <- -x
  r <- rank(x, ties.method = "average", na.last = "keep")
  r / max(r, na.rm = TRUE)
}

eligible$score_saturation <- rank01(eligible$max_saturation_fraction)
eligible$score_rank <- rank01(eligible$min_relative_effective_rank_entropy, decreasing = TRUE)
eligible$score_condition <- rank01(log10(pmax(eligible$max_condition_cov, .Machine$double.eps)))
eligible$score_corr <- rank01(eligible$max_abs_corr)
eligible$selection_score <-
  0.30 * eligible$score_saturation +
  0.35 * eligible$score_rank +
  0.20 * eligible$score_condition +
  0.15 * eligible$score_corr
eligible <- eligible[order(eligible$selection_score, eligible$max_saturation_fraction, -eligible$min_relative_effective_rank_entropy), , drop = FALSE]

pick_top <- function(x, n, reason) {
  if (!nrow(x) || n <= 0L) return(x[0, , drop = FALSE])
  x <- x[order(x$selection_score, x$max_saturation_fraction, -x$min_relative_effective_rank_entropy), , drop = FALSE]
  x <- utils::head(x, n)
  x$selection_reason <- reason
  x
}

pick_by_base_case <- function(x, n_per_case, max_n, reason) {
  if (!nrow(x)) return(x[0, , drop = FALSE])
  parts <- split(x, x$base_case)
  out <- do.call(rbind, lapply(parts, function(z) pick_top(z, n_per_case, reason)))
  out <- out[order(out$selection_score, out$max_saturation_fraction, -out$min_relative_effective_rank_entropy), , drop = FALSE]
  utils::head(out, max_n)
}

max_positive <- as.integer(args$max_positive_control)
max_shallow <- as.integer(args$max_shallow)
max_two <- as.integer(args$max_two_layer)
max_total <- as.integer(args$max_total)

selected <- list()

reference_id <- "d1n300_refine_m100_a0p92_r0p97_w0p20_boundnone"
reference <- eligible[eligible$spec_id == reference_id, , drop = FALSE]
if (nrow(reference)) {
  reference$selection_reason <- "current_reference_control"
  selected[[length(selected) + 1L]] <- reference
}

selected[[length(selected) + 1L]] <- pick_top(
  eligible[eligible$family == "positive_control_d1n300", , drop = FALSE],
  max_positive,
  "top_positive_control_d1n300"
)
selected[[length(selected) + 1L]] <- pick_by_base_case(
  eligible[eligible$family == "shallow_capacity_ladder", , drop = FALSE],
  n_per_case = 3L,
  max_n = max_shallow,
  reason = "top_shallow_capacity_by_base_case"
)
selected[[length(selected) + 1L]] <- pick_by_base_case(
  eligible[eligible$family == "two_layer_ladder", , drop = FALSE],
  n_per_case = 2L,
  max_n = max_two,
  reason = "top_two_layer_by_base_case"
)

shortlist <- app_bind_rows_fill(selected)
shortlist <- shortlist[!duplicated(shortlist$spec_id), , drop = FALSE]

if (nrow(shortlist) < max_total) {
  remaining <- eligible[!eligible$spec_id %in% shortlist$spec_id, , drop = FALSE]
  fill <- utils::head(remaining, max_total - nrow(shortlist))
  if (nrow(fill)) {
    fill$selection_reason <- "global_score_fill"
    shortlist <- app_bind_rows_fill(list(shortlist, fill))
  }
}

shortlist <- shortlist[order(
  match(shortlist$selection_reason, c(
    "current_reference_control",
    "top_positive_control_d1n300",
    "top_shallow_capacity_by_base_case",
    "top_two_layer_by_base_case",
    "global_score_fill"
  )),
  shortlist$selection_score,
  shortlist$family,
  shortlist$base_case
), , drop = FALSE]
shortlist <- utils::head(shortlist, max_total)
shortlist$selection_rank <- seq_len(nrow(shortlist))
shortlist$shortlist_source <- app_prefer_repo_relative_path(triage_path)
shortlist$shortlist_created_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
shortlist$multiseed_seed_policy <- "20260512:20260518"
shortlist$screening_only <- TRUE

grid_cols <- c(
  "spec_id", "family", "base_case", "D", "n_vector", "n_tilde", "m",
  "alpha", "rho", "pi_w", "pi_in", "win_scale_global", "win_scale_bias",
  "input_bound", "launch_seed", "rationale", "selection_rank",
  "selection_reason", "selection_score", "max_saturation_fraction",
  "min_relative_effective_rank_entropy", "max_condition_cov", "max_abs_corr",
  "shortlist_source", "multiseed_seed_policy", "screening_only"
)
grid_cols <- intersect(grid_cols, names(shortlist))
shortlist_grid <- shortlist[, grid_cols, drop = FALSE]

summary <- aggregate(
  spec_id ~ family + base_case + D + n_vector + n_tilde + selection_reason,
  data = shortlist,
  FUN = length
)
names(summary)[names(summary) == "spec_id"] <- "n_shortlisted"
summary$total_units <- vapply(strsplit(summary$n_vector, ";", fixed = TRUE), function(x) sum(as.integer(x)), integer(1L))
summary <- summary[order(summary$family, summary$total_units, summary$base_case, summary$selection_reason), , drop = FALSE]
row.names(summary) <- NULL

grid_path <- app_resolve_path(args$output_grid, must_work = FALSE)
summary_path <- app_resolve_path(args$output_summary, must_work = FALSE)
app_ensure_dir(dirname(grid_path))
app_ensure_dir(dirname(summary_path))
app_write_csv(shortlist_grid, grid_path)
app_write_csv(summary, summary_path)

cat(sprintf("eligible_main_admissible=%d\n", nrow(eligible)))
cat(sprintf("shortlist_rows=%d\n", nrow(shortlist_grid)))
cat(sprintf("wrote %s\n", app_prefer_repo_relative_path(grid_path)))
cat(sprintf("wrote %s\n", app_prefer_repo_relative_path(summary_path)))
