#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_richer_discrepancy_campaign.R"))

args <- app_parse_args(list(
  screen_id = "glofas_richer_discrepancy_initial_20260827",
  output_root = "local_trackers/runtime_configs/glofas_richer_discrepancy_initial_20260827",
  cores = "3,4,5,6,7,8,9,10,11,15,16,17,18,19,20,22,23,24,25,26",
  authorize_launch = FALSE
))
cores <- as.integer(strsplit(as.character(args$cores), ",", fixed = TRUE)[[1L]])
if (length(cores) != 20L || any(!is.finite(cores)) || anyDuplicated(cores)) {
  stop("--cores must contain exactly 20 distinct CPU identifiers.", call. = FALSE)
}
space <- app_glofas_richer_screen_space(args$screen_id, args$output_root, cores)
space_path <- app_path(args$output_root, "reviewed_screening_space.yaml")
app_write_yaml(space, space_path)
cmd <- c(
  "application/scripts/glofas_constrained_median_screen_prepare.R",
  "--space", space_path,
  "--output_root", app_path(args$output_root),
  "--authorize_launch", if (app_as_bool(args$authorize_launch)) "true" else "false"
)
status <- system2("Rscript", cmd)
if (!identical(status, 0L)) stop("Generic median-screen preparation failed.", call. = FALSE)
