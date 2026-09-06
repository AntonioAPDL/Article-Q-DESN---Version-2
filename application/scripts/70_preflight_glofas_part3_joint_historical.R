#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_desn_part2_bridge.R"))
source(app_path("application/R/glofas_normal_desn_part3_joint_bridge.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml",
  runtime_root = "",
  winner_manifest = "",
  max_available_memory_fraction = "0.35"
))

runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
winner_manifest <- app_resolve_path(args$winner_manifest, must_work = TRUE)
base_config <- app_resolve_path(args$base_config, must_work = TRUE)
max_fraction <- as.numeric(args$max_available_memory_fraction)
if (!is.finite(max_fraction) || max_fraction <= 0 || max_fraction >= 1) {
  stop("max_available_memory_fraction must be strictly between zero and one.", call. = FALSE)
}

status_dir <- app_ensure_dir(file.path(runtime_root, "status"))
config_dir <- app_ensure_dir(file.path(runtime_root, "configs"))
running_path <- file.path(status_dir, "part3_preflight.running")
completed_path <- file.path(status_dir, "part3_preflight.completed")
failed_path <- file.path(status_dir, "part3_preflight.failed")
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), running_path)

available_memory_bytes <- function() {
  path <- "/proc/meminfo"
  if (!file.exists(path)) return(NA_real_)
  lines <- readLines(path, warn = FALSE)
  hit <- grep("^MemAvailable:", lines, value = TRUE)
  if (!length(hit)) return(NA_real_)
  kb <- suppressWarnings(as.numeric(sub("^MemAvailable:[[:space:]]*([0-9]+).*$", "\\1", hit[[1L]])))
  if (!is.finite(kb)) NA_real_ else kb * 1024
}

tryCatch({
  manifest <- app_glofas_normal_part3_validate_winner_manifest(
    winner_manifest,
    require_frozen = TRUE
  )
  base_cfg <- app_read_config(base_config)
  candidate <- app_glofas_normal_part3_candidate_from_winners(
    manifest,
    candidate_id = "part3_selected_normal_historical_bridge",
    require_frozen = TRUE
  )
  design <- app_glofas_normal_part3_build_design(base_cfg, candidate)
  split <- app_glofas_normal_part3_validation_split(design, candidate)
  stack_split <- app_glofas_normal_part3_stack_split(design, split)
  app_glofas_normal_part3_validate_design(design)

  p <- ncol(design$H)
  n <- nrow(design$H)
  p2_bytes <- as.numeric(p) * as.numeric(p) * 8
  design_bytes <- as.numeric(object.size(design))
  estimated_peak_bytes <- design_bytes + 12 * p2_bytes + 4 * as.numeric(n) * as.numeric(p) * 8
  available_bytes <- available_memory_bytes()
  memory_pass <- is.na(available_bytes) || estimated_peak_bytes <= max_fraction * available_bytes
  sign_gap <- max(abs(design$y_reference + design$d_g - design$g_retrospective))
  usgs_discrepancy_block_max_abs <- max(abs(design$H[seq_len(design$n_dates), design$alpha_index, drop = FALSE]))
  train_hash <- app_glofas_normal_part1_design_fingerprint(
    design$H[stack_split$train_idx, , drop = FALSE],
    design$z[stack_split$train_idx],
    design$row_info$date[stack_split$train_idx],
    design$feature_info
  )
  certificate <- data.frame(
    status = if (memory_pass) "pass" else "fail_memory_headroom",
    candidate_id = as.character(candidate$candidate_id[[1L]]),
    reference_candidate_id = as.character(candidate$ref_source_candidate_id[[1L]]),
    discrepancy_candidate_id = as.character(candidate$disc_source_candidate_id[[1L]]),
    n_dates = design$n_dates,
    n_stacked_rows = n,
    n_train_stacked_rows = length(stack_split$train_idx),
    n_valid_stacked_rows = length(stack_split$valid_idx),
    p_reference = design$p_beta,
    p_discrepancy = design$p_alpha,
    p_joint = p,
    sign_gap = sign_gap,
    usgs_discrepancy_block_max_abs = usgs_discrepancy_block_max_abs,
    reference_design_hash = as.character(design$design_hash[["reference_full"]]),
    discrepancy_design_hash = as.character(design$design_hash[["discrepancy_full"]]),
    part3_stacked_full_hash = as.character(design$design_hash[["part3_stacked_full"]]),
    part3_stacked_train_hash = train_hash,
    design_object_bytes = design_bytes,
    dense_p_by_p_bytes = p2_bytes,
    estimated_peak_bytes = estimated_peak_bytes,
    available_memory_bytes = available_bytes,
    max_available_memory_fraction = max_fraction,
    memory_headroom_pass = memory_pass,
    winner_manifest = winner_manifest,
    winner_manifest_sha256 = app_sha256_file(winner_manifest),
    base_config = base_config,
    base_config_sha256 = app_sha256_file(base_config),
    checked_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    stringsAsFactors = FALSE
  )
  certificate_path <- file.path(config_dir, "part3_design_preflight.csv")
  app_write_csv(certificate, certificate_path)
  if (!memory_pass) {
    stop("Part 3 dense-fit memory estimate exceeds the approved available-memory fraction.", call. = FALSE)
  }
  writeLines(
    c(
      sprintf("certificate=%s", certificate_path),
      sprintf("certificate_sha256=%s", app_sha256_file(certificate_path)),
      sprintf("part3_stacked_train_hash=%s", train_hash)
    ),
    completed_path
  )
  if (file.exists(running_path)) unlink(running_path)
  if (file.exists(failed_path)) unlink(failed_path)
  print(certificate)
}, error = function(e) {
  writeLines(conditionMessage(e), failed_path)
  if (file.exists(running_path)) unlink(running_path)
  stop(e)
})
