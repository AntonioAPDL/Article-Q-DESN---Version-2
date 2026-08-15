#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_qdesn_phase154_mcmc_evidence_reconciliation.R",
  "joint_qdesn_phase155_article_promotion.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  phase155_dir = "application/cache/joint_qdesn_phase155_article_promotion_20260731",
  output_dir = "",
  main_tex = "main.tex",
  supplement_tex = "qdesn-supplement.tex"
))

value <- function(name) {
  hyphen <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen]])) args[[hyphen]] else args[[name]]
}
resolve <- function(path, default = "", must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, winslash = "/", mustWork = must_work)
}

phase155_dir <- resolve(value("phase155_dir"), must_work = TRUE)
result <- app_joint_qdesn_run_phase155_article_audit(
  phase155_dir = phase155_dir,
  main_tex = resolve(value("main_tex"), must_work = TRUE),
  supplement_tex = resolve(value("supplement_tex"), must_work = TRUE),
  out_dir = resolve(
    value("output_dir"),
    file.path(phase155_dir, "article_readiness_audit"),
    must_work = FALSE
  )
)

cat(sprintf("Joint QDESN Phase 155 article audit written to %s\n", result$out_dir))
print(result$summary, row.names = FALSE)
cat("Manuscript checks:\n")
print(result$manuscript_checks, row.names = FALSE)
