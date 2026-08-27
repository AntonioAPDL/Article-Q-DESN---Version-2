#!/usr/bin/env Rscript
# Purpose: classify collected reservoir-screening candidates into conservative
# follow-up tiers for application micro-pilot selection.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
setwd(repo_root)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  screening_dir = "",
  ranked_candidates = "",
  output = "",
  saturation_main = "0.30",
  saturation_pilot = "0.35",
  saturation_exploratory = "0.40",
  rank_main = "0.05",
  rank_pilot = "0.04",
  rank_exploratory = "0.03"
))

screening_dir <- as.character(args$screening_dir %||% "")[[1L]]
ranked_path <- as.character(args$ranked_candidates %||% "")[[1L]]
if (!nzchar(ranked_path)) {
  if (!nzchar(screening_dir)) stop("Provide --screening_dir or --ranked_candidates.", call. = FALSE)
  ranked_path <- file.path(screening_dir, "ranked_candidates.csv")
}
ranked_path <- app_resolve_path(ranked_path, must_work = TRUE)
ranked <- app_read_csv(ranked_path)

sat_main <- as.numeric(args$saturation_main)
sat_pilot <- as.numeric(args$saturation_pilot)
sat_exploratory <- as.numeric(args$saturation_exploratory)
rank_main <- as.numeric(args$rank_main)
rank_pilot <- as.numeric(args$rank_pilot)
rank_exploratory <- as.numeric(args$rank_exploratory)

required <- c(
  "decision", "max_saturation_fraction", "min_relative_effective_rank_entropy",
  "max_condition_cov", "max_condition_z"
)
missing <- setdiff(required, names(ranked))
if (length(missing)) {
  stop(sprintf("Ranked candidate table is missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
}

sat <- as.numeric(ranked$max_saturation_fraction)
rel_rank <- as.numeric(ranked$min_relative_effective_rank_entropy)
cond_cov <- as.numeric(ranked$max_condition_cov)
cond_z <- as.numeric(ranked$max_condition_z)

condition_ok <- is.finite(cond_cov) & cond_cov <= 1.0e12 & is.finite(cond_z) & cond_z <= 1.0e6
not_reject <- ranked$decision %in% c("pass", "repair")

triage <- rep("reject", nrow(ranked))
triage[not_reject & condition_ok & sat <= sat_exploratory & rel_rank >= rank_exploratory] <- "exploratory_only"
triage[not_reject & condition_ok & sat <= sat_pilot & rel_rank >= rank_pilot] <- "pilot_override"
triage[not_reject & condition_ok & sat <= sat_main & rel_rank >= rank_main] <- "main_admissible"

# A rejected row may still be a close near-miss worth reading manually, but it
# stays in a non-launchable tier.
near_miss <- ranked$decision == "reject" &
  condition_ok &
  sat <= sat_pilot &
  rel_rank >= rank_pilot
triage[near_miss] <- "manual_near_miss"

ranked$triage_class <- triage
ranked$main_gate_saturation_margin <- sat_main - sat
ranked$main_gate_rank_margin <- rel_rank - rank_main
ranked$pilot_gate_saturation_margin <- sat_pilot - sat
ranked$pilot_gate_rank_margin <- rel_rank - rank_pilot

triage_rank <- match(ranked$triage_class, c("main_admissible", "pilot_override", "manual_near_miss", "exploratory_only", "reject"))
ranked <- ranked[order(
  triage_rank,
  ranked$family %||% "",
  ranked$base_case %||% ranked$spec_id,
  ranked$max_saturation_fraction,
  -ranked$min_relative_effective_rank_entropy,
  ranked$max_condition_cov
), , drop = FALSE]
row.names(ranked) <- NULL

out_path <- as.character(args$output %||% "")[[1L]]
if (!nzchar(out_path)) {
  out_dir <- if (nzchar(screening_dir)) screening_dir else dirname(ranked_path)
  out_path <- file.path(out_dir, "pilot_triage_candidates.csv")
}
out_path <- app_resolve_path(out_path, must_work = FALSE)
app_ensure_dir(dirname(out_path))
app_write_csv(ranked, out_path)

tab <- as.data.frame(table(ranked$triage_class), stringsAsFactors = FALSE)
names(tab) <- c("triage_class", "n_candidates")
app_write_csv(tab, file.path(dirname(out_path), "pilot_triage_summary.csv"))

print(tab)
cat(out_path, "\n")
