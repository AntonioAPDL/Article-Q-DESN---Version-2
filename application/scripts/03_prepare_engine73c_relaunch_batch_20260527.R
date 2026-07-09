#!/usr/bin/env Rscript
# Purpose: prepare clean relaunch configs for application candidates affected
# by the moving-engine SHA mismatch on 2026-05-27. This script writes new
# config/model-grid copies only; it does not launch fitting.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  batch_id = "engine73c_relaunch_20260527",
  run_stamp = format(Sys.time(), "%Y%m%d_%H%M"),
  core_start = "0",
  engine_path = "/data/jaguir26/local/src/exdqlm__wt__article_app_engine_73c043f",
  engine_branch = "article/app-engine-73c043f",
  engine_commit = "73c043f0436b508808366f312350fd44c2d06771"
))

if (!requireNamespace("yaml", quietly = TRUE)) {
  stop("The yaml package is required to prepare relaunch configs.", call. = FALSE)
}

batch_id <- as.character(args$batch_id)[[1L]]
run_stamp <- as.character(args$run_stamp)[[1L]]
core_start <- as.integer(args$core_start)
engine_path <- normalizePath(as.character(args$engine_path)[[1L]], mustWork = TRUE)
engine_branch <- as.character(args$engine_branch)[[1L]]
engine_commit <- as.character(args$engine_commit)[[1L]]

engine_sha <- system2("git", c("-C", engine_path, "rev-parse", "HEAD"), stdout = TRUE)
engine_head_branch <- system2("git", c("-C", engine_path, "rev-parse", "--abbrev-ref", "HEAD"), stdout = TRUE)
engine_so <- file.path(engine_path, "src", "exdqlm.so")
if (!identical(engine_sha[[1L]], engine_commit)) {
  stop(sprintf("Frozen engine SHA mismatch: expected %s, found %s", engine_commit, engine_sha[[1L]]), call. = FALSE)
}
if (!identical(engine_head_branch[[1L]], engine_branch)) {
  stop(sprintf("Frozen engine branch mismatch: expected %s, found %s", engine_branch, engine_head_branch[[1L]]), call. = FALSE)
}
if (!file.exists(engine_so)) {
  stop(sprintf("Frozen engine is missing compiled shared object: %s", engine_so), call. = FALSE)
}

source_configs <- data.frame(
  relaunch_group = c(
    "diverse8",
    rep("flex8", 8L),
    rep("seedrepeat16", 14L)
  ),
  source_config = c(
    "glofas_latent_path_al_vb_dec25_diverse8_d1n1000_m120_a92_r93_w15_tau3em3_main1000.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w018_bt3em03_at1em02_skip_main1000.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w018_bt3em03_at3em02_skip_main1000.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w018_bt3em03_at1em01_skip_main1000.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m360_a92_r95_w018_bt3em03_at3em02_skip_main1000.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m360_a92_r95_w018_bt3em03_at1em01_skip_main1000.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m360_a92_r95_w018_bt3em02_at3em02_skip_main1000.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w022_bt3em03_at1em01_skip_main1000.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m360_a92_r95_w022_bt3em03_at1em01_skip_main1000.yaml",
    "glofas_latent_path_al_vb_dec25_diverse8_d1n300_m100_a92_r95_w15_tau3em3_main1000_seed20260526.yaml",
    "glofas_latent_path_al_vb_dec25_diverse8_d1n500_m100_a92_r93_w10_tau3em3_main1000_seed20260526.yaml",
    "glofas_latent_path_al_vb_dec25_diverse8_d1n700_m120_a92_r93_w10_tau3em3_main1000_seed20260526.yaml",
    "glofas_latent_path_al_vb_dec25_diverse8_d1n1000_m120_a92_r93_w15_tau3em3_main1000_seed20260526.yaml",
    "glofas_latent_path_al_vb_dec25_diverse8_d2n250x250_m120_a92_r90_w025_tau3em3_main1000_seed20260526.yaml",
    "glofas_latent_path_al_vb_dec25_diverse8_d2n400x300_m120_a92_r93_w050_tau3em3_main1000_seed20260526.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w018_bt3em03_at1em02_skip_main1000_seed20260526.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w018_bt3em03_at3em02_skip_main1000_seed20260526.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w018_bt3em03_at1em01_skip_main1000_seed20260526.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m360_a92_r95_w018_bt3em03_at3em02_skip_main1000_seed20260526.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m360_a92_r95_w018_bt3em03_at1em01_skip_main1000_seed20260526.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m360_a92_r95_w018_bt3em02_at3em02_skip_main1000_seed20260526.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m180_a92_r95_w022_bt3em03_at1em01_skip_main1000_seed20260526.yaml",
    "glofas_latent_path_al_vb_dec25_flex8_d1n300_m360_a92_r95_w022_bt3em03_at1em01_skip_main1000_seed20260526.yaml"
  ),
  stringsAsFactors = FALSE
)

slug_from_config <- function(path) {
  x <- sub("^glofas_latent_path_al_vb_dec25_", "", sub("\\.yaml$", "", basename(path)))
  x <- sub("_tau3em3_main1000", "", x, fixed = TRUE)
  x <- sub("_main1000", "", x, fixed = TRUE)
  x <- gsub("_seed20260526", "_s20260526", x, fixed = TRUE)
  x
}

rewrite_model_grid <- function(source_grid, target_grid, suffix, batch_id) {
  grid <- read.csv(source_grid, stringsAsFactors = FALSE, check.names = FALSE)
  qdesn_rows <- grid$model_family == "qdesn_glofas_discrepancy"
  for (col in intersect(c("fit_id", "model_id"), names(grid))) {
    grid[[col]][qdesn_rows] <- paste0(grid[[col]][qdesn_rows], "_", suffix)
  }
  if ("notes" %in% names(grid)) {
    grid$notes[qdesn_rows] <- paste(
      grid$notes[qdesn_rows],
      sprintf("Relaunch batch %s uses frozen application engine %s.", batch_id, suffix)
    )
    grid$notes[!qdesn_rows] <- paste(
      grid$notes[!qdesn_rows],
      sprintf("Raw reference row retained for relaunch batch %s.", batch_id)
    )
  }
  utils::write.csv(grid, target_grid, row.names = FALSE, na = "")
}

rows <- vector("list", nrow(source_configs))
suffix <- "engine73c"

for (i in seq_len(nrow(source_configs))) {
  source_config <- file.path("application/config", source_configs$source_config[[i]])
  if (!file.exists(app_path(source_config))) {
    stop(sprintf("Missing source config: %s", source_config), call. = FALSE)
  }
  cfg <- yaml::read_yaml(app_path(source_config))
  old_name <- as.character(cfg$application_name %||% sub("\\.yaml$", "", basename(source_config)))[[1L]]
  new_name <- paste(old_name, suffix, sep = "_")
  source_grid <- as.character(cfg$paths$model_grid)[[1L]]
  target_config <- file.path("application/config", paste0(new_name, ".yaml"))
  target_grid <- file.path("application/config", paste0(sub("\\.csv$", "", basename(source_grid)), "_", suffix, ".csv"))
  slug <- slug_from_config(source_config)
  run_id <- sprintf("engine73c_%02d_%s_%s", i, slug, run_stamp)

  cfg$application_name <- new_name
  cfg$description <- paste(
    cfg$description %||% "",
    sprintf("Relaunch copy for batch %s after the application engine was frozen at %s (%s).", batch_id, engine_commit, engine_branch)
  )
  cfg$paths$model_grid <- target_grid
  cfg$paths$cache <- file.path("application/cache", new_name)
  cfg$dependencies$qdesn_engine_repo_hint <- engine_path
  cfg$dependencies$qdesn_engine_expected_repo_hint <- engine_path
  cfg$dependencies$qdesn_engine_required_branch <- engine_branch
  cfg$dependencies$qdesn_engine_required_commit <- engine_commit
  cfg$execution$inference_support$note <- paste(
    cfg$execution$inference_support$note %||% "",
    sprintf("Engine-frozen relaunch batch %s; application engine path %s; commit %s.", batch_id, engine_path, engine_commit)
  )
  cfg$execution$final_launch$note <- paste(
    cfg$execution$final_launch$note %||% "",
    sprintf("Engine-frozen relaunch batch %s. Do not compare partial stopped/failed runs against this clean relaunch without checking engine provenance.", batch_id)
  )

  rewrite_model_grid(app_path(source_grid), app_path(target_grid), suffix, batch_id)
  yaml::write_yaml(cfg, app_path(target_config), indent.mapping.sequence = TRUE)

  rows[[i]] <- data.frame(
    batch_id = batch_id,
    run_index = i,
    relaunch_group = source_configs$relaunch_group[[i]],
    source_config = source_config,
    target_config = target_config,
    source_model_grid = source_grid,
    target_model_grid = target_grid,
    engine_path = engine_path,
    engine_branch = engine_branch,
    engine_commit = engine_commit,
    run_id = run_id,
    core = core_start + i - 1L,
    stringsAsFactors = FALSE
  )
}

manifest <- do.call(rbind, rows)
manifest_path <- file.path("application/config", paste0("glofas_", batch_id, "_launch_manifest.csv"))
app_write_csv(manifest, app_path(manifest_path))
cat(manifest_path, "\n")
