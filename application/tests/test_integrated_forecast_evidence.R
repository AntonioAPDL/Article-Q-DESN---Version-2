#!/usr/bin/env Rscript
local({
  root <- if (exists("app_repo_root", mode = "function")) app_repo_root() else {
    arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
    normalizePath(file.path(dirname(sub("^--file=", "", arg)), "..", ".."))
  }
  source(file.path(root, "scripts/prepare_integrated_forecast_evidence.R"), local = TRUE)
  fixture <- tempfile("iqf-evidence-"); dir.create(fixture)
  on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
  evidence <- file.path(fixture, "evidence"); dir.create(evidence)
  for (name in c("design", "posterior", "origins")) saveRDS(list(fixture = name),
    file.path(evidence, paste0(name, ".rds")))
  spec <- list(schema_version = "integrated_quantile_forecast_bundle_v1", adapter = "mq_desn_native_v1",
    payloads = list(design = "design.rds", posterior = "posterior.rds", origins = "origins.rds"))
  spec_file <- file.path(evidence, "spec.json")
  jsonlite::write_json(spec, spec_file, auto_unbox = TRUE)
  out <- file.path(fixture, "enrolled")
  good <- app_iqf_enroll_evidence(evidence, "spec.json", out)
  stopifnot(identical(good$allow_launch, FALSE), good$files == 4L,
    good$trajectories_generated == 0L, file.exists(file.path(out, "input_manifest.csv")))
  rejects <- 0L
  reject <- function(expr) {
    error <- tryCatch({force(expr); NULL}, error = identity)
    stopifnot(inherits(error, "error")); rejects <<- rejects + 1L
  }
  reject(app_iqf_enroll_evidence(evidence, "spec.json", out))
  reject(app_iqf_enroll_evidence(evidence, "spec.json", file.path(evidence, "new")))
  reject(app_iqf_enroll_evidence(evidence, "spec.json", file.path(fixture, "too-big"), 1))
  reject(app_iqf_evidence_path(evidence, "../spec.json"))
  reject(app_iqf_evidence_path(evidence, spec_file))
  reject(app_iqf_evidence_path(evidence, ".git/config"))
  reject(app_iqf_evidence_path(evidence, "missing.rds"))
  linked <- file.path(evidence, "linked.rds")
  stopifnot(file.symlink(file.path(evidence, "design.rds"), linked))
  reject(app_iqf_evidence_path(evidence, "linked.rds"))
  bad <- spec; bad$payloads$oracle <- "future_truth.rds"
  jsonlite::write_json(bad, spec_file, auto_unbox = TRUE)
  reject(app_iqf_enroll_evidence(evidence, "spec.json", file.path(fixture, "bad-role")))
  bad <- spec; bad$payloads$posterior <- "design.rds"
  jsonlite::write_json(bad, spec_file, auto_unbox = TRUE)
  reject(app_iqf_enroll_evidence(evidence, "spec.json", file.path(fixture, "duplicate")))
  cat(sprintf("IQF_EVIDENCE_TEST_PASS mutation_rejections=%d production_runs=0\n", rejects))
})
