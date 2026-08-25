#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/glofas_constrained_median_screening.R"))
source(app_path("application/R/glofas_median_response_surface_campaign.R"))
source(app_path("application/R/glofas_median_structural_campaign.R"))

args <- app_parse_args(list(
  campaign = "application/config/glofas_p50_structural_memory_geometry_20260821.yaml",
  output_root = "",
  authorize_launch = FALSE
))

campaign_path <- app_resolve_path(args$campaign, must_work = TRUE)
campaign <- app_read_yaml(campaign_path)
if (nzchar(as.character(args$output_root %||% ""))) {
  campaign$output_root <- as.character(args$output_root)
}
anchor <- app_glofas_median_campaign_verify_anchor(campaign)
space <- app_glofas_median_structural_space(campaign, anchor = anchor)
output_root <- app_resolve_path(space$output_root, must_work = FALSE)
app_ensure_dir(output_root)

materialized_path <- file.path(output_root, "materialized_screening_space.yaml")
app_write_yaml(space, materialized_path)
manifest <- app_glofas_median_screen_candidate_manifest(space)
app_write_csv(data.frame(
  field = c(
    "campaign_path", "campaign_sha256", "anchor_candidate_id", "anchor_ranking_path",
    "anchor_ranking_sha256", "anchor_config_path", "anchor_config_sha256",
    "anchor_fit_object_path", "anchor_fit_object_sha256", "candidate_count",
    "max_iter", "max_parallel"
  ),
  value = c(
    campaign_path, app_sha256_file(campaign_path), anchor$candidate_id,
    anchor$ranking_path, app_sha256_file(anchor$ranking_path), anchor$config_path,
    app_sha256_file(anchor$config_path), anchor$fit_object_path,
    app_sha256_file(anchor$fit_object_path), nrow(manifest),
    as.integer(space$fixed$inference$max_iter),
    as.integer(space$scheduler$max_parallel)
  ),
  stringsAsFactors = FALSE
), file.path(output_root, "campaign_anchor_contract.csv"))
app_write_csv(
  as.data.frame(table(manifest$candidate_role), stringsAsFactors = FALSE),
  file.path(output_root, "campaign_role_counts.csv")
)

prepare_script <- app_path("application/scripts/glofas_constrained_median_screen_prepare.R")
status <- system2(Sys.which("Rscript"), c(
  prepare_script,
  "--space", materialized_path,
  "--output_root", output_root,
  "--authorize_launch", if (app_as_bool(args$authorize_launch)) "true" else "false"
))
if (!identical(as.integer(status), 0L)) {
  stop(sprintf("Generic constrained-screen preparation failed with exit code %s.", status), call. = FALSE)
}
cat(file.path(output_root, "runtime_manifest.csv"), "\n")
