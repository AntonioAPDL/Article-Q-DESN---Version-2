#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_part4_exal_inner_audit.R"))

args <- app_parse_args(list(
  source_runtime_root = "local_trackers/runtime_configs/glofas_part4_search3_dependency_closure_20260930_r4",
  release_runtime_root = "local_trackers/runtime_configs/glofas_part4_search3_joint_release_r1_20261004",
  output_runtime_root = "local_trackers/runtime_configs/glofas_part4_exal_terminal_audit_20261006",
  final_job_id = "part4_joint_exal_continuation_b03",
  previous_job_id = "part4_joint_exal_continuation_b02",
  expected_final_fit_sha256 = "4dfb1bd05733c9a538483d6d5feca0ce413399ae18d09a0edb6eec68420da027",
  parameter_tolerance = 1.0e-4,
  quadrature_tolerance = 1.0e-6,
  outer_tolerance = 1.0e-3
))

source_root <- app_resolve_path(args$source_runtime_root, must_work = TRUE)
release_root <- app_resolve_path(args$release_runtime_root, must_work = TRUE)
output_root <- app_resolve_path(args$output_runtime_root, must_work = FALSE)
if (dir.exists(output_root) && length(list.files(output_root, all.files = TRUE, no.. = TRUE))) {
  stop(sprintf("Audit output root is non-empty: %s", output_root), call. = FALSE)
}
invisible(lapply(file.path(output_root, c("tables", "reports", "manifests", "status")), app_ensure_dir))

final_job <- as.character(args$final_job_id)[[1L]]
previous_job <- as.character(args$previous_job_id)[[1L]]
fit_path <- function(job) file.path(release_root, "objects", paste0(job, "_fit_side.rds"))
manifest_path <- function(job) file.path(release_root, "manifests", paste0(job, "_artifacts.csv"))
verify_manifest <- function(job) {
  manifest <- app_read_csv(manifest_path(job))
  observed <- vapply(manifest$relative_path, function(path) {
    target <- file.path(release_root, path)
    if (!file.exists(target)) return(NA_character_)
    app_sha256_file(target)
  }, character(1L))
  if (anyNA(observed) || any(tolower(observed) != tolower(manifest$sha256))) {
    stop(sprintf("Artifact verification failed for %s.", job), call. = FALSE)
  }
  manifest
}
invisible(lapply(c(previous_job, final_job), verify_manifest))
expected <- tolower(as.character(args$expected_final_fit_sha256)[[1L]])
observed <- tolower(app_sha256_file(fit_path(final_job)))
if (!identical(expected, observed)) stop("Final exAL fit SHA256 mismatch.", call. = FALSE)

previous <- readRDS(fit_path(previous_job))
final <- readRDS(fit_path(final_job))
inner <- app_glofas_part4_exal_inner_table(
  final,
  parameter_tolerance = as.numeric(args$parameter_tolerance),
  quadrature_tolerance = as.numeric(args$quadrature_tolerance)
)
stability <- app_glofas_part4_exal_stability_summary(previous, final)
outer <- as.data.frame(final$trace)
scores <- do.call(rbind, lapply(c("b01", "b02", "b03"), function(batch) {
  app_read_csv(file.path(release_root, "scores", paste0("part4_joint_exal_continuation_", batch, "_summary.csv")))
}))
source_scores <- app_read_csv(file.path(
  source_root, "scores", "glofas_part4_search3_dependency_closure_20260930_r4_joint_exal_rhs_vb_summary.csv"
))
source_scores$checkpoint <- "source"
scores$checkpoint <- c("outer10", "outer15", "outer20")
score_columns <- intersect(names(source_scores), names(scores))
score_stability <- rbind(source_scores[, c(score_columns, "checkpoint")], scores[, c(score_columns, "checkpoint")])

app_write_csv(inner, file.path(output_root, "tables", "terminal_inner_gate_decomposition.csv"))
app_write_csv(stability, file.path(output_root, "tables", "outer15_to_outer20_state_stability.csv"))
app_write_csv(outer, file.path(output_root, "tables", "outer_trace.csv"))
app_write_csv(score_stability, file.path(output_root, "tables", "checkpoint_score_stability.csv"))

outer_tail <- tail(outer, 5L)
outer_stable <- nrow(outer_tail) == 5L && all(outer_tail$outer_tolerance_met) &&
  all(diff(outer_tail$parameter_change) < 0)
rhs_stable <- isTRUE(final$converged_rhs) && all(final$rhs_convergence_diagnostics$passed)
inner_stable <- all(inner$recorded_converged)
classification <- if (outer_stable && rhs_stable && !inner_stable) {
  "PRACTICALLY_STABLE_OUTER_AND_RHS__INNER_EXAL_UNCERTIFIED"
} else if (outer_stable && rhs_stable && inner_stable) {
  "STRICTLY_CONVERGED"
} else {
  "TERMINAL_STATE_REQUIRES_FURTHER_DIAGNOSIS"
}

report <- c(
  "# Part 4 Joint exAL Terminal Audit",
  "",
  sprintf("Generated: %s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  "",
  "## Immutable result",
  "",
  sprintf("- Final job: `%s`", final_job),
  sprintf("- Final fit SHA256: `%s`", observed),
  sprintf("- Outer iterations: %d", max(outer$outer_iteration)),
  sprintf("- Classification: `%s`", classification),
  "",
  "## Gate decomposition",
  "",
  sprintf("- Outer stable across iterations 16--20: `%s`", outer_stable),
  sprintf("- RHS qualified: `%s`", rhs_stable),
  sprintf("- All inner levels converged: `%s`", inner_stable),
  sprintf("- Parameter blockers: `%s`", paste(format(inner$quantile_level[!inner$parameter_pass], trim = TRUE), collapse = ", ")),
  sprintf("- Quadrature blockers: `%s`", paste(format(inner$quantile_level[!inner$quadrature_pass], trim = TRUE), collapse = ", ")),
  "",
  "## Decision",
  "",
  "Do not continue the full joint fit blindly and do not relax tolerances retrospectively.",
  "Run the frozen-RHS seven-quantile inner probe. It preserves the posterior target and separates",
  "an insufficient 30-iteration inner budget from a genuine exAL tail update-map defect.",
  "",
  sprintf("Status: `%s`", classification)
)
writeLines(report, file.path(output_root, "reports", "terminal_audit.md"), useBytes = TRUE)

inputs <- c(
  final_fit = fit_path(final_job), previous_fit = fit_path(previous_job),
  final_manifest = manifest_path(final_job), previous_manifest = manifest_path(previous_job)
)
input_manifest <- data.frame(
  label = names(inputs), path = normalizePath(inputs, mustWork = TRUE),
  size_bytes = as.numeric(file.info(inputs)$size),
  sha256 = vapply(inputs, app_sha256_file, character(1L)), stringsAsFactors = FALSE
)
app_write_csv(input_manifest, file.path(output_root, "manifests", "input_manifest.csv"))
outputs <- list.files(output_root, recursive = TRUE, full.names = TRUE)
outputs <- outputs[file.info(outputs)$isdir %in% FALSE]
output_manifest <- data.frame(
  relative_path = substring(outputs, nchar(normalizePath(output_root, mustWork = TRUE)) + 2L),
  size_bytes = as.numeric(file.info(outputs)$size),
  sha256 = vapply(outputs, app_sha256_file, character(1L)), stringsAsFactors = FALSE
)
app_write_csv(output_manifest, file.path(output_root, "manifests", "output_manifest.csv"))
writeLines(classification, file.path(output_root, "status", "audit.completed"))
cat(sprintf("classification=%s\nruntime_root=%s\n", classification, normalizePath(output_root, mustWork = TRUE)))
