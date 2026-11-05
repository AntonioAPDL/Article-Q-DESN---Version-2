#!/usr/bin/env Rscript
# Bounded CSV/JSON/YAML/source audit only. No RDS is opened, hashed or statted;
# no model, forecast, scoring, historical-runtime mutation or publication occurs.
app_gsr_audit_link_free <- function(path, missing_leaf = FALSE) {
  q <- app_gsr_require
  parts <- strsplit(path, "/", fixed = TRUE)[[1L]]; parts <- parts[nzchar(parts)]
  current <- "/"
  for (i in seq_along(parts)) {
    current <- file.path(current, parts[i]); link <- Sys.readlink(current)
    if (is.na(link)) q(isTRUE(missing_leaf) && i == length(parts) && !file.exists(current),
      "missing metadata path component") else q(!nzchar(link), "metadata symlink forbidden")
  }
  invisible(TRUE)
}
app_gsr_audit_pin <- function(path, expected_hash = NULL, extension = NULL) {
  q <- app_gsr_require
  q(is.character(path) && length(path) == 1L && startsWith(path, "/") &&
    !grepl("(^|/)\\.\\.(/|$)", path) && !grepl("\\.(rds|rda|rdata)$", path, ignore.case = TRUE),
    "only explicit non-RDS metadata paths are permitted")
  q(is.null(extension) || endsWith(tolower(path), extension), "metadata role extension differs")
  app_gsr_audit_link_free(path)
  info <- file.info(path)
  q(file.exists(path) && !isTRUE(info$isdir) && info$size > 0 && info$size <= 4 * 1024^2 &&
    identical(normalizePath(path, mustWork = TRUE), path), "bounded regular metadata required")
  digest <- unname(tools::sha256sum(path))
  if (!is.null(expected_hash)) q(is.character(expected_hash) && length(expected_hash) == 1L &&
    grepl("^[0-9a-f]{64}$", expected_hash) && identical(digest, expected_hash), "metadata hash changed")
  list(path = path, size_bytes = as.numeric(info$size), sha256 = digest)
}
app_gsr_audit_output <- function(root, out) {
  q <- app_gsr_require
  q(is.character(out) && length(out) == 1L && startsWith(out, paste0(root, "/local_trackers/")) &&
    !grepl("(^|/)\\.\\.(/|$)", out), "fresh ignored audit output required")
  app_gsr_audit_link_free(out, missing_leaf = TRUE)
  q(!file.exists(out) && dir.exists(dirname(out)) && identical(normalizePath(dirname(out)), dirname(out)) &&
    system2("/usr/bin/git", c("-C", shQuote(root), "check-ignore", "--quiet", "--", shQuote(out))) == 0L,
    "fresh ignored audit output required")
  invisible(TRUE)
}

app_glofas_specification_audit_main <- function(args = commandArgs(TRUE)) {
if (!length(args) || identical(args, "--help")) {
  cat(paste0("Usage: Rscript scripts/audit_glofas_specification_reconciliation.R ",
    "--selected CSV --selected-sha256 SHA --executed CSV --executed-sha256 SHA ",
    "--replay-summary JSON --replay-summary-sha256 SHA --reused-source-manifest CSV ",
    "--reused-source-manifest-sha256 SHA --decision JSON --decision-sha256 SHA --output IGNORED_DIR\n"))
} else {
  script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  root <- normalizePath(file.path(dirname(script), ".."), mustWork = TRUE)
  setwd(root); source("application/R/glofas_specification_reconciliation.R")
  q <- app_gsr_require
  expected <- c("selected", "selected-sha256", "executed", "executed-sha256", "replay-summary",
    "replay-summary-sha256", "reused-source-manifest", "reused-source-manifest-sha256",
    "decision", "decision-sha256", "output")
  q(length(args) == 2L * length(expected) && all(startsWith(args[seq(1L, length(args), 2L)], "--")),
    "exact paired metadata-only arguments required")
  opt <- as.list(args[seq(2L, length(args), 2L)]); names(opt) <- sub("^--", "", args[seq(1L, length(args), 2L)])
  q(!anyDuplicated(names(opt)) && setequal(names(opt), expected), "unknown, missing or duplicate audit argument")
  git <- function(a) {
    value <- system2("/usr/bin/git", c("--no-replace-objects", "-c", "core.fsmonitor=false", a), stdout = TRUE)
    q(is.null(attr(value, "status")), "source Git check failed"); unname(value)
  }
  q(identical(git(c("rev-parse", "--show-toplevel")), root) &&
    !length(git(c("status", "--porcelain", "--untracked-files=all"))), "clean committed source required")
  commit <- git(c("rev-parse", "HEAD")); tree <- git(c("rev-parse", "HEAD^{tree}"))
  pin <- app_gsr_audit_pin
  out <- opt$output; app_gsr_audit_output(root, out)
  roles <- c("selected", "executed", "replay-summary", "reused-source-manifest", "decision")
  bindings <- lapply(roles, function(role) pin(opt[[role]], opt[[paste0(role, "-sha256")]],
    if (role %in% c("replay-summary", "decision")) ".json" else ".csv")); names(bindings) <- roles
  selected <- read.csv(opt$selected, stringsAsFactors = FALSE, check.names = FALSE)
  executed <- read.csv(opt$executed, stringsAsFactors = FALSE, check.names = FALSE)
  decision <- jsonlite::read_json(opt$decision, simplifyVector = FALSE)
  replay <- jsonlite::read_json(opt[["replay-summary"]], simplifyVector = FALSE)
  result <- app_glofas_reconcile_specification(selected, executed, decision$policy, decision)
  result <- app_glofas_bind_executed_replay(result, replay)
  proof <- app_glofas_assert_specification_basis(result$authorized_specification, result, decision$policy,
    result$specification_basis, if (decision$policy == "preserve_executed") result$frozen_numeric_identity else NULL)
  reuse <- read.csv(opt[["reused-source-manifest"]], stringsAsFactors = FALSE, check.names = FALSE)
  q(identical(names(reuse), c("path", "size_bytes", "sha256")) && !anyDuplicated(reuse$path),
    "exact unique reused-source manifest schema required")
  # Filter role/path strings BEFORE any stat/hash/open. Binary and data payloads
  # in the historical manifest remain outside this audit's read surface.
  yaml_rows <- reuse[grepl("\\.ya?ml$", reuse$path, ignore.case = TRUE), , drop = FALSE]
  q(nrow(yaml_rows) == 21L, "exact 21 retained YAML metadata records required")
  yaml_pins <- list(); gain_records <- list()
  for (i in seq_len(nrow(yaml_rows))) {
    p <- pin(yaml_rows$path[i], yaml_rows$sha256[i])
    q(p$size_bytes == yaml_rows$size_bytes[i], "YAML byte size differs from frozen reuse manifest")
    yaml_pins[[i]] <- p
    text <- trimws(readLines(p$path, warn = FALSE))
    gains <- text[grepl("^win_scale_(global|bias):", text)]
    if (length(gains)) {
      q(identical(gains, c("win_scale_global: 0.5", "win_scale_bias: 1",
        "win_scale_global: 0.35", "win_scale_bias: 1", "win_scale_global: 0.5", "win_scale_bias: 1")),
        "retained model YAML differs from frozen applied gain convention")
      gain_records[[length(gain_records) + 1L]] <- data.frame(path = p$path,
        beta_gain = .5, alpha_gain = .35, bias_gain = 1, sha256 = p$sha256, stringsAsFactors = FALSE)
    }
  }
  q(length(gain_records) == 18L, "all 18 retained model configurations must share frozen gain convention")
  source_paths <- c("application/R/glofas_specification_reconciliation.R",
    "scripts/audit_glofas_specification_reconciliation.R", "application/tests/test_glofas_specification_reconciliation.R",
    "application/R/glofas_post_search2_workflow.R", "application/R/glofas_search_phase2.R",
    "application/R/glofas_search3_rainy_season.R", "application/R/glofas_normal_desn_part1_screening.R",
    "application/R/latent_path_design.R", "application/scripts/prepare_glofas_unit_member_correction.R",
    "application/scripts/prepare_glofas_family_transition.R")
  source_pins <- lapply(source_paths, function(rel) {
    p <- pin(file.path(root, rel))
    q(identical(git(c("hash-object", "--no-filters", "--", shQuote(rel))),
      git(c("rev-parse", shQuote(paste0(commit, ":", rel))))), "audit source differs from committed blob")
    c(list(relative_path = rel), p)
  })
  # The complete underlying generator source is identical at screening,
  # frozen application and this audit. This rules out an introduced source-
  # level compensating gain convention, not every possible numeric model fact.
  generator_blobs <- vapply(c("0c71f075d3ef623a15b7c2a9e9f1e3f3ea410e5d",
    "fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6", commit), function(revision)
      git(c("rev-parse", paste0(revision, ":application/R/latent_path_design.R"))), character(1L))
  q(length(unique(generator_blobs)) == 1L, "generator source changed across screened/applied/current authorities")
  app_gsr_audit_output(root, out)
  q(dir.create(out, mode = "0700"), "exclusive audit output creation failed")
  write_json <- function(x, name) jsonlite::write_json(x, file.path(out, name), auto_unbox = TRUE,
    null = "null", na = "null", digits = 17, pretty = TRUE)
  write.csv(result$gain_comparison, file.path(out, "gain_comparison.csv"), row.names = FALSE)
  write.csv(result$shared_feature_checks, file.path(out, "shared_feature_checks.csv"), row.names = FALSE)
  write.csv(result$replay_checks, file.path(out, "executed_replay_checks.csv"), row.names = FALSE)
  write.csv(do.call(rbind, gain_records), file.path(out, "retained_yaml_checks.csv"), row.names = FALSE)
  write_json(result, "reconciliation.json"); write_json(proof, "preflight.json")
  write_json(source_pins, "source_pins.json")
  receipt <- list(schema_version = "glofas_specification_audit_receipt_v1", status = "METADATA_RECONCILIATION_COMPLETE_NO_MODEL_CHANGE",
    source_root = root, source_commit = commit, source_tree = tree, source_files = source_pins,
    input_bindings = bindings, retained_YAML_bindings = yaml_pins, decision = decision,
    specification_basis = result$specification_basis, screened_equals_executed = FALSE,
    original_RDS_reads = 0L, original_RDS_hashes = 0L, generated_RDS_reads = 0L,
    model_runs = 0L, feature_builds = 0L, forecast_loss_selection = FALSE, future_USGS_accessed = FALSE,
    historical_runtime_modified = FALSE, article_changed = FALSE,
    generator_source_blob = unname(generator_blobs[1L]))
  for (p in c(bindings, yaml_pins, source_pins)) pin(p$path, p$sha256)
  q(!length(git(c("status", "--porcelain", "--untracked-files=all"))), "source changed during metadata audit")
  write_json(receipt, "AUDIT_RECEIPT.json")
  files <- list.files(out, full.names = TRUE)
  q(sum(file.info(files)$size) < 4 * 1024^2, "compact audit output limit exceeded")
  inventory <- data.frame(relative_path = basename(files), size_bytes = as.numeric(file.info(files)$size),
    sha256 = unname(tools::sha256sum(files)))
  write.csv(inventory, file.path(out, "artifact_manifest.csv"), row.names = FALSE)
  cat("GLOFAS_SPECIFICATION_RECONCILIATION_COMPLETE_NO_MODEL_CHANGE\n")
}
}
if (sys.nframe() == 0L) app_glofas_specification_audit_main()
