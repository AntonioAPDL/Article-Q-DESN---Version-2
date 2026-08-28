#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/artifact_hygiene.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_qdesn_features.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/latent_path_runtime_backend.R"))
source(app_path("application/R/latent_path_checkpoint.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))

args <- app_parse_args(list(
  campaign = "application/config/glofas_discrepancy_grouped_rhs_stage_a_20260827.yaml",
  output = ""
))
if (!nzchar(as.character(args$output %||% ""))) {
  stop("Warm-source snapshot requires --output.", call. = FALSE)
}
campaign <- app_read_yaml(app_resolve_path(args$campaign, must_work = TRUE))
source_cfg <- campaign$source %||% list()
design_path <- normalizePath(as.character(source_cfg$design_object), mustWork = TRUE)
backend_path <- normalizePath(as.character(source_cfg$runtime_backend_manifest), mustWork = TRUE)
if (!identical(tolower(app_sha256_file(design_path)), tolower(as.character(source_cfg$design_object_sha256)))) {
  stop("Retained source design failed its SHA-256 contract.", call. = FALSE)
}
if (!identical(tolower(app_sha256_file(backend_path)), tolower(as.character(source_cfg$runtime_backend_manifest_sha256)))) {
  stop("Retained source runtime-backend manifest failed its SHA-256 contract.", call. = FALSE)
}

source_backend <- app_read_csv(backend_path)
active_backend <- app_latent_runtime_backend_manifest(fail_closed = TRUE)
if (nrow(source_backend) != 1L || nrow(active_backend) != 1L ||
    !identical(as.character(source_backend$backend[[1L]]), "bundled_rblas") ||
    !identical(as.character(active_backend$backend[[1L]]), "bundled_rblas")) {
  stop("The retained-source future snapshot must be generated under bundled R BLAS.", call. = FALSE)
}

design <- app_latent_path_restore_legacy_view(readRDS(design_path))
snapshot <- app_latent_path_numerical_future_snapshot(
  design,
  design_object_sha256 = source_cfg$design_object_sha256
)
fit_contract <- app_latent_path_warm_start_contract_from_fit(
  normalizePath(as.character(source_cfg$fit_object), mustWork = TRUE)
)
if (is.null(fit_contract) || !identical(
  app_latent_path_contract_hash(snapshot$warm_start_contract, "source_snapshot_contract_"),
  app_latent_path_contract_hash(fit_contract, "source_snapshot_contract_")
)) {
  stop("Retained source design and fit warm-start contracts do not agree.", call. = FALSE)
}

output <- normalizePath(as.character(args$output), mustWork = FALSE)
app_ensure_dir(dirname(output))
saveRDS(snapshot, output, version = 2L, compress = FALSE)
cat(sprintf("Wrote bundled-BLAS future snapshot: %s\n", output))
