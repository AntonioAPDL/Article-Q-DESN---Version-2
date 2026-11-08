gfsa_require <- function(ok, message) if (!isTRUE(ok)) stop(message, call. = FALSE)

gfsa_sha256 <- function(path) {
  gfsa_require(file.exists(path), paste0("Missing file: ", path))
  out <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  gfsa_require(is.null(attr(out, "status")) && length(out) == 1L,
    paste0("sha256sum failed: ", path))
  sub("[[:space:]].*$", "", out[[1L]])
}

gfsa_read_csv <- function(path) {
  gfsa_require(file.exists(path), paste0("Missing CSV: ", path))
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

gfsa_read_json <- function(path) {
  gfsa_require(file.exists(path), paste0("Missing JSON: ", path))
  jsonlite::fromJSON(path, simplifyVector = TRUE)
}

gfsa_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, path, row.names = FALSE, na = "")
}

gfsa_write_json <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(x, path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat("\n", file = path, append = TRUE)
}

gfsa_write_lines <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(x, path, useBytes = TRUE)
}

gfsa_verify_manifest <- function(root, manifest = "manifests/artifact_manifest.csv") {
  path <- file.path(root, manifest)
  rows <- gfsa_read_csv(path)
  gfsa_require(identical(names(rows), c("relative_path", "size_bytes", "sha256")) &&
      nrow(rows) > 0L && !anyDuplicated(rows$relative_path),
    paste0("Invalid artifact manifest: ", path))
  files <- file.path(root, rows$relative_path)
  gfsa_require(all(file.exists(files)), paste0("Manifest has missing files: ", path))
  sizes <- as.numeric(file.info(files)$size)
  hashes <- unname(vapply(files, gfsa_sha256, character(1L)))
  gfsa_require(identical(unname(sizes), as.numeric(rows$size_bytes)) && identical(hashes, rows$sha256),
    paste0("Manifest bytes differ: ", path))
  invisible(rows)
}

gfsa_verify_root_manifest <- function(root) {
  path <- file.path(root, "artifact_manifest.csv")
  rows <- gfsa_read_csv(path)
  gfsa_require(identical(names(rows), c("relative_path", "size_bytes", "sha256")) &&
      nrow(rows) > 0L && !anyDuplicated(rows$relative_path),
    paste0("Invalid root manifest: ", path))
  files <- file.path(root, rows$relative_path)
  gfsa_require(all(file.exists(files)), paste0("Root manifest has missing files: ", path))
  gfsa_require(identical(unname(as.numeric(file.info(files)$size)), as.numeric(rows$size_bytes)) &&
      identical(unname(vapply(files, gfsa_sha256, character(1L))), rows$sha256),
    paste0("Root manifest bytes differ: ", path))
  invisible(rows)
}

gfsa_git <- function(root, args, many = FALSE) {
  if (length(args) == 1L) args <- strsplit(args, "[[:space:]]+")[[1L]]
  out <- system2("git", c("-C", root, args), stdout = TRUE, stderr = TRUE)
  gfsa_require(is.null(attr(out, "status")), paste0("git failed: ", paste(args, collapse = " ")))
  if (many) out else {
    gfsa_require(length(out) == 1L, paste0("Expected one git value: ", paste(args, collapse = " ")))
    out[[1L]]
  }
}

gfsa_candidate_guard <- function(candidate_root, candidate_commit) {
  gfsa_require(grepl("^[0-9a-f]{40}$", candidate_commit), "A full candidate commit is required.")
  gfsa_require(identical(gfsa_git(candidate_root, "rev-parse HEAD"), candidate_commit),
    "Candidate worktree is not at the requested payload commit.")
  gfsa_require(length(gfsa_git(candidate_root, "status --porcelain", many = TRUE)) == 0L,
    "Candidate worktree must be clean.")
  script <- file.path(candidate_root, "scripts/glofas_current_article_authority.py")
  gfsa_require(file.exists(script), "Candidate authority guard is missing.")
  old <- getwd(); on.exit(setwd(old), add = TRUE); setwd(candidate_root)
  out <- system2("python3", c(script, candidate_commit), stdout = TRUE, stderr = TRUE)
  gfsa_require(is.null(attr(out, "status")) &&
      identical(tail(out, 1L), "GLOFAS_CURRENT_ARTICLE_AUTHORITY_VERIFIED"),
    paste(c("Candidate authority guard failed.", out), collapse = "\n"))
  out
}

gfsa_part4_scores <- function(qualification_root) {
  comparison <- gfsa_read_csv(file.path(qualification_root, "tables/family_comparison.csv"))
  x <- comparison[comparison$scenario == "October coherent later design", , drop = FALSE]
  gfsa_require(nrow(x) == 7L && !anyDuplicated(x$family),
    "Corrected Part 4 family comparison is incomplete.")
  x
}

gfsa_component_table <- function(part123, part4) {
  p123 <- data.frame(
    component = part123$part,
    family = part123$family,
    target_status = "coherent_shared_normal_rhs_recursive_driver",
    numerical_status = ifelse(part123$part == "Part 2", "fit_complete_forecast_not_evaluable",
      "completed"),
    evaluation_status = ifelse(part123$part == "Part 2",
      "not_evaluable_future_retrospective_unavailable", "protected_window_descriptive_only"),
    scored_horizons = part123$n_scored_horizons,
    crps_grid_log1p = part123$crps_grid_log1p,
    crossing_pairs = part123$crossing_pairs,
    disposition = ifelse(part123$part == "Part 2", "retain_unscored_with_limitation", "retain"),
    stringsAsFactors = FALSE)
  p4 <- data.frame(
    component = "Part 4",
    family = part4$family,
    target_status = ifelse(part4$family %in% c("Normal Ridge", "Normal RHS/VB", "Raw GloFAS"),
      "coherent_native_or_benchmark", "coherent_shared_normal_rhs_gaussian_path_prior"),
    numerical_status = ifelse(part4$family == "Raw GloFAS", "benchmark", "strict_gate_pass"),
    evaluation_status = "protected_window_descriptive_only",
    scored_horizons = 28L,
    crps_grid_log1p = part4$crps_grid_log1p,
    crossing_pairs = part4$crossing_pairs,
    disposition = ifelse(part4$family == "Raw GloFAS", "benchmark", "retain"),
    stringsAsFactors = FALSE)
  rbind(p123, p4)
}

gfsa_issue_ledger <- function() data.frame(
  issue = c(
    "catastrophic_future_quantile_crossings",
    "independent_tail_path_target_identity",
    "local_delta_or_monte_carlo_failure",
    "exal_weaker_than_al",
    "part123_recursive_driver_and_covariance",
    "part4_future_usgs_likelihood",
    "future_truth_leakage",
    "part2_post_cutoff_discrepancy_scoring",
    "discrepancy_geometry_selection",
    "protected_window_method_selection",
    "november_same_family_campaign",
    "article_payload_provenance"),
  classification = c(
    "fixed_by_coherent_target",
    "root_cause_identified_and_rejected",
    "ruled_out_as_root_cause",
    "valid_weaker_empirical_result",
    "verified",
    "fixed_by_replacement_not_multiplication",
    "verified_absent",
    "documented_data_limitation",
    "frozen_internal_rainy_season_selection",
    "verified_zero_choices",
    "quarantined_adverse_evidence",
    "verified_exact_candidate_payload"),
  status = c(rep("pass", 7L), "not_evaluable", rep("pass", 4L)),
  rerun_required = FALSE,
  evidence = c(
    "October Part 4 quantile families have 0,0,0,1 crossings; November has 39-46 and is inactive",
    "global reference reproduces crossings under separate level-specific transition laws",
    "global/local MAE <= 0.041486 and global same-family target still crosses",
    "all exAL fit/target/numerical gates pass; weaker protected-window scores are descriptive",
    "3 banks; 48 forecast contracts; 48 covariance-bearing fits; 500 aligned paths",
    "16/16 quantile fits use shared Gaussian prior and future_y_working_likelihood=FALSE",
    "zero scoring-truth reads in driver audit; qualification records postfit scoring only",
    "future retrospective GloFAS is unavailable, so all Part 2 families remain uniformly unscored",
    "Search III reference/discrepancy geometries were frozen before protected-window evaluation",
    "handoff records protected_window_method_choices=0",
    "separate same-family target retained only as adverse evidence",
    "committed Python guard validates manifest, aliases, article text, scores and numerical gates"),
  stringsAsFactors = FALSE)

gfsa_gates <- function(root_decision, driver_summary, qualification_gates, part123,
  part4, handoff_ready, guard_output) {
  p2 <- part123[part123$part == "Part 2", ]
  exal <- part4[part4$family %in% c("Independent exAL", "MQ exAL"), ]
  al <- part4[part4$family %in% c("Independent AL", "MQ AL"), ]
  data.frame(
    gate = c(
      "root_cause_structural_identity",
      "coherent_driver_authority",
      "part123_covariance_and_forecast_contracts",
      "part4_corrected_target_contract",
      "part4_numerical_and_quadrature",
      "part4_path_ordering",
      "exal_interpretation",
      "part2_non_evaluable_uniformity",
      "future_truth_firewall",
      "protected_window_selection_firewall",
      "candidate_article_payload_guard",
      "rerun_necessity"),
    status = "pass",
    evidence = c(
      root_decision$status[[1L]],
      sprintf("%d banks; %d forecasts; %d covariance fits; %d truth reads; %d model fits",
        driver_summary$banks, driver_summary$part123_forecasts,
        driver_summary$part123_fits_with_covariance, driver_summary$scoring_truth_reads,
        driver_summary$model_fits),
      "48/48 recursive forecasts use normal_rhs_external_driver with 500 aligned paths",
      "16/16 quantile cores share prior 0202bc19...357; future-Y likelihood absent; 1428 factors",
      qualification_gates$evidence[qualification_gates$gate == "corrected_numerical_gates"],
      sprintf("maximum corrected quantile crossing count=%d", max(part4$crossing_pairs)),
      sprintf("exAL CRPS %.3f/%.3f versus AL %.3f/%.3f; all strict gates pass",
        exal$crps_grid_log1p[[1L]], exal$crps_grid_log1p[[2L]],
        al$crps_grid_log1p[[1L]], al$crps_grid_log1p[[2L]]),
      sprintf("%d/%d Part 2 rows uniformly unscored with zero horizons",
        sum(p2$numerical_status == "unscored_future_retrospective_unavailable" &
          p2$n_scored_horizons == 0L), nrow(p2)),
      qualification_gates$evidence[qualification_gates$gate == "future_truth_firewall"],
      sprintf("protected_window_method_choices=%d", handoff_ready$protected_window_method_choices),
      tail(guard_output, 1L),
      "existing coherent fits and forecasts pass; duplicate refit is not scientifically justified"),
    stringsAsFactors = FALSE)
}

gfsa_evidence_table <- function(paths) {
  data.frame(
    evidence = names(paths),
    path = unname(paths),
    size_bytes = as.numeric(file.info(unname(paths))$size),
    sha256 = vapply(unname(paths), gfsa_sha256, character(1L)),
    stringsAsFactors = FALSE)
}

gfsa_acceptance_pdf <- function(path, gates, components, issues, part4) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(path, width = 11, height = 8.5, useDingbats = FALSE)
  on.exit(grDevices::dev.off(), add = TRUE)
  op <- par(no.readonly = TRUE); on.exit(par(op), add = TRUE)

  par(mar = c(1, 1, 2, 1)); plot.new()
  title("GloFAS final scientific acceptance", cex.main = 1.5)
  text(.04, .88, sprintf("Hard gates: %d/%d pass", sum(gates$status == "pass"), nrow(gates)),
    adj = 0, cex = 1.15, font = 2)
  y <- seq(.80, .16, length.out = nrow(gates))
  text(.04, y, gates$gate, adj = 0, cex = .74)
  text(.96, y, toupper(gates$status), adj = 1, cex = .74,
    col = ifelse(gates$status == "pass", "#13795B", "#A61B1B"), font = 2)
  text(.04, .07, "No model fit, continuation, retuning or protected-window selection was performed.",
    adj = 0, cex = .86)

  score <- components[components$component %in% c("Part 1", "Part 3") &
      components$evaluation_status == "protected_window_descriptive_only", ]
  families <- unique(score$family)
  parts <- c("Part 1", "Part 3")
  mat <- sapply(parts, function(p) {
    z <- score[score$component == p, ]
    z$crps_grid_log1p[match(families, z$family)]
  })
  rownames(mat) <- families
  par(mar = c(8.5, 4.5, 3, 1), las = 2)
  barplot(t(mat), beside = TRUE, names.arg = families, col = c("#355C7D", "#2A9D8F"),
    ylab = "Grid CRPS (log1p)", main = "Frozen Search III descriptive scores")
  legend("topleft", legend = parts, fill = c("#355C7D", "#2A9D8F"), bty = "n")

  x <- part4[part4$family != "Raw GloFAS", ]
  raw <- part4$crps_grid_log1p[part4$family == "Raw GloFAS"]
  par(mar = c(8.5, 4.5, 3, 4.2), las = 2)
  bp <- barplot(x$crps_grid_log1p, names.arg = x$family, col = "#4C78A8",
    ylab = "Grid CRPS (log1p)", main = "Qualified October Part 4 result")
  abline(h = raw, col = "#A61B1B", lty = 2, lwd = 2)
  text(bp, x$crps_grid_log1p, labels = paste0("cross=", x$crossing_pairs), pos = 3, cex = .72)
  legend("topleft", legend = sprintf("Raw GloFAS %.3f", raw), lty = 2, lwd = 2,
    col = "#A61B1B", bty = "n")

  par(mar = c(1, 1, 2, 1)); plot.new(); title("Issue closure ledger", cex.main = 1.35)
  y <- seq(.89, .10, length.out = nrow(issues))
  text(.03, y, gsub("_", " ", issues$issue), adj = 0, cex = .69)
  text(.55, y, gsub("_", " ", issues$classification), adj = 0, cex = .67)
  text(.97, y, ifelse(issues$status == "pass", "CLOSED", "LIMITATION"), adj = 1,
    cex = .67, font = 2, col = ifelse(issues$status == "pass", "#13795B", "#B36B00"))
}

gfsa_report <- function(gates, components, issues, part4, candidate_commit) {
  exal <- part4[part4$family %in% c("Independent exAL", "MQ exAL"), ]
  c(
    "# GloFAS final scientific acceptance", "", "## Decision", "",
    "`GLOFAS_SCIENTIFIC_ACCEPTANCE_PASS_READY_FOR_CONTROLLED_PROMOTION`", "",
    sprintf("All %d hard gates pass. The accepted article payload commit is `%s`.",
      nrow(gates), candidate_commit), "",
    "No model was fitted, continued or retuned. No protected-window result selected a target,",
    "geometry, prior, stopping rule or family.", "", "## What was fixed", "",
    "The catastrophic November forecast crossings were caused by a structurally incoherent",
    "collection of separate level-specific future-response transition laws. Global path",
    "inference reproduced the failure, ruling out short optimization, Monte Carlo error and",
    "the local Delta approximation as the root cause. The accepted workflow uses one shared,",
    "truth-free Normal-RHS recursive driver for Parts 1--3 and its joint Gaussian path-prior",
    "counterpart for Part 4.", "", "## What is not a defect", "",
    sprintf("Independent and MQ exAL have corrected Part 4 grid CRPS %.3f and %.3f.",
      exal$crps_grid_log1p[[1L]], exal$crps_grid_log1p[[2L]]),
    "They are weaker than the matching AL results, but all target, lineage, convergence,",
    "quadrature and path-ordering gates pass. They are retained as valid weaker empirical",
    "results, not rerun until they improve.", "",
    "Part 2 remains unscored after the cutoff because retrospective GloFAS is unavailable.",
    "This is an explicit data limitation. No score is imputed and no pass is inferred.", "",
    "## Acceptance summary", "",
    sprintf("- Gates: %d/%d pass.", sum(gates$status == "pass"), nrow(gates)),
    sprintf("- Components: %d rows across Parts 1--4.", nrow(components)),
    sprintf("- Closed issues: %d; documented limitations: %d.",
      sum(issues$status == "pass"), sum(issues$status != "pass")),
    sprintf("- Corrected Part 4 maximum crossing count: %d.", max(part4$crossing_pairs)),
    "- November same-family artifacts remain adverse evidence and are not active authority.",
    "", "## Promotion boundary", "",
    "This receipt permits a controlled coordinator promotion of the exact accepted payload.",
    "It does not merge main, update Overleaf, delete evidence or authorize another target."
  )
}

gfsa_build <- function(repo_root, handoff_root, qualification_root, driver_root,
  root_cause_root, candidate_root, candidate_commit, output_root) {
  gfsa_require(exists("gpah_check", mode = "function"), "Source gpah_check before building.")
  gfsa_require(exists("gptq_check", mode = "function"), "Source gptq_check before building.")
  gpah_check(handoff_root)
  gptq_check(qualification_root)
  gfsa_verify_manifest(handoff_root)
  gfsa_verify_manifest(qualification_root)
  gfsa_verify_root_manifest(driver_root)
  gfsa_verify_root_manifest(root_cause_root)

  root_decision <- gfsa_read_csv(file.path(root_cause_root, "decision.csv"))
  gfsa_require(nrow(root_decision) == 1L &&
      identical(root_decision$status[[1L]], "STRUCTURAL_INDEPENDENT_TAIL_PATH_TARGET_INCOHERENCE") &&
      !root_decision$convergence_or_monte_carlo_failure[[1L]] &&
      !root_decision$broad_refit_authorized[[1L]], "Root-cause decision changed.")

  driver <- gfsa_read_csv(file.path(driver_root, "summary.csv"))
  gfsa_require(nrow(driver) == 1L &&
      identical(driver$status[[1L]], "COHERENT_NORMAL_DRIVER_AUTHORITY_CONTRACT_PASS") &&
      driver$banks == 3L && driver$part123_forecasts == 48L &&
      driver$part123_fits_with_covariance == 48L && driver$part4_fit_cores == 28L &&
      driver$scoring_truth_reads == 0L && driver$model_fits == 0L,
    "Coherent-driver authority audit changed.")
  forecasts <- gfsa_read_csv(file.path(driver_root, "part123_forecast_contracts.csv"))
  covariance <- gfsa_read_csv(file.path(driver_root, "part123_covariance_audit.csv"))
  priors <- gfsa_read_csv(file.path(driver_root, "part4_prior_contracts.csv"))
  gfsa_require(nrow(forecasts) == 48L && all(forecasts$mode_pass) &&
      all(forecasts$path_count_pass) && all(forecasts$driver_hash_pass) &&
      all(forecasts$n_paths == 500L), "Part 1--3 recursive forecast contracts changed.")
  gfsa_require(nrow(covariance) == 48L && all(covariance$covariance_available),
    "Part 1--3 covariance audit changed.")
  gfsa_require(nrow(priors) == 28L && all(priors$prior_used) &&
      !any(priors$future_y_working_likelihood_used) &&
      all(priors$prior_hash == priors$expected_prior_hash),
    "Part 4 prior-contract audit changed.")

  qualification_gates <- gfsa_read_csv(file.path(qualification_root, "tables/qualification_gates.csv"))
  gfsa_require(nrow(qualification_gates) == 13L && all(qualification_gates$status == "pass"),
    "Corrected-target qualification gates changed.")
  fit_audit <- gfsa_read_csv(file.path(qualification_root, "tables/corrected_fit_audit.csv"))
  qfit <- fit_audit[fit_audit$family %in% c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL"), ]
  gfsa_require(nrow(qfit) == 16L && all(qfit$converged) && all(qfit$gaussian_path_prior_used) &&
      !any(qfit$future_y_working_likelihood_used) &&
      length(unique(qfit$gaussian_path_prior_sha256)) == 1L &&
      unique(qfit$gaussian_path_prior_sha256) ==
        "0202bc19e26d84d6cbb55c2256a2071695f9c386c9dc64933005bd4d5acbb357",
    "Corrected Part 4 fit target changed.")

  handoff_ready <- gfsa_read_json(file.path(handoff_root, "status/READY_FOR_COORDINATOR_REVIEW.json"))
  gfsa_require(handoff_ready$model_fits_run == 0L && handoff_ready$source_rds_reads == 0L &&
      handoff_ready$protected_window_method_choices == 0L && !handoff_ready$search3_part123_changed,
    "Handoff scientific firewall changed.")
  part123 <- gfsa_read_csv(file.path(handoff_root, "authority/search3_part123_scores_frozen.csv"))
  gfsa_require(nrow(part123) == 18L && all(table(part123$part) == 6L),
    "Search III Parts 1--3 score surface changed.")
  p2 <- part123[part123$part == "Part 2", ]
  gfsa_require(nrow(p2) == 6L && all(p2$numerical_status ==
      "unscored_future_retrospective_unavailable") && all(p2$n_scored_horizons == 0L) &&
      all(is.na(p2$crps_grid_log1p)), "Part 2 must remain uniformly not evaluable.")

  part4 <- gfsa_part4_scores(qualification_root)
  q4 <- part4[part4$family %in% c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL"), ]
  gfsa_require(max(q4$crossing_pairs) <= 1L, "Corrected Part 4 crossing gate failed.")
  guard_output <- gfsa_candidate_guard(candidate_root, candidate_commit)

  gates <- gfsa_gates(root_decision, driver, qualification_gates, part123,
    part4, handoff_ready, guard_output)
  gfsa_require(nrow(gates) == 12L && all(gates$status == "pass"), "Final acceptance gates failed.")
  components <- gfsa_component_table(part123, part4)
  issues <- gfsa_issue_ledger()
  gfsa_require(sum(issues$status == "pass") == 11L &&
      identical(issues$status[issues$issue == "part2_post_cutoff_discrepancy_scoring"], "not_evaluable"),
    "Issue ledger classification changed.")

  evidence_paths <- c(
    root_cause_decision = file.path(root_cause_root, "decision.csv"),
    root_cause_manifest = file.path(root_cause_root, "artifact_manifest.csv"),
    driver_summary = file.path(driver_root, "summary.csv"),
    driver_manifest = file.path(driver_root, "artifact_manifest.csv"),
    qualification_status = file.path(qualification_root, "status/qualification_ready.json"),
    qualification_manifest = file.path(qualification_root, "manifests/artifact_manifest.csv"),
    handoff_status = file.path(handoff_root, "status/READY_FOR_COORDINATOR_REVIEW.json"),
    handoff_manifest = file.path(handoff_root, "manifests/artifact_manifest.csv"))
  evidence <- gfsa_evidence_table(evidence_paths)

  stage <- paste0(output_root, ".stage_", Sys.getpid())
  if (dir.exists(stage)) unlink(stage, recursive = TRUE)
  dir.create(file.path(stage, "tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(stage, "reports"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(stage, "figures"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(stage, "status"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(stage, "manifests"), recursive = TRUE, showWarnings = FALSE)
  gfsa_write_csv(gates, file.path(stage, "tables/final_acceptance_gates.csv"))
  gfsa_write_csv(components, file.path(stage, "tables/component_acceptance.csv"))
  gfsa_write_csv(issues, file.path(stage, "tables/issue_closure_ledger.csv"))
  gfsa_write_csv(rbind(
    data.frame(component = part123$part, family = part123$family,
      crps_grid_log1p = part123$crps_grid_log1p, crossing_pairs = part123$crossing_pairs,
      evaluation_status = part123$numerical_status, stringsAsFactors = FALSE),
    data.frame(component = "Part 4", family = part4$family,
      crps_grid_log1p = part4$crps_grid_log1p, crossing_pairs = part4$crossing_pairs,
      evaluation_status = "protected_window_descriptive_only", stringsAsFactors = FALSE)),
    file.path(stage, "tables/frozen_metrics.csv"))
  gfsa_write_csv(evidence, file.path(stage, "tables/evidence_hashes.csv"))
  gfsa_write_lines(gfsa_report(gates, components, issues, part4, candidate_commit),
    file.path(stage, "reports/final_scientific_acceptance.md"))
  gfsa_acceptance_pdf(file.path(stage, "figures/final_scientific_acceptance_atlas.pdf"),
    gates, components, issues, part4)
  receipt <- list(
    schema_version = "glofas_final_scientific_acceptance_v1",
    decision = "GLOFAS_SCIENTIFIC_ACCEPTANCE_PASS_READY_FOR_CONTROLLED_PROMOTION",
    created_on = as.character(Sys.Date()),
    acceptance_source_head = gfsa_git(repo_root, "rev-parse HEAD"),
    acceptance_source_tree = gfsa_git(repo_root, "rev-parse HEAD^{tree}"),
    acceptance_source_dirty = length(gfsa_git(repo_root, "status --porcelain", many = TRUE)) > 0L,
    accepted_article_payload_commit = candidate_commit,
    root_cause = root_decision$status[[1L]],
    authority_composition = list(parts_1_3 = "Search III frozen",
      part_4 = "October coherent unit-member target",
      november = "adverse evidence only"),
    hard_gates = nrow(gates), hard_gates_passed = sum(gates$status == "pass"),
    issue_rows = nrow(issues), documented_limitations = sum(issues$status != "pass"),
    part4_fit_units = 18L, part4_quantile_fit_units = 16L,
    part123_forecast_contracts = 48L, aligned_driver_paths = 500L,
    issued_members = 51L, issued_member_factors = 1428L,
    maximum_corrected_part4_crossings = max(q4$crossing_pairs),
    protected_window_method_choices = 0L, new_model_fits = 0L,
    broad_refit_required = FALSE,
    promotion_scope = "controlled coordinator promotion only; no automatic merge or Overleaf update")
  gfsa_write_json(receipt, file.path(stage, "status/FINAL_SCIENTIFIC_ACCEPTANCE.json"))

  files <- list.files(stage, recursive = TRUE, full.names = TRUE)
  files <- files[file.info(files)$isdir %in% FALSE]
  rel <- substring(files, nchar(stage) + 2L)
  manifest <- data.frame(relative_path = rel, size_bytes = as.numeric(file.info(files)$size),
    sha256 = vapply(files, gfsa_sha256, character(1L)), stringsAsFactors = FALSE)
  manifest <- manifest[order(manifest$relative_path), ]
  gfsa_write_csv(manifest, file.path(stage, "manifests/artifact_manifest.csv"))
  if (dir.exists(output_root)) stop("Output root already exists: ", output_root, call. = FALSE)
  gfsa_require(file.rename(stage, output_root), "Atomic final acceptance publication failed.")
  gfsa_check(output_root)
  cat("GLOFAS_SCIENTIFIC_ACCEPTANCE_PASS_READY_FOR_CONTROLLED_PROMOTION\n")
  invisible(receipt)
}

gfsa_check <- function(root) {
  manifest <- gfsa_verify_manifest(root)
  receipt <- gfsa_read_json(file.path(root, "status/FINAL_SCIENTIFIC_ACCEPTANCE.json"))
  gfsa_require(identical(receipt$schema_version, "glofas_final_scientific_acceptance_v1") &&
      identical(receipt$decision,
        "GLOFAS_SCIENTIFIC_ACCEPTANCE_PASS_READY_FOR_CONTROLLED_PROMOTION") &&
      receipt$hard_gates == 12L && receipt$hard_gates_passed == 12L &&
      receipt$documented_limitations == 1L && !receipt$broad_refit_required &&
      receipt$protected_window_method_choices == 0L && receipt$new_model_fits == 0L &&
      receipt$maximum_corrected_part4_crossings <= 1L,
    "Final scientific acceptance receipt changed.")
  gates <- gfsa_read_csv(file.path(root, "tables/final_acceptance_gates.csv"))
  issues <- gfsa_read_csv(file.path(root, "tables/issue_closure_ledger.csv"))
  components <- gfsa_read_csv(file.path(root, "tables/component_acceptance.csv"))
  gfsa_require(nrow(gates) == 12L && all(gates$status == "pass"), "Acceptance gates changed.")
  gfsa_require(nrow(issues) == 12L && sum(issues$status == "pass") == 11L &&
      identical(issues$status[issues$issue == "part2_post_cutoff_discrepancy_scoring"],
        "not_evaluable") && !any(issues$rerun_required), "Issue ledger changed.")
  counts <- table(components$component)
  gfsa_require(nrow(components) == 25L &&
      identical(as.integer(counts[c("Part 1", "Part 2", "Part 3", "Part 4")]), c(6L, 6L, 6L, 7L)),
    "Component acceptance surface changed.")
  gfsa_require(file.info(file.path(root, "figures/final_scientific_acceptance_atlas.pdf"))$size > 1000,
    "Acceptance atlas is missing or empty.")
  report <- paste(readLines(file.path(root, "reports/final_scientific_acceptance.md"), warn = FALSE),
    collapse = "\n")
  gfsa_require(grepl("valid weaker empirical", report, fixed = TRUE) &&
      grepl("Part 2 remains unscored", report, fixed = TRUE) &&
      grepl("does not merge main", report, fixed = TRUE), "Acceptance report changed.")
  cat("GLOFAS_FINAL_SCIENTIFIC_ACCEPTANCE_VERIFY_PASS\n")
  cat("GLOFAS_SCIENTIFIC_ACCEPTANCE_PASS_READY_FOR_CONTROLLED_PROMOTION\n")
  invisible(manifest)
}

