# Search III promotion reconciliation after rejection of the November
# same-family future-path experiment. This module never fits or forecasts.

gpr_expected <- c(
  search3_output_manifest = "968096fe310b61c4b05423890cad529e7c891e51691cd997ef253753c7c9de9f",
  search3_projection_manifest = "5a7ac4fc1b35f3e7b19c4535e5e5c1cc56c4dfe87927b42f6f66122d49a01335",
  november_authority = "ef1a21307f581ff5ce9813e37ce15b84ddad866e410f522f88c05de618426640",
  root_cause_pdf = "6d52d9131dd6b49280bf9d474d487aa747c246e9f3a60774e8fe94bc90face0c",
  root_cause_decision = "7370fbd46ee4c88fdeea35a0ab7f85c98cff95f06a6ecff28bee60b102aa180b",
  driver_audit_summary = "6bb1572d711d8a74eda24a3bcefcc700532e3bb179387d3791e3860b6bcf1b02"
)

gpr_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste0("GloFAS promotion reconciliation: ", message), call. = FALSE)
  invisible(TRUE)
}

gpr_sha <- function(path) {
  gpr_require(file.exists(path), paste0("missing file: ", path))
  unname(tools::sha256sum(path))
}

gpr_read_csv <- function(path) read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)

gpr_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write.csv(x, path, row.names = FALSE, na = "NA")
  invisible(path)
}

gpr_validate_root_cause <- function(decision_path, summary_path) {
  decision <- gpr_read_csv(decision_path)
  summary <- gpr_read_csv(summary_path)
  gpr_require(nrow(decision) == 1L && identical(
    decision$status, "STRUCTURAL_INDEPENDENT_TAIL_PATH_TARGET_INCOHERENCE"
  ), "root-cause decision changed")
  gpr_require(
    decision$local_delta_crossings >= 10L &&
      decision$global_same_family_unit_crossings >= 10L &&
      decision$maximum_local_global_mae < .05 &&
      !decision$convergence_or_monte_carlo_failure &&
      !decision$broad_refit_authorized,
    "root-cause evidence no longer supports the bounded decision"
  )
  gpr_require(nrow(summary) == 1L && identical(
    summary$status, "COHERENT_NORMAL_DRIVER_AUTHORITY_CONTRACT_PASS"
  ), "coherent-driver authority status changed")
  gpr_require(
    summary$banks == 3L && summary$part123_forecasts == 48L &&
      summary$part123_fits_with_covariance == 48L &&
      summary$part4_fit_artifacts == 16L && summary$part4_fit_cores == 28L &&
      summary$scoring_truth_reads == 0L && summary$model_fits == 0L,
    "coherent-driver authority cardinality changed"
  )
  invisible(list(decision = decision, summary = summary))
}

gpr_verify_manifest <- function(root, manifest_path) {
  manifest <- gpr_read_csv(manifest_path)
  gpr_require(nrow(manifest) > 0L && all(c("relative_path", "size_bytes", "sha256") %in% names(manifest)),
    "manifest is malformed")
  unsafe <- vapply(manifest$relative_path, function(path) {
    grepl("^/", path) || ".." %in% strsplit(gsub("\\\\", "/", path), "/", fixed = TRUE)[[1L]]
  }, logical(1L))
  gpr_require(!any(unsafe) && !anyDuplicated(manifest$relative_path), "manifest path is unsafe or duplicated")
  paths <- file.path(root, manifest$relative_path)
  gpr_require(all(file.exists(paths)), "manifest target is missing")
  gpr_require(all(as.numeric(file.info(paths)$size) == manifest$size_bytes), "manifest size mismatch")
  observed <- vapply(paths, gpr_sha, character(1L))
  gpr_require(all(tolower(observed) == tolower(manifest$sha256)), "manifest hash mismatch")
  manifest
}

gpr_public_pdf_check <- function(path) {
  info <- system2("pdfinfo", shQuote(path), stdout = TRUE, stderr = TRUE)
  images <- system2("pdfimages", c("-list", shQuote(path)), stdout = TRUE, stderr = TRUE)
  text <- system2("pdftotext", c(shQuote(path), "-"), stdout = TRUE, stderr = TRUE)
  gpr_require(any(grepl("^Pages:[[:space:]]+[1-9]", info)), "PDF is unreadable")
  gpr_require(!any(grepl("^[[:space:]]*[0-9]+[[:space:]]+[0-9]+", images)), "PDF contains raster images")
  gpr_require(!grepl("/data/|/home/|/tmp/|local_trackers|runtime_configs|[.]rds", paste(text, collapse = "\n"), ignore.case = TRUE),
    "PDF exposes private runtime material")
  invisible(TRUE)
}

gpr_copy <- function(source, destination) {
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  gpr_require(file.copy(source, destination, overwrite = TRUE), paste0("copy failed: ", source))
  destination
}

gpr_compatibility_aliases <- function() {
  c(
    "% Coordinator candidate only. Load after the Search III current-output aliases.",
    "% It fills names introduced by the rejected November presentation layer.",
    "\\providecommand{\\GlofasApplicationCurrentFullComparisonFigure}{figures/glofas_application/glofas_search3_part1234_final_20261007_part4.pdf}",
    "\\providecommand{\\GlofasApplicationCurrentIssuedSupplementScoreTable}{tables/glofas_search3_part1234_final_20261007_part4_scores.tex}",
    "\\providecommand{\\GlofasApplicationCurrentNormalRidgeAcrps}{0.8471}",
    "\\providecommand{\\GlofasApplicationCurrentNormalRhsAcrps}{1.4790}"
  )
}

gpr_source_row <- function(role, path, disposition, note) {
  data.frame(
    role = role,
    path = normalizePath(path, mustWork = TRUE),
    size_bytes = as.numeric(file.info(path)$size),
    sha256 = gpr_sha(path),
    disposition = disposition,
    note = note,
    stringsAsFactors = FALSE
  )
}

gpr_build <- function(repo_root, closeout_root, root_cause_root, driver_audit_root,
                      output_root) {
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  closeout_root <- normalizePath(closeout_root, mustWork = TRUE)
  root_cause_root <- normalizePath(root_cause_root, mustWork = TRUE)
  driver_audit_root <- normalizePath(driver_audit_root, mustWork = TRUE)
  output_root <- normalizePath(output_root, mustWork = FALSE)
  gpr_require(!dir.exists(output_root), "output root already exists")

  decision_path <- file.path(root_cause_root, "decision.csv")
  driver_summary_path <- file.path(driver_audit_root, "summary.csv")
  root_pdf <- file.path(root_cause_root, "global_tail_root_cause_closeout.pdf")
  current_authority <- file.path(repo_root, "tables/glofas_same_family_current_authority.json")
  closeout_manifest <- file.path(closeout_root, "manifests/output_manifest.csv")
  closeout_pdf <- file.path(closeout_root, "figures/glofas_search3_part1234_final_comparison.pdf")
  closeout_report <- file.path(closeout_root, "reports/final_closeout_report.md")
  closeout_handoff <- file.path(closeout_root, "reports/coordinator_integration_handoff.md")
  implementation_note <- file.path(repo_root, "docs/implementation_notes/glofas_forecast_root_cause_closeout_20261107.md")

  gpr_validate_root_cause(decision_path, driver_summary_path)
  gpr_require(identical(gpr_sha(closeout_manifest), gpr_expected[["search3_output_manifest"]]),
    "Search III closeout manifest changed")
  gpr_require(identical(gpr_sha(current_authority), gpr_expected[["november_authority"]]),
    "committed November authority is not the audited rejected packet")
  gpr_require(identical(gpr_sha(root_pdf), gpr_expected[["root_cause_pdf"]]) &&
    identical(gpr_sha(decision_path), gpr_expected[["root_cause_decision"]]) &&
    identical(gpr_sha(driver_summary_path), gpr_expected[["driver_audit_summary"]]),
    "root-cause or driver-audit fingerprint changed")

  stage <- tempfile("glofas-search3-promotion-", tmpdir = dirname(output_root))
  dir.create(stage, recursive = TRUE)
  on.exit(if (dir.exists(stage)) unlink(stage, recursive = TRUE, force = TRUE), add = TRUE)
  article_safe <- file.path(stage, "article_safe")
  dir.create(article_safe)

  # Rebuild the complete historical Search III projection in isolation. The
  # projection performs the independent 11/11 closeout check before reading
  # any authority source and never fits or forecasts.
  g3_build(repo_root, closeout_root, article_safe)
  projection_manifest <- file.path(article_safe, g3_path("tables", "publication_manifest", "csv"))
  gpr_require(identical(gpr_sha(projection_manifest), gpr_expected[["search3_projection_manifest"]]),
    "isolated Search III projection is not byte-identical to its reviewed authority")
  projection <- gpr_read_csv(projection_manifest)
  versioned <- projection$relative_path[grepl(paste0("^.*", g3_tag), projection$relative_path)]
  retained <- file.path(repo_root, versioned)
  rebuilt <- file.path(article_safe, versioned)
  gpr_require(all(file.exists(retained)) && all(vapply(retained, gpr_sha, character(1L)) ==
    vapply(rebuilt, gpr_sha, character(1L))), "retained Search III article derivatives differ from isolated rebuild")

  compatibility <- file.path(stage, "coordinator_candidate/tables/glofas_search3_current_compatibility.tex")
  dir.create(dirname(compatibility), recursive = TRUE, showWarnings = FALSE)
  writeLines(gpr_compatibility_aliases(), compatibility, useBytes = TRUE)

  gpr_copy(closeout_pdf, file.path(stage, "evidence/search3_final_comparison_six_pages.pdf"))
  gpr_copy(root_pdf, file.path(stage, "evidence/november_root_cause_closeout.pdf"))
  gpr_copy(closeout_report, file.path(stage, "evidence/search3_final_closeout_report.md"))
  gpr_copy(closeout_handoff, file.path(stage, "evidence/search3_original_coordinator_handoff.md"))
  gpr_copy(implementation_note, file.path(stage, "evidence/root_cause_implementation_note.md"))

  rebound <- file.path(driver_audit_root, sprintf("part%d_normal_rhs_driver_bank_rebound.rds", 1:3))
  gpr_require(all(file.exists(rebound)), "rebound Normal-RHS driver bank is missing")
  rebound_copy <- file.path(stage, "authority_objects", basename(rebound))
  Map(gpr_copy, rebound, rebound_copy)

  source_seal <- do.call(rbind, list(
    gpr_source_row("search3_closeout_manifest", closeout_manifest, "canonical", "11/11 frozen closeout authority"),
    gpr_source_row("search3_closeout_pdf", closeout_pdf, "canonical_article_derivative", "six-page vector comparison"),
    gpr_source_row("november_current_article_authority", current_authority, "diagnostic_rejected_not_authority", "structurally incoherent separate-tail future targets"),
    gpr_source_row("root_cause_decision", decision_path, "canonical_diagnostic", "global path reference reproduces crossings"),
    gpr_source_row("root_cause_pdf", root_pdf, "canonical_diagnostic", "truth-free bounded closeout"),
    gpr_source_row("coherent_driver_audit", driver_summary_path, "canonical_contract_evidence", "3 banks, 48 forecasts, 48 covariance fits, 28 Part 4 cores"),
    gpr_source_row("isolated_projection_manifest", projection_manifest, "candidate_article_projection", "byte-identical Search III rebuild")
  ))
  for (i in seq_along(rebound)) source_seal <- rbind(source_seal,
    gpr_source_row(sprintf("part%d_rebound_driver_bank", i), rebound_copy[[i]],
      "sealed_provenance_object", "source path rebound only after retained-fit SHA256 match"))
  gpr_write_csv(source_seal, file.path(stage, "manifests/source_authority_seal.csv"))

  transition <- data.frame(
    authority = c("Search III shared Normal-RHS driver", "November same-family AL/exAL transition",
      "Global-path root-cause diagnostic", "Search III coherent-driver audit"),
    prior_status = c("historical_authority", "current_article_authority", "diagnostic", "contract_audit"),
    final_status = c("canonical_article_authority", "diagnostic_rejected_not_authority",
      "canonical_diagnostic", "canonical_contract_evidence"),
    reason = c(
      "One shared recursive response law; internally selected rainy-season geometry; protected window scoring only.",
      "Separate tau-specific future response laws do not define one predictive distribution; global references reproduce crossings.",
      "Rules out convergence, Monte Carlo, and local Delta as material causes of the severe crossings.",
      "Authentic retained Search III banks, forecasts, covariance blocks, and Part 4 prior replacement all pass."
    ), stringsAsFactors = FALSE
  )
  gpr_write_csv(transition, file.path(stage, "tables/authority_transition.csv"))

  gates <- data.frame(
    gate = c("search3_closeout_11_of_11", "search3_projection_rebuilt", "search3_versioned_assets_match",
      "root_cause_decision", "november_excluded", "normal_driver_banks", "part123_forecast_contracts",
      "part123_full_covariance", "part4_replacement_prior", "future_truth_firewall", "model_fit_firewall",
      "article_tree_unchanged"),
    status = "pass",
    evidence = c("READY_FOR_COORDINATOR_INTEGRATION", gpr_sha(projection_manifest),
      "all manifest-listed versioned SHA256 values identical", "STRUCTURAL_INDEPENDENT_TAIL_PATH_TARGET_INCOHERENCE",
      "diagnostic_rejected_not_authority", "3/3", "48/48", "48/48", "28/28 inner cores",
      "0 diagnostic truth reads", "0 model fits", "projection built in ignored isolated packet"),
    stringsAsFactors = FALSE
  )
  gpr_write_csv(gates, file.path(stage, "tables/promotion_gates.csv"))

  replacement <- data.frame(
    surface = c("main and supplement alias load", "current authority JSON", "main score table",
      "main forecast figure", "supplement family comparison", "calibration table/figure",
      "convergence table/figure", "main result prose"),
    current_november_surface = c("tables/glofas_same_family_20261103_display_aliases.tex",
      "tables/glofas_same_family_current_authority.json", "glofas_same_family_20261103_main_scores.tex",
      "glofas_same_family_20261103_main.pdf", "glofas_same_family_20261103_all_families.pdf",
      "glofas_same_family_20261103_calibration.*", "glofas_same_family_20261103_convergence.*",
      "Normal Ridge described from rejected packet"),
    coordinator_action = c("remove the later November alias input; load Search III aliases plus compatibility file",
      "replace with a reviewed Search III authority receipt generated during integration",
      "use glofas_search3_part1234_final_20261007_part4_scores.tex",
      "use glofas_search3_part1234_final_20261007_part4.pdf",
      "use the six Search III role PDFs; do not use November same-family paths",
      "use Search III calibration derivatives", "use Search III strict convergence derivatives",
      "describe Independent AL as protected-window descriptive leader, not a selected model"),
    requires_manuscript_edit = c(TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE, TRUE),
    stringsAsFactors = FALSE
  )
  gpr_write_csv(replacement, file.path(stage, "tables/article_replacement_map.csv"))

  report <- c(
    "# GloFAS Search III promotion reconciliation", "",
    "## Decision", "",
    "Search III is the canonical Part 1--4 article authority. The November same-family future-transition packet is retained as adverse diagnostic evidence and must not be used for article tables, figures, aliases, or claims.", "",
    "The global p05/p50/p95 path reference reproduces the severe crossings, while remaining close to the local Gaussian-Delta result. The defect is therefore structural target incoherence, not failed convergence, Monte Carlo error, or a local approximation artifact. Additional fitting cannot repair it.", "",
    "## Reconciliation result", "",
    "- Search III final closeout: 11/11 gates passed.",
    "- Search III article projection: rebuilt in isolation and byte-identical to the retained reviewed assets.",
    "- Coherent Normal-driver authority: 3/3 banks, 48/48 forecasts, 48/48 covariance-bearing fits, and 28/28 Part 4 inner cores passed.",
    "- Diagnostic truth reads: 0; model fits: 0.",
    "- Current tracked article and Overleaf state: intentionally unchanged pending coordinator transaction.", "",
    "## Scientific boundary", "",
    "Search III retained `search3_ref_001` and adopted rainy-season discrepancy candidate `search3_dis_007` using internal training evidence. Parts 1 and 3 retain 30-day recursive scoring, Part 2 remains unscored after the cutoff because retrospective GloFAS is unavailable, and Part 4 retains 28 issued horizons. Independent AL is the Part 4 descriptive leader; this is evaluation evidence, not protected-window model selection.", "",
    "Decision: `READY_FOR_COORDINATOR_INTEGRATION_AFTER_ALIAS_TRANSACTION`"
  )
  dir.create(file.path(stage, "reports"), recursive = TRUE, showWarnings = FALSE)
  writeLines(report, file.path(stage, "reports/final_promotion_reconciliation.md"))

  handoff <- c(
    "# Coordinator handoff: restore coherent GloFAS Search III authority", "",
    "## Mandatory preflight", "",
    "1. Verify this packet with `application/scripts/450_check_glofas_search3_promotion_reconciliation.R`.",
    "2. Re-run the frozen Search III closeout checker and projection checker before editing article files.",
    "3. Confirm `tables/authority_transition.csv` marks the November packet `diagnostic_rejected_not_authority`.", "",
    "## Atomic article transaction", "",
    "1. Preserve all November files as historical adverse evidence; do not delete or silently rewrite them.",
    "2. Remove the later November alias input from `main.tex` and `qdesn-supplement.tex`.",
    "3. Install the isolated Search III article-safe files and load `coordinator_candidate/tables/glofas_search3_current_compatibility.tex` after the Search III current-output aliases.",
    "4. Follow `tables/article_replacement_map.csv` and revise prose that currently reports the rejected November Normal-Ridge-led comparison.",
    "5. Generate a new reviewed current-authority receipt; do not relabel the November receipt.",
    "6. Build and inspect both manuscripts, run the complete GloFAS authority and document suites, then commit the article switch atomically.",
    "7. Push main and publish Overleaf only after remote readback verifies the exact integration commit.", "",
    "## Claims to preserve", "",
    "- Search III geometry was selected using internal rainy-season training evidence, not the final window.",
    "- Independent AL is the Part 4 issued-window descriptive leader, not a protected-window selection.",
    "- Part 2 future discrepancy remains unscored.",
    "- Search III uses coherent shared Normal-RHS recursive paths; the November separate-tail path target is rejected.",
    "- No model was refitted by this reconciliation.", "",
    "Gate: `READY_FOR_COORDINATOR_INTEGRATION_AFTER_ALIAS_TRANSACTION`"
  )
  writeLines(handoff, file.path(stage, "reports/coordinator_integration_handoff.md"))

  article_paths <- file.path(stage, c("article_safe", "coordinator_candidate", "reports", "tables", "evidence"))
  archive <- file.path(stage, "packages/glofas_search3_coordinator_packet_20261107.tar.gz")
  dir.create(dirname(archive), recursive = TRUE, showWarnings = FALSE)
  old <- getwd(); setwd(stage); on.exit(setwd(old), add = TRUE)
  status <- system2("tar", c("--sort=name", "--mtime=2026-11-07T00:00:00Z", "--owner=0", "--group=0",
    "--numeric-owner", "--use-compress-program=gzip -n", "-cf", shQuote(archive),
    "article_safe", "coordinator_candidate", "reports", "tables", "evidence"))
  setwd(old)
  gpr_require(status == 0L && file.exists(archive), "coordinator archive creation failed")

  all_files <- list.files(stage, recursive = TRUE, full.names = TRUE)
  all_files <- all_files[!grepl("(^|/)manifests/output_manifest[.]csv$|(^|/)status/promotion_ready[.]json$", all_files)]
  relative <- substring(all_files, nchar(stage) + 2L)
  output_manifest <- data.frame(relative_path = relative,
    size_bytes = as.numeric(file.info(all_files)$size),
    sha256 = vapply(all_files, gpr_sha, character(1L)), stringsAsFactors = FALSE)
  output_manifest <- output_manifest[order(output_manifest$relative_path), ]
  gpr_write_csv(output_manifest, file.path(stage, "manifests/output_manifest.csv"))
  ready <- list(
    decision = "READY_FOR_COORDINATOR_INTEGRATION_AFTER_ALIAS_TRANSACTION",
    created_on = "2026-11-07",
    source_head = system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE),
    search3_output_manifest_sha256 = gpr_sha(closeout_manifest),
    isolated_projection_manifest_sha256 = gpr_sha(projection_manifest),
    root_cause_decision_sha256 = gpr_sha(decision_path),
    driver_audit_summary_sha256 = gpr_sha(driver_summary_path),
    coordinator_archive_sha256 = gpr_sha(archive),
    output_manifest_sha256 = gpr_sha(file.path(stage, "manifests/output_manifest.csv")),
    model_fits = 0L,
    diagnostic_truth_reads = 0L,
    article_files_modified = 0L
  )
  dir.create(file.path(stage, "status"), recursive = TRUE)
  writeLines(jsonlite::toJSON(ready, auto_unbox = TRUE, pretty = TRUE),
    file.path(stage, "status/promotion_ready.json"))

  gpr_check(stage, closeout_root = closeout_root, repo_root = repo_root)
  gpr_require(file.rename(stage, output_root), "atomic promotion-packet publication failed")
  on.exit(NULL, add = FALSE)
  cat("GLOFAS_SEARCH3_PROMOTION_RECONCILIATION_BUILD_PASS\n")
  cat("READY_FOR_COORDINATOR_INTEGRATION_AFTER_ALIAS_TRANSACTION\n")
  invisible(output_root)
}

gpr_check <- function(root, closeout_root = NULL, repo_root = NULL) {
  root <- normalizePath(root, mustWork = TRUE)
  manifest <- gpr_verify_manifest(root, file.path(root, "manifests/output_manifest.csv"))
  ready <- jsonlite::fromJSON(file.path(root, "status/promotion_ready.json"))
  gpr_require(identical(ready$decision, "READY_FOR_COORDINATOR_INTEGRATION_AFTER_ALIAS_TRANSACTION"),
    "ready decision changed")
  gpr_require(ready$model_fits == 0L && ready$diagnostic_truth_reads == 0L &&
    ready$article_files_modified == 0L, "reconciliation crossed a scientific or article boundary")
  gpr_require(identical(gpr_sha(file.path(root, "manifests/output_manifest.csv")),
    ready$output_manifest_sha256), "ready receipt does not bind the output manifest")
  gpr_require(all(gpr_read_csv(file.path(root, "tables/promotion_gates.csv"))$status == "pass"),
    "promotion gate failed")
  transition <- gpr_read_csv(file.path(root, "tables/authority_transition.csv"))
  gpr_require(identical(transition$final_status[transition$authority ==
    "November same-family AL/exAL transition"], "diagnostic_rejected_not_authority"),
    "November authority was not excluded")
  gpr_require(!any(grepl("glofas_same_family_20261103", manifest$relative_path[grepl("^article_safe/", manifest$relative_path)])),
    "rejected November asset leaked into article-safe packet")
  gpr_require(!any(grepl("[.](rds|rda|rdata)$", utils::untar(
    file.path(root, "packages/glofas_search3_coordinator_packet_20261107.tar.gz"), list = TRUE),
    ignore.case = TRUE)), "coordinator package contains model payloads")
  g3_check(file.path(root, "article_safe"), closeout_root)
  pdfs <- list.files(file.path(root, "article_safe/figures"), pattern = "[.]pdf$", recursive = TRUE, full.names = TRUE)
  invisible(lapply(pdfs, gpr_public_pdf_check))
  compatibility <- paste(readLines(file.path(root,
    "coordinator_candidate/tables/glofas_search3_current_compatibility.tex"), warn = FALSE), collapse = "\n")
  for (token in c("CurrentFullComparisonFigure", "CurrentIssuedSupplementScoreTable",
    "CurrentNormalRidgeAcrps", "CurrentNormalRhsAcrps")) {
    gpr_require(grepl(token, compatibility, fixed = TRUE), paste0("compatibility alias missing: ", token))
  }
  if (!is.null(repo_root)) {
    repo_root <- normalizePath(repo_root, mustWork = TRUE)
    gpr_require(identical(gpr_sha(file.path(repo_root, "tables/glofas_same_family_current_authority.json")),
      gpr_expected[["november_authority"]]), "checker observed an unreviewed article-authority mutation")
  }
  cat("GLOFAS_SEARCH3_PROMOTION_RECONCILIATION_VERIFY_PASS\n")
  cat("READY_FOR_COORDINATOR_INTEGRATION_AFTER_ALIAS_TRANSACTION\n")
  invisible(manifest)
}
