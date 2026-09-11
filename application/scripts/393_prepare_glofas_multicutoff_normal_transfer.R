#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- sub("^--file=", "", script_arg[[1L]])
repo_root <- normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "engine_contract.R", "model_contract.R", "feature_contract.R",
  "covariate_design.R", "build_application_panel.R",
  "glofas_part4_ensemble_likelihood_contract.R",
  "glofas_part4_multicutoff_normal_transfer.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  bundle_root = "",
  cutoff_date = "",
  anchor_manifest = "",
  base_config = "application/config/glofas_latent_path_al_vb_dec25_main.yaml",
  run_label = "",
  runtime_root = "",
  max_iter = "100",
  min_iter = "30",
  tol = "0.01",
  freeze_beta_warmup_iters = "20",
  min_beta_updates = "10",
  n_draws = "500"
))
required <- c("bundle_root", "cutoff_date", "anchor_manifest", "run_label")
missing <- required[!vapply(required, function(name) nzchar(as.character(args[[name]])[[1L]]), logical(1L))]
if (length(missing)) stop(sprintf("Missing required arguments: %s.", paste(missing, collapse = ", ")), call. = FALSE)
run_label <- as.character(args$run_label)[[1L]]
if (grepl("[^A-Za-z0-9_.-]", run_label)) stop("run_label must be path-safe.", call. = FALSE)
runtime_root <- as.character(args$runtime_root)[[1L]]
if (!nzchar(runtime_root)) runtime_root <- file.path("local_trackers", "runtime_configs", run_label)

prepared <- app_glofas_multicutoff_prepare_normal_transfer(
  base_config_path = as.character(args$base_config)[[1L]],
  anchor_manifest_path = as.character(args$anchor_manifest)[[1L]],
  bundle_root = as.character(args$bundle_root)[[1L]],
  runtime_root = runtime_root,
  run_label = run_label,
  cutoff_date = as.character(args$cutoff_date)[[1L]],
  max_iter = as.integer(args$max_iter),
  min_iter = as.integer(args$min_iter),
  tol = as.numeric(args$tol),
  freeze_beta_warmup_iters = as.integer(args$freeze_beta_warmup_iters),
  min_beta_updates = as.integer(args$min_beta_updates),
  n_draws = as.integer(args$n_draws)
)
cat("NORMAL_TRANSFER_PREPARED\n")
cat(sprintf("runtime_root=%s\n", prepared$runtime_root))
cat(sprintf("jobs=%d\n", nrow(prepared$manifest)))
cat(sprintf("cutoff_date=%s\n", as.character(args$cutoff_date)[[1L]]))
cat("dec25_fitted_state_transferred=false\n")

