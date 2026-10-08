#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_search3_final_closeout.R"))

args <- app_parse_args(list(
  runtime_root = "local_trackers/runtime_configs/glofas_search3_part1234_final_closeout_20261007"
))
root <- app_resolve_path(args$runtime_root, must_work = TRUE)
required <- file.path(root, c(
  "status/closeout.completed",
  "manifests/output_manifest.csv",
  "manifests/authority_ledger.csv",
  "manifests/supersession_ledger.csv",
  "tables/campaign_health.csv",
  "tables/selected_components.csv",
  "tables/part123_family_scores.csv",
  "tables/part4_family_scores.csv",
  "tables/part4_quantile_calibration.csv",
  "tables/final_joint_convergence.csv",
  "figures/glofas_search3_part1234_final_comparison.pdf",
  "reports/final_closeout_report.md",
  "reports/coordinator_integration_handoff.md"
))
if (any(!file.exists(required))) stop("Final closeout package is incomplete.", call. = FALSE)

manifest <- app_glofas_closeout_verify_manifest(root, file.path(root, "manifests/output_manifest.csv"))
if (nrow(manifest) != 11L || anyDuplicated(manifest$relative_path)) {
  stop("Final closeout output manifest has the wrong cardinality.", call. = FALSE)
}

status <- jsonlite::fromJSON(file.path(root, "status/closeout.completed"))
if (!identical(status$decision, "READY_FOR_COORDINATOR_INTEGRATION") ||
    status$closure_completed != 133L || status$part4_completed != 18L ||
    status$output_manifest_rows != 11L ||
    !identical(
      tolower(status$output_manifest_sha256),
      tolower(app_sha256_file(file.path(root, "manifests/output_manifest.csv")))
    )) {
  stop("Final closeout status does not reproduce.", call. = FALSE)
}

health <- read.csv(file.path(root, "tables/campaign_health.csv"), stringsAsFactors = FALSE)
if (nrow(health) != 6L || any(health$running != 0L) || any(health$failed != 0L) ||
    any(health$left != 0L) || any(health$completed != health$planned)) {
  stop("Final campaign health is not complete.", call. = FALSE)
}

selected <- read.csv(file.path(root, "tables/selected_components.csv"), stringsAsFactors = FALSE)
if (nrow(selected) != 2L ||
    selected$candidate_id[selected$component == "reference"] != "search3_ref_001" ||
    selected$candidate_id[selected$component == "discrepancy"] != "search3_dis_007" ||
    selected$adoption_action[selected$component == "reference"] != "retain_search2_incumbent" ||
    selected$adoption_action[selected$component == "discrepancy"] != "adopt_search3_challenger") {
  stop("Search III selection does not match its frozen adoption contract.", call. = FALSE)
}

joint <- read.csv(file.path(root, "tables/final_joint_convergence.csv"), stringsAsFactors = FALSE)
if (nrow(joint) != 2L || !setequal(joint$family, c("Joint AL", "Joint exAL")) ||
    !all(joint$converged) || any(joint$parameter_change >= 1e-3) ||
    any(joint$max_rhs_global_relative_change >= 1e-3) ||
    any(joint$terminal_consecutive_passes < 3L) ||
    any(!file.exists(joint$fit_path)) ||
    any(tolower(vapply(joint$fit_path, app_sha256_file, character(1L))) != tolower(joint$fit_sha256))) {
  stop("Corrected terminal joint fits do not satisfy the final convergence contract.", call. = FALSE)
}

part4 <- read.csv(file.path(root, "tables/part4_family_scores.csv"), stringsAsFactors = FALSE)
families <- c(
  "Normal Ridge", "Normal RHS/VB", "Independent AL", "Independent exAL",
  "Joint AL", "Joint exAL", "Raw GloFAS"
)
if (nrow(part4) != 7L || !setequal(part4$family, families) ||
    any(part4$n_scored_horizons != 28L) || any(!is.finite(part4$crps_grid_log1p)) ||
    any(part4$crossing_pairs != 0L) ||
    !identical(as.character(part4$family[which.min(part4$crps_grid_log1p)]), "Independent AL") ||
    !identical(status$descriptive_part4_leader, "Independent AL") ||
    !isTRUE(all.equal(
      as.numeric(status$descriptive_part4_leader_crps),
      part4$crps_grid_log1p[part4$family == "Independent AL"], tolerance = 1e-12
    ))) {
  stop("Part 4 common-grid family comparison does not reproduce.", call. = FALSE)
}

part123 <- read.csv(file.path(root, "tables/part123_family_scores.csv"), stringsAsFactors = FALSE)
if (nrow(part123) != 18L || !setequal(part123$part, c("Part 1", "Part 2", "Part 3")) ||
    any(part123$n_scored_horizons[part123$part %in% c("Part 1", "Part 3")] != 30L) ||
    any(part123$n_scored_horizons[part123$part == "Part 2"] != 0L) ||
    any(!is.na(part123$crps_grid_log1p[part123$part == "Part 2"]))) {
  stop("Part 1-3 score and Part 2 no-score boundary changed.", call. = FALSE)
}

calibration <- read.csv(file.path(root, "tables/part4_quantile_calibration.csv"), stringsAsFactors = FALSE)
if (nrow(calibration) != 49L || !setequal(calibration$family, families) ||
    any(calibration$empirical_coverage < 0 | calibration$empirical_coverage > 1)) {
  stop("Part 4 calibration ledger is incomplete.", call. = FALSE)
}

authority <- read.csv(file.path(root, "manifests/authority_ledger.csv"), stringsAsFactors = FALSE)
if (nrow(authority) != 15L || anyDuplicated(authority$role) ||
    any(authority$authority_status != "canonical") || any(!file.exists(authority$path)) ||
    any(as.numeric(file.info(authority$path)$size) != authority$size_bytes) ||
    any(tolower(vapply(authority$path, app_sha256_file, character(1L))) != tolower(authority$sha256))) {
  stop("Authority ledger verification failed.", call. = FALSE)
}

supersession <- read.csv(file.path(root, "manifests/supersession_ledger.csv"), stringsAsFactors = FALSE)
if (nrow(supersession) != 5L ||
    sum(supersession$disposition == "canonical") != 1L ||
    sum(supersession$disposition == "canonical_sensitivity") != 1L) {
  stop("Supersession ledger is incomplete.", call. = FALSE)
}

pdf_path <- file.path(root, "figures/glofas_search3_part1234_final_comparison.pdf")
pdf_info <- suppressWarnings(system2("pdfinfo", pdf_path, stdout = TRUE, stderr = TRUE))
if (!any(grepl("^Pages:[[:space:]]+6$", pdf_info))) {
  stop("Comprehensive final comparison PDF must contain exactly six pages.", call. = FALSE)
}
pdf_images <- suppressWarnings(system2("pdfimages", c("-list", pdf_path), stdout = TRUE, stderr = TRUE))
image_rows <- grep("^[[:space:]]*[0-9]+[[:space:]]+[0-9]+", pdf_images, value = TRUE)
if (length(image_rows)) stop("Comprehensive comparison PDF contains raster images.", call. = FALSE)

report <- paste(readLines(file.path(root, "reports/final_closeout_report.md"), warn = FALSE), collapse = "\n")
handoff <- paste(readLines(file.path(root, "reports/coordinator_integration_handoff.md"), warn = FALSE), collapse = "\n")
for (token in c(
  "READY_FOR_COORDINATOR_INTEGRATION", "Independent AL", "protected scoring window",
  "search3_ref_001", "search3_dis_007"
)) {
  if (!grepl(token, paste(report, handoff), fixed = TRUE)) stop("Closeout prose omits: ", token, call. = FALSE)
}

checks <- data.frame(
  check = c(
    "output_manifest", "campaign_health", "search3_selection", "joint_convergence",
    "part4_family_comparison", "part123_boundaries", "calibration_ledger",
    "authority_ledger", "supersession_ledger", "vector_pdf", "coordinator_handoff"
  ),
  status = "pass",
  stringsAsFactors = FALSE
)
print(checks, row.names = FALSE)
cat("GLOFAS_SEARCH3_FINAL_CLOSEOUT_VERIFY_PASS 11/11\n")
cat("READY_FOR_COORDINATOR_INTEGRATION\n")
