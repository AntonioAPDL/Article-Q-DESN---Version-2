#!/usr/bin/env Rscript
# Purpose: prepare a second-seed repeat of the active GloFAS application
# candidate batch. This rewrites only configuration/model-grid copies; it does
# not launch application fitting.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  seed = "20260526",
  batch_id = "seedrepeat16_20260526_seed20260526",
  run_stamp = format(Sys.time(), "%Y%m%d_%H%M"),
  core_start = "32"
))

if (!requireNamespace("yaml", quietly = TRUE)) {
  stop("The yaml package is required to prepare seed-repeat configs.", call. = FALSE)
}

repeat_seed <- as.integer(args$seed)
if (!is.finite(repeat_seed)) stop("--seed must be an integer.", call. = FALSE)
batch_id <- as.character(args$batch_id)[[1L]]
run_stamp <- as.character(args$run_stamp)[[1L]]
core_start <- as.integer(args$core_start)

source_configs <- c(
  "glofas_latent_path_al_vb_dec25_diverse8_d1n300_m100_a92_r97_w20_tau3em3_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_diverse8_d1n300_m100_a92_r95_w15_tau3em3_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_diverse8_d1n400_m120_a92_r90_w10_tau3em3_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_diverse8_d1n500_m100_a92_r93_w10_tau3em3_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_diverse8_d1n700_m120_a92_r93_w10_tau3em3_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_diverse8_d1n1000_m120_a92_r93_w15_tau3em3_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_diverse8_d2n250x250_m120_a92_r90_w025_tau3em3_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_diverse8_d2n400x300_m120_a92_r93_w050_tau3em3_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w018_bt3em03_at1em02_skip_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w018_bt3em03_at3em02_skip_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w018_bt3em03_at1em01_skip_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_flex8_d1n300_m360_a92_r95_w018_bt3em03_at3em02_skip_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_flex8_d1n300_m360_a92_r95_w018_bt3em03_at1em01_skip_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_flex8_d1n300_m360_a92_r95_w018_bt3em02_at3em02_skip_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w022_bt3em03_at1em01_skip_main1000.yaml",
  "glofas_latent_path_al_vb_dec25_flex8_d1n300_m360_a92_r95_w022_bt3em03_at1em01_skip_main1000.yaml"
)

slug_from_config <- function(path) {
  x <- sub("^glofas_latent_path_al_vb_dec25_", "", sub("\\.yaml$", "", basename(path)))
  x <- sub("_tau3em3_main1000$", "", x)
  x <- sub("_main1000$", "", x)
  x
}

rewrite_model_grid <- function(source_grid, target_grid, repeat_seed, seed_tag) {
  grid <- read.csv(source_grid, stringsAsFactors = FALSE, check.names = FALSE)
  qdesn_rows <- grid$model_family == "qdesn_glofas_discrepancy"
  grid$reservoir_seed[qdesn_rows] <- repeat_seed
  for (col in intersect(c("fit_id", "model_id"), names(grid))) {
    grid[[col]][qdesn_rows] <- paste0(grid[[col]][qdesn_rows], "_", seed_tag)
  }
  if ("notes" %in% names(grid)) {
    grid$notes[qdesn_rows] <- paste(
      grid$notes[qdesn_rows],
      sprintf("Seed-repeat batch %s uses reservoir seed %d for seed-sensitivity assessment.", batch_id, repeat_seed)
    )
    grid$notes[!qdesn_rows] <- paste(
      grid$notes[!qdesn_rows],
      sprintf("Included unchanged as the deterministic raw-reference row for seed-repeat batch %s.", batch_id)
    )
  }
  utils::write.csv(grid, target_grid, row.names = FALSE, na = "")
}

rows <- vector("list", length(source_configs))
seed_tag <- paste0("seed", repeat_seed)

for (i in seq_along(source_configs)) {
  source_config <- file.path("application/config", source_configs[[i]])
  cfg <- yaml::read_yaml(app_path(source_config))
  old_name <- as.character(cfg$application_name %||% sub("\\.yaml$", "", basename(source_config)))[[1L]]
  new_name <- paste(old_name, seed_tag, sep = "_")
  source_grid <- as.character(cfg$paths$model_grid)[[1L]]
  target_config <- file.path("application/config", paste0(new_name, ".yaml"))
  target_grid <- file.path("application/config", paste0(sub("\\.csv$", "", basename(source_grid)), "_", seed_tag, ".csv"))
  slug <- slug_from_config(source_config)
  run_id <- sprintf("seedrep16_%02d_%s_s%d_%s", i, slug, repeat_seed, run_stamp)

  cfg$application_name <- new_name
  cfg$description <- paste(
    cfg$description %||% "",
    sprintf("Seed-repeat copy for batch %s; only the reservoir seed, cache path, model-grid copy, and identifiers are changed from the source config.", batch_id)
  )
  cfg$paths$model_grid <- target_grid
  cfg$paths$cache <- file.path("application/cache", new_name)
  cfg$reservoir$seed <- repeat_seed
  cfg$execution$inference_support$note <- paste(
    cfg$execution$inference_support$note %||% "",
    sprintf("Seed-repeat batch %s; same specification with reservoir seed %d.", batch_id, repeat_seed)
  )
  cfg$execution$final_launch$note <- paste(
    cfg$execution$final_launch$note %||% "",
    sprintf("Seed-repeat batch %s with reservoir seed %d.", batch_id, repeat_seed)
  )

  rewrite_model_grid(app_path(source_grid), app_path(target_grid), repeat_seed, seed_tag)
  yaml::write_yaml(cfg, app_path(target_config), indent.mapping.sequence = TRUE)

  rows[[i]] <- data.frame(
    batch_id = batch_id,
    run_index = i,
    source_config = source_config,
    seed_config = target_config,
    source_model_grid = source_grid,
    seed_model_grid = target_grid,
    source_seed = 20260512L,
    repeat_seed = repeat_seed,
    run_id = run_id,
    core = core_start + i - 1L,
    stringsAsFactors = FALSE
  )
}

manifest <- do.call(rbind, rows)
manifest_path <- file.path("application/config", paste0("glofas_", batch_id, "_launch_manifest.csv"))
app_write_csv(manifest, app_path(manifest_path))
cat(manifest_path, "\n")
