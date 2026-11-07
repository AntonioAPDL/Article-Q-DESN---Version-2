#!/usr/bin/env Rscript
# Issue a private source-bound purpose for one admitted AL tail. This script
# hashes files only; the tail reader performs the two authorized RDS reads.
source("scripts/glofas_global_path_tail_reader.R")

fail <- function(message) stop(paste0("GloFAS tail purpose: ", message), call. = FALSE)
git <- function(args) {
  out <- system2("/usr/bin/git", c("--no-replace-objects", "-c",
    "core.fsmonitor=false", args), stdout = TRUE)
  if (!is.null(attr(out, "status"))) fail("Git provenance command failed")
  unname(out)
}
arg <- function(name, default = NULL) {
  at <- match(name, args)
  if (is.na(at)) return(default)
  if (at == length(args)) fail(paste("missing value for", name))
  args[[at + 1L]]
}
pin <- function(path, maximum = 8 * 1024^3) {
  path <- normalizePath(path, mustWork = TRUE)
  info <- file.info(path)
  if (isTRUE(info$isdir) || info$size <= 0 || info$size > maximum)
    fail(paste("invalid pinned file", path))
  list(path = path, size_bytes = unname(info$size),
    sha256 = unname(tools::sha256sum(path)))
}

args <- commandArgs(TRUE)
if (identical(args, "--help")) {
  cat("Usage: Rscript --vanilla scripts/prepare_glofas_global_path_tail_purpose.R --task gft-al-p005|gft-al-p095 --operation measure|execute --prior-receipt FILE [--measurement-receipt FILE] [--logical-cpu N]\n")
  quit(save = "no", status = 0L)
}
task_id <- arg("--task")
probability <- ggtr_task(task_id)
operation <- arg("--operation", "measure")
if (!operation %in% c("measure", "execute")) fail("invalid operation")
logical_cpu <- as.integer(arg("--logical-cpu", if (task_id == "gft-al-p005")
  "26" else "27"))
if (is.na(logical_cpu) || !logical_cpu %in% 0:63) fail("invalid logical CPU")
prior_path <- arg("--prior-receipt")
if (is.null(prior_path)) fail("--prior-receipt is required")
measurement_path <- arg("--measurement-receipt")
if (operation == "execute" && is.null(measurement_path))
  fail("execution requires --measurement-receipt")
if (operation == "measure" && !is.null(measurement_path))
  fail("measurement cannot consume a prior measurement")

root <- normalizePath(getwd(), mustWork = TRUE)
if (!identical(git(c("rev-parse", "--show-toplevel")), root) ||
    length(git(c("status", "--porcelain", "--untracked-files=all"))))
  fail("purpose issuance requires the exact clean worktree root")
commit <- git(c("rev-parse", "HEAD")); tree <- git(c("rev-parse", "HEAD^{tree}"))
stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
short <- substring(commit, 1L, 8L)
prepared <- paste0("/data/jaguir26/local/src/",
  "Article-Q-DESN---Version-2__wt__glofas_family_transition_launch_20261101/",
  "local_trackers/glofas_transition_launch_20261101/prepared_r2")
claim <- c(`gft-al-p005` = "3804acfc9e0a8b96700c070ece66fdd241ddf411c3dc777b",
  `gft-al-p095` = "70bd478b134f42e8061247cb806dbca25eec6f97d0d314a0")
external <- list(
  collection = "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_same_family_closeout_execution_v2_20261103/local_trackers/glofas_article_closeout_20261103/assemble/accepted_producers.json",
  input_manifest = file.path(prepared, "manifests/input_manifest.csv"),
  design = file.path(prepared, "objects/shared_truth_free_design.rds"),
  model = file.path(prepared, "results", task_id, claim[[task_id]], "fit.rds"),
  prior_receipt = prior_path,
  measurement_receipt = measurement_path)
source_files <- lapply(ggtr_sources(), function(rel) pin(file.path(root, rel),
  2 * 1024^2))
controls <- jsonlite::read_json(file.path(root,
  "scripts/diagnostics/glofas_global_path_tail_controls.json"),
  simplifyVector = FALSE)
task <- ggtr_controls(controls, task_id, operation)
model <- pin(external$model)
if (model$size_bytes != task$fit_size_bytes || model$sha256 != task$fit_sha256)
  fail("accepted tail fit differs from tracked controls")
output_parent <- file.path(root, "local_trackers",
  "glofas_forecast_root_cause_reference_20261106")
output_root <- file.path(output_parent, paste0("native_global_path_tail_",
  operation, "_", task_id, "_", stamp, "_", short))
scratch <- tempfile(paste0("glofas_tail_", task_id, "_", operation, "_"),
  tmpdir = "/tmp")
if (!dir.create(scratch, mode = "0700")) fail("cannot create private scratch root")
purpose <- list(schema_version = "glofas_global_path_tail_purpose_v1",
  purpose = "TAIL_AL_FIXED_PARAMETER_GLOBAL_PATH_NO_FIT_NO_TRUTH",
  operation = operation, task_id = task_id, probability = probability,
  nonce = paste(sample(c(0:9, letters[1:6]), 48L, replace = TRUE), collapse = ""),
  expires_utc = format(Sys.time() + 12 * 3600, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  source_root = root, source_commit = commit, source_tree = tree,
  source_files = source_files, expected_identity = gsc_identity(),
  collection = pin(external$collection, 4 * 1024^2),
  input_manifest = pin(external$input_manifest, 4 * 1024^2),
  design = pin(external$design), model = model,
  prior_receipt = pin(external$prior_receipt, 4 * 1024^2),
  acceptance_budget = pin(file.path(root,
    "scripts/diagnostics/glofas_native_stage_e_acceptance_budget.json"), 4 * 1024^2),
  controls = pin(file.path(root,
    "scripts/diagnostics/glofas_global_path_tail_controls.json"), 4 * 1024^2),
  measurement_receipt = if (is.null(external$measurement_receipt)) NULL else
    pin(external$measurement_receipt, 4 * 1024^2),
  read_budget = list(max_payload_hash_bytes = 2 * (4014834693 + model$size_bytes),
    max_deserialization_bytes = 4014834693 + model$size_bytes,
    max_RDS_deserializations = 2L, max_generated_RDS_deserializations = 0L,
    max_metadata_bytes = 64 * 1024^2,
    max_diagnostic_output_bytes = 48 * 1024^2),
  limits = list(cpu_seconds = 14400L, wall_seconds = 14400L,
    memory_bytes = 32 * 1024^3, output_bytes = 64 * 1024^2,
    logical_cpu = logical_cpu), output_root = output_root,
  metadata_scratch_root = normalizePath(scratch),
  metadata_serialization = list(max_files = 64L,
    max_file_bytes = 4 * 1024^2, max_total_bytes = 32 * 1024^2),
  allow_original_reads = TRUE, allow_prior_metadata_read = TRUE,
  allow_fresh_source_feature_replay = TRUE,
  allow_fixed_parameter_diagnostic = TRUE, allow_metadata_serialization = TRUE,
  allow_generated_RDS_read = FALSE, allow_saved_callbacks = FALSE,
  allow_parameter_optimization = FALSE, allow_model_fit = FALSE,
  allow_truth_read = FALSE, allow_retuning = FALSE, allow_scoring = FALSE,
  allow_article_changes = FALSE, allow_publication = FALSE,
  allow_authority_replacement = FALSE)
ggtr_scope(purpose)
purpose_file <- arg("--purpose-file", file.path("/tmp", paste0(
  "glofas_global_path_tail_", task_id, "_", operation, "_", stamp, "_",
  short, ".json")))
if (file.exists(purpose_file)) fail("purpose file already exists")
writeLines(jsonlite::toJSON(purpose, auto_unbox = TRUE, pretty = TRUE,
  digits = 17, null = "null"), purpose_file, useBytes = TRUE)
Sys.chmod(purpose_file, mode = "0600")
purpose_file <- normalizePath(purpose_file)
cat(sprintf("PURPOSE_FILE=%s\nPURPOSE_SHA256=%s\nOUTPUT_ROOT=%s\nSCRATCH_ROOT=%s\n",
  purpose_file, unname(tools::sha256sum(purpose_file)), output_root,
  normalizePath(scratch)))
