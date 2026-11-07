#!/usr/bin/env Rscript
# Issue one source-bound config-only prior-export purpose for an admitted AL
# tail. This script hashes metadata but never deserializes a config or fit.
source("scripts/diagnostics/glofas_native_prior_contract.R")

fail <- function(message) stop(paste0("GloFAS tail prior purpose: ", message),
  call. = FALSE)
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
pin <- function(path, role = NULL, maximum = 2 * 1024^2) {
  path <- normalizePath(path, mustWork = TRUE)
  info <- file.info(path)
  if (isTRUE(info$isdir) || info$size <= 0 || info$size > maximum)
    fail(paste("invalid pinned file", path))
  value <- list(path = path, size_bytes = unname(info$size),
    sha256 = unname(tools::sha256sum(path)))
  if (!is.null(role)) value$role <- role
  value
}

args <- commandArgs(TRUE)
if (identical(args, "--help")) {
  cat("Usage: Rscript --vanilla scripts/prepare_glofas_native_tail_prior_purpose.R --task gft-al-p005|gft-al-p095 [--purpose-file FILE]\n")
  quit(save = "no", status = 0L)
}
task_id <- arg("--task")
if (is.null(task_id) || !task_id %in% c("gft-al-p005", "gft-al-p095"))
  fail("only gft-al-p005 and gft-al-p095 are admitted")
probability <- gnpc_task_probability(task_id)
root <- normalizePath(getwd(), mustWork = TRUE)
if (!identical(git(c("rev-parse", "--show-toplevel")), root) ||
    length(git(c("status", "--porcelain", "--untracked-files=all"))))
  fail("purpose issuance requires the exact clean worktree root")
commit <- git(c("rev-parse", "HEAD"))
tree <- git(c("rev-parse", "HEAD^{tree}"))
stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
short <- substring(commit, 1L, 8L)
prepared <- paste0("/data/jaguir26/local/src/",
  "Article-Q-DESN---Version-2__wt__glofas_family_transition_launch_20261101/",
  "local_trackers/glofas_transition_launch_20261101/prepared_r2")
config <- pin(file.path(prepared, "configs", paste0(task_id, ".rds")),
  "transition_task_configuration", 1024^2)
expected_config <- c(`gft-al-p005` =
  "81ec20c1b010996297f1ecde3b5323f7ccae9d54c5b767c793f4433b60fb6509",
  `gft-al-p095` =
  "6b30294a257ccb1afdda7b1fdba22dfa0d678b248c35306e86c13173f7e693c2")
if (!identical(config$sha256, unname(expected_config[[task_id]])) ||
    config$size_bytes != 3798) fail("tail config identity changed")
source_rel <- c("scripts/diagnostics/glofas_native_prior_contract.R",
  "application/R/latent_path_vb_al.R",
  "application/R/glofas_family_transition.R")
source_files <- lapply(source_rel, function(path) pin(file.path(root, path),
  maximum = 2 * 1024^2))
output_parent <- file.path(root, "local_trackers",
  "glofas_forecast_root_cause_reference_20261106")
output_root <- file.path(output_parent, paste0("native_tail_prior_", task_id,
  "_", stamp, "_", short))
purpose <- list(schema_version = "glofas_native_prior_config_read_purpose_v2",
  purpose = "ONE_ADMITTED_AL_CONFIG_PRIOR_EXPORT_NO_MODEL_RUN",
  nonce = paste(sample(c(0:9, letters[1:6]), 64L, replace = TRUE), collapse = ""),
  expires_utc = format(Sys.time() + 3600, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  source_root = root, source_commit = commit, source_tree = tree,
  source_files = source_files, config = config,
  expected = list(task_id = task_id, probability = probability,
    posterior_target_sha256 =
      "72ef0550393106009b100636e1b11e8c21d4da31e77ed01a3dc2663439dbef03"),
  read_budget = list(max_RDS_deserializations = 1L,
    max_deserialization_bytes = config$size_bytes,
    max_hash_bytes = 2 * config$size_bytes, max_output_bytes = 1024^2),
  output_root = output_root, allow_config_read = TRUE,
  allow_design_read = FALSE, allow_fit_read = FALSE, allow_model_run = FALSE,
  allow_truth_read = FALSE, allow_publication = FALSE)
gnpc_validate_purpose(purpose)
purpose_file <- arg("--purpose-file", file.path("/tmp", paste0(
  "glofas_native_tail_prior_", task_id, "_", stamp, "_", short, ".json")))
if (file.exists(purpose_file)) fail("purpose file already exists")
writeLines(jsonlite::toJSON(purpose, auto_unbox = TRUE, pretty = TRUE,
  digits = 17, null = "null"), purpose_file, useBytes = TRUE)
Sys.chmod(purpose_file, mode = "0600")
purpose_file <- normalizePath(purpose_file)
cat(sprintf("PURPOSE_FILE=%s\nPURPOSE_SHA256=%s\nOUTPUT_ROOT=%s\n",
  purpose_file, unname(tools::sha256sum(purpose_file)), output_root))
