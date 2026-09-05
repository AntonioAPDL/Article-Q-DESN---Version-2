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
  part1_score_path = "",
  part2_score_path = "",
  part1_rhs_candidate_id = "normal_rhs_top10_03_part1wide_0150_D1_n3000__Y360_X180__a050_r090__tau1",
  part2_rhs_candidate_id = "normal_part2_rhs_top16_part2ridge_targeted_0016_disc_covars__D1_n2500__a080_r070__reftau1e00_disctau1em03",
  part1_source_runtime_root = "local_trackers/runtime_configs/glofas_normal_rhs_top10_vb_20260901",
  part2_source_runtime_root = "local_trackers/runtime_configs/glofas_normal_part2_rhs_top50_jerez_recovery_20260904",
  output_path = "",
  evidence_path = ""
))

base_config <- app_resolve_path(args$base_config, must_work = TRUE)
part1_score_path <- app_resolve_path(args$part1_score_path, must_work = TRUE)
part2_score_path <- app_resolve_path(args$part2_score_path, must_work = TRUE)
output_path <- app_resolve_path(args$output_path, must_work = FALSE)
evidence_path <- app_resolve_path(args$evidence_path, must_work = FALSE)
app_ensure_dir(dirname(output_path))
app_ensure_dir(dirname(evidence_path))

part1_scores <- app_read_csv(part1_score_path)
part2_scores <- app_read_csv(part2_score_path)
app_check_required_columns(
  part1_scores,
  c("rhs_candidate_id", "candidate_id", "n_vector", "m", "output_lag_max", "covariate_lag_max", "washout", "alpha", "rho", "seed", "rhs_tau0", "status"),
  "Part 1 Normal RHS score table"
)
app_check_required_columns(
  part2_scores,
  c("rhs_candidate_id", "candidate_id", "disc_n_vector", "disc_m", "disc_output_lag_max", "disc_covariate_lag_max", "disc_auxiliary_lag_max", "disc_washout", "disc_alpha", "disc_rho", "disc_seed", "rhs_tau0_discrepancy", "disc_input_contract", "status"),
  "Part 2 Normal RHS score table"
)

part1 <- part1_scores[part1_scores$rhs_candidate_id == args$part1_rhs_candidate_id, , drop = FALSE]
part2 <- part2_scores[part2_scores$rhs_candidate_id == args$part2_rhs_candidate_id, , drop = FALSE]
if (nrow(part1) != 1L) stop("Part 1 winner ID must select exactly one score row.", call. = FALSE)
if (nrow(part2) != 1L) stop("Part 2 winner ID must select exactly one score row.", call. = FALSE)
if (!identical(tolower(as.character(part1$status[[1L]])), "completed")) stop("Part 1 winner is not completed.", call. = FALSE)
if (!identical(tolower(as.character(part2$status[[1L]])), "completed")) stop("Part 2 winner is not completed.", call. = FALSE)

manifest <- data.frame(
  component = c("reference", "discrepancy"),
  stage = c("G1", "G2"),
  candidate_id = c(as.character(part1$rhs_candidate_id[[1L]]), as.character(part2$rhs_candidate_id[[1L]])),
  source_runtime_root = c(as.character(args$part1_source_runtime_root), as.character(args$part2_source_runtime_root)),
  score_path = c(part1_score_path, part2_score_path),
  method = c("normal_rhs_vb", "normal_rhs_vb"),
  status = c("completed", "completed"),
  winner_role = c("reference_anchor", "discrepancy_anchor"),
  n_vector = c(as.character(part1$n_vector[[1L]]), as.character(part2$disc_n_vector[[1L]])),
  m = c(as.integer(part1$m[[1L]]), as.integer(part2$disc_m[[1L]])),
  output_lag_max = c(as.integer(part1$output_lag_max[[1L]]), as.integer(part2$disc_output_lag_max[[1L]])),
  covariate_lag_max = c(as.integer(part1$covariate_lag_max[[1L]]), as.integer(part2$disc_covariate_lag_max[[1L]])),
  auxiliary_lag_max = c(0L, as.integer(part2$disc_auxiliary_lag_max[[1L]])),
  input_contract = c("reference_usgs_covars", as.character(part2$disc_input_contract[[1L]])),
  washout = c(as.integer(part1$washout[[1L]]), as.integer(part2$disc_washout[[1L]])),
  alpha = c(as.numeric(part1$alpha[[1L]]), as.numeric(part2$disc_alpha[[1L]])),
  rho = c(as.numeric(part1$rho[[1L]]), as.numeric(part2$disc_rho[[1L]])),
  seed = c(as.integer(part1$seed[[1L]]), as.integer(part2$disc_seed[[1L]])),
  rhs_tau0 = c(as.numeric(part1$rhs_tau0[[1L]]), as.numeric(part2$rhs_tau0_discrepancy[[1L]])),
  design_hash = c("pending_deterministic_rebuild", "pending_deterministic_rebuild"),
  frozen = c(FALSE, FALSE),
  stringsAsFactors = FALSE
)

candidate <- app_glofas_normal_part3_candidate_from_winners(
  manifest,
  candidate_id = "part3_selected_normal_historical_bridge",
  require_frozen = FALSE
)
design <- app_glofas_normal_part3_build_design(app_read_config(base_config), candidate)
manifest$design_hash <- c(
  as.character(design$design_hash[["reference_full"]]),
  as.character(design$design_hash[["discrepancy_full"]])
)
if (anyNA(manifest$design_hash) || any(!nzchar(manifest$design_hash))) {
  stop("Deterministic source design hashes were not produced.", call. = FALSE)
}
manifest$frozen <- TRUE
app_glofas_normal_part3_validate_winner_manifest(manifest, require_frozen = TRUE)
app_write_csv(manifest, output_path)

evidence <- data.frame(
  part1_rhs_candidate_id = as.character(part1$rhs_candidate_id[[1L]]),
  part2_rhs_candidate_id = as.character(part2$rhs_candidate_id[[1L]]),
  part1_score_path = part1_score_path,
  part1_score_sha256 = app_sha256_file(part1_score_path),
  part2_score_path = part2_score_path,
  part2_score_sha256 = app_sha256_file(part2_score_path),
  base_config = base_config,
  base_config_sha256 = app_sha256_file(base_config),
  reference_design_hash = manifest$design_hash[[1L]],
  discrepancy_design_hash = manifest$design_hash[[2L]],
  part3_stacked_design_hash = as.character(design$design_hash[["part3_stacked_full"]]),
  sign_gap = max(abs(design$y_reference + design$d_g - design$g_retrospective)),
  manifest_path = output_path,
  manifest_sha256 = app_sha256_file(output_path),
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  stringsAsFactors = FALSE
)
app_write_csv(evidence, evidence_path)
print(manifest)
cat(sprintf("winner_manifest=%s\n", output_path))
cat(sprintf("winner_manifest_sha256=%s\n", app_sha256_file(output_path)))
cat(sprintf("evidence=%s\n", evidence_path))
