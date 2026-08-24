#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  summary = "",
  candidate_id = "",
  reject_decision = "reject",
  output = ""
))
if (!nzchar(args$summary) || !nzchar(args$candidate_id) || !nzchar(args$output)) {
  stop("--summary, --candidate_id, and --output are required.", call. = FALSE)
}
summary_path <- app_resolve_path(args$summary, must_work = TRUE)
summary <- app_read_csv(summary_path)
if (nrow(summary) != 1L || !"decision" %in% names(summary)) {
  stop("Reservoir preflight requires exactly one architecture decision.", call. = FALSE)
}
decision <- tolower(as.character(summary$decision[[1L]]))
if (!decision %in% c("pass", "repair", "reject")) {
  stop(sprintf("Reservoir preflight returned invalid decision '%s'.", decision), call. = FALSE)
}
reject_decision <- match.arg(as.character(args$reject_decision), c("reject", "none"))
gate_pass <- !(identical(reject_decision, "reject") && identical(decision, "reject"))
audit <- data.frame(
  candidate_id = as.character(args$candidate_id),
  decision = decision,
  gate_pass = gate_pass,
  reject_policy = reject_decision,
  summary_path = summary_path,
  summary_sha256 = app_sha256_file(summary_path),
  checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  stringsAsFactors = FALSE
)
app_write_csv(audit, app_resolve_path(args$output, must_work = FALSE))
cat(sprintf("Reservoir preflight %s: %s\n", args$candidate_id, decision))
if (!gate_pass) quit(save = "no", status = 42L)
