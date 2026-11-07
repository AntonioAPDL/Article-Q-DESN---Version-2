#!/usr/bin/env Rscript
# Issue a private, source-bound purpose for the fixed-parameter native median
# diagnostic. This prepares admission metadata only; it does not read RDS
# payloads, fit a model, access future truth, or launch the reader.
source("scripts/glofas_global_path_native_reader.R")

fail <- function(message) stop(paste0("GloFAS global-path purpose: ", message),
  call. = FALSE)
git <- function(args) {
  value <- system2("/usr/bin/git", c("--no-replace-objects", "-c",
    "core.fsmonitor=false", args), stdout = TRUE)
  if (!is.null(attr(value, "status"))) fail("Git provenance command failed")
  unname(value)
}
pin <- function(path, maximum = 8 * 1024^3) {
  path <- normalizePath(path, mustWork = TRUE)
  info <- file.info(path)
  if (isTRUE(info$isdir) || info$size <= 0 || info$size > maximum)
    fail(paste("invalid pinned file", path))
  list(path = path, size_bytes = unname(info$size),
    sha256 = unname(tools::sha256sum(path)))
}
arg <- function(name, default = NULL) {
  at <- match(name, args)
  if (is.na(at)) return(default)
  if (at == length(args)) fail(paste("missing value for", name))
  args[[at + 1L]]
}

args <- commandArgs(TRUE)
if (identical(args, "--help")) {
  cat(paste0("Usage: Rscript --vanilla scripts/prepare_glofas_global_path_native_purpose.R ",
    "[--operation measure|execute] [--logical-cpu N] [--purpose-file FILE]\n"))
  quit(save = "no", status = 0L)
}
operation <- arg("--operation", "measure")
if (!operation %in% c("measure", "execute")) fail("invalid operation")
logical_cpu <- suppressWarnings(as.integer(arg("--logical-cpu", "26")))
if (is.na(logical_cpu) || !logical_cpu %in% 0:63) fail("invalid logical CPU")

root <- normalizePath(getwd(), mustWork = TRUE)
if (!identical(git(c("rev-parse", "--show-toplevel")), root) ||
    length(git(c("status", "--porcelain", "--untracked-files=all"))))
  fail("purpose issuance requires the exact clean worktree root")
commit <- git(c("rev-parse", "HEAD"))
tree <- git(c("rev-parse", "HEAD^{tree}"))
stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
short <- substring(commit, 1L, 8L)

external <- list(
  collection = "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_same_family_closeout_execution_v2_20261103/local_trackers/glofas_article_closeout_20261103/assemble/accepted_producers.json",
  input_manifest = "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_family_transition_launch_20261101/local_trackers/glofas_transition_launch_20261101/prepared_r2/manifests/input_manifest.csv",
  design = "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_family_transition_launch_20261101/local_trackers/glofas_transition_launch_20261101/prepared_r2/objects/shared_truth_free_design.rds",
  median_model = "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_family_transition_launch_20261101/local_trackers/glofas_transition_launch_20261101/prepared_r2/results/gft-al-p050/ae23d06dbcc3f87d31ed65e3173b186d8d1044a117a6e609/fit.rds",
  prior_receipt = "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_native_optimizer_continuation_20261106/local_trackers/glofas_native_optimizer_continuation_20261106/native_prior_export_stageA/NATIVE_PRIOR_CONFIG_READ_RECEIPT.json")
source_files <- lapply(ggrr_sources(), function(rel) pin(file.path(root, rel),
  2 * 1024^2))
source_paths <- vapply(source_files, function(x) x$path, character(1L))
source_pin <- function(rel) source_files[[match(file.path(root, rel), source_paths)]]

output_parent <- file.path(root, "local_trackers",
  "glofas_forecast_root_cause_reference_20261106")
if (!dir.exists(output_parent)) fail("ignored diagnostic output parent is absent")
output_root <- file.path(output_parent,
  paste0("native_global_path_", operation, "_", stamp, "_", short))
scratch <- tempfile(paste0("glofas_global_path_", operation, "_", stamp, "_"),
  tmpdir = "/tmp")
if (!dir.create(scratch, mode = "0700")) fail("cannot create private scratch root")
on_failure <- TRUE
on.exit(if (on_failure) unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)

purpose <- list(schema_version = "glofas_global_path_native_purpose_v1",
  purpose = "MEDIAN_AL_FIXED_PARAMETER_GLOBAL_PATH_NO_FIT_NO_TRUTH",
  operation = operation,
  nonce = paste(sample(c(0:9, letters[1:6]), 48L, replace = TRUE), collapse = ""),
  expires_utc = format(Sys.time() + 12 * 3600, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  source_root = root, source_commit = commit, source_tree = tree,
  source_files = source_files, expected_identity = gsc_identity(),
  collection = pin(external$collection, 4 * 1024^2),
  input_manifest = pin(external$input_manifest, 4 * 1024^2),
  design = pin(external$design), median_model = pin(external$median_model),
  prior_receipt = pin(external$prior_receipt, 4 * 1024^2),
  acceptance_budget = source_pin(
    "scripts/diagnostics/glofas_native_stage_e_acceptance_budget.json"),
  controls = source_pin(
    "scripts/diagnostics/glofas_global_path_native_controls.json"),
  read_budget = list(max_payload_hash_bytes = 8305310364,
    max_deserialization_bytes = 4152655182,
    max_RDS_deserializations = 2L, max_generated_RDS_deserializations = 0L,
    max_metadata_bytes = 64 * 1024^2,
    max_diagnostic_output_bytes = 48 * 1024^2),
  limits = list(cpu_seconds = 14400L, wall_seconds = 14400L,
    memory_bytes = 32 * 1024^3, output_bytes = 64 * 1024^2,
    logical_cpu = logical_cpu), output_root = output_root,
  metadata_scratch_root = normalizePath(scratch),
  metadata_serialization = list(max_files = 64L,
    max_file_bytes = 4 * 1024^2, max_total_bytes = 32 * 1024^2),
  execution_controls = list(authorized = FALSE,
    probabilities = c(.05, .2, .35, .5, .65, .8, .95),
    proposal_covariance_inflation = 1,
    importance = list(particles = 2048L, max_evaluations = 2048L,
      max_wall_seconds = 10800, min_ess_fraction = .10,
      max_weight_fraction = .02),
    tempering = list(particles = 1024L, max_evaluations = 132096L,
      max_wall_seconds = 10800, min_ess_fraction = .50,
      max_weight_fraction = .01, ess_target_fraction = .70,
      max_tempering_steps = 64L, rejuvenation_steps = 2L,
      random_walk_scale = .30, resample_final = TRUE)),
  allow_original_reads = TRUE, allow_prior_metadata_read = TRUE,
  allow_fresh_source_feature_replay = TRUE,
  allow_fixed_parameter_diagnostic = TRUE, allow_metadata_serialization = TRUE,
  allow_generated_RDS_read = FALSE, allow_saved_callbacks = FALSE,
  allow_parameter_optimization = FALSE, allow_model_fit = FALSE,
  allow_truth_read = FALSE, allow_retuning = FALSE, allow_scoring = FALSE,
  allow_article_changes = FALSE, allow_publication = FALSE,
  allow_authority_replacement = FALSE)
ggrr_scope(purpose)

purpose_file <- arg("--purpose-file", file.path("/tmp", paste0(
  "glofas_global_path_native_purpose_", stamp, "_", short, ".json")))
if (file.exists(purpose_file)) fail("purpose file already exists")
json <- jsonlite::toJSON(purpose, auto_unbox = TRUE, pretty = TRUE,
  digits = 17, null = "null")
con <- file(purpose_file, open = "wb")
writeBin(charToRaw(paste0(json, "\n")), con)
close(con)
Sys.chmod(purpose_file, mode = "0600")
purpose_file <- normalizePath(purpose_file)
on_failure <- FALSE
cat(sprintf("PURPOSE_FILE=%s\nPURPOSE_SHA256=%s\nOUTPUT_ROOT=%s\nSCRATCH_ROOT=%s\n",
  purpose_file, unname(tools::sha256sum(purpose_file)), output_root,
  normalizePath(scratch)))
